# 📋 PLAN-003: Cola de Reproducción, Automix y Radio

- **Alcance**: Epic 3 de 5
- **Estado**: `[Completado - 100%]`
- **Dominios**: Core (Rust) + Shell (Swift 6 & AVFoundation)

---

## 🎯 1. Objetivo y Alcance
Proveer un sistema de reproducción continua e infinita idéntico a YouTube Music nativo, gestionando la lista de reproducción activa (*Up Next*), el avance automático sin interrupciones sonoras, la generación automática de mezclas continuas (*Automix*) y la creación de estaciones de radio instantáneas basadas en cualquier canción o artista.

---

## 📋 2. Checklist de Tareas

### 🦀 A. Core en Rust & UniFFI (`sideb-core` / `innertube`)
- [x] Exportar record tipado `NextResultRecord` con lista de pistas siguientes y continuaciones (`continuation: Option<String>`).
- [x] Implementar `get_next(video_id, playlist_id)` en `SideBCore` para consultar el endpoint `/next`.
- [x] Implementar `get_radio(video_id)` con resolución de playlist de radio automática (`RDAMVM...`) y fallback a `automix_playlist_id`.
- [x] Soporte para extensión de radio continua (`get_radio_continuation`) para automix infinito sin límites de tamaño.

### 🎨 B. Motor y UI en Swift (`apple`)
- [x] Implementar `QueueManager.swift` con enum tipado `QueueContext` (.radio, .album, .playlist, .custom), reemplazo atómico de colas (`replaceQueue`) y soporte FIFO.
- [x] Avance automático a la siguiente pista al finalizar el tema (`AVPlayerItemDidPlayToEndTime`) y sensor de cola `isNearTail`.
- [x] Panel de Cola en la Vista Fullscreen (`queuePanel`) renderizado con `NativeTrackTableView` (AppKit a 120 FPS) con cabecera informativa de contexto ("Radio de [Canción]", contador de temas y spinner).
- [x] Reproducción al clic de cualquier pista de la cola sin desfasar el índice.
- [x] Disparo transparente de Automix: al aproximarse al final de la cola (últimas 2 pistas), solicitar automáticamente la continuación `/next` y añadir nuevos temas a la cola sin duplicados.
- [x] Menús contextuales universales en `AppContextMenuFactory.swift` con "Iniciar mix / Radio", "Reproducir a continuación" y "Añadir a la cola" sincronizados con el nuevo motor de colas.
- [x] Eliminación segura de temas individuales (`removeTrack`) y vaciado de cola (`clearQueue`).

---

## 🧪 3. Criterio de Finalización de la Epic
- [x] La música nunca se detiene: al reproducir una sola canción en Inicio, la cola previa se destruye, se genera automáticamente radio continuo de 50 temas y se extiende al aproximarse al final.
- [x] Al reproducir un Álbum o Playlist, la cola anterior se sustituye íntegramente por las canciones correspondientes.
- [x] La tabla de cola en Fullscreen mantiene 120 FPS y memoria plana (~15 celdas) sin importar si la cola tiene 100 canciones.
- [x] Registro del cierre del hito en `FIXES_LOG.md` y `PROJECT_STATE.md`.

