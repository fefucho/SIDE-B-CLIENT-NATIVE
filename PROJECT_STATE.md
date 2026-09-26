# 🎵 Side B (v2) - Estado del Proyecto y Hoja de Ruta Viva

> **Última actualización**: 2026-09-18  
> **Estado general**: Enfoque prioritario en macOS nativo (Fase 1 completada, Gobernanza simplificada, Ejecución de PLAN-001 en curso).  
> **Objetivo central**: Reconstruir el cliente nativo de YouTube Music para macOS combinando la excelencia visual de **Side B Old** (Liquid Glass, 120Hz ProMotion, centrado de isla flotante) con el rendimiento ultra-rápido del motor en Rust de **Limusic** (InnerTube nativo, PoToken, SQLite).

---

## 🏛️ 1. Arquitectura del Sistema

```
┌────────────────────────────────────────────────────────────────────────┐
│                        FRONTEND (macOS Nativo)                         │
│   SwiftUI (macOS 15+) • AVPlayer nativo • MVVM Observable             │
│   Materiales Liquid Glass (.ultraThinMaterial) • 120Hz ProMotion       │
│   Controles Multimedia (MPRemoteCommandCenter, MPNowPlayingInfoCenter)  │
└───────────────────────────────────▲────────────────────────────────────┘
                                    │  UniFFI Bindings Tipados (SideBCore.xcframework)
                                    │  Structs en memoria (Cero JSON String overhead)
                                    │  Cero WebViews de reproducción
┌───────────────────────────────────▼────────────────────────────────────┐
│                         BACKEND (Rust Core)                            │
│   crates/sideb-core • crates/innertube • SQLite local (rusqlite)       │
│   • Búsqueda, Home, Álbumes, Artistas, Playlists (Records UniFFI)     │
│   • Orquestador de Streams (Prioridad AAC itag 140/141 para AVPlayer) │
│   • Descifrador de Cipher, PoToken, WEB_REMIX                          │
│   • Letras sincronizadas (LRCLIB + YouTube Timed Lyrics)               │
└────────────────────────────────────────────────────────────────────────┘
```

> **Decisión de Plataforma**: Enfoque prioritario 100% en macOS. Se descartan compromisos multiplataforma que degraden la fidelidad en Mac (la reproducción es 100% `AVPlayer` nativo en Swift). Si en el futuro se aborda Windows, se implementará con su propio motor dedicado en Rust sin comprometer la pureza de la UI de macOS.

---

## 👥 2. Los 2 Dominios Técnicos y Fuentes de Consulta

| Dominio | Tecnologías | Alcance y Archivos | Responsabilidad |
|---|---|---|---|
| **🦀 Core (Rust)** | Rust, InnerTube, UniFFI, SQLite (`rusqlite`) | `SIDE B/core/`, `SIDE B/apple/build_xcframework.sh` | Contratos tipados en memoria (`#[derive(uniffi::Record)]`), filtrado estricto de streams AAC para Apple, concurrencia segura y caché local. |
| **🎨 UI / Shell (Swift)** | Swift 6, SwiftUI, `AVPlayer`, MediaPlayer | `SIDE B/apple/Sources/SideB/` | Arquitectura de 4 capas ([`UI_ARCHITECTURE.md`](UI_ARCHITECTURE.md)), experiencia Liquid Glass a 120Hz, centrado dinámico del player y enlaces a comandos de sistema. |
| **🔬 Limusic (Consulta pasiva)** | Rust, InnerTube, Tauri | `limusic-master/` | *Referencia pasiva*: Algoritmos de desofuscación, PoToken, fallback de streams y letras LRCLIB. |
| **🔍 Side B Old (Consulta pasiva)** | Swift, SwiftUI | `sideb OLD/` | *Referencia pasiva*: Diseños del Scrubber estilo Apple Music, MiniPlayer y especificaciones visuales. |

---

## 📊 3. Matriz Técnica de Decisiones

