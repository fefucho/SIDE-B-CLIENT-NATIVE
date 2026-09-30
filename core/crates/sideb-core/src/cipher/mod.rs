//! `CipherDeobfuscator` — player analysis in Rust and signature evaluation in JavaScriptCore.
//!
//! Ties [`fetcher`] (player.js) + [`extractor`]/[`config`] (function names & STS).
//! STS extraction is done directly via literal search without needing any web process.
//! If deciphering or n-transform is unavailable, public methods degrade gracefully to the
//! direct-URL clients.

mod config;
mod extractor;
mod fetcher;

pub use config::PlayerConfigStore;

use std::path::Path;
use std::sync::Arc;
use std::time::Duration;

use fetcher::PlayerJsFetcher;
use tokio::sync::Mutex;

use crate::CipherJsRuntime;

#[derive(Default)]
struct Inner {
    sts: Option<i32>,
    built_epoch: u64,
    analyzed: bool,
    runtime_ready: bool,
}

impl Inner {
    fn owes_work(&self, epoch: u64) -> bool {
        !self.analyzed || self.built_epoch != epoch
    }
}

pub struct CipherDeobfuscator {
    fetcher: PlayerJsFetcher,
    config: Arc<PlayerConfigStore>,
    inner: Mutex<Inner>,
    runtime: std::sync::RwLock<Option<Arc<dyn CipherJsRuntime>>>,
}

impl CipherDeobfuscator {
    pub fn new(app_data_dir: &Path, config: Arc<PlayerConfigStore>) -> Self {
        CipherDeobfuscator {
            fetcher: PlayerJsFetcher::new(app_data_dir),
            config,
            inner: Mutex::new(Inner::default()),
            runtime: std::sync::RwLock::new(None),
        }
    }

    pub fn set_runtime(&self, runtime: Arc<dyn CipherJsRuntime>) {
        *self.runtime.write().unwrap() = Some(runtime);
    }

    /// STS of the player.js we decipher with (preferred over any other source).
    pub async fn signature_timestamp(&self) -> Option<i32> {
        if self.ensure_analyzed().await.is_err() {
            return None;
        }
        self.inner.lock().await.sts
    }

    /// `signatureCipher` string -> a full, signed stream URL. None on any failure.
    pub async fn deobfuscate_stream_url(&self, cipher: &str, _video_id: &str) -> Option<String> {
        self.ensure_runtime().await.ok()?;
        let (signature, parameter, mut url) = parse_cipher(cipher)?;
        let runtime = self.runtime.read().unwrap().clone()?;
        let expression = format!(
            "window._cipherSigFunc({})",
            serde_json::to_string(&signature).ok()?
        );
        let signed = runtime.evaluate(expression)?;
        if signed.is_empty() || signed == "null" || signed == "undefined" {
            return None;
        }
        let separator = if url.contains('?') { '&' } else { '?' };
        url.push(separator);
        url.push_str(&parameter);
        url.push('=');
        url.push_str(&urlencoding::encode(&signed));
        Some(url)
    }

    /// Replace `&n=` with its throttling-deobfuscated value. Returns the URL unchanged on failure.
    pub async fn transform_n_param_in_url(&self, url: &str) -> String {
        self.try_transform_n(url)
            .await
            .unwrap_or_else(|| url.to_owned())
    }

    async fn try_transform_n(&self, url: &str) -> Option<String> {
        self.ensure_runtime().await.ok()?;
        let parsed = reqwest::Url::parse(url).ok()?;
        let n = parsed.query_pairs().find(|(k, _)| k == "n")?.1.into_owned();
        let runtime = self.runtime.read().unwrap().clone()?;
        let expression = format!(
            "window._nTransformFunc({})",
            serde_json::to_string(&n).ok()?
        );
        let transformed = runtime.evaluate(expression)?;
        if transformed.is_empty() || transformed == n || transformed == "null" {
            return None;
        }
        let mut updated = parsed.clone();
        let pairs: Vec<(String, String)> = parsed
            .query_pairs()
            .map(|(k, v)| {
                (
                    k.to_string(),
                    if k == "n" {
                        transformed.clone()
                    } else {
                        v.into_owned()
                    },
                )
            })
            .collect();
        updated.query_pairs_mut().clear().extend_pairs(pairs);
        Some(updated.into())
    }

