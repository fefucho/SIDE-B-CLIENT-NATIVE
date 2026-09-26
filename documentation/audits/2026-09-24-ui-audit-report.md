# 🔬 Auditoría Exhaustiva de UI — Side B Swift/SwiftUI
> **Fecha**: 2026-09-24 | **Archivos auditados**: 38 archivos Swift | **Problemas encontrados**: 19

---

## 📊 Dashboard de Estado

| Severidad | Cantidad | Estado |
|-----------|----------|--------|
| 🔴 CRÍTICO | 1 | Requiere fix inmediato |
| 🟠 ALTO | 6 | Fix en próxima sesión |
| 🟡 MEDIO | 7 | Deuda técnica planificada |
| 🟢 BAJO | 5 | Backlog estético/estilo |

---

## 🗂️ Índice de Archivos Auditados

| Archivo | Tamaño | Veredicto |
|---------|--------|-----------|
| `SideBApp.swift` | 8.9 KB | 🔴 BUG CRÍTICO |
| `Models/HomeFeedBlock.swift` | 3.7 KB | ✅ Limpio |
| `Services/Navigation/NavigationRouter.swift` | 1.5 KB | ✅ Limpio |
| `Services/Storage/CookieStorage.swift` | 6.9 KB | ✅ Limpio |
| `Services/Player/AudioPlayerService.swift` | 8.7 KB | 🟡 1 problema |
| `Services/Player/QueueManager.swift` | 7.5 KB | 🟢 1 menor |
| `ViewModels/PlayerViewModel.swift` | 15.9 KB | 🟡 2 problemas |
| `ViewModels/AccountViewModel.swift` | 1.9 KB | ✅ Limpio |
| `ViewModels/LibraryViewModel.swift` | 2.0 KB | ✅ Limpio |
| `ViewModels/AlbumDetailViewModel.swift` | 2.0 KB | ✅ Limpio |
| `ViewModels/ArtistDetailViewModel.swift` | 3.0 KB | ✅ Limpio |
| `ViewModels/PlaylistDetailViewModel.swift` | 2.7 KB | ✅ Limpio |
| `Views/Common/NativeTrackTableView.swift` | 21.7 KB | 🟡 2 problemas |
| `Views/Common/TrackRowView.swift` | 5.0 KB | 🟡 Posible zombie |
| `Views/Common/CachedAsyncImage.swift` | 2.8 KB | ✅ Limpio |
| `Views/Common/DescriptionCardModal.swift` | 4.0 KB | ✅ Limpio |
| `Views/Components/PlayerBarView.swift` | 18.5 KB | 🟡 2 problemas |
| `Views/Components/AirPlayRoutePicker.swift` | 1.9 KB | ✅ Limpio |
| `Views/Components/AppleMusicScrubber.swift` | 3.6 KB | 🟡 ZOMBIE CONFIRMADO |
| `Views/Components/FloatingNavigationCapsule.swift` | 3.3 KB | ✅ Limpio |
| `Views/Detail/AlbumDetailView.swift` | 15.1 KB | 🟠 2 problemas |
| `Views/Detail/PlaylistDetailView.swift` | 15.4 KB | 🟠 2 problemas |
| `Views/Detail/ArtistDetailView.swift` | 29.0 KB | 🟠 3 problemas |
| `Views/Fullscreen/FullscreenNowPlayingView.swift` | 26.4 KB | 🟠 3 problemas |
| `Views/History/HistoryView.swift` | 2.8 KB | 🟡 1 problema |
| `Views/Home/HomeView.swift` | 27.9 KB | 🟠 4 problemas |
| `Views/Login/LoginSheet.swift` | 1.7 KB | 🟢 1 menor |
| `Views/Login/LoginWebView.swift` | 4.5 KB | 🟡 1 problema |
| `Views/Login/LoginPasskeySuppression.swift` | 2.1 KB | ✅ Limpio |
| `Views/Sidebar/SidebarView.swift` | 17.5 KB | 🟡 1 problema |
| `Views/Sidebar/SidebarProfileView.swift` | 5.7 KB | 🟡 1 problema |
| `Views/Sidebar/AccountPopoverView.swift` | 4.2 KB | ✅ Limpio |
| `UI/AppContextMenuFactory.swift` | 25.2 KB | 🟠 1 problema |
| `UI/AppTheme.swift` | 2.4 KB | ✅ Limpio |
| `UI/LiquidGlassCompat.swift` | 4.5 KB | ✅ Limpio |
| `UI/WindowTrafficLightRevealer.swift` | 4.9 KB | ✅ Limpio |
| `Utilities/ImageCache.swift` | 9.9 KB | 🟢 1 menor |
| `Utilities/ImageURLHelper.swift` | 2.3 KB | ✅ Limpio |

