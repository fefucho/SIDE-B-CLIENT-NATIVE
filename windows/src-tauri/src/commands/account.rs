use std::sync::Arc;
use std::sync::atomic::Ordering;
use crate::{AppState, BrowseCardDto, CommandError, HistoryGroupDto, PlaylistContinuationDto};

pub(crate) fn account_core(state: &AppState, generation: u64) -> Result<Arc<sideb_core::SideBCore>, CommandError> {
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
pub(crate) async fn get_library_playlists(state: tauri::State<'_, AppState>) -> Result<Vec<BrowseCardDto>, CommandError> {
    let generation = state.auth_generation.load(Ordering::SeqCst);
    let _operation = state.auth_operation.lock().await;
    let core = account_core(&state, generation)?;
    let result = core.get_library_playlists().await.map(|v| v.into_iter().map(BrowseCardDto::from).collect())
        .map_err(|_| CommandError::new("LIBRARY_FAILED", "No se pudieron cargar tus playlists."))?;
    if state.auth_generation.load(Ordering::SeqCst) != generation { return Err(CommandError::new("SESSION_CHANGED", "La sesión cambió durante la operación.")); }
    Ok(result)
}

#[tauri::command]
pub(crate) async fn get_library_albums(state: tauri::State<'_, AppState>) -> Result<Vec<BrowseCardDto>, CommandError> {
    let generation = state.auth_generation.load(Ordering::SeqCst);
    let _operation = state.auth_operation.lock().await;
    let core = account_core(&state, generation)?;
    let result = core.get_library_albums().await.map(|v| v.into_iter().map(BrowseCardDto::from).collect())
        .map_err(|_| CommandError::new("LIBRARY_FAILED", "No se pudieron cargar tus álbumes."))?;
    if state.auth_generation.load(Ordering::SeqCst) != generation { return Err(CommandError::new("SESSION_CHANGED", "La sesión cambió durante la operación.")); }
    Ok(result)
}

#[tauri::command]
pub(crate) async fn get_library_artists(state: tauri::State<'_, AppState>) -> Result<Vec<BrowseCardDto>, CommandError> {
    let generation = state.auth_generation.load(Ordering::SeqCst);
    let _operation = state.auth_operation.lock().await;
    let core = account_core(&state, generation)?;
    let result = core.get_library_artists().await.map(|v| v.into_iter().map(BrowseCardDto::from).collect())
        .map_err(|_| CommandError::new("LIBRARY_FAILED", "No se pudieron cargar tus artistas."))?;
    if state.auth_generation.load(Ordering::SeqCst) != generation { return Err(CommandError::new("SESSION_CHANGED", "La sesión cambió durante la operación.")); }
    Ok(result)
}

#[tauri::command]
pub(crate) async fn get_library_songs(state: tauri::State<'_, AppState>) -> Result<PlaylistContinuationDto, CommandError> {
    let generation = state.auth_generation.load(Ordering::SeqCst);
    let _operation = state.auth_operation.lock().await;
    let core = account_core(&state, generation)?;
    let result = core.get_library_songs().await.map(PlaylistContinuationDto::from)
        .map_err(|_| CommandError::new("LIBRARY_FAILED", "No se pudieron cargar tus canciones."))?;
    if state.auth_generation.load(Ordering::SeqCst) != generation { return Err(CommandError::new("SESSION_CHANGED", "La sesión cambió durante la operación.")); }
    Ok(result)
}


#[tauri::command]
pub(crate) async fn get_playlist_continuation(state: tauri::State<'_, AppState>, token: String) -> Result<PlaylistContinuationDto, CommandError> {
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
pub(crate) async fn get_history(state: tauri::State<'_, AppState>) -> Result<Vec<HistoryGroupDto>, CommandError> {
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
pub(crate) async fn rate_song(state: tauri::State<'_, AppState>, video_id: String, rating: String) -> Result<(), CommandError> {
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
pub(crate) async fn apply_song_library_action(state: tauri::State<'_, AppState>, token: String) -> Result<(), CommandError> {
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
pub(crate) async fn create_playlist(state: tauri::State<'_, AppState>, title: String, description: String) -> Result<String, CommandError> {
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
pub(crate) async fn toggle_album_library(state: tauri::State<'_, AppState>, playlist_id: String, save: bool) -> Result<(), CommandError> {
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
pub(crate) async fn set_artist_subscription(state: tauri::State<'_, AppState>, channel_id: String, subscribe: bool) -> Result<(), CommandError> {
    let id = channel_id.trim();
    if id.is_empty() { return Err(CommandError::new("INVALID_ID", "El identificador del artista no puede estar vacío.")); }
    let generation = state.auth_generation.load(Ordering::SeqCst);
    let _operation = state.auth_operation.lock().await;
    let core = account_core(&state, generation)?;
    core.subscribe_artist(id.to_owned(), subscribe).await.map_err(|_| CommandError::new("ARTIST_SUBSCRIPTION_FAILED", "No se pudo actualizar la suscripción al artista."))?;
    if state.auth_generation.load(Ordering::SeqCst) != generation { return Err(CommandError::new("SESSION_CHANGED", "La sesión cambió durante la operación.")); }
    Ok(())
}