| Componente | Estado Anterior / Riesgo | Decisión Técnica Side B v2 |
|---|---|---|
| **Reproducción de Audio** | `WKWebView` o libmpv embebido | **`AVPlayer` nativo en Swift**. Cero WebViews. Cero sobrecarga C/Tauri. |
| **Formato de Audio YouTube** | Mezcla de Opus (`itag 251`) y AAC | **Filtrado estricto a AAC (`itag 140/141`)** en Rust para máxima compatibilidad con macOS. |
| **Serialización UniFFI** | Antipatrón `_json` (`String` + `JSONDecoder`) | **Exportación directa de `uniffi::Record`** en memoria (sin serialización JSON intermedia). |
| **Gobernanza y Tareas** | Micro-planes burocráticos y debates simulados | **5 Epics Estructurales** con checklists vivos integrados en `SIDE B/plans/`. |
| **Registro de Cambios** | Micro-registro por cada bug menor | **`FIXES_LOG.md` reservado exclusivamente para hitos de Epic y cambios de contrato UniFFI**. |

---

## 🗺️ 4. Las 5 Grandes Epics (Roadmap Estructural Sincerado)

1. ✅ [`PLAN-001: Pipeline de Audio y MVP Flotante`](plans/PLAN-001-motor_audio_avplayer.md)
   - Filtrado AAC (itag 140) en Rust e InnerTube con score prioritario sobre Opus.
   - UniFFI con records tipados en memoria (`SongItemRecord`, `resolve_stream`).
   - `AudioPlayerService` nativo (`AVPlayer`) con observadores de tiempo a 10Hz.
   - Barra flotante Liquid Glass con Play/Pause, Scrubber reactivo, volumen y Now Playing real.
2. ✅ [`PLAN-002: Shell de 4 Capas, Sidebar y Feed de Inicio`](plans/PLAN-002-navegador_paginas_y_ui.md)
   - Sistema de 4 capas y centrado de isla flotante en área de contenido ([`UI_ARCHITECTURE.md`](UI_ARCHITECTURE.md)).
   - Barra lateral colapsable (220px a 0px), perfil de usuario y autenticación Google en Keychain.
   - Router de navegación nativa con historial web-like (`NavigationRouter`, `⌘[` y `⌘]`).
   - Feed de Inicio 100% dinámico con chips de ánimo (*Relax*, *Energize*, etc.), grillas de 3 filas y continuaciones.
   - Rediseño de Player Bar Liquid Glass estilo Apple Music macOS 26.
3. ✅ [`PLAN-003: Cola de Reproducción, Automix y Radio`](plans/PLAN-003-cola_automix_radio.md) (100% completado)
   - [x] `QueueManager.swift` reactivo con `QueueContext` tipado (.radio, .album, .playlist), `replaceQueue` atómico y soporte FIFO.
   - [x] Avance automático sin interrupciones y sensor de proximidad `isNearTail` para disparar Automix en segundo plano.
   - [x] Contrato UniFFI `NextResultRecord` con `continuation: Option<String>` y métodos dedicados `get_radio(video_id)` y `get_radio_continuation(...)`.
   - [x] Generación de Radio Dinámica automática de 50 temas al hacer clic en cualquier canción de Inicio/Búsqueda.
   - [x] Reemplazo limpio y destrucción de cola previa al cambiar de canción, álbum o playlist.
   - [x] Acciones "Reproducir a continuación" y "Añadir a la cola" operativas en todos los menús de la app.
   - [x] Cabecera de contexto en Fullscreen ("Radio de...", contador de temas y spinner).
4. ✅ [`PLAN-004: Catálogo y Búsqueda Reactiva`](plans/PLAN-004-catalogo_y_busqueda.md) (100% completado)
   - [x] Vistas de detalle de Playlist y Álbum con `NativeTrackTableView` a 120 FPS, cabecera fija de 180pt y click derecho completo.
   - [x] Paginación de listas largas por centinela de proximidad (`onNearBottom` con continuaciones tipadas).
   - [x] Colección de usuario: Tus Me Gusta (`LM`), Álbumes guardados e Historial unificado.
   - [x] Vista dedicada de Artista (`ArtistDetailView.swift` con avatar 180x180, métricas, top tracks, suscripciones y discografía completa).
   - [x] Sistema universal de menús contextuales (`AppContextMenuFactory.swift`) con soporte idéntico a YouTube Music oficial.
   - [x] Modal flotante Spotlight (`SpotlightSearchModal.swift`) activable con `⌘K`, `⌘F` o Sidebar, con categorías dinámicas y montado bajo Fullscreen.
   - [x] Vista de Búsqueda global reactiva (`SearchView.swift`) con barra superior flotante, topdown dropdown en tiempo real y chips de filtrado (Canciones, Álbumes, Artistas, Playlists).
