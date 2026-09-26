# 📋 PLAN-005: Modo Fullscreen Cinemático y Letras Sincronizadas

- **Alcance**: Epic 5 de 5
- **Estado**: `[Completado - ~90% Operativo]`
- **Dominios**: Shell (SwiftUI & AppKit) + Core (Rust)

---

## 🎯 1. Objetivo y Alcance
Crear una experiencia cinemática inmersiva para escuchar música a pantalla completa (*Big Picture / Fullscreen Overlay*), con resplandor dinámico reactivo a la carátula de la canción en reproducción, visualización de portada en gran formato, selector fluido entre la Cola activa, Letras sincronizadas con seguimiento al segundo y temas recomendados similares.

---

## 📋 2. Checklist de Tareas

### 🌌 A. Capa 2: Overlay Fullscreen en Swift (`FullscreenNowPlayingView.swift`)
- [x] Despliegue fluido por encima de Capa 1 con transición suave sin interrumpir la reproducción sonora.
- [x] Fondo difuminado dinámico `ArtworkGlow` adaptado a la carátula actual con desenfoque extremo para alto contraste.
- [x] Columna izquierda: Carátula grande (400x400), título en tipografía prominente, artista/álbum y botón de Me Gusta (`rate_song`).
- [x] Columna derecha con selector de 3 pestañas en cápsula Liquid Glass:
  - [x] **Cola (Queue)**: Renderizada con `NativeTrackTableView` (AppKit a 120 FPS).
  - [x] **Letras (Lyrics)**: Renderizada con `SyncedLyricsView`.
  - [x] **Recomendados (Related)**: Pistas sugeridas obtenidas a través de `get_next`.
- [x] Barra de reproducción Liquid Glass anclada en el pie con controles de transporte y volumen.
- [x] Botón de colapso rápido para volver al navegador sin alterar el estado de reproducción.

### 🎤 B. Motor de Letras Sincronizadas (`SyncedLyricsView.swift` & Core)
- [x] Obtención de letras sincronizadas de YouTube Music mediante `SideBCore.get_lyrics(video_id)`.
- [x] Resaltado reactivo de la línea activa según el tiempo transcurrido del reproductor.
- [x] Auto-scroll suave que centra la estrofa actual sin saltos bruscos.
- [x] Interacción al clic: hacer clic en cualquier línea de la letra realiza un seek inmediato a ese segundo de la canción.
- [ ] Fallback automático secundario a LRCLIB en Rust cuando YouTube Music no cuente con `timed_lyrics` en su respuesta.

---

## 🧪 3. Criterio de Finalización de la Epic
- [x] La vista Fullscreen abre y cierra a 120 FPS sin parpadeos ni fugas de memoria.
- [x] Las letras se sincronizan con precisión de décimas de segundo y permiten saltos temporales interactivos.
- [x] Registro del hito en `FIXES_LOG.md` y `PROJECT_STATE.md`.
