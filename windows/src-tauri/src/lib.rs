use std::sync::{Arc, Mutex, RwLock};
use std::sync::atomic::{AtomicU64, Ordering};
use tauri::{Emitter, Manager};

mod queue;
use queue::{QueueEntryDto, QueueSourceDto, QueueStateDto};

#[cfg(target_os = "windows")]
mod session_store;
#[cfg(target_os = "windows")]
mod session;

#[derive(Debug, Clone, serde::Serialize, serde::Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct AuthStatusDto {
    pub state: String,
    pub name: Option<String>,
    pub email: Option<String>,
    pub thumbnail: Option<String>,
    pub message: Option<String>,
}

impl AuthStatusDto {
    fn guest() -> Self {
        Self { state: "guest".into(), name: None, email: None, thumbnail: None, message: None }
    }
    fn authorizing() -> Self {
        Self { state: "authorizing".into(), ..Self::guest() }
    }
    fn ready(info: sideb_core::AccountInfoRecord) -> Self {
        Self { state: "ready".into(), name: info.name, email: info.email, thumbnail: info.thumbnail, message: None }
    }
    fn error(message: &str) -> Self {
        Self { state: "error".into(), message: Some(message.into()), ..Self::guest() }
    }
}

pub struct PlaybackManager {
    pub is_playing: bool,
    pub is_loading: bool,
    pub is_ended: bool,
    pub position: f64,
    pub duration: f64,
    pub volume: f64,
    pub current_track: Option<PlaybackTrackDto>,
    pub error: Option<String>,
    pub generation: u64,
    pub loaded_generation: Option<u64>,
    pub queue: QueueStateDto,
}

impl PlaybackManager {
    pub fn new() -> Self {
        Self {
            is_playing: false,
            is_loading: false,
            is_ended: false,
            position: 0.0,
            duration: 0.0,
            volume: 100.0,
            current_track: None,
            error: None,
            generation: 0,
            loaded_generation: None,
            queue: QueueStateDto::default(),
        }
    }

    pub fn to_dto(&self) -> PlaybackStateDto {
        PlaybackStateDto {
            is_playing: self.is_playing,
            is_loading: self.is_loading,
            is_ended: self.is_ended,
            position: self.position,
            duration: self.duration,
            volume: self.volume,
            current_track: self.current_track.clone(),
            error: self.error.clone(),
            generation: self.generation,
            queue: self.queue.clone(),
        }
    }
}

pub struct AppState {
    pub core: RwLock<Option<Arc<sideb_core::SideBCore>>>,
    pub init_error: RwLock<Option<String>>,
    pub player: RwLock<Option<Arc<player::Player>>>,
    pub player_error: RwLock<Option<String>>,
    pub playback: Arc<Mutex<PlaybackManager>>,
    pub auth: RwLock<AuthStatusDto>,
    pub auth_generation: AtomicU64,
    pub auth_operation: tokio::sync::Mutex<()>,
}

fn set_auth_status(app: &tauri::AppHandle, status: AuthStatusDto) {
    let state = app.state::<AppState>();
    if let Ok(mut lock) = state.auth.write() {
        *lock = status.clone();
    }
    let _ = app.emit("auth-status-changed", status);
}

fn auth_generation(app: &tauri::AppHandle) -> u64 {
    app.state::<AppState>().auth_generation.load(Ordering::SeqCst)
}

#[tauri::command]
fn get_auth_status(state: tauri::State<'_, AppState>) -> Result<AuthStatusDto, CommandError> {
    state.auth.read().map(|status| status.clone())
        .map_err(|_| CommandError::new("AUTH_STATE_ERROR", "No se pudo leer el estado de la sesión."))
}

#[cfg(target_os = "windows")]
#[tauri::command]
// Keep this command async: WebViewWindowBuilder can deadlock Windows when invoked from a
// synchronous Tauri command (the blank, unclosable login window seen in W12).
async fn login_webview(app: tauri::AppHandle) -> Result<(), CommandError> {
    session::open_login(app)
        .map_err(|message| CommandError::new("LOGIN_WINDOW_ERROR", message))
}

#[cfg(target_os = "windows")]
#[tauri::command]
async fn cancel_login(app: tauri::AppHandle, state: tauri::State<'_, AppState>) -> Result<AuthStatusDto, CommandError> {
    state.auth_generation.fetch_add(1, Ordering::SeqCst);
    set_auth_status(&app, AuthStatusDto::guest());
    session::close_login_window(&app)
        .map_err(|message| CommandError::new("LOGIN_WINDOW_ERROR", message))?;
    Ok(AuthStatusDto::guest())
}

#[cfg(target_os = "windows")]
#[tauri::command]
async fn sign_out(app: tauri::AppHandle, state: tauri::State<'_, AppState>) -> Result<AuthStatusDto, CommandError> {
    state.auth_generation.fetch_add(1, Ordering::SeqCst);
    let _auth_operation = state.auth_operation.lock().await;
    let dir = app.path().app_data_dir()
        .map_err(|_| CommandError::new("STORAGE_ERROR", "No se pudo resolver el almacén de sesión."))?;
    session_store::delete(&dir)
        .map_err(|message| CommandError::new("STORAGE_ERROR", message))?;
    let core = state.core.read().map_err(|_| CommandError::new("AUTH_STATE_ERROR", "No se pudo cerrar la sesión."))?.clone();
    if let Some(core) = core { core.set_cookie_memory(None); }
    if let Ok(Some(player)) = state.player.read().map(|lock| lock.clone()) {
        let _ = player.stop();
        let _ = player.clear_playlist();
    }
    if let Ok(mut playback) = state.playback.lock() {
        playback.generation += 1;
        playback.loaded_generation = None;
        playback.is_playing = false;
        playback.is_loading = false;
        playback.is_ended = false;
        playback.position = 0.0;
        playback.duration = 0.0;
        playback.current_track = None;
        playback.error = None;
        playback.queue = QueueStateDto::default();
        let _ = app.emit("playback-state-changed", playback.to_dto());
    }
    set_auth_status(&app, AuthStatusDto::guest());
    session::clear_login_cookies(&app).await
        .map_err(|message| CommandError::new("PROFILE_CLEANUP_ERROR", message))?;
    Ok(AuthStatusDto::guest())
}

#[derive(Debug, Clone, serde::Serialize, serde::Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct PlaybackTrackDto {
    pub video_id: String,
    pub title: String,
    pub artists: String,
    pub thumbnail: Option<String>,
    pub duration: Option<f64>,
}

#[derive(Debug, Clone, serde::Serialize, serde::Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct PlaybackStateDto {
    pub is_playing: bool,
    pub is_loading: bool,
    pub is_ended: bool,
    pub position: f64,
    pub duration: f64,
    pub volume: f64,
    pub current_track: Option<PlaybackTrackDto>,
    pub error: Option<String>,
    pub generation: u64,
    pub queue: QueueStateDto,
}

#[derive(Debug, Clone, serde::Serialize, serde::Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct PlaybackProgressDto {
    pub position: f64,
    pub duration: f64,
    pub generation: u64,
}

#[derive(Debug, Clone, serde::Serialize, serde::Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct SongDto {
    pub video_id: String,
    pub title: String,
    pub artists: String,
    pub album: Option<String>,
    pub duration: Option<String>,
    pub thumbnail: Option<String>,
    pub is_video: bool,
    pub artist_id: Option<String>,
    pub album_id: Option<String>,
    pub set_video_id: Option<String>,
    pub library: Option<LibraryToggleDto>,
}

#[derive(Debug, Clone, serde::Serialize, serde::Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct LibraryToggleDto { pub in_library: bool, pub add_token: Option<String>, pub remove_token: Option<String> }

impl From<sideb_core::SongItemRecord> for SongDto {
    fn from(r: sideb_core::SongItemRecord) -> Self {
        Self {
            video_id: r.video_id,
            title: r.title,
            artists: r.artists,
            album: r.album,
            duration: r.duration,
            thumbnail: r.thumbnail,
            is_video: r.is_video,
            artist_id: r.artist_id,
            album_id: r.album_id,
            set_video_id: r.set_video_id,
            library: r.library.map(|v| LibraryToggleDto { in_library: v.in_library, add_token: v.add_token, remove_token: v.remove_token }),
        }
    }
}

#[derive(Debug, Clone, serde::Serialize, serde::Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct AlbumCardDto {
    pub id: String,
    pub title: String,
    pub subtitle: Option<String>,
    pub thumbnail: Option<String>,
}

impl From<sideb_core::BrowseCardRecord> for AlbumCardDto {
    fn from(r: sideb_core::BrowseCardRecord) -> Self {
        Self {
            id: r.id,
            title: r.title,
            subtitle: r.subtitle,
            thumbnail: r.thumbnail,
        }
    }
}