    /// Self-heal after a 403 on a deciphered URL: refresh config table + invalidate player.js.
    pub async fn on_stream_rejected(&self) -> bool {
        let table_changed = self.config.refresh_after_stream_rejection().await;
        self.fetcher.invalidate();
        {
            let mut inner = self.inner.lock().await;
            inner.analyzed = false;
            inner.runtime_ready = false;
        }
        table_changed
    }

    /// Warm player.js cache and analyze STS.
    pub async fn prewarm(&self) {
        if let Err(e) = self.ensure_analyzed().await {
            tracing::warn!(error = %e, "cipher prewarm failed (will retry on demand)");
        }
    }

    pub async fn teardown_if_idle(&self, _idle: Duration) {
        // No hidden webview resident, nothing to teardown.
    }

    /// Ensure player.js analysis (STS + config lookup) is fresh for current config epoch.
    async fn ensure_analyzed(&self) -> Result<(), String> {
        let epoch = self.config.config_epoch();
        {
            let inner = self.inner.lock().await;
            if !inner.owes_work(epoch) {
                return Ok(());
            }
        }

        let player = self.fetcher.fetch().await.map_err(|e| e.to_string())?;
        let cfg = self.config.get(&player.hash);
        let sts = cfg
            .as_ref()
            .and_then(|c| c.sts)
            .or_else(|| extractor::extract_sts(&player.js));

        let mut inner = self.inner.lock().await;
        inner.sts = sts;
        inner.built_epoch = epoch;
        inner.analyzed = true;
        tracing::info!(hash = player.hash, ?sts, "cipher: analysis complete");
        Ok(())
    }

    async fn ensure_runtime(&self) -> Result<(), String> {
        self.ensure_analyzed().await?;
        let mut inner = self.inner.lock().await;
        if inner.runtime_ready {
            return Ok(());
        }
        let player = self.fetcher.fetch().await.map_err(|e| e.to_string())?;
        let config = match self.config.get(&player.hash) {
            Some(config) => config,
            None => {
                self.config.force_refresh().await;
                self.config
                    .get(&player.hash)
                    .ok_or("unknown player config")?
            }
        };
        let runtime = self
            .runtime
            .read()
            .unwrap()
            .clone()
            .ok_or("cipher runtime unavailable")?;
        let script = extractor::build_injection(&player.js, Some(&config));
        if !runtime.load(script) {
            return Err("player.js runtime failed to load".into());
        }
        if runtime
            .evaluate("typeof window._cipherSigFunc".into())
            .as_deref()
            != Some("function")
        {
            return Err("signature function unavailable".into());
        }
        inner.runtime_ready = true;
        Ok(())
    }
}

fn parse_cipher(cipher: &str) -> Option<(String, String, String)> {
    let mut signature = None;
    let mut parameter = None;
    let mut url = None;
    for pair in cipher.split('&') {
        let (key, value) = pair.split_once('=')?;
        let decoded = urlencoding::decode(value).ok()?.into_owned();
        match key {
            "s" => signature = Some(decoded),
            "sp" => parameter = Some(decoded),
            "url" => url = Some(decoded),
            _ => {}
        }
    }
    let parameter = parameter.unwrap_or_else(|| "signature".into());
    if !parameter
        .chars()
        .all(|c| c.is_ascii_alphanumeric() || c == '_')
    {
        return None;
    }
    Some((signature?, parameter, url?))
}

#[cfg(test)]
mod tests {
    use super::parse_cipher;

    #[test]
    fn parses_escaped_signature_and_url() {
        let parts =
            parse_cipher("s=abc%2F123&sp=sig&url=https%3A%2F%2Fx.googlevideo.com%2Fv%3Fn%3Dabc")
                .unwrap();
        assert_eq!(
            parts,
            (
                "abc/123".into(),
                "sig".into(),
                "https://x.googlevideo.com/v?n=abc".into()
            )
        );
        assert_eq!(parse_cipher("s=abc&sp=sig%26bad&url=https%3A%2F%2Fx"), None);
    }
}