5. ✅ [`PLAN-005: Modo Fullscreen y Letras Sincronizadas`](plans/PLAN-005-fullscreen_y_letras.md) (~90% completado)
   - [x] Overlay cinematográfico `FullscreenNowPlayingView` con resplandor difuminado dinámico `ArtworkGlow`.
   - [x] Columna izquierda: Carátula gigante en alta resolución (400x400), metadata y botón Like.
   - [x] Selector en cápsula de 3 pestañas: Cola (`Queue`), Letras (`Lyrics`), Recomendados (`Related`).
   - [x] Motor de letras sincronizadas `SyncedLyricsView` con auto-scroll a 120Hz y salto al clic.
   - [ ] Fallback dual a LRCLIB en Rust ante temas sin letras sincronizadas en YouTube Music.

---

## 📝 5. Historial de Hitos Estructurales

- **2026-09-17**:
  - `[FIX-001]`: Análisis técnico de `innertube`, arquitectura Rust pura sin WebViews.
  - `[FIX-002]`: Creación del sistema de registro `FIXES_LOG.md`.
  - `[FIX-003]`: Blueprint de arquitectura UI ([`UI_ARCHITECTURE.md`](UI_ARCHITECTURE.md)) con 4 capas y centrado de isla.
  - `[FIX-004]`: Repositorio oficial de planes ([`SIDE B/plans/`](plans/)).
  - `[FIX-005]`: **Simplificación de Gobernanza y Desbloqueo Técnico**:
    - Adopción de macOS prioritario (`AVPlayer` nativo).
    - Eliminación del antipatrón de JSON sobre UniFFI (transición a `uniffi::Record` tipados).
    - Mandato de filtrado de streams a AAC (itag 140/141) para compatibilidad nativa de audio en Apple.
    - Consolidación a 2 dominios técnicos y 5 Epics con checklists vivos.
  - `[FIX-006]`: Finalización de `PLAN-001` (Pipeline de audio nativo con AVPlayer y MVP de barra flotante Liquid Glass).
  - `[FIX-007]`: Corrección de error 403 en AVPlayer; resolución exitosa de streams directos AAC (itag 140) mediante `VISIONOS` y bootstrap de `visitor_data`.
  - `[FIX-008]`: Rediseño de barra flotante estilo Apple Music macOS 26 y vista Fullscreen cinematográfica con pestañas (Cola, Letras, Recomendados).
  - `[FIX-009]`: Solución a la desincronización de cola de reproducción e índices entre UniFFI y UI.
  - `[FIX-010]`: Integración de autenticación Google/YouTube con CookieStorage en Keychain y WebView de login.
  - `[FIX-011]`: Integración de perfil de usuario en Sidebar (`SidebarProfileView`, avatar, popover de cierre de sesión).
  - `[FIX-012]`: Integración de biblioteca de usuario (`LibraryViewModel`, Liked Music `LM`, álbumes, historial cronológico y vistas de detalle).
  - `[FIX-013]`: **Optimización de Rendimiento a 120 FPS en Listas y Playlists (Estrategia Limusic)**:
    - Erradicación de `.drawingGroup()` para eliminar costosos pases Metal offscreen por fila.
    - Implementación de `Equatable` y `.equatable()` en `TrackRowView` para aislar re-renderizados.
    - Claves compuestas e índices estables (`id: \.self`) para anular colisiones por canciones repetidas en historial y playlists.
    - Expansión de RAM caché (1500 items / 150MB) y throttling con prioridad `.utility` en `ImageCache`.
  - `[FIX-014]`: **Virtualización Real por Ventana (Virtual Windowing Limusic `rows.ts`) en SwiftUI a 120 FPS**:
    - Creación de `VirtualTrackListView` con ventana de 30-40 filas físicas y espaciadores milimétricos `padTop`/`padBottom`.
    - Discretización de `onScrollGeometryChange` con `TrackListWindow: Equatable` (0% de impacto en el hilo principal durante el 99% del scroll).
    - Desacoplamiento total de geometría respecto a las vistas padre de Álbum y Playlist.
    - Eliminación de animaciones de hover en celdas y aplanamiento de secciones en el Historial.
  - `[FIX-015]`: **Sensor de Ventana en `ScrollView` y Paginación Infinita Automática**:
    - Reubicación de `.onScrollGeometryChange` en el contenedor `ScrollView` raíz para desplazamiento continuo de ventana (`start..<end`).
    - Paginación automática por continuación (`get_playlist_continuation_json`) para playlists y Liked Music con >100 temas.
  - `[FIX-016]`: **Arquitectura Definitiva a 120 FPS (Limusic `thumb.ts` CDN 96px + Root `LazyVStack`)**:
    - Reescritura dinámica de URLs de miniaturas (`ImageURLHelper.swift`) pasando de 544x544 (~100KB) a 96x96 (~2KB), reduciendo en 98% el uso de ancho de banda y memoria gráfica.
    - Conversión a arquitectura de `LazyVStack` como hijo directo de `ScrollView` sin contenedores `VStack` intermedios, preservando la pereza nativa sin sobrecarga en la inercia del trackpad.
    - Cero mutaciones de `@State` durante el scroll: renderizado 100% acelerado por hardware Metal/CoreAnimation a 120 FPS estables.
    - Paginación continua asíncrona mediante centinela `onAppear` al aproximarse al final de la lista (`count - 15`).
  - `[FIX-017]`: **Migración a `NSTableView` Nativo de AppKit (`NativeTrackTableView`)**:
    - Adopción de la arquitectura estándar de Apple Music y NetNewsWire para listas de canciones en macOS vía `NSViewRepresentable`.
    - Reciclaje estricto de celdas (`makeView(withIdentifier:owner:)`): memoria constante de solo ~15 celdas en RAM.
  - `[FIX-018]`: **Perfeccionamiento 120 FPS y Unificación Global de Listas**:
    - Bloqueo de altura de cabecera a 180pt en `PlaylistDetailView` y `AlbumDetailView`, eliminando el espacio vertical vacío y anclando los botones de Reproducir/Aleatorio en la base de la portada.
    - Hover de Fuente Única de Verdad (`NativeTrackTableViewInternal.hoveredRowIndex` + observación de `boundsDidChangeNotification` en `NSClipView`), erradicando las marcas múltiples de hover al scrollear.
    - Extensión de la arquitectura `NativeTrackTableView` a la Cola de Reproducción (`FullscreenNowPlayingView`), Historial (`HistoryView`) y Búsquedas en Inicio (`HomeView`).
    - Publicación del informe técnico completo en [`SCROLLING_PERFORMANCE_REPORT.md`](SCROLLING_PERFORMANCE_REPORT.md).
  - `[FIX-019]`: **Integración Completa y Modular del Feed de Inicio de YouTube Music (PLAN-002)**:
    - Extensión de contratos UniFFI con `HomeChipRecord`, `HomePageRecord` y actualización de `HomeSectionRecord` (con `moreBrowseId` y `moreParams`).
    - Métodos tipados `get_home_page(chip_params:)` y `get_home_continuation(token:)` eliminando el traspaso de JSON crudo en la interfaz.
    - Creación del modelo modular `HomeFeedBlock` con categorizador heurístico de secciones.
    - Interfaz reactiva con barra de chips de ánimo (*Todos*, *Relax*, *Sleep*, *Energize*, etc.), grilla de 3 filas para *Quick Picks* / *Listen again*, carruseles destacados para mixes (*My Supermix*), navegación nativa a álbumes/playlists y scroll infinito.
  - `[FIX-020]`: **Controles Flotantes de Navegación Liquid Glass (Back / Forward) y Unificación con NavigationRouter**:
    - Creación de `FloatingNavigationCapsule` flotante en Capa 1 con materiales Liquid Glass (`.ultraThinMaterial`), sin desplazar el contenido de las páginas.
    - Botones interactivos Atrás (`◀`, `⌘[`) y Adelante (`▶`, `⌘]`) vinculados a `NavigationRouter`.
    - Inclusión dinámica de botón de reapertura de barra lateral (`sidebar.left`) al colapsar a 0px, con offset seguro respecto a los semáforos de macOS.
    - Unificación de `NavigationRouter` en `SideBApp`, `SidebarView` y `HomeView` como fuente única de verdad para el historial de rutas.
    - Depuración del encabezado de `HomeView` eliminando la barra de búsqueda para preservar la estética pura de navegador.
  - `[FIX-021]`: **Auditoría Forense, Higiene de Repositorio y Sinceramiento de Epics**:
    - Corrección de la regla `20-frontend.md`: eliminación del obsoleto `VirtualTrackListView` y formalización de `NativeTrackTableView` (AppKit `NSTableView`) como estándar 120 FPS.
    - Activación de la skill profesional `.agents/skills/swiftui-pro/SKILL.md` con pautas de macOS 15, SwiftUI 6, AppKit y Liquid Glass.
    - Eliminación de carpetas zombie (`SIDE B/windows/`, `.agents/skills/swiftui-performance-audit/`), logs residuales de compilación (`build.log`) y scripts legacy de Sparkle/AppleScript.
    - Sinceramiento de las 5 Grandes Epics en `SIDE B/plans/`: desacoplamiento de PLAN-002, creación de `PLAN-003`, `PLAN-004` y `PLAN-005`, y actualización de `README.md` desterrando aprobaciones burocráticas intermedias.