---

## 🔴 CRÍTICO (1)

### BUG-01 — `SideBApp.swift` línea ~20: SQLite en directorio temporal del OS

```swift
// CÓDIGO ACTUAL — INCORRECTO:
let core = try SideBCore(dataDir: NSTemporaryDirectory())
```

**Impacto**: El motor Rust guarda en ese directorio:
- El token de sesión de YouTube (`session_cookie`)
- El `visitor_data` para InnerTube
- El PoToken cacheado (~12h de TTL)
- La caché de metadatos (historial, playlists, pins)
- El `sideb.db` SQLite completo

macOS puede purgar `NSTemporaryDirectory()` en cualquier momento: en reposo prolongado, bajo presión de memoria, o al reiniciar. Cuando eso ocurre, la sesión de usuario se pierde silenciosamente y hay que hacer login de nuevo.

**Corrección**:
```swift
// CORRECTO:
let appSupport = FileManager.default
    .urls(for: .applicationSupportDirectory, in: .userDomainMask)
    .first!
    .appendingPathComponent("SideB", isDirectory: true)
let core = try SideBCore(dataDir: appSupport.path)
```

---

## 🟠 ALTOS (6)

### BUG-02 — `SideBApp.swift`: Error de init del Core sin feedback al usuario

```swift
@State private var initError: String?
// El body simplemente no muestra nada si rustCore == nil
```

Si `SideBCore(dataDir:)` lanza, la app arranca con una **ventana completamente en blanco y muda**. No hay mensaje de error, no hay botón de reintento.

**Corrección**: Agregar en el `body` una rama `if let error = initError`:
```swift
if let error = initError {
    ContentUnavailableView("Error al iniciar Side B", systemImage: "exclamationmark.triangle", description: Text(error))
}
```

---

### BUG-03 — `HomeView.swift`: Vista sin ViewModel propio (violación de arquitectura)

`HomeView` (27.9 KB) es el único módulo de la app donde **toda la lógica de negocio vive directamente en la Vista**:
- `loadHomeFeed()` — fetch inicial + fallback de sesión expirada
- `loadMoreContent()` — paginación infinita con anti-debounce (`lastLoadMoreTimestamp`)
- `loadChip(_:)` — cambio de mood chip

Con 9 variables `@State` de dominio:
```swift
@State private var chips: [HomeChipRecord] = []
@State private var selectedChipParams: String? = nil
@State private var blocks: [HomeFeedBlock] = []
@State private var continuationToken: String? = nil
@State private var isLoading = false
@State private var isLoadingChip = false
@State private var isLoadingMore = false
@State private var lastLoadMoreTimestamp: Date = .distantPast
@State private var errorMessage: String?
```

**Consecuencia**: Al colapsar/expandir la sidebar o al navegar fuera y volver (NavigationRouter), SwiftUI puede destruir y recrear `HomeView`, perdiendo todo el feed y haciendo un re-fetch innecesario.

**Corrección**: Crear `HomeViewModel.swift` (`@Observable`, inyectado como dependencia en el environment), mover las 9 variables y los 3 métodos.

---

### BUG-04 — `HomeView.swift`: Detección de sesión expirada por string matching frágil

