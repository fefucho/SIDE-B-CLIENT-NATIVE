use crate::{AppState, CommandError, PlaybackStateDto, PlaybackTrackDto};
use crate::queue::{QueueEntryDto, QueueSourceDto, QueueStateDto};
use tauri::{Emitter, Manager};

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
pub(crate) async fn play_song(
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
pub(crate) async fn next_track(app: tauri::AppHandle, state: tauri::State<'_, AppState>) -> Result<PlaybackStateDto, CommandError> {
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
pub(crate) async fn previous_track(app: tauri::AppHandle, state: tauri::State<'_, AppState>) -> Result<PlaybackStateDto, CommandError> {
    let (target, generation) = {
        let playback = state.playback.lock().map_err(|_| CommandError::new("LOCK_ERROR", "No se pudo leer la cola."))?;
        let index = playback.queue.current_index.ok_or_else(|| CommandError::new("EMPTY_QUEUE", "No hay una pista activa en la cola."))?;
        let target = if playback.position > 3.0 || index == 0 { index } else { index - 1 };
        (target, playback.generation)
    };
    start_queue_entry(app, target, generation).await
}

#[tauri::command]
pub(crate) async fn pause_playback(
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
pub(crate) async fn resume_playback(
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
pub(crate) async fn seek_playback(
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
pub(crate) async fn set_playback_volume(
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
pub(crate) async fn get_playback_state(
    state: tauri::State<'_, AppState>,
) -> Result<PlaybackStateDto, CommandError> {
    let pb = state.playback.lock().map_err(|_| {
        CommandError::new("LOCK_ERROR", "Error de concurrencia al leer el estado de reproducción.")
    })?;
    Ok(pb.to_dto())
}

#[tauri::command]
pub(crate) async fn stop_playback(
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