- **2026-09-18**:
  - `[FIX-022]`: **Restauración del Semáforo Nativo de macOS 27 y Adopción Global de Liquid Glass Real**:
    - Creación de `LiquidGlassCompat.swift` implementando `.compatGlass(interactive:tint:in:)` conectando directamente al shader nativo `.glassEffect` (`Glass.regular.interactive()`).
    - Despliegue global de Liquid Glass real en Player Bar flotante, Cápsula de Navegación, botón de alternancia de barra lateral, Popovers, botones de acción de detalle y selector Fullscreen.
  - `[FIX-027]`: **Sistema de Colas Dinámicas, Radios Automáticas y Reemplazo Contextual (PLAN-003 Cerrado al 100%)**:
    - Contrato UniFFI extendido en Rust (`NextResultRecord`) incorporando `continuation: Option<String>` y métodos dedicados `get_radio(video_id)` y `get_radio_continuation(last_video_id, radio_seed)`.
    - `QueueManager.swift` profesionalizado con `QueueContext` tipado (`.radio`, `.album`, `.playlist`, `.custom`), reemplazo atómico `replaceQueue` y sensor `isNearTail`.
    - Al hacer clic en cualquier canción de Inicio/Búsqueda, la cola previa se destruye, arranca el tema al instante y se puebla una radio dinámica continua de 50 temas.
    - Al reproducir un Álbum o Playlist, la cola anterior se sustituye íntegramente por su contenido sin mezclas obsoletas.
    - Acciones "Reproducir a continuación" y "Añadir a la cola" operativas en toda la aplicación.
    - Cabecera contextual en Fullscreen con badge de origen, título dinámico, recuento de canciones y spinner de carga en segundo plano.