#[derive(Debug, Clone, serde::Serialize, serde::Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct AlbumDetailDto {
    pub browse_id: String,
    pub title: String,
    pub artist: Option<String>,
    pub subtitle: Option<String>,
    pub second_subtitle: Option<String>,
    pub description: Option<String>,
    pub thumbnail: Option<String>,
    pub items: Vec<SongDto>,
    pub artist_id: Option<String>,
    pub playlist_id: Option<String>,
    pub in_library: bool,
    pub sections: Vec<ArtistCarouselDto>,
}

impl From<sideb_core::AlbumDetailRecord> for AlbumDetailDto {
    fn from(r: sideb_core::AlbumDetailRecord) -> Self {
        Self {
            browse_id: r.browse_id,
            title: r.title,
            artist: r.artist,
            subtitle: r.subtitle,
            second_subtitle: r.second_subtitle,
            description: r.description,
            thumbnail: r.thumbnail,
            items: r.items.into_iter().map(SongDto::from).collect(),
            artist_id: r.artist_id,
            playlist_id: r.playlist_id,
            in_library: r.in_library,
            sections: r.sections.into_iter().map(ArtistCarouselDto::from).collect(),
        }
    }
}

#[derive(Debug, Clone, serde::Serialize, serde::Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct HomeChipDto {
    pub title: String,
    pub params: String,
}

impl From<sideb_core::HomeChipRecord> for HomeChipDto {
    fn from(c: sideb_core::HomeChipRecord) -> Self {
        Self {
            title: c.title,
            params: c.params,
        }
    }
}

#[derive(Debug, Clone, serde::Serialize, serde::Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct HomeItemDto {
    pub kind: String,
    pub id: String,
    pub title: String,
    pub subtitle: Option<String>,
    pub thumbnail: Option<String>,
    pub duration: Option<String>,
    pub artists: Option<String>,
    pub album_id: Option<String>,
    pub artist_id: Option<String>,
    pub album: Option<String>,
    pub artist_runs: Vec<HomeArtistRunDto>,
    pub explicit: bool,
}

impl From<sideb_core::HomeItemRecord> for HomeItemDto {
    fn from(i: sideb_core::HomeItemRecord) -> Self {
        Self {
            kind: i.kind,
            id: i.id,
            title: i.title,
            subtitle: i.subtitle,
            thumbnail: i.thumbnail,
            duration: i.duration,
            artists: i.artists,
            album_id: i.album_id,
            artist_id: i.artist_id,
            album: i.album,
            artist_runs: i.artist_runs.into_iter().map(HomeArtistRunDto::from).collect(),
            explicit: i.explicit,
        }
    }
}

#[derive(Debug, Clone, serde::Serialize, serde::Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct HomeSectionDto {
    pub title: String,
    pub format: String,
    pub items: Vec<HomeItemDto>,
    pub more_browse_id: Option<String>,
    pub more_params: Option<String>,
}

impl From<sideb_core::HomeSectionRecord> for HomeSectionDto {
    fn from(s: sideb_core::HomeSectionRecord) -> Self {
        let format_str = match s.format {
            sideb_core::HomeSectionFormatRecord::LargeCards => "largeCards",
            sideb_core::HomeSectionFormatRecord::CompactSongs => "compactSongs",
            sideb_core::HomeSectionFormatRecord::Mixed => "mixed",
        };
        Self {
            title: s.title,
            format: format_str.to_string(),
            items: s.items.into_iter().map(HomeItemDto::from).collect(),
            more_browse_id: s.more_browse_id,
            more_params: s.more_params,
        }
    }
}

#[derive(Debug, Clone, serde::Serialize, serde::Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct HomePageDto {
    pub chips: Vec<HomeChipDto>,
    pub sections: Vec<HomeSectionDto>,
    pub continuation: Option<String>,
}

impl From<sideb_core::HomePageRecord> for HomePageDto {
    fn from(p: sideb_core::HomePageRecord) -> Self {
        Self {
            chips: p.chips.into_iter().map(HomeChipDto::from).collect(),
            sections: p.sections.into_iter().map(HomeSectionDto::from).collect(),
            continuation: p.continuation,
        }
    }
}

#[derive(Debug, Clone, serde::Serialize, serde::Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct HomeArtistRunDto { pub text: String, pub id: Option<String> }
impl From<sideb_core::HomeArtistRunRecord> for HomeArtistRunDto {
    fn from(r: sideb_core::HomeArtistRunRecord) -> Self { Self { text: r.text, id: r.id } }
}

#[derive(Debug, Clone, serde::Serialize, serde::Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct BrowseCardDto { pub kind: String, pub id: String, pub title: String, pub subtitle: Option<String>, pub thumbnail: Option<String>, pub duration: Option<String> }
impl From<sideb_core::BrowseCardRecord> for BrowseCardDto {
    fn from(r: sideb_core::BrowseCardRecord) -> Self { Self { kind: r.kind, id: r.id, title: r.title, subtitle: r.subtitle, thumbnail: r.thumbnail, duration: r.duration } }
}

#[derive(Debug, Clone, serde::Serialize, serde::Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct ArtistCarouselDto { pub title: String, pub items: Vec<BrowseCardDto>, pub more_browse_id: Option<String>, pub more_params: Option<String> }
impl From<sideb_core::ArtistCarouselRecord> for ArtistCarouselDto {
    fn from(r: sideb_core::ArtistCarouselRecord) -> Self { Self { title: r.title, items: r.items.into_iter().map(BrowseCardDto::from).collect(), more_browse_id: r.more_browse_id, more_params: r.more_params } }
}

#[derive(Debug, Clone, serde::Serialize, serde::Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct ArtistDetailDto {
    pub channel_id: String, pub name: String, pub thumbnail: Option<String>, pub description: Option<String>,
    pub subscribers: Option<String>, pub monthly_listeners: Option<String>, pub subscribed: bool,
    pub radio_playlist_id: Option<String>, pub top_songs: Vec<SongDto>, pub top_songs_id: Option<String>, pub sections: Vec<ArtistCarouselDto>,
}
impl From<sideb_core::ArtistDetailRecord> for ArtistDetailDto {
    fn from(r: sideb_core::ArtistDetailRecord) -> Self { Self {
        channel_id: r.channel_id, name: r.name, thumbnail: r.thumbnail, description: r.description,
        subscribers: r.subscribers, monthly_listeners: r.monthly_listeners, subscribed: r.subscribed,
        radio_playlist_id: r.radio_playlist_id, top_songs: r.top_songs.into_iter().map(SongDto::from).collect(),
        top_songs_id: r.top_songs_id, sections: r.sections.into_iter().map(ArtistCarouselDto::from).collect(),
    } }
}

#[derive(Debug, Clone, serde::Serialize, serde::Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct PlaylistDetailDto { pub id: String, pub title: String, pub subtitle: Option<String>, pub thumbnail: Option<String>, pub description: Option<String>, pub items: Vec<SongDto>, pub continuation: Option<String>, pub owned: bool, pub in_library: bool, pub privacy: Option<String>, pub collaborative: bool, pub sort: Option<String>, pub sort_editable: bool }
impl From<sideb_core::PlaylistDetailRecord> for PlaylistDetailDto {
    fn from(r: sideb_core::PlaylistDetailRecord) -> Self { Self { id: r.id, title: r.title, subtitle: r.subtitle, thumbnail: r.thumbnail, description: r.description, items: r.items.into_iter().map(SongDto::from).collect(), continuation: r.continuation, owned: r.owned, in_library: r.in_library, privacy: r.privacy, collaborative: r.collaborative, sort: r.sort, sort_editable: r.sort_editable } }
}

#[derive(Debug, Clone, serde::Serialize, serde::Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct HistoryGroupDto { pub title: String, pub items: Vec<SongDto> }
impl From<sideb_core::HistoryGroupRecord> for HistoryGroupDto { fn from(r: sideb_core::HistoryGroupRecord) -> Self { Self { title: r.title, items: r.items.into_iter().map(SongDto::from).collect() } } }

#[derive(Debug, Clone, serde::Serialize, serde::Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct BackendStatusDto {
    pub ready: bool,
    pub status: String,
}

#[derive(Debug, Clone, serde::Serialize, serde::Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct CommandError {
    pub code: String,
    pub message: String,
}

impl CommandError {
    pub fn new(code: impl Into<String>, message: impl Into<String>) -> Self {
        Self {
            code: code.into(),
            message: message.into(),
        }
    }
}

fn parse_duration_to_seconds(s: &str) -> Option<f64> {
    if let Ok(sec) = s.parse::<f64>() {
        return Some(sec);
    }
    let parts: Vec<&str> = s.split(':').collect();
    if parts.len() == 2 {
        let m = parts[0].trim().parse::<f64>().ok()?;
        let s = parts[1].trim().parse::<f64>().ok()?;
        Some(m * 60.0 + s)
    } else if parts.len() == 3 {
        let h = parts[0].trim().parse::<f64>().ok()?;
        let m = parts[1].trim().parse::<f64>().ok()?;
        let s = parts[2].trim().parse::<f64>().ok()?;
        Some(h * 3600.0 + m * 60.0 + s)
    } else {
        None
    }
}