```swift
// Línea ~638:
if error.localizedDescription.contains("session expired") {
    self.setCookie(nil) // reset
}
```

Si el mensaje de error del Rust Core cambia (por un cambio en `SideBError`, una actualización del crate, o localización), este fallback falla silenciosamente y el usuario queda atascado con una pantalla de error.

**Corrección**: El binding UniFFI ya expone `SideBError` tipado. Usar:
```swift
if case .sessionExpired = sideBError { ... }
```

---

### BUG-05 — `FullscreenNowPlayingView.swift`: `isLiked` local nunca sincronizado con backend

```swift
@State private var isLiked: Bool = false
// Al tocar el corazón:
isLiked.toggle()
viewModel.rateSong(rating: isLiked ? "LIKE" : "INDIFFERENT")
```

El corazón **siempre aparece vacío** al abrir el fullscreen, sin importar si el track ya estaba en "Me Gusta". No hay ninguna llamada al backend para leer el estado real.

**Corrección**: Mover `isLiked` a `PlayerViewModel` como `@Published var currentTrackIsLiked: Bool`. Al resolver un stream nuevo, consultar el estado de rating vía UniFFI (o mantenerlo localmente basado en la última acción de `rateSong`).

---

### BUG-06 — `AppContextMenuFactory.swift`: Submenú "Añadir a playlist" siempre vacío

```swift
let addToPlaylistItem = NSMenuItem(...)
let playlistSubmenu = NSMenu(title: "Playlists")
if let core = core {
    Task { @MainActor in
        if let userPlaylists = try? await core.getLibraryPlaylists() {
            for p in userPlaylists {
                playlistSubmenu.addItem(...)  // ← Llega tarde
            }
        }
    }
}
addToPlaylistItem.submenu = playlistSubmenu  // ← Se asigna ANTES de que Task termine
menu.addItem(addToPlaylistItem)
```

El `Task` es asíncrono. El submenú se asigna vacío antes de que la red responda. En la práctica, **este ítem del menú contextual nunca muestra playlists**.

**Corrección**: Pre-cargar las playlists del usuario en `LibraryViewModel` y pasarlas como parámetro síncrono a `AppContextMenuFactory.buildMenu(track:playlists:)`.

---

### BUG-07 — `ArtistDetailView` + `HomeView`: `SongItemRecord` construido sin `artistId`/`albumId`

En 4 lugares del código, se construye un `SongItemRecord` ad-hoc desde un `BrowseCardRecord` o `HomeItemRecord`:

```swift
let song = SongItemRecord(
    videoId: card.id,
    title: card.title,
    artists: card.subtitle ?? "",
    album: nil,
    duration: card.duration,
    thumbnail: card.thumbnail,
    artistId: nil,   // ← Siempre nil
    albumId: nil     // ← Siempre nil
)
playerViewModel.playSong(song)
```

Consecuencia: los botones "Ir al artista" y "Ir al álbum" en `PlayerBarView` y `FullscreenNowPlayingView` no pueden navegar correctamente para estas canciones.

**Corrección**: Crear un método en `PlayerViewModel`:
```swift
func playSongFromCard(_ card: BrowseCardRecord, knownArtistId: String? = nil) { ... }
```
que resuelva los IDs faltantes vía `getNext(videoId:playlistId:)` antes de construir el `SongItemRecord`.

---

## 🟡 MEDIOS (7)

### MED-01 — `AppleMusicScrubber.swift`: Código zombie confirmado

`AppleMusicScrubber` (3.6 KB) existe como componente independiente con scrubber, tiempo transcurrido y tiempo restante. Sin embargo:
- `PlayerBarView` implementa su propio scrubber inline (`topScrubberBar`)
- `FullscreenNowPlayingView` no lo usa
- Ningún `import` o referencia en el resto del proyecto lo invoca

**Acción**: Eliminar el archivo o restaurarlo como el scrubber canónico reemplazando las implementaciones inline duplicadas.

---

### MED-02 — `TrackRowView.swift`: Potencialmente zombie

