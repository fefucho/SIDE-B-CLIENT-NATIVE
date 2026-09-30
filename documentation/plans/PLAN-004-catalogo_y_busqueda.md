# 📋 PLAN-004: Navegación de Catálogo (Álbum, Playlist, Artista) y Búsqueda Reactiva

- **Alcance**: Epic 4 de 5
- **Estado**: `[Completado - 100%]`
- **Dominios**: Core (Rust) + Shell (Swift 6 & SwiftUI)

---

## 🎯 1. Objetivo y Alcance
Brindar navegación fluida tipo navegador web hacia cualquier elemento del catálogo musical de YouTube Music: vistas completas de Álbumes, Playlists públicas y de usuario, páginas ricas de Artistas (con Top Canciones, Discografía y Artistas Similares), y un motor de búsqueda instantáneo con filtrado reactivo por categorías (Canciones, Álbumes, Artistas, Videos).

---

## 📋 2. Checklist de Tareas

### 🦀 A. Core en Rust & UniFFI (`sideb-core` / `innertube`)
- [x] Contratos tipados: `BrowseCardRecord`, `PlaylistDetailRecord`, `AlbumDetailRecord`, `HistoryGroupRecord`.
- [x] Endpoints tipados: `get_playlist(playlist_id)`, `get_album(browse_id)`, `get_library_playlists()`, `get_library_albums()`, `get_history()`.
- [x] Continuaciones de playlists largas mediante `get_playlist_continuation(token:)` fuertemente tipado.
- [x] Implementar `get_artist(browse_id)` exportando `ArtistDetailRecord` (nombre, descripción, suscriptores, oyentes mensuales, top tracks, radio_playlist_id y secciones de carruseles).
- [x] Métodos de interacción con catálogo: `subscribe_artist`, `like_playlist`, `add_to_playlist`, `remove_from_playlist`.
- [x] Sistema local de anclado en SQLite: `pin_item`, `unpin_item`, `is_pinned`, `get_pinned_items`.
- [x] Implementar `search_all(query, record_history)` y `search_cards(query, filter, record_history)` exportando `SearchResultsRecord` para búsqueda tipada y reactiva en YouTube Music.

### 🎨 B. UI y Navegación en Swift (`apple`)
- [x] Integración en `NavigationRouter.swift` con rutas `.playlist(id)`, `.album(id)`, `.history`, `.search(query)` y `.artist(browseId)`.
- [x] Cápsula flotante `FloatingNavigationCapsule` con botones Atrás (`◀`, `⌘[`) y Adelante (`▶`, `⌘]`).
- [x] Vista de Detalle de Playlist (`PlaylistDetailView.swift`) con cabecera fija de 180pt, botón biblioteca, botón de elipsis y tabla AppKit `NativeTrackTableView` a 120 FPS con click derecho.
- [x] Vista de Detalle de Álbum (`AlbumDetailView.swift`) con enlace clicable a artista, botón biblioteca, botón de elipsis y tabla AppKit a 120 FPS con click derecho.
- [x] Paginación infinita por centinela de proximidad (`onNearBottom`) en playlists con >100 pistas (Tus Me Gusta).
- [x] Historial unificado (`HistoryView.swift`) con AppKit `NativeTrackTableView`.
- [x] Vista dedicada de Artista (`ArtistDetailView.swift`):
  - [x] Banner Liquid Glass con avatar circular (180x180 px), estadísticas (oyentes y subs) y botones de acción (Iniciar mix, Aleatorio, Suscribirse).
  - [x] Top canciones con soporte individual de click derecho oficial.
  - [x] Carruseles horizontales dinámicos de Álbumes, Sencillos / EPs, Vídeos y Artistas relacionados con navegación y menús contextuales.
- [x] Sistema universal y consistente de menús contextuales (`AppContextMenuFactory.swift`) con soporte idéntico a YouTube Music en Canciones, Álbumes, Playlists y Artistas en Home, Tablas, Detalles y Sidebar.
- [x] Modal flotante Spotlight (`SpotlightSearchModal.swift`) activable con `⌘K`, `⌘F` o botón en Sidebar:
  - [x] Debouncing reactivo (250ms) con orden dinámico de categorías (destacando Artistas al escribir coincidencias como "trav").
  - [x] Renderizado con Glassmorphism y ubicado en la jerarquía estrictamente por debajo de la vista Fullscreen (`zIndex: 15` vs `20`).
- [x] Vista de Búsqueda Dedicada (`SearchView.swift` conectada a `PageDestination.search`):
  - [x] Barra superior flotante con debounce y topdown dropdown con resultados rápidos mientras se teclea sin recargar el fondo de forma continua.
  - [x] Actualización del contenido de la página solo al pulsar `Enter`.
  - [x] Barra de chips de categorías: *Todo*, *Canciones*, *Álbumes*, *Artistas*, *Playlists*.
  - [x] Resultados de pistas renderizados mediante `NativeTrackTableView` a 120 FPS y cuadrículas adaptativas para álbumes, artistas y playlists.

---

## 🧪 3. Criterio de Finalización de la Epic
- [x] Clic en el nombre de un artista en cualquier punto de la app navega limpiamente a `ArtistDetailView`.
- [x] La búsqueda arroja resultados tipados categorizados en menos de 400ms sin tirones en el hilo principal.
- [x] Registro del cierre del hito en `FIXES_LOG.md` y `PROJECT_STATE.md`.