#[tauri::command]
fn get_backend_status(
    state: tauri::State<'_, AppState>,
) -> Result<BackendStatusDto, CommandError> {
    let core_opt = state.core.read().map_err(|_| {
        CommandError::new("LOCK_ERROR", "Error de concurrencia al leer el estado del core.")
    })?;

    if core_opt.is_some() {
        Ok(BackendStatusDto {
            ready: true,
            status: "Motor Side B conectado".to_string(),
        })
    } else {
        let err_guard = state.init_error.read().map_err(|_| {
            CommandError::new("LOCK_ERROR", "Error de concurrencia al leer el estado del core.")
        })?;
        let msg = err_guard
            .as_deref()
            .unwrap_or("Motor Side B no inicializado");
        Ok(BackendStatusDto {
            ready: false,
            status: msg.to_string(),
        })
    }
}

#[tauri::command]
fn retry_init_core(
    app: tauri::AppHandle,
    state: tauri::State<'_, AppState>,
) -> Result<BackendStatusDto, CommandError> {
    let app_data_dir = app.path().app_data_dir().map_err(|_| {
        CommandError::new(
            "STORAGE_ERROR",
            "No se pudo determinar el directorio de datos de la aplicación.",
        )
    })?;

    let data_dir_str = app_data_dir.to_string_lossy().to_string();
    match sideb_core::SideBCore::new_windows(data_dir_str) {
        Ok(core) => {
            let mut core_lock = state.core.write().map_err(|_| {
                CommandError::new("LOCK_ERROR", "Error de concurrencia al actualizar el core.")
            })?;
            let mut err_lock = state.init_error.write().map_err(|_| {
                CommandError::new("LOCK_ERROR", "Error de concurrencia al actualizar el core.")
            })?;
            *core_lock = Some(core);
            *err_lock = None;

            if let Some(core) = core_lock.clone() {
                tauri::async_runtime::spawn(session::restore(app.clone(), core.clone()));
                tauri::async_runtime::spawn(session::watch_rotations(app.clone(), core));
            }

            Ok(BackendStatusDto {
                ready: true,
                status: "Motor Side B conectado".to_string(),
            })
        }
        Err(_) => {
            let mut err_lock = state.init_error.write().map_err(|_| {
                CommandError::new("LOCK_ERROR", "Error de concurrencia al actualizar el core.")
            })?;
            *err_lock = Some("Error al inicializar el almacenamiento local de Side B.".to_string());
            Err(CommandError::new(
                "INIT_FAILED",
                "No se pudo inicializar el almacenamiento local de Side B.",
            ))
        }
    }
}

#[tauri::command]
async fn search_songs(
    state: tauri::State<'_, AppState>,
    query: String,
) -> Result<Vec<SongDto>, CommandError> {
    let trimmed = query.trim();
    if trimmed.is_empty() {
        return Err(CommandError::new(
            "EMPTY_QUERY",
            "La consulta de búsqueda no puede estar vacía.",
        ));
    }

    let core = {
        let lock = state.core.read().map_err(|_| {
            CommandError::new("LOCK_ERROR", "Error de concurrencia al acceder al motor.")
        })?;
        lock.clone().ok_or_else(|| {
            CommandError::new(
                "CORE_NOT_INITIALIZED",
                "El motor de Side B no está listo. Reintentá la inicialización.",
            )
        })?
    };

    match core.search_songs(trimmed.to_string(), false).await {
        Ok(results) => Ok(results.into_iter().map(SongDto::from).collect()),
        Err(_) => Err(CommandError::new(
            "SEARCH_FAILED",
            "No se pudo completar la búsqueda en YouTube Music. Comprobá tu conexión a internet.",
        )),
    }
}

#[tauri::command]
async fn search_albums(
    state: tauri::State<'_, AppState>,
    query: String,
) -> Result<Vec<AlbumCardDto>, CommandError> {
    let trimmed = query.trim();
    if trimmed.is_empty() {
        return Err(CommandError::new(
            "EMPTY_QUERY",
            "La consulta de búsqueda no puede estar vacía.",
        ));
    }

    let core = {
        let lock = state.core.read().map_err(|_| {
            CommandError::new("LOCK_ERROR", "Error de concurrencia al acceder al motor.")
        })?;
        lock.clone().ok_or_else(|| {
            CommandError::new(
                "CORE_NOT_INITIALIZED",
                "El motor de Side B no está listo. Reintentá la inicialización.",
            )
        })?
    };

    match core
        .search_cards(trimmed.to_string(), "albums".to_string())
        .await
    {
        Ok(results) => Ok(results.into_iter().map(AlbumCardDto::from).collect()),
        Err(_) => Err(CommandError::new(
            "SEARCH_FAILED",
            "No se pudo completar la búsqueda de álbumes en YouTube Music. Comprobá tu conexión a internet.",
        )),
    }
}

#[tauri::command]
async fn get_album(
    state: tauri::State<'_, AppState>,
    browse_id: String,
) -> Result<AlbumDetailDto, CommandError> {
    let trimmed = browse_id.trim();
    if trimmed.is_empty() {
        return Err(CommandError::new(
            "INVALID_ID",
            "El identificador de álbum no puede estar vacío.",
        ));
    }

    let core = {
        let lock = state.core.read().map_err(|_| {
            CommandError::new("LOCK_ERROR", "Error de concurrencia al acceder al motor.")
        })?;
        lock.clone().ok_or_else(|| {
            CommandError::new(
                "CORE_NOT_INITIALIZED",
                "El motor de Side B no está listo. Reintentá la inicialización.",
            )
        })?
    };

    match core.get_album(trimmed.to_string()).await {
        Ok(record) => Ok(AlbumDetailDto::from(record)),
        Err(_) => Err(CommandError::new(
            "ALBUM_FAILED",
            "No se pudo cargar el detalle del álbum. Comprobá tu conexión a internet o el identificador.",
        )),
    }
}

#[tauri::command]
async fn get_home_page(
    state: tauri::State<'_, AppState>,
    chip_params: Option<String>,
) -> Result<HomePageDto, CommandError> {
    let core = {
        let lock = state.core.read().map_err(|_| {
            CommandError::new("LOCK_ERROR", "Error de concurrencia al acceder al motor.")
        })?;
        lock.clone().ok_or_else(|| {
            CommandError::new(
                "CORE_NOT_INITIALIZED",
                "El motor de Side B no está listo. Reintentá la inicialización.",
            )
        })?
    };

    let params = chip_params.and_then(|p| {
        let trimmed = p.trim().to_string();
        if trimmed.is_empty() {
            None
        } else {
            Some(trimmed)
        }
    });

    match core.get_home_page(params).await {
        Ok(page) => Ok(HomePageDto::from(page)),
        Err(_) => Err(CommandError::new(
            "HOME_FAILED",
            "No se pudo cargar la página de inicio de YouTube Music. Comprobá tu conexión a internet.",
        )),
    }
}

#[tauri::command]
async fn get_home_continuation(state: tauri::State<'_, AppState>, token: String) -> Result<HomePageDto, CommandError> {
    let token = token.trim();
    if token.is_empty() { return Err(CommandError::new("INVALID_TOKEN", "El token de continuación no puede estar vacío.")); }
    let core = state.core.read().map_err(|_| CommandError::new("LOCK_ERROR", "Error de concurrencia al acceder al motor."))?.clone()
        .ok_or_else(|| CommandError::new("CORE_NOT_INITIALIZED", "El motor de Side B no está listo. Reintentá la inicialización."))?;
    core.get_home_continuation(token.to_owned()).await.map(HomePageDto::from)
        .map_err(|_| CommandError::new("HOME_FAILED", "No se pudo cargar más contenido de Inicio. Comprobá tu conexión a internet."))
}

#[tauri::command]
async fn get_artist(state: tauri::State<'_, AppState>, browse_id: String) -> Result<ArtistDetailDto, CommandError> {
    let id = browse_id.trim();
    if id.is_empty() { return Err(CommandError::new("INVALID_ID", "El identificador del artista no puede estar vacío.")); }
    let core = state.core.read().map_err(|_| CommandError::new("LOCK_ERROR", "Error de concurrencia al acceder al motor."))?.clone()
        .ok_or_else(|| CommandError::new("CORE_NOT_INITIALIZED", "El motor de Side B no está listo. Reintentá la inicialización."))?;
    core.get_artist(id.to_owned()).await.map(ArtistDetailDto::from)
        .map_err(|_| CommandError::new("ARTIST_FAILED", "No se pudo cargar el perfil del artista. Comprobá tu conexión a internet o el identificador."))
}