`TrackRowView` es una vista SwiftUI para filas de track. Desde la migración a `NativeTrackTableView` (AppKit), no aparece referenciada en ningún archivo auditado. Si no tiene uso activo → candidato a eliminación.

**Acción pendiente**: Confirmar con `grep -r "TrackRowView" Sources/` antes de eliminar.

---

### MED-03 — `FullscreenNowPlayingView.swift`: `LazyVStack` para panel "Recomendados"

```swift
// Panel "Recomendados" (pestana 3):
ScrollView {
    LazyVStack(spacing: 6) {
        ForEach(viewModel.recommendedTracks, id: \.videoId) { track in
            Button { ... } label: { ... }
        }
    }
}
```

La radio de YouTube devuelve 25+ pistas. Se usa `LazyVStack` + SwiftUI puro, violando la regla de `NativeTrackTableView` para listas >20 ítems. El panel de Cola ya usa `NativeTrackTableView` correctamente.

**Corrección**: Extender `NativeTrackTableView` al panel de Recomendados igual que se hizo para el panel de Cola.

---

### MED-04 — `FullscreenNowPlayingView.swift`: Búsqueda lineal de letras activas a 10Hz en main thread

```swift
.onChange(of: viewModel.currentTime) { _, _ in
    let currentTimeMs = UInt64(viewModel.currentTime * 1000)
    if let activeIndex = lyrics.lines.firstIndex(where: { line in ... }) {
        withAnimation(.easeInOut(duration: 0.3)) {
            proxy.scrollTo(activeIndex, anchor: .center)
        }
    }
}
```

`currentTime` cambia cada ~100ms. Cada cambio lanza `firstIndex(where:)` sobre toda la lista de líneas de letras. Para 80+ líneas = ~4.800 búsquedas por minuto en el main thread.

**Corrección**: Pre-computar el índice activo en `PlayerViewModel` usando `didSet` sobre `currentTime`, con un guard que solo dispare si el índice efectivamente cambia:
```swift
var currentLyricsIndex: Int = 0
```

---

### MED-05 — `NativeTrackTableView.swift`: Detección de cambio de lista superficial

```swift
let tracksChanged = oldParent.tracks.count != tracks.count ||
                    oldParent.tracks.first?.videoId != tracks.first?.videoId ||
                    oldParent.tracks.last?.videoId != tracks.last?.videoId
```

Solo compara `.count`, primer y último `videoId`. Si se reordena la cola o se insertan pistas en el medio, la tabla **no se recargará** y mostrará datos desactualizados.

**Corrección**: Comparar un hash del array completo o usar `zip(old, new).contains(where: { $0.videoId != $1.videoId })`.

---

### MED-06 — `SidebarProfileView.swift`: `AsyncImage` nativo en lugar de `CachedAsyncImage`

```swift
AsyncImage(url: url) { phase in ... }
```

El avatar del usuario se descarga de red cada vez que el sidebar se actualiza. El proyecto tiene `CachedAsyncImage` con caché en RAM + disco, y debería usarse aquí.

**Corrección**: Reemplazar con `CachedAsyncImage(url: url)`.

---

### MED-07 — `PlayerViewModel.swift`: `@unchecked Sendable` sin documentar

```swift
extension SideBCore: @unchecked Sendable {}
```

Suprime la verificación de thread-safety del compilador Swift sobre el binding de UniFFI. Esto es necesario porque UniFFI genera código que Swift no puede verificar automáticamente, pero debe documentarse explícitamente:
```swift
// SAFETY: SideBCore está protegido internamente por Arc<Mutex<T>> de Rust.
// UniFFI garantiza que todos los métodos son Send+Sync. Verificado en lib.rs.
extension SideBCore: @unchecked Sendable {}
```

---

## 🟢 BAJOS (5)

### LOW-01 — `LoginWebView.swift`: GCD legacy en lugar de Swift Concurrency
```swift
DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { [weak self] in ... }
```
Inconsistente con el resto del proyecto. Usar `Task { try? await Task.sleep(for: .milliseconds(800)); await ... }`.