- **2026-09-24**:
  - `[FIX-028]`: **Estabilización de Rendimiento 120 FPS ProMotion en Home Feed y Detalle (PLAN-006 Cerrado al 100%)**:
    - Erradicación de `.drawingGroup()` en `mixCardView` y `standardCardView` de `HomeView.swift`, eliminando framebuffers Metal offscreen por tarjeta.
    - Desempaquetado del `VStack` intermedio e implementación de `LazyVStack` directo bajo `ScrollView`, recuperando la virtualización de estantes.
    - Aislamiento de re-renders a 10Hz con `QuickPickSongCell: View, Equatable` (`nonisolated static func ==` + `MainActor.assumeIsolated`).
    - Blindaje de claves `ForEach` por offset en Quick Picks y downsampling CDN en `ArtistDetailView.swift` con `ImageURLHelper`.
  - `[FIX-031]`: **Ejecución Integral del Plan de Auditoría de UI (Sprints 1, 2 y 3 Completados al 100%)**:
    - Migración de SQLite a `Application Support/SideB` persistente, erradicando pérdida silenciosa de sesión de YouTube.
    - Creación de `HomeViewModel.swift` (`@MainActor`, `@Observable`) absorbiendo el estado del feed y preservando la pantalla ante navegación.
    - Unificación universal de listas bajo `NativeTrackTableView` (AppKit `NSTableView` a 120 FPS) en panel Recomendados de Fullscreen.
    - Creación de `DetailSharedComponents.swift` deduplicando skeletons, placeholders y vistas de error en vistas de Álbum y Playlist.
    - Centralización de radios y mixes en `PlayerViewModel.startRadioForCollection(...)`, eliminando 8+ duplicaciones en vistas y menús.
    - Erradicación definitiva de código zombie (`AppleMusicScrubber.swift`, `TrackRowView.swift`).
    - Migración de concurrencia legacy a Swift Concurrency en `LoginWebView` y logging en `ImageCache`.
  - `[FIX-032]`: **Reingeniería del Pipeline del Player, Cancelación Atómica y Carátulas Reactivas**:
    - Reingeniería reactiva de `CachedAsyncImage.swift` rastreando `loadedUrl`, eliminando el congelamiento de carátulas previas al skipear.
    - Asignación de identidades `.id(...)` en `PlayerBarView` y `FullscreenNowPlayingView` con downsampling CDN instantáneo.
    - Cancelación atómica (`resolveStreamTask?.cancel()`, `lyricsTask?.cancel()`) y tokens UUID de correlación en `PlayerViewModel.playSongNow`, impidiendo carreras asíncronas entre audio y metadatos.
    - Sincronización obligatoria de `queueManager.syncCurrentIndex(for:)` al reproducir cualquier pista.
  - `[FIX-041]`: **Avance Automático Fiable al Final de la Canción (Auto-Skip CoreMedia & AVPlayer)**:
    - Mitigación del bug de duración duplicada en streams fMP4 de YouTube Music con `forwardPlaybackEndTime` y triple centinela de seguridad en `AudioPlayerService.swift`.
    - Continuidad automática en `PlayerViewModel.swift` al expandir la radio de reproducción en segundo plano.
  - `[FIX-042]`: **Agrandamiento Ergonómico del TabBar Fullscreen y Sistema Integral de 4 Estantes de Recomendaciones**:
    - Ampliación del ancho de panel y cápsula estilo BigPicture de `sideb OLD`.
    - Estantes dinámicos de descubrimiento musical ("Más del artista", "Del mismo álbum", "Te podría gustar", "A los fans también les gusta").
  - `[FIX-043]`: **Sistema de Búsqueda Reactiva: Modal Spotlight Dinámico y SearchView con Topdown Dropdown (PLAN-004 Cerrado al 100%)**:
    - Contrato UniFFI fuertemente tipado `SearchResultsRecord`, `search_all` y `search_cards` en Rust `sideb-core`.
    - Modal flotante Spotlight (`⌘K`, `⌘F`, botón Sidebar) con debounce de 250ms y categorización dinámica adaptativa (elevando Artistas al escribir coincidencias como "trav").
    - Montaje estricto de Spotlight en Capa 1 por debajo de la vista Fullscreen (`zIndex: 15` vs `20`).
    - Vista `SearchView.swift` con barra superior Liquid Glass, dropdown topdown de sugerencias rápidas en tiempo real, actualización de página de fondo únicamente con `Enter` y renderizado de canciones a 120 FPS mediante `NativeTrackTableView`.
  - `[FIX-044]`: **Canciones Parecidas y Artistas Afines vía Endpoint Oficial Related (MPTR) de YouTube Music**:
    - Extracción en Rust de `related_browse_id` (`MPTRt_...`) en `/next` y consulta directa a `/browse` para carruseles *"You might also like"* y *"Similar artists"*.
    - Integración en `PlayerViewModel` y vista `RecommendedContentView` a 120 FPS con estante de canciones parecidas.
  - `[FIX-045]`: **Spotlight 50% más Amplio y Radio Automática Inmediata en Resultados de Búsqueda**:
    - Ampliación del modal Spotlight a 850×740pt con visualización de hasta 8 canciones y 5 de artistas/álbumes/playlists simultáneos.
    - Corrección en la selección de canciones: uso de `playWithRadio(song)` para arrancar la reproducción de inmediato y poblar concurrentemente la radio dinámica de 50 temas en segundo plano.
  - `[FIX-046]`: **Rediseño de Tarjetas de Canciones en Inicio estilo Apple Music macOS, Artistas y Álbumes Clickeables y Ecualizador Animado**:
    - Extensión de contrato UniFFI en Rust con `artists`, `artist_id`, `album`, `album_id` en `HomeItemRecord` y `BrowseItem`.
    - Eliminación del aura roja y marco rígido en `QuickPickSongCell` en favor de filas limpias estilo Apple Music macOS (Foto 1).
    - Portada interactiva: oscurecimiento con icono de `play.fill` / `pause.fill` en hover, y animación viva de 4 barras ecualizadoras (`AudioEqualizerBarsView`) en reproducción (Foto 2).
    - Subtítulo interactivo con enlaces clicables individuales a la página del artista y del álbum separados por punto medio.
    - Menú contextual `...` en el extremo derecho y divisor inferior sutil.