#[tauri::command]
async fn get_browse_grid(state: tauri::State<'_, AppState>, browse_id: String, params: Option<String>) -> Result<Vec<BrowseCardDto>, CommandError> {
    let id = browse_id.trim();
    if id.is_empty() { return Err(CommandError::new("INVALID_ID", "El identificador de la sección no puede estar vacío.")); }
    let params = params.and_then(|p| { let p = p.trim().to_owned(); (!p.is_empty()).then_some(p) });
    let core = state.core.read().map_err(|_| CommandError::new("LOCK_ERROR", "Error de concurrencia al acceder al motor."))?.clone()
        .ok_or_else(|| CommandError::new("CORE_NOT_INITIALIZED", "El motor de Side B no está listo. Reintentá la inicialización."))?;
    core.get_browse_grid(id.to_owned(), params).await.map(|items| items.into_iter().map(BrowseCardDto::from).collect())
        .map_err(|_| CommandError::new("BROWSE_FAILED", "No se pudo cargar esta sección. Comprobá tu conexión a internet."))
}

#[tauri::command]
async fn get_playlist(state: tauri::State<'_, AppState>, playlist_id: String) -> Result<PlaylistDetailDto, CommandError> {
    let id = playlist_id.trim();
    if id.is_empty() { return Err(CommandError::new("INVALID_ID", "El identificador de la lista no puede estar vacío.")); }
    if matches!(id.to_ascii_uppercase().as_str(), "LM" | "VLLM") {
        let generation = state.auth_generation.load(Ordering::SeqCst);
        let _operation = state.auth_operation.lock().await;
        let core = account_core(&state, generation)?;
        let result = core.get_playlist(id.to_owned()).await.map(PlaylistDetailDto::from)
            .map_err(|_| CommandError::new("PLAYLIST_FAILED", "No se pudo cargar la lista. Comprobá tu conexión a internet o el identificador."))?;
        if state.auth_generation.load(Ordering::SeqCst) != generation { return Err(CommandError::new("SESSION_CHANGED", "La sesión cambió durante la operación.")); }
        return Ok(result);
    }
    let core = state.core.read().map_err(|_| CommandError::new("LOCK_ERROR", "Error de concurrencia al acceder al motor."))?.clone()
        .ok_or_else(|| CommandError::new("CORE_NOT_INITIALIZED", "El motor de Side B no está listo. Reintentá la inicialización."))?;
    core.get_playlist(id.to_owned()).await.map(PlaylistDetailDto::from)
        .map_err(|_| CommandError::new("PLAYLIST_FAILED", "No se pudo cargar la lista. Comprobá tu conexión a internet o el identificador."))
}

/// Load the same initial artist-radio queue that macOS gets from getNext(nil, playlistId).
/// The returned first song is the queue's first/current candidate; the frontend owns playback.
#[tauri::command]
async fn get_artist_radio(state: tauri::State<'_, AppState>, playlist_id: String) -> Result<Vec<SongDto>, CommandError> {
    let id = playlist_id.trim();
    if id.is_empty() { return Err(CommandError::new("INVALID_ID", "El identificador de radio no puede estar vacío.")); }
    let core = state.core.read().map_err(|_| CommandError::new("LOCK_ERROR", "Error de concurrencia al acceder al motor."))?.clone()
        .ok_or_else(|| CommandError::new("CORE_NOT_INITIALIZED", "El motor de Side B no está listo. Reintentá la inicialización."))?;
    core.get_next(None, Some(id.to_owned())).await
        .map(|result| result.items.into_iter().map(SongDto::from).collect())
        .map_err(|_| CommandError::new("ARTIST_RADIO_FAILED", "No se pudo cargar la radio del artista. Comprobá tu conexión a internet."))
}

fn account_core(state: &AppState, generation: u64) -> Result<Arc<sideb_core::SideBCore>, CommandError> {
    if state.auth_generation.load(Ordering::SeqCst) != generation {
        return Err(CommandError::new("SESSION_CHANGED", "La sesión cambió durante la operación."));
    }
    let ready = state.auth.read().map(|a| a.state == "ready")
        .map_err(|_| CommandError::new("AUTH_STATE_ERROR", "No se pudo comprobar el estado de la sesión."))?;
    if !ready { return Err(CommandError::new("AUTH_REQUIRED", "Iniciá sesión para acceder a tu biblioteca.")); }
    state.core.read().map_err(|_| CommandError::new("LOCK_ERROR", "Error de concurrencia al acceder al motor."))?.clone()
        .ok_or_else(|| CommandError::new("CORE_NOT_INITIALIZED", "El motor de Side B no está listo. Reintentá la inicialización."))
}

#[tauri::command]
async fn get_library_playlists(state: tauri::State<'_, AppState>) -> Result<Vec<BrowseCardDto>, CommandError> {
    let generation = state.auth_generation.load(Ordering::SeqCst);
    let _operation = state.auth_operation.lock().await;
    let core = account_core(&state, generation)?;
    let result = core.get_library_playlists().await.map(|v| v.into_iter().map(BrowseCardDto::from).collect())
        .map_err(|_| CommandError::new("LIBRARY_FAILED", "No se pudieron cargar tus playlists."))?;
    if state.auth_generation.load(Ordering::SeqCst) != generation { return Err(CommandError::new("SESSION_CHANGED", "La sesión cambió durante la operación.")); }
    Ok(result)
}

#[tauri::command]
async fn get_library_albums(state: tauri::State<'_, AppState>) -> Result<Vec<BrowseCardDto>, CommandError> {
    let generation = state.auth_generation.load(Ordering::SeqCst);
    let _operation = state.auth_operation.lock().await;
    let core = account_core(&state, generation)?;
    let result = core.get_library_albums().await.map(|v| v.into_iter().map(BrowseCardDto::from).collect())
        .map_err(|_| CommandError::new("LIBRARY_FAILED", "No se pudieron cargar tus álbumes."))?;
    if state.auth_generation.load(Ordering::SeqCst) != generation { return Err(CommandError::new("SESSION_CHANGED", "La sesión cambió durante la operación.")); }
    Ok(result)
}

#[tauri::command]
async fn get_library_artists(state: tauri::State<'_, AppState>) -> Result<Vec<BrowseCardDto>, CommandError> {
    let generation = state.auth_generation.load(Ordering::SeqCst);
    let _operation = state.auth_operation.lock().await;
    let core = account_core(&state, generation)?;
    let result = core.get_library_artists().await.map(|v| v.into_iter().map(BrowseCardDto::from).collect())
        .map_err(|_| CommandError::new("LIBRARY_FAILED", "No se pudieron cargar tus artistas."))?;
    if state.auth_generation.load(Ordering::SeqCst) != generation { return Err(CommandError::new("SESSION_CHANGED", "La sesión cambió durante la operación.")); }
    Ok(result)
}

#[tauri::command]
async fn get_library_songs(state: tauri::State<'_, AppState>) -> Result<PlaylistContinuationDto, CommandError> {
    let generation = state.auth_generation.load(Ordering::SeqCst);
    let _operation = state.auth_operation.lock().await;
    let core = account_core(&state, generation)?;
    let result = core.get_library_songs().await.map(PlaylistContinuationDto::from)
        .map_err(|_| CommandError::new("LIBRARY_FAILED", "No se pudieron cargar tus canciones."))?;
    if state.auth_generation.load(Ordering::SeqCst) != generation { return Err(CommandError::new("SESSION_CHANGED", "La sesión cambió durante la operación.")); }
    Ok(result)
}

#[derive(Debug, Clone, serde::Serialize, serde::Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct PlaylistContinuationDto { pub items: Vec<SongDto>, pub continuation: Option<String> }
impl From<sideb_core::PlaylistContinuationRecord> for PlaylistContinuationDto { fn from(r: sideb_core::PlaylistContinuationRecord) -> Self { Self { items: r.items.into_iter().map(SongDto::from).collect(), continuation: r.continuation } } }

#[tauri::command]
async fn get_playlist_continuation(state: tauri::State<'_, AppState>, token: String) -> Result<PlaylistContinuationDto, CommandError> {
    let token = token.trim();
    if token.is_empty() { return Err(CommandError::new("INVALID_TOKEN", "El token de continuación no puede estar vacío.")); }
    let generation = state.auth_generation.load(Ordering::SeqCst);
    let _operation = state.auth_operation.lock().await;
    if state.auth_generation.load(Ordering::SeqCst) != generation { return Err(CommandError::new("SESSION_CHANGED", "La sesión cambió durante la operación.")); }
    let core = state.core.read().map_err(|_| CommandError::new("LOCK_ERROR", "Error de concurrencia al acceder al motor."))?.clone()
        .ok_or_else(|| CommandError::new("CORE_NOT_INITIALIZED", "El motor de Side B no está listo. Reintentá la inicialización."))?;
    let result = core.get_playlist_continuation(token.to_owned()).await.map(PlaylistContinuationDto::from)
        .map_err(|_| CommandError::new("CONTINUATION_FAILED", "No se pudieron cargar más canciones."))?;
    if state.auth_generation.load(Ordering::SeqCst) != generation { return Err(CommandError::new("SESSION_CHANGED", "La sesión cambió durante la operación.")); }
    Ok(result)
}