### LOW-02 — `QueueManager.swift`: Métodos legacy sin `@available(*, deprecated)`
```swift
public func setQueue(_ items: [SongItemRecord], ...) { replaceQueue(...) }
public func appendTracks(_ tracks: [SongItemRecord]) { appendRadioTracks(tracks) }
```
Sin marcar como deprecated, los futuros desarrolladores no sabrán que deben usar `replaceQueue` y `appendRadioTracks`.

### LOW-03 — `ImageCache.swift`: Errores de escritura a disco silenciados
```swift
try? data.write(to: path, options: .atomic)  // Error ignorado
```
Si el disco está lleno, el caché falla silenciosamente sin log.

### LOW-04 — `LoginSheet.swift`: `await` superfluo en función síncrona
```swift
try await cookieStorage.saveSessionCookie(cookieString)  // saveSessionCookie no es async
```
Compila sin error pero confunde a lectores.

### LOW-05 — `HomeView.swift` línea ~560: Espaciado inconsistente
3 líneas en blanco consecutivas entre funciones. Cosmético, pero indica edición apresurada de múltiples agentes.

---

## 🔁 Mapa de Duplicaciones

| Patrón duplicado | Archivos afectados | Instancias |
|------------------|--------------------|------------|
| Lógica "Iniciar mix" (`buildRadioId + replaceQueue`) | `AlbumDetailView`, `PlaylistDetailView`, `ArtistDetailView`×3, `AppContextMenuFactory`×3 | **8+** |
| Construcción de `SongItemRecord` desde `HomeItemRecord`/`BrowseCardRecord` | `HomeView`×2, `ArtistDetailView`×2 | **4** |
| `loadingHeader` skeleton de carga | `AlbumDetailView`, `PlaylistDetailView`, `ArtistDetailView` | **3** |
| Estado de error + botón "Reintentar" | `AlbumDetailView`, `PlaylistDetailView`, `ArtistDetailView` | **3** |
| `DescriptionCardModal` + `isHoveringDesc` + cursor management | `AlbumDetailView`, `PlaylistDetailView`, `ArtistDetailView` | **3** |
| `navigateToArtist` + `navigateToAlbum` | `PlayerBarView`, `FullscreenNowPlayingView` | **2** |
| `playAll` / `shuffle` / `playTrack` | `AlbumDetailViewModel`, `PlaylistDetailViewModel` | **2** |
| Placeholder artwork fallback | `AlbumDetailView`, `PlaylistDetailView`, `ArtistDetailView`, `PlayerBarView`, `FullscreenNowPlayingView` | **5** |

---

## 🔗 Mapa de ViewModels → UniFFI

| ViewModel / Service | Funciones UniFFI consumidas |
|---------------------|-----------------------------|
| `PlayerViewModel` | `resolveStream`, `rateSong`, `getLyrics`, `getRadio`, `getRadioContinuation` |
| `AccountViewModel` | `getAccountInfo`, `isLoggedIn`, `setCookie` |
| `LibraryViewModel` | `getLibraryPlaylists`, `getLibraryAlbums`, `getHistory`, `isLoggedIn` |
| `AlbumDetailViewModel` | `getAlbum`, `likePlaylist` |
| `ArtistDetailViewModel` | `getArtist`, `subscribeArtist`, `getNext` |
| `PlaylistDetailViewModel` | `getPlaylist`, `getPlaylistContinuation`, `likePlaylist` |
| `HomeView` ⚠️ **directo en vista** | `getHomePage`, `getHomeContinuation`, `setCookie` |
| `AppContextMenuFactory` ⚠️ **directo** | `getLibraryPlaylists`, `addToPlaylist`, `getAlbum`, `getPlaylist`, `getNext`, `likePlaylist`, `subscribeArtist` |
| `AlbumDetailView` ⚠️ **directo en vista** | `getNext` (lógica inline) |
| `PlaylistDetailView` ⚠️ **directo en vista** | `getNext` (lógica inline) |
| `ArtistDetailView` ⚠️ **directo en vista** | `getAlbum`, `getNext` (lógica inline) |

