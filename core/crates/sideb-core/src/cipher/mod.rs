//! `CipherDeobfuscator` — pure-Rust signature timestamp and player analysis runtime.
//!
//! Ties [`fetcher`] (player.js) + [`extractor`]/[`config`] (function names & STS).
//! STS extraction is done directly via literal search without needing any web process.
//! If deciphering or n-transform is not configured, public methods degrade gracefully:
//! yielding None / original URL, allowing the orchestrator to fall through to direct-URL
//! clients (VISIONOS, ANDROID_VR, IOS).

mod config;
mod extractor;
mod fetcher;

pub use config::PlayerConfigStore;

use std::path::Path;
use std::sync::Arc;
use std::time::{Duration, Instant};

use tokio::sync::Mutex;
use fetcher::PlayerJsFetcher;

#[derive(Default)]
struct Inner {
    sts: Option<i32>,
    built_epoch: u64,
    n_available: bool,
    sig_available: bool,
    analyzed: bool,
    discovered: bool,
    last_used: Option<Instant>,
}

impl Inner {
    fn owes_work(&self, epoch: u64) -> bool {
        !self.analyzed || self.built_epoch != epoch
    }

    fn idle_for(&self, idle: Duration) -> bool {
        !self.last_used.is_some_and(|t| t.elapsed() < idle)
    }
}

pub struct CipherDeobfuscator {
    fetcher: PlayerJsFetcher,
    config: Arc<PlayerConfigStore>,
    inner: Mutex<Inner>,
}

impl CipherDeobfuscator {
    pub fn new(app_data_dir: &Path, config: Arc<PlayerConfigStore>) -> Self {
        CipherDeobfuscator {
            fetcher: PlayerJsFetcher::new(app_data_dir),
            config,
            inner: Mutex::new(Inner::default()),
        }
    }

    /// STS of the player.js we decipher with (preferred over any other source).
    pub async fn signature_timestamp(&self) -> Option<i32> {
        if self.ensure_analyzed().await.is_err() {
            return None;
        }
        self.inner.lock().await.sts
    }

    /// `signatureCipher` string -> a full, signed stream URL. None on any failure.
    pub async fn deobfuscate_stream_url(&self, _cipher: &str, _video_id: &str) -> Option<String> {
        if self.ensure_analyzed().await.is_err() {
            return None;
        }
        // Graceful fallback to direct clients (VISIONOS/ANDROID_VR/IOS)
        None
    }

    /// Replace `&n=` with its throttling-deobfuscated value. Returns the URL unchanged on failure.
    pub async fn transform_n_param_in_url(&self, url: &str) -> String {
        url.to_owned()
    }

    /// Self-heal after a 403 on a deciphered URL: refresh config table + invalidate player.js.
    pub async fn on_stream_rejected(&self) -> bool {
        let table_changed = self.config.refresh_after_stream_rejection().await;
        self.fetcher.invalidate();
        {
            let mut inner = self.inner.lock().await;
            inner.analyzed = false;
            inner.discovered = false;
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
        if cfg.is_none() {
            let config = self.config.clone();
            tokio::spawn(async move {
                config.force_refresh().await;
            });
        }

        let sts = cfg.as_ref().and_then(|c| c.sts).or_else(|| extractor::extract_sts(&player.js));

        let mut inner = self.inner.lock().await;
        inner.sts = sts;
        inner.built_epoch = epoch;
        inner.analyzed = true;
        inner.discovered = true;
        inner.last_used = Some(Instant::now());
        tracing::info!(hash = player.hash, ?sts, "cipher: analysis complete");
        Ok(())
    }
}