#[tauri::command]
async fn get_history(state: tauri::State<'_, AppState>) -> Result<Vec<HistoryGroupDto>, CommandError> {
    let generation = state.auth_generation.load(Ordering::SeqCst);
    let _operation = state.auth_operation.lock().await;
    if state.auth_generation.load(Ordering::SeqCst) != generation { return Err(CommandError::new("SESSION_CHANGED", "La sesión cambió durante la operación.")); }
    let core = state.core.read().map_err(|_| CommandError::new("LOCK_ERROR", "Error de concurrencia al acceder al motor."))?.clone()
        .ok_or_else(|| CommandError::new("CORE_NOT_INITIALIZED", "El motor de Side B no está listo."))?;
    let result = core.get_history().await.map(|v| v.into_iter().map(HistoryGroupDto::from).collect())
        .map_err(|_| CommandError::new("HISTORY_FAILED", "No se pudo cargar el historial."))?;
    if state.auth_generation.load(Ordering::SeqCst) != generation { return Err(CommandError::new("SESSION_CHANGED", "La sesión cambió durante la operación.")); }
    Ok(result)
}

#[tauri::command]
async fn rate_song(state: tauri::State<'_, AppState>, video_id: String, rating: String) -> Result<(), CommandError> {
    let id = video_id.trim();
    if id.is_empty() { return Err(CommandError::new("INVALID_ID", "El identificador de canción no puede estar vacío.")); }
    let rating = rating.trim().to_ascii_uppercase();
    if !matches!(rating.as_str(), "LIKE" | "DISLIKE" | "INDIFFERENT") { return Err(CommandError::new("INVALID_RATING", "La valoración no es válida.")); }
    let generation = state.auth_generation.load(Ordering::SeqCst);
    let _operation = state.auth_operation.lock().await;
    let core = account_core(&state, generation)?;
    core.rate_song(id.to_owned(), rating).await.map_err(|_| CommandError::new("RATE_FAILED", "No se pudo actualizar Me Gusta."))?;
    if state.auth_generation.load(Ordering::SeqCst) != generation { return Err(CommandError::new("SESSION_CHANGED", "La sesión cambió durante la operación.")); }
    Ok(())
}

#[tauri::command]
async fn apply_song_library_action(state: tauri::State<'_, AppState>, token: String) -> Result<(), CommandError> {
    let token = token.trim();
    if token.is_empty() { return Err(CommandError::new("INVALID_ACTION", "La acción de biblioteca no es válida.")); }
    let generation = state.auth_generation.load(Ordering::SeqCst);
    let _operation = state.auth_operation.lock().await;
    let core = account_core(&state, generation)?;
    core.apply_song_library_action(token.to_owned()).await.map_err(|_| CommandError::new("LIBRARY_ACTION_FAILED", "No se pudo actualizar la biblioteca de la canción."))?;
    if state.auth_generation.load(Ordering::SeqCst) != generation { return Err(CommandError::new("SESSION_CHANGED", "La sesión cambió durante la operación.")); }
    Ok(())
}

#[tauri::command]
async fn create_playlist(state: tauri::State<'_, AppState>, title: String, description: String) -> Result<String, CommandError> {
    let title = title.trim();
    let description = description.trim();
    if title.is_empty() || title.len() > 150 || title.contains(['<', '>']) { return Err(CommandError::new("INVALID_TITLE", "El nombre de la playlist debe tener entre 1 y 150 caracteres válidos.")); }
    if description.len() > 5000 { return Err(CommandError::new("INVALID_DESCRIPTION", "La descripción es demasiado larga.")); }
    let generation = state.auth_generation.load(Ordering::SeqCst);
    let _operation = state.auth_operation.lock().await;
    let core = account_core(&state, generation)?;
    let id = core.create_playlist(title.to_owned(), description.to_owned(), "PRIVATE".into()).await
        .map_err(|_| CommandError::new("PLAYLIST_CREATE_FAILED", "No se pudo crear la playlist."))?;
    if state.auth_generation.load(Ordering::SeqCst) != generation { return Err(CommandError::new("SESSION_CHANGED", "La sesión cambió durante la operación.")); }
    Ok(id)
}

#[tauri::command]
async fn toggle_album_library(state: tauri::State<'_, AppState>, playlist_id: String, save: bool) -> Result<(), CommandError> {
    let id = playlist_id.trim();
    if id.is_empty() { return Err(CommandError::new("INVALID_ID", "El identificador del álbum no puede estar vacío.")); }
    let generation = state.auth_generation.load(Ordering::SeqCst);
    let _operation = state.auth_operation.lock().await;
    let core = account_core(&state, generation)?;
    core.like_playlist(id.to_owned(), save).await.map_err(|_| CommandError::new("ALBUM_LIBRARY_FAILED", "No se pudo actualizar la biblioteca del álbum."))?;
    if state.auth_generation.load(Ordering::SeqCst) != generation { return Err(CommandError::new("SESSION_CHANGED", "La sesión cambió durante la operación.")); }
    Ok(())
}

#[tauri::command]
async fn set_artist_subscription(state: tauri::State<'_, AppState>, channel_id: String, subscribe: bool) -> Result<(), CommandError> {
    let id = channel_id.trim();
    if id.is_empty() { return Err(CommandError::new("INVALID_ID", "El identificador del artista no puede estar vacío.")); }
    let generation = state.auth_generation.load(Ordering::SeqCst);
    let _operation = state.auth_operation.lock().await;
    let core = account_core(&state, generation)?;
    core.subscribe_artist(id.to_owned(), subscribe).await.map_err(|_| CommandError::new("ARTIST_SUBSCRIPTION_FAILED", "No se pudo actualizar la suscripción al artista."))?;
    if state.auth_generation.load(Ordering::SeqCst) != generation { return Err(CommandError::new("SESSION_CHANGED", "La sesión cambió durante la operación.")); }
    Ok(())
}