> [!WARNING]
> Las filas marcadas con ⚠️ son llamadas directas a UniFFI desde una Vista, violando el patrón MVVM. Estas deben migrarse a sus respectivos ViewModels.

---

## 🗺️ Plan de Acción Priorizado

### Sprint 1 — Bugs funcionales que el usuario nota (esta semana)
| # | Fix | Archivo | Esfuerzo |
|---|-----|---------|---------|
| 1 | 🔴 Cambiar `NSTemporaryDirectory()` por `applicationSupportDirectory` | `SideBApp.swift` | 5 min |
| 2 | 🟠 Agregar vista de error si `initError != nil` | `SideBApp.swift` | 15 min |
| 3 | 🟠 Submenú "Añadir a playlist" — pre-cargar desde `LibraryViewModel` | `AppContextMenuFactory.swift` | 1h |
| 4 | 🟠 `isLiked` — mover a `PlayerViewModel` con lectura inicial del backend | `FullscreenNowPlayingView.swift` | 45 min |

### Sprint 2 — Deuda arquitectónica alta (próxima semana)
| # | Fix | Archivo | Esfuerzo |
|---|-----|---------|---------|
| 5 | 🟠 Crear `HomeViewModel.swift` con las 9 variables y 3 métodos | Nuevo archivo | 2h |
| 6 | 🟡 Reemplazar `LazyVStack` del panel "Recomendados" por `NativeTrackTableView` | `FullscreenNowPlayingView.swift` | 1h |
| 7 | 🟡 Fix detección de lista en `NativeTrackTableView` (hash completo) | `NativeTrackTableView.swift` | 30 min |
| 8 | 🟡 Mover índice activo de letras a `PlayerViewModel` | `PlayerViewModel.swift` + `FullscreenNowPlayingView.swift` | 1h |

### Sprint 3 — Limpieza y refactors (cuando haya tiempo)
| # | Fix | Archivo | Esfuerzo |
|---|-----|---------|---------|
| 9 | Eliminar `AppleMusicScrubber.swift` | `AppleMusicScrubber.swift` | 2 min |
| 10 | Confirmar y eliminar `TrackRowView.swift` si es zombie | `TrackRowView.swift` | 10 min |
| 11 | Extraer `DetailPageShell` genérico | Nuevo archivo | 2h |
| 12 | Centralizar lógica "Iniciar mix" en `PlayerViewModel.startRadioForCollection(id:title:)` | `PlayerViewModel.swift` | 1.5h |
| 13 | Reemplazar `AsyncImage` por `CachedAsyncImage` en Sidebar | `SidebarProfileView.swift` | 5 min |
| 14 | Marcar métodos legacy en `QueueManager` como `@available(*, deprecated)` | `QueueManager.swift` | 5 min |
| 15 | Agregar comentario de safety en `@unchecked Sendable` | `PlayerViewModel.swift` | 2 min |

---

## ✅ Lo que está bien (no tocar)

- **`NativeTrackTableView`** implementado en todas las listas de tracks (correctísimo)
- **`LiquidGlassCompat`** conectado al shader nativo, sin fallbacks CSS
- **`QueueManager`** con `replaceQueue` atómico y `isNearTail` sensor (sólido)
- **`CookieStorage`** con Keychain correctamente implementado
- **`NavigationRouter`** limpio y sin efectos secundarios
- **`CachedAsyncImage`** existe y funciona — solo falta aplicarlo en sidebar
- **`ImageURLHelper`** con downsampling CDN 96x96 correcto
- **Todos los ViewModels** (excepto `HomeViewModel` ausente) tienen `@Observable` + `@MainActor` correctamente aplicado
- **`AudioPlayerService`** con workaround del bug CoreMedia 2x correctamente documentado
- **Todos los observers KVO** en `NativeTrackTableView` y `AudioPlayerService` se limpian en `deinit`