#[tauri::command]
async fn play_song(
    app: tauri::AppHandle,
    state: tauri::State<'_, AppState>,
    video_id: String,
    title: Option<String>,
    artists: Option<String>,
    thumbnail: Option<String>,
    queue_items: Option<Vec<QueueEntryDto>>,
    queue_current_index: Option<usize>,
    queue_source: Option<QueueSourceDto>,
    preserve_queue: Option<bool>,
    expected_generation: Option<u64>,
) -> Result<PlaybackStateDto, CommandError> {
    let trimmed_id = video_id.trim();
    if trimmed_id.is_empty() {
        return Err(CommandError::new(
            "EMPTY_ID",
            "El identificador de la canción no puede estar vacío.",
        ));
    }

    let core = {
        let lock = state.core.read().map_err(|_| {
            CommandError::new("LOCK_ERROR", "Error de concurrencia al acceder al motor.")
        })?;
        lock.clone().ok_or_else(|| {
            CommandError::new(
                "CORE_NOT_INITIALIZED",
                "El motor de Side B no está listo. Reintentá la inicialización.",
            )
        })?
    };

    let player = {
        let lock = state.player.read().map_err(|_| {
            CommandError::new("LOCK_ERROR", "Error de concurrencia al acceder al reproductor.")
        })?;
        lock.clone().ok_or_else(|| {
            let err_guard = state.player_error.read().ok();
            let msg = err_guard
                .as_deref()
                .and_then(|e| e.as_deref())
                .unwrap_or("El reproductor de audio no está listo.");
            CommandError::new("PLAYER_NOT_INITIALIZED", msg)
        })?
    };

    let my_gen = {
        let mut pb = state.playback.lock().map_err(|_| {
            CommandError::new("LOCK_ERROR", "Error de concurrencia al actualizar reproducción.")
        })?;
        // EOF schedules the next entry off the player event pump. A newer manual
        // selection must win even if that scheduled task starts later.
        if expected_generation.is_some_and(|expected| pb.generation != expected) {
            return Ok(pb.to_dto());
        }
        if let Some(items) = queue_items {
            let index = queue_current_index.unwrap_or(0);
            if items.get(index).map(|entry| entry.video_id.as_str()) != Some(trimmed_id) {
                return Err(CommandError::new("QUEUE_TRACK_MISMATCH", "La pista no coincide con la ocurrencia seleccionada."));
            }
            let source = queue_source.unwrap_or(QueueSourceDto { kind: "song".into(), id: Some(trimmed_id.into()), title: title.clone() });
            if pb.queue.replace(items, index, source).is_none() {
                return Err(CommandError::new("INVALID_QUEUE", "La posición inicial no pertenece a la cola."));
            }
        } else if let Some(index) = queue_current_index {
            if pb.queue.items.get(index).map(|entry| entry.video_id.as_str()) != Some(trimmed_id) {
                return Err(CommandError::new("QUEUE_TRACK_MISMATCH", "La pista no coincide con la ocurrencia seleccionada."));
            }
            pb.queue.select(index).ok_or_else(|| CommandError::new("INVALID_QUEUE_INDEX", "La pista ya no está en la cola."))?;
        } else if preserve_queue != Some(true) {
            let entry = QueueEntryDto::new(trimmed_id.to_owned(), title.clone().unwrap_or_else(|| "Canción".into()), artists.clone().unwrap_or_default(), thumbnail.clone(), None);
            let _ = pb.queue.replace(vec![entry], 0, QueueSourceDto { kind: "song".into(), id: Some(trimmed_id.into()), title: title.clone() });
        }
        let active_entry = pb.queue.current().ok_or_else(|| {
            CommandError::new("INVALID_QUEUE", "No hay una pista activa en la cola.")
        })?;
        if active_entry.video_id != trimmed_id {
            return Err(CommandError::new("QUEUE_TRACK_MISMATCH", "La pista no coincide con la ocurrencia seleccionada."));
        }
        // Serializar parada y anuncio con la carga de otros play_song. Si se detiene fuera
        // de este cerrojo, una petición anterior puede cargar después de la parada y
        // seguir sonando mientras la nueva todavía se resuelve.
        player.stop().map_err(|_| {
            CommandError::new("STOP_FAILED", "No se pudo detener la pista anterior.")
        })?;
        if player.clear_playlist().is_err() {
            pb.loaded_generation = None;
            pb.is_playing = false;
            pb.is_loading = false;
            pb.error = Some("No se pudo preparar el reproductor para otra pista.".to_string());
            let _ = app.emit("playback-state-changed", &pb.to_dto());
            return Err(CommandError::new(
                "CLEAR_FAILED",
                "No se pudo preparar el reproductor para otra pista.",
            ));
        }
        pb.generation += 1;
        pb.loaded_generation = None;
        pb.is_loading = true;
        pb.is_playing = false;
        pb.is_ended = false;
        pb.position = 0.0;
        pb.duration = 0.0;
        pb.error = None;
        pb.current_track = Some(PlaybackTrackDto {
            video_id: trimmed_id.to_string(),
            title: active_entry.title,
            artists: active_entry.artists,
            thumbnail: active_entry.thumbnail,
            duration: None,
        });
        let dto = pb.to_dto();
        let _ = app.emit("playback-state-changed", &dto);
        pb.generation
    };

    let resolve_res = core.resolve_stream(trimmed_id.to_string(), false).await;

    let stream_info = match resolve_res {
        Ok(info) => info,
        Err(_) => {
            let mut pb = state.playback.lock().map_err(|_| {
                CommandError::new("LOCK_ERROR", "Error de concurrencia al actualizar reproducción.")
            })?;
            // Sólo registrar el error si este intento sigue siendo la selección más reciente
            if pb.generation == my_gen {
                pb.is_loading = false;
                pb.is_playing = false;
                pb.is_ended = false;
                pb.error = Some("No se pudo obtener el flujo de audio para esta pista.".to_string());
                pb.loaded_generation = None;
                let dto = pb.to_dto();
                let _ = app.emit("playback-state-changed", &dto);
            }
            return Err(CommandError::new(
                "STREAM_RESOLVE_FAILED",
                "No se pudo obtener el flujo de audio para esta canción.",
            ));
        }
    };

    let mut pb = state.playback.lock().map_err(|_| {
        CommandError::new("LOCK_ERROR", "Error de concurrencia al actualizar reproducción.")
    })?;
    if pb.generation != my_gen {
        return Ok(pb.to_dto());
    }

    let parsed_duration = stream_info
        .duration
        .as_deref()
        .and_then(parse_duration_to_seconds)
        .unwrap_or(0.0);

    let resolved_title = pb.current_track.as_ref().map(|t| t.title.clone())
        .filter(|title| !title.is_empty() && title != "Canción")
        .or_else(|| stream_info.title.clone()).unwrap_or_else(|| "Canción".to_string());
    let resolved_artists = pb.current_track.as_ref().map(|t| t.artists.clone())
        .filter(|artists| !artists.is_empty())
        .or_else(|| stream_info.artists.clone()).unwrap_or_default();
    // La portada de la ocurrencia elegida tiene prioridad; los metadatos del stream
    // pueden pertenecer a una versión/edición distinta del mismo video.
    let resolved_thumbnail = pb.current_track.as_ref().and_then(|t| t.thumbnail.clone())
        .or_else(|| stream_info.thumbnail.clone());

    // The queue row and the two now-playing surfaces must show the same metadata.
    // A stream response may fill gaps, but it never changes the selected occurrence.
    if let Some(index) = pb.queue.current_index {
        if let Some(entry) = pb.queue.items.get_mut(index) {
            if entry.video_id == trimmed_id {
                let resolved_duration = (parsed_duration > 0.0).then_some(parsed_duration).or(entry.duration);
                let changed = entry.title != resolved_title
                    || entry.artists != resolved_artists
                    || entry.thumbnail != resolved_thumbnail
                    || entry.duration != resolved_duration;
                entry.title = resolved_title.clone();
                entry.artists = resolved_artists.clone();
                entry.thumbnail = resolved_thumbnail.clone();
                entry.duration = resolved_duration;
                if changed { pb.queue.revision += 1; }
            }
        }
    }

    pb.current_track = Some(PlaybackTrackDto {
        video_id: trimmed_id.to_string(),
        title: resolved_title,
        artists: resolved_artists,
        thumbnail: resolved_thumbnail,
        duration: if parsed_duration > 0.0 {
            Some(parsed_duration)
        } else {
            None
        },
    });
    if parsed_duration > 0.0 {
        pb.duration = parsed_duration;
    }

    if player
        .load(&stream_info.stream_url, &stream_info.headers, stream_info.loudness_db)
        .is_err()
    {
        pb.is_loading = false;
        pb.is_playing = false;
        pb.is_ended = false;
        pb.error = Some("Error al cargar la pista en el motor de audio.".to_string());
        pb.loaded_generation = None;
        let dto = pb.to_dto();
        let _ = app.emit("playback-state-changed", &dto);
        return Err(CommandError::new(
            "LOAD_FAILED",
            "Error al cargar la pista en el motor de audio.",
        ));
    }

    if player.play().is_err() {
        pb.is_loading = false;
        pb.is_playing = false;
        pb.is_ended = false;
        pb.error = Some("Error al iniciar reproducción en el motor de audio.".to_string());
        pb.loaded_generation = None;
        let dto = pb.to_dto();
        let _ = app.emit("playback-state-changed", &dto);
        return Err(CommandError::new(
            "PLAY_FAILED",
            "Error al iniciar reproducción en el motor de audio.",
        ));
    }

    // Mantener is_loading = true e is_playing = false hasta recibir el evento real Playing(true).
    // Se activa loaded_generation para que sólo a partir de ahora se procesen eventos del motor para este intento.
    pb.is_loading = true;
    pb.is_playing = false;
    pb.is_ended = false;
    pb.error = None;
    pb.loaded_generation = Some(my_gen);
    let dto = pb.to_dto();
    let _ = app.emit("playback-state-changed", &dto);
    Ok(dto)
}

async fn start_queue_entry(app: tauri::AppHandle, index: usize, expected_generation: u64) -> Result<PlaybackStateDto, CommandError> {
    let state = app.state::<AppState>();
    let entry = {
        let playback = state.playback.lock().map_err(|_| CommandError::new("LOCK_ERROR", "No se pudo leer la cola."))?;
        if playback.generation != expected_generation { return Ok(playback.to_dto()); }
        playback.queue.items.get(index).cloned().ok_or_else(|| CommandError::new("INVALID_QUEUE_INDEX", "La pista ya no está en la cola."))?
    };
    play_song(
        app.clone(), state, entry.video_id, Some(entry.title), Some(entry.artists), entry.thumbnail,
        None, Some(index), None, Some(true), Some(expected_generation),
    ).await
}

#[tauri::command]
async fn next_track(app: tauri::AppHandle, state: tauri::State<'_, AppState>) -> Result<PlaybackStateDto, CommandError> {
    let (next, generation) = {
        let playback = state.playback.lock().map_err(|_| CommandError::new("LOCK_ERROR", "No se pudo leer la cola."))?;
        let next = playback.queue.current_index
            .and_then(|index| index.checked_add(1))
            .filter(|index| *index < playback.queue.items.len());
        (next, playback.generation)
    };
    match next { Some(index) => start_queue_entry(app, index, generation).await, None => get_playback_state(state).await }
}

#[tauri::command]
async fn previous_track(app: tauri::AppHandle, state: tauri::State<'_, AppState>) -> Result<PlaybackStateDto, CommandError> {
    let (target, generation) = {
        let playback = state.playback.lock().map_err(|_| CommandError::new("LOCK_ERROR", "No se pudo leer la cola."))?;
        let index = playback.queue.current_index.ok_or_else(|| CommandError::new("EMPTY_QUEUE", "No hay una pista activa en la cola."))?;
        let target = if playback.position > 3.0 || index == 0 { index } else { index - 1 };
        (target, playback.generation)
    };
    start_queue_entry(app, target, generation).await
}

#[tauri::command]
async fn pause_playback(
    app: tauri::AppHandle,
    state: tauri::State<'_, AppState>,
) -> Result<PlaybackStateDto, CommandError> {
    let player = {
        let lock = state.player.read().map_err(|_| {
            CommandError::new("LOCK_ERROR", "Error de concurrencia al acceder al reproductor.")
        })?;
        lock.clone().ok_or_else(|| {
            CommandError::new("PLAYER_NOT_INITIALIZED", "El reproductor de audio no está listo.")
        })?
    };

    let mut pb = state.playback.lock().map_err(|_| {
        CommandError::new("LOCK_ERROR", "Error de concurrencia al actualizar reproducción.")
    })?;

    // Bloquear si no hay pista efectivamente cargada, si está cargando, o si ya no está sonando
    if pb.loaded_generation.is_none() || pb.is_loading || !pb.is_playing || player.is_idle() {
        return Err(CommandError::new(
            "NOT_PLAYING",
            "No hay reproducción activa para pausar.",
        ));
    }

    player.pause().map_err(|_| {
        CommandError::new("PAUSE_FAILED", "No se pudo pausar la reproducción.")
    })?;

    pb.is_playing = false;
    let dto = pb.to_dto();
    let _ = app.emit("playback-state-changed", &dto);
    Ok(dto)
}

#[tauri::command]
async fn resume_playback(
    app: tauri::AppHandle,
    state: tauri::State<'_, AppState>,
) -> Result<PlaybackStateDto, CommandError> {
    let player = {
        let lock = state.player.read().map_err(|_| {
            CommandError::new("LOCK_ERROR", "Error de concurrencia al acceder al reproductor.")
        })?;
        lock.clone().ok_or_else(|| {
            CommandError::new("PLAYER_NOT_INITIALIZED", "El reproductor de audio no está listo.")
        })?
    };

    let mut pb = state.playback.lock().map_err(|_| {
        CommandError::new("LOCK_ERROR", "Error de concurrencia al actualizar reproducción.")
    })?;

    // Bloquear reanudar si no hay pista cargada, si está en carga, si finalizó o si hay error
    if pb.loaded_generation.is_none() || pb.is_loading || pb.is_ended || pb.error.is_some() || player.is_idle() {
        return Err(CommandError::new(
            "IDLE_PLAYER",
            "La pista ha finalizado, está cargando o no hay reproducción activa para reanudar.",
        ));
    }

    player.play().map_err(|_| {
        CommandError::new("RESUME_FAILED", "No se pudo reanudar la reproducción.")
    })?;

    pb.is_playing = true;
    pb.is_ended = false;
    let dto = pb.to_dto();
    let _ = app.emit("playback-state-changed", &dto);
    Ok(dto)
}

#[tauri::command]
async fn seek_playback(
    app: tauri::AppHandle,
    state: tauri::State<'_, AppState>,
    seconds: f64,
) -> Result<PlaybackStateDto, CommandError> {
    if !seconds.is_finite() || seconds < 0.0 {
        return Err(CommandError::new(
            "INVALID_SEEK",
            "La posición de seek debe ser un número finito no negativo.",
        ));
    }

    let player = {
        let lock = state.player.read().map_err(|_| {
            CommandError::new("LOCK_ERROR", "Error de concurrencia al acceder al reproductor.")
        })?;
        lock.clone().ok_or_else(|| {
            CommandError::new("PLAYER_NOT_INITIALIZED", "El reproductor de audio no está listo.")
        })?
    };

    let mut pb = state.playback.lock().map_err(|_| {
        CommandError::new("LOCK_ERROR", "Error de concurrencia al actualizar reproducción.")
    })?;

    // Bloquear seek si no hay pista cargada o está cargando
    if pb.loaded_generation.is_none() || pb.is_loading || pb.current_track.is_none() || player.is_idle() {
        return Err(CommandError::new(
            "NOT_READY",
            "No se puede cambiar la posición: no hay pista cargada en reproducción.",
        ));
    }

    player.seek(seconds).map_err(|_| {
        CommandError::new("SEEK_FAILED", "No se pudo cambiar la posición de reproducción.")
    })?;

    pb.position = seconds;
    pb.is_ended = false;
    let dto = pb.to_dto();
    let _ = app.emit("playback-state-changed", &dto);
    Ok(dto)
}

#[tauri::command]
async fn set_playback_volume(
    app: tauri::AppHandle,
    state: tauri::State<'_, AppState>,
    volume: f64,
) -> Result<PlaybackStateDto, CommandError> {
    if !volume.is_finite() {
        return Err(CommandError::new(
            "INVALID_VOLUME",
            "El nivel de volumen debe ser un número finito.",
        ));
    }
    let clamped = volume.clamp(0.0, 100.0);

    let player = {
        let lock = state.player.read().map_err(|_| {
            CommandError::new("LOCK_ERROR", "Error de concurrencia al acceder al reproductor.")
        })?;
        lock.clone().ok_or_else(|| {
            CommandError::new("PLAYER_NOT_INITIALIZED", "El reproductor de audio no está listo.")
        })?
    };

    player.set_volume(clamped.round() as i64).map_err(|_| {
        CommandError::new("VOLUME_FAILED", "No se pudo cambiar el volumen.")
    })?;

    let mut pb = state.playback.lock().map_err(|_| {
        CommandError::new("LOCK_ERROR", "Error de concurrencia al actualizar reproducción.")
    })?;
    pb.volume = clamped;
    let dto = pb.to_dto();
    let _ = app.emit("playback-state-changed", &dto);
    Ok(dto)
}

#[tauri::command]
async fn get_playback_state(
    state: tauri::State<'_, AppState>,
) -> Result<PlaybackStateDto, CommandError> {
    let pb = state.playback.lock().map_err(|_| {
        CommandError::new("LOCK_ERROR", "Error de concurrencia al leer el estado de reproducción.")
    })?;
    Ok(pb.to_dto())
}

#[tauri::command]
async fn stop_playback(
    app: tauri::AppHandle,
    state: tauri::State<'_, AppState>,
) -> Result<PlaybackStateDto, CommandError> {
    let player = {
        let lock = state.player.read().map_err(|_| {
            CommandError::new("LOCK_ERROR", "Error de concurrencia al acceder al reproductor.")
        })?;
        lock.clone().ok_or_else(|| {
            CommandError::new("PLAYER_NOT_INITIALIZED", "El reproductor de audio no está listo.")
        })?
    };

    let _ = player.stop();
    let _ = player.clear_playlist();

    let mut pb = state.playback.lock().map_err(|_| {
        CommandError::new("LOCK_ERROR", "Error de concurrencia al actualizar reproducción.")
    })?;
    pb.generation += 1;
    pb.loaded_generation = None;
    pb.is_playing = false;
    pb.is_loading = false;
    pb.is_ended = false;
    pb.position = 0.0;
    pb.duration = 0.0;
    pb.current_track = None;
    pb.error = None;
    pb.queue = QueueStateDto::default();
    let dto = pb.to_dto();
    let _ = app.emit("playback-state-changed", &dto);
    Ok(dto)
}

#[cfg_attr(mobile, tauri::mobile_entry_point)]
pub fn run() {
    tauri::Builder::default()
        .setup(|app| {
            #[cfg(target_os = "windows")]
            {
                // Si SIDEB_MPV_DIR está definido en el entorno, se agrega a PATH para desarrollo local.
                // En ejecución normal, Windows carga automáticamente libmpv-2.dll desde la carpeta del ejecutable.
                if let Ok(mpv_dir) = std::env::var("SIDEB_MPV_DIR") {
                    if let Ok(current_path) = std::env::var("PATH") {
                        if !current_path.contains(&mpv_dir) {
                            std::env::set_var("PATH", format!("{mpv_dir};{current_path}"));
                        }
                    }
                }
                if std::env::var("LIMUSIC_MPV_LOG").is_err() {
                    std::env::set_var("LIMUSIC_MPV_LOG", "no");
                }
            }

            let playback_manager = Arc::new(Mutex::new(PlaybackManager::new()));
            let state = AppState {
                core: RwLock::new(None),
                init_error: RwLock::new(None),
                player: RwLock::new(None),
                player_error: RwLock::new(None),
                playback: playback_manager.clone(),
                auth: RwLock::new(AuthStatusDto::guest()),
                auth_generation: AtomicU64::new(0),
                auth_operation: tokio::sync::Mutex::new(()),
            };

            match app.path().app_data_dir() {
                Ok(app_data_dir) => {
                    let data_dir_str = app_data_dir.to_string_lossy().to_string();
                    match sideb_core::SideBCore::new_windows(data_dir_str) {
                        Ok(core) => {
                            *state.core.write().unwrap() = Some(core);
                        }
                        Err(_) => {
                            *state.init_error.write().unwrap() = Some(
                                "Error al inicializar el almacenamiento local de Side B.".to_string(),
                            );
                        }
                    }
                }
                Err(_) => {
                    *state.init_error.write().unwrap() = Some(
                        "No se pudo resolver el directorio de datos de la aplicación.".to_string(),
                    );
                }
            }

            let mut player_event_rx = None;
            match app.path().app_cache_dir() {
                Ok(cache_dir) => {
                    let audio_cache = cache_dir.join("audio_cache");
                    if let Err(e) = std::fs::create_dir_all(&audio_cache) {
                        *state.player_error.write().unwrap() = Some(
                            format!("Error al crear el directorio de caché de audio: {e}"),
                        );
                    } else {
                        let cache_str = audio_cache.to_string_lossy().to_string();
                        match player::Player::new(&cache_str) {
                            Ok(mut p) => {
                                player_event_rx = p.take_events();
                                *state.player.write().unwrap() = Some(Arc::new(p));
                            }
                            Err(_) => {
                                *state.player_error.write().unwrap() = Some(
                                    "No se pudo inicializar el motor de audio (libmpv).".to_string(),
                                );
                            }
                        }
                    }
                }
                Err(_) => {
                    *state.player_error.write().unwrap() = Some(
                        "No se pudo resolver el directorio de caché de audio.".to_string(),
                    );
                }
            }

            if let Some(mut rx) = player_event_rx {
                let app_handle = app.handle().clone();
                let pb_ref = playback_manager.clone();
                tauri::async_runtime::spawn(async move {
                    let mut last_progress_emit = std::time::Instant::now();
                    while let Some(ev) = rx.recv().await {
                        match ev {
                            player::PlayerEvent::Position(pos) => {
                                let should_emit = last_progress_emit.elapsed()
                                    >= std::time::Duration::from_millis(200);
                                if let Ok(mut pb) = pb_ref.lock() {
                                    // Sólo procesar eventos de posición si hay una pista efectivamente cargada para la generación activa
                                    if pb.loaded_generation.is_some() && !pb.is_ended {
                                        pb.position = pos;
                                        if pb.is_loading && pos > 0.0 {
                                            pb.is_loading = false;
                                            pb.is_playing = true;
                                        }
                                        let dur = pb.duration;
                                        let gen = pb.generation;
                                        drop(pb);
                                        if should_emit {
                                            let prog = PlaybackProgressDto {
                                                position: pos,
                                                duration: dur,
                                                generation: gen,
                                            };
                                            let _ = app_handle.emit("playback-progress", &prog);
                                            last_progress_emit = std::time::Instant::now();
                                        }
                                    }
                                }
                            }
                            player::PlayerEvent::Duration(dur) => {
                                if dur > 0.0 {
                                    if let Ok(mut pb) = pb_ref.lock() {
                                        // Sólo aplicar si hay una pista cargada activa
                                        if pb.loaded_generation.is_some() {
                                            pb.duration = dur;
                                            let dto = pb.to_dto();
                                            drop(pb);
                                            let _ = app_handle.emit("playback-state-changed", &dto);
                                        }
                                    }
                                }
                            }
                            player::PlayerEvent::Playing(playing) => {
                                if let Ok(mut pb) = pb_ref.lock() {
                                    if playing {
                                        // Sólo pasar a playing si la pista está cargada en el motor
                                        if pb.loaded_generation.is_some() {
                                            pb.is_playing = true;
                                            pb.is_loading = false;
                                            pb.is_ended = false;
                                            let dto = pb.to_dto();
                                            drop(pb);
                                            let _ = app_handle.emit("playback-state-changed", &dto);
                                        }
                                    } else {
                                        if pb.is_playing {
                                            pb.is_playing = false;
                                            let dto = pb.to_dto();
                                            drop(pb);
                                            let _ = app_handle.emit("playback-state-changed", &dto);
                                        }
                                    }
                                }
                            }
                            player::PlayerEvent::TrackEnded => {
                                if let Ok(mut pb) = pb_ref.lock() {
                                    // Evitar que un fin de pista de la pista anterior A afecte a B mientras B carga
                                    if pb.loaded_generation.is_some() {
                                        let next = pb.queue.current_index
                                            .and_then(|index| index.checked_add(1))
                                            .and_then(|index| pb.queue.items.get(index).cloned().map(|entry| (index, entry)));
                                        pb.is_playing = false;
                                        pb.is_loading = false;
                                        pb.is_ended = true;
                                        pb.position = pb.duration;
                                        pb.loaded_generation = None;
                                        let dto = pb.to_dto();
                                        let generation = pb.generation;
                                        drop(pb);
                                        let _ = app_handle.emit("playback-state-changed", &dto);
                                        if let Some((index, entry)) = next {
                                            let app_for_next = app_handle.clone();
                                            tauri::async_runtime::spawn(async move {
                                                let state = app_for_next.state::<AppState>();
                                                let _ = play_song(
                                                    app_for_next.clone(), state, entry.video_id,
                                                    Some(entry.title), Some(entry.artists), entry.thumbnail,
                                                    None, Some(index), None, Some(true), Some(generation),
                                                ).await;
                                            });
                                        }
                                    }
                                }
                            }
                            player::PlayerEvent::TrackFailed(_) => {
                                if let Ok(mut pb) = pb_ref.lock() {
                                    if pb.loaded_generation.is_some() {
                                        pb.is_playing = false;
                                        pb.is_loading = false;
                                        pb.is_ended = false;
                                        pb.error = Some(
                                            "Error al reproducir la pista en el motor de audio.".to_string(),
                                        );
                                        pb.loaded_generation = None;
                                        let dto = pb.to_dto();
                                        drop(pb);
                                        let _ = app_handle.emit("playback-state-changed", &dto);
                                    }
                                }
                            }
                            player::PlayerEvent::Error(_) => {
                                if let Ok(mut pb) = pb_ref.lock() {
                                    if pb.loaded_generation.is_some() {
                                        pb.is_playing = false;
                                        pb.is_loading = false;
                                        pb.error = Some("Error en el reproductor de audio.".to_string());
                                        pb.loaded_generation = None;
                                        let dto = pb.to_dto();
                                        drop(pb);
                                        let _ = app_handle.emit("playback-state-changed", &dto);
                                    }
                                }
                            }
                        }
                    }
                });
            }

            let core_to_restore = state.core.read().ok().and_then(|lock| lock.clone());
            app.manage(state);
            if let Some(core) = core_to_restore {
                tauri::async_runtime::spawn(session::restore(app.handle().clone(), core.clone()));
                tauri::async_runtime::spawn(session::watch_rotations(app.handle().clone(), core));
            }
            Ok(())
        })
        .on_window_event(|window, event| {
            if window.label() == "sideb-login" && matches!(event, tauri::WindowEvent::Destroyed) {
                let app = window.app_handle();
                let state = app.state::<AppState>();
                let authorizing = state.auth.read().map(|status| status.state == "authorizing").unwrap_or(false);
                if authorizing {
                    state.auth_generation.fetch_add(1, Ordering::SeqCst);
                    set_auth_status(app, AuthStatusDto::guest());
                }
            }
        })
        .invoke_handler(tauri::generate_handler![
            get_backend_status,
            get_auth_status,
            login_webview,
            cancel_login,
            sign_out,
            retry_init_core,
            search_songs,
            search_albums,
            get_album,
            get_home_page,
            get_home_continuation,
            get_artist,
            get_browse_grid,
            get_playlist,
            get_library_playlists,
            get_library_albums,
            get_library_artists,
            get_library_songs,
            get_playlist_continuation,
            get_history,
            rate_song,
            apply_song_library_action,
            create_playlist,
            get_artist_radio,
            toggle_album_library,
            set_artist_subscription,
            play_song,
            next_track,
            previous_track,
            pause_playback,
            resume_playback,
            seek_playback,
            set_playback_volume,
            get_playback_state,
            stop_playback
        ])
        .run(tauri::generate_context!())
        .expect("error while running tauri application");
}
