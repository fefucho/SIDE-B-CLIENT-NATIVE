# Plan Maestro de Correcciones y Refactorización — Side B (2026)

**Origen:** Auditoría Integral de Codex ([`AUDITORIA_INTEGRAL_2026-09-24.md`](file:///Users/stefano/Documents/PROGRAMACION%20PADRE/SIDE%20B%20RUST%20BASED%20PROJECTO/SIDE%20B/Cosas%20a%20mejorar/AUDITORIA_INTEGRAL_2026-09-24.md))  
**Reglas del Proyecto Aplicables:** [`.agents/rules/00-project_rules.md`](file:///Users/stefano/Documents/PROGRAMACION%20PADRE/SIDE%20B%20RUST%20BASED%20PROJECTO/.agents/rules/00-project_rules.md), [`.agents/rules/10-backend.md`](file:///Users/stefano/Documents/PROGRAMACION%20PADRE/SIDE%20B%20RUST%20BASED%20PROJECTO/.agents/rules/10-backend.md), [`.agents/rules/20-frontend.md`](file:///Users/stefano/Documents/PROGRAMACION%20PADRE/SIDE%20B%20RUST%20BASED%20PROJECTO/.agents/rules/20-frontend.md), [`swiftui-pro/SKILL.md`](file:///Users/stefano/Documents/PROGRAMACION%20PADRE/SIDE%20B%20RUST%20BASED%20PROJECTO/.agents/skills/swiftui-pro/SKILL.md)  
**Objetivo:** Resolver de forma metódica y estructurada los 26 hallazgos (A01 a A26) y la investigación de rendimiento en el Home Feed, organizados por dominios técnicos y prioridades de ingeniería.

---

## Índice General por Secciones

- [Sección 1: Seguridad, Aislamiento de Entorno y Pruebas](#sección-1-seguridad-aislamiento-de-entorno-y-pruebas) (A01, A08)
- [Sección 2: Autenticación, Gestión de Sesión y Persistencia](#sección-2-autenticación-gestión-de-sesión-y-persistencia) (A02, A14, A17)
- [Sección 3: Motor de Reproducción, Sincronización de Cola y Radio](#sección-3-motor-de-reproducción-sincronización-de-cola-y-radio) (A04, A10, A11, A13, A23, A24)
- [Sección 4: Búsqueda, Modal Spotlight y Navegación](#sección-4-búsqueda-modal-spotlight-y-navegación) (A03, A09, A20, A22, A25, A26)
- [Sección 5: Feed de Inicio, Catálogo y Vistas de Detalle](#sección-5-feed-de-inicio-catálogo-y-vistas-de-detalle) (A05, A06, A07, A12, A19)
- [Sección 6: Manejo Granular de Errores, Estados Vacíos y Resiliencia de UI](#sección-6-manejo-granular-de-errores-estados-vacíos-y-resiliencia-de-ui) (A15, A16)
- [Sección 7: Gestión de Recursos de Disco, Caché y Accesibilidad](#sección-7-gestión-de-recursos-de-disco-caché-y-accesibilidad) (A18, A21)
- [Sección 8: Rendimiento del Home Feed y Optimización Medida de Scroll](#sección-8-rendimiento-del-home-feed-y-optimización-medida-de-scroll) (Investigación Específica)
- [Estrategia de Ejecución por Fases y Verificación](#estrategia-de-ejecución-por-fases-y-verificación)

---

## Sección 1: Seguridad, Aislamiento de Entorno y Pruebas

Esta sección contiene los puntos críticos de seguridad y separación de datos para garantizar que el desarrollo, las pruebas y los entornos paralelos no colisionen con las credenciales o bases de datos de producción.

### [A01] Aislamiento de Identidad, Bundle ID, Keychain y Application Support
- **Prioridad:** P1
- **Archivos Afectados:**
  - [`apple/Sources/SideB/Services/HomeLabConfiguration.swift`](file:///Users/stefano/Documents/PROGRAMACION%20PADRE/SIDE%20B%20RUST%20BASED%20PROJECTO/SIDE%20B/apple/Sources/SideB/Services/HomeLabConfiguration.swift)
  - [`apple/Sources/SideB/Services/Storage/CookieStorage.swift`](file:///Users/stefano/Documents/PROGRAMACION%20PADRE/SIDE%20B%20RUST%20BASED%20PROJECTO/SIDE%20B/apple/Sources/SideB/Services/Storage/CookieStorage.swift)
  - [`apple/Sources/SideB/Views/Login/LoginWebView.swift`](file:///Users/stefano/Documents/PROGRAMACION%20PADRE/SIDE%20B%20RUST%20BASED%20PROJECTO/SIDE%20B/apple/Sources/SideB/Views/Login/LoginWebView.swift)
  - [`Scripts/build-app.sh`](file:///Users/stefano/Documents/PROGRAMACION%20PADRE/SIDE%20B%20RUST%20BASED%20PROJECTO/SIDE%20B/Scripts/build-app.sh)
- **Diagnóstico:**
  La copia de trabajo o ejecutable comparte el bundle identifier `com.fefucho.SideB`, el directorio `Application Support/SideB`, la caché y el servicio Keychain `com.fefucho.SideB.auth`. `WKWebsiteDataStore` usa `.default()`. Un cambio en la copia sobrescribe o lee la sesión de la app principal.
- **Tareas Técnicas:**
  1. Parametrizar de forma robusta el prefijo de servicio Keychain (`KeychainConfiguration`/`AppEnvironment`) y el subdirectorio de datos (`Application Support/SideB-Dev` o condicionado por bundle/flag de compilación).
  2. Implementar `WKWebsiteDataStore` no persistente o con identificador aislado para instancias de prueba o laboratorio, impidiendo contaminación de cookies compartidas con Safari/otra instancia.
  3. Ajustar [`build-app.sh`](file:///Users/stefano/Documents/PROGRAMACION%20PADRE/SIDE%20B%20RUST%20BASED%20PROJECTO/SIDE%20B/Scripts/build-app.sh) para soportar identificadores de compilación de desarrollo diferenciados.
- **Verificación:**
  Ejecutar dos instancias en paralelo; iniciar sesión con cuentas distintas en cada una y verificar que cerrar sesión en una deja intacta la otra.

### [A08] Desacoplamiento de Pruebas Automáticas del Keychain y Red de Producción
- **Prioridad:** P1
- **Archivos Afectados:**
  - [`apple/Tests/SideBTests/SideBTests.swift`](file:///Users/stefano/Documents/PROGRAMACION%20PADRE/SIDE%20B%20RUST%20BASED%20PROJECTO/SIDE%20B/apple/Tests/SideBTests/SideBTests.swift)
- **Diagnóstico:**
  `testLiveAccountAndLibraryWithKeychainCookie` lee la cookie de producción del Keychain real y ejecuta `SecItemUpdate` si la sanea. Ejecutar `swift test` altera silenciosamente la sesión del usuario en macOS. Además, `testGetHomeSections` depende de red en vivo sin determinismo.
- **Tareas Técnicas:**
  1. Extraer o deshabilitar `testLiveAccountAndLibraryWithKeychainCookie` de la suite estándar de pruebas (`swift test`).
  2. Condicionar cualquier prueba de diagnóstico en vivo a un flag explícito de entorno (`RUN_LIVE_AUTH_TESTS=1`) y a un Keychain simulado/temporal (`NSTemporaryDirectory()` / cuenta efímera).
  3. Reemplazar pruebas que dependen de red en vivo en la suite básica por pruebas con fixtures estáticos (JSON pregrabados en `core/crates/innertube` y tests de deserialización).
- **Verificación:**
  Ejecutar `swift test` completo y comprobar que no se realizan llamadas de red a YouTube Music ni modificaciones (`SecItemUpdate`) en el Keychain real.

---

## Sección 2: Autenticación, Gestión de Sesión y Persistencia

Esta sección aborda la consistencia entre Rust y Swift respecto a cookies, expiración de sesión, transiciones de cuenta y prevención de condiciones de carrera.

### [A02] Carreras en Respuestas Tardías al Cambiar de Cuenta (Invalidación por Generación)
- **Prioridad:** P1
- **Archivos Afectados:**
  - [`apple/Sources/SideB/ViewModels/AccountViewModel.swift`](file:///Users/stefano/Documents/PROGRAMACION%20PADRE/SIDE%20B%20RUST%20BASED%20PROJECTO/SIDE%20B/apple/Sources/SideB/ViewModels/AccountViewModel.swift)
  - [`apple/Sources/SideB/ViewModels/LibraryViewModel.swift`](file:///Users/stefano/Documents/PROGRAMACION%20PADRE/SIDE%20B%20RUST%20BASED%20PROJECTO/SIDE%20B/apple/Sources/SideB/ViewModels/LibraryViewModel.swift)
  - [`apple/Sources/SideB/UI/AppContextMenuFactory.swift`](file:///Users/stefano/Documents/PROGRAMACION%20PADRE/SIDE%20B%20RUST%20BASED%20PROJECTO/SIDE%20B/apple/Sources/SideB/UI/AppContextMenuFactory.swift)
- **Diagnóstico:**
  `AccountViewModel.fetchAccount` y `LibraryViewModel.loadLibrary` asignan datos después de `await` sin verificar si la sesión sigue siendo la misma o si la petición fue cancelada. `LibraryViewModel.clear()` no vacía `AppContextMenuFactory.cachedUserPlaylists`. Un logout durante una petición en vuelo puede volver a pintar la cuenta anterior.
- **Tareas Técnicas:**
  1. Implementar un identificador de sesión o token de generación monotónico (`sessionGeneration: UInt64`) en `AccountViewModel` y `LibraryViewModel`.
  2. Cancelar explícitamente todas las tareas asíncronas activas de carga (`accountTask?.cancel()`, `libraryTask?.cancel()`) al invocar `logout()` o `setSession()`.
  3. Validar `guard currentGeneration == self.sessionGeneration else { return }` inmediatamente tras cada `await`.
  4. Purgar `AppContextMenuFactory.cachedUserPlaylists` y todas las memorias intermedias por cuenta en `LibraryViewModel.clear()`.
- **Verificación:**
  Simular retardo artificial en `getAccountInfo`, cerrar sesión inmediatamente tras lanzar la petición y validar que la UI permanece en estado no autenticado.

### [A14] Unificación de la Autoridad de Persistencia de Sesión (Rust SQLite vs. Swift Keychain)
- **Prioridad:** P2
- **Archivos Afectados:**
  - [`core/crates/sideb-core/src/lib.rs`](file:///Users/stefano/Documents/PROGRAMACION%20PADRE/SIDE%20B%20RUST%20BASED%20PROJECTO/SIDE%20B/core/crates/sideb-core/src/lib.rs)
  - [`core/crates/sideb-core/src/db.rs`](file:///Users/stefano/Documents/PROGRAMACION%20PADRE/SIDE%20B%20RUST%20BASED%20PROJECTO/SIDE%20B/core/crates/sideb-core/src/db.rs)
  - [`core/crates/innertube/src/transport.rs`](file:///Users/stefano/Documents/PROGRAMACION%20PADRE/SIDE%20B%20RUST%20BASED%20PROJECTO/SIDE%20B/core/crates/innertube/src/transport.rs)
  - [`apple/Sources/SideB/ViewModels/AccountViewModel.swift`](file:///Users/stefano/Documents/PROGRAMACION%20PADRE/SIDE%20B%20RUST%20BASED%20PROJECTO/SIDE%20B/apple/Sources/SideB/ViewModels/AccountViewModel.swift)
  - [`apple/Sources/SideB/Services/Storage/CookieStorage.swift`](file:///Users/stefano/Documents/PROGRAMACION%20PADRE/SIDE%20B%20RUST%20BASED%20PROJECTO/SIDE%20B/apple/Sources/SideB/Services/Storage/CookieStorage.swift)
- **Diagnóstico:**
  Existen múltiples fuentes de la verdad para la cookie: SQLite en Rust, Keychain en Swift y archivos de fallback. Cuando `getHomePage` reporta `SessionExpired`, Rust borra su cookie local en SQLite, pero el Keychain en Swift no se invalida, provocando que el próximo arranque reinyecte la cookie inválida. Además, las cookies rotadas en `transport.rs` no se persisten hacia el Keychain.
- **Tareas Técnicas:**
  1. Definir una jerarquía clara: Swift Keychain es la autoridad persistente en macOS; Rust mantiene el estado en memoria para InnerTube y notifica eventos de expiración/rotación mediante contratos UniFFI.
  2. Exponer un callback/notificación desde Rust a Swift ante eventos de sesión (`SessionExpired`, `CookieRotated(String)`).
  3. Al recibir `SessionExpired`, ejecutar borrado coordinado en Keychain, almacenamiento local y estado de memoria.
  4. Eliminar el archivo plano de fallback residual de cookies una vez completada la persistencia en Keychain.
- **Verificación:**
  Forzar un error `SessionExpired` (HTTP 401/403 de InnerTube); confirmar que la app limpia el Keychain y no reanuda sesión rota al reiniciar.

### [A17] Consistencia en el Proceso de Login, Saneamiento de Cookies y Estado de WebKit
- **Prioridad:** P2
- **Archivos Afectados:**
  - [`apple/Sources/SideB/Views/Login/LoginSheet.swift`](file:///Users/stefano/Documents/PROGRAMACION%20PADRE/SIDE%20B%20RUST%20BASED%20PROJECTO/SIDE%20B/apple/Sources/SideB/Views/Login/LoginSheet.swift)
  - [`apple/Sources/SideB/Views/Login/LoginWebView.swift`](file:///Users/stefano/Documents/PROGRAMACION%20PADRE/SIDE%20B%20RUST%20BASED%20PROJECTO/SIDE%20B/apple/Sources/SideB/Views/Login/LoginWebView.swift)
  - [`apple/Sources/SideB/ViewModels/AccountViewModel.swift`](file:///Users/stefano/Documents/PROGRAMACION%20PADRE/SIDE%20B%20RUST%20BASED%20PROJECTO/SIDE%20B/apple/Sources/SideB/ViewModels/AccountViewModel.swift)
- **Diagnóstico:**
  `LoginSheet` calcula la cookie saneada y la guarda en Keychain, pero inyecta al núcleo Rust (`core.setCookie`) la cadena cruda original sin sanear, provocando discrepancia entre la sesión viva y la restaurada tras reiniciar. En caso de fallo al escribir en Keychain, solo imprime en consola sin avisar al usuario. `WKWebsiteDataStore` no se limpia al cerrar sesión.
- **Tareas Técnicas:**
  1. Inyectar al Core de Rust exactamente la misma cadena saneada y canónica que se almacena en el Keychain.
  2. Propagar errores de guardado de Keychain a la UI en `LoginSheet` con alerta y opción de reintento.
  3. Limpiar las cookies de `WKWebsiteDataStore` asociadas a YouTube/Google cuando el usuario hace logout explícito en la app.
- **Verificación:**
  Iniciar sesión con una cuenta que emita cookies con parámetros irrelevantes/duplicados; verificar igualdad de la cookie en Rust antes y después de reiniciar la app.

---

## Sección 3: Motor de Reproducción, Sincronización de Cola y Radio

Esta sección asegura que el reproductor de audio (`AVPlayer`), la cola (`QueueManager`), el estado visual y las continuaciones de radio y playlists permanezcan perfectamente sincronizados.

### [A04] Protección de Cola contra Respuestas Tardías de Radio (Tokens de Cola) — ✅ RESUELTO
- **Prioridad:** P1
- **Estado:** ✅ Resuelto y verificado.
- **Solución Implementada:**
  - Se agregó `queueToken: UUID` a [`QueueManager.swift`](file:///Users/stefano/Documents/PROGRAMACION%20PADRE/SIDE%20B%20RUST%20BASED%20PROJECTO/SIDE%20B/apple/Sources/SideB/Services/Player/QueueManager.swift) que rota atómicamente con cada `replaceQueue`.
  - Se implementaron tokens de generación y cancelación de tareas asíncronas (`currentRadioToken`, `currentAutomixToken`, `radioTask`, `automixTask`, `collectionRadioTask`) en [`PlayerViewModel.swift`](file:///Users/stefano/Documents/PROGRAMACION%20PADRE/SIDE%20B%20RUST%20BASED%20PROJECTO/SIDE%20B/apple/Sources/SideB/ViewModels/PlayerViewModel.swift).
  - Comprobación estricta post-`await` en `startRadioForCollection`, `fetchRadio` y `extendRadioIfNeeded` asegurando que ninguna respuesta tardía o cancelada contamine la cola activa.

### [A10] Sincronización entre Transición de Audio y Presentación en UI (Manejo de Errores) — ✅ RESUELTO
- **Prioridad:** P2
- **Estado:** ✅ Resuelto y verificado.
- **Solución Implementada:**
  - En `playSongNow`, el audio anterior se pausa de inmediato (`audioService.pause()`), evitando que siga sonando mientras se resuelve el nuevo stream.
  - Se agregó el método `retryPlayback()` en [`PlayerViewModel.swift`](file:///Users/stefano/Documents/PROGRAMACION%20PADRE/SIDE%20B%20RUST%20BASED%20PROJECTO/SIDE%20B/apple/Sources/SideB/ViewModels/PlayerViewModel.swift).
  - En [`PlayerBarView.swift`](file:///Users/stefano/Documents/PROGRAMACION%20PADRE/SIDE%20B%20RUST%20BASED%20PROJECTO/SIDE%20B/apple/Sources/SideB/Views/Components/PlayerBarView.swift), el botón de transporte conmuta a icono de reintento (`arrow.clockwise`) ante error de stream y se presenta banner con aviso y botón "Reintentar" en el subtítulo.

### [A11] Hidratación y Reversión Optimista de «Me gusta» en el Reproductor — ✅ RESUELTO
- **Prioridad:** P2
- **Estado:** ✅ Resuelto y verificado.
- **Solución Implementada:**
  - Se añadió `hydrateLikedSongs()` en [`PlayerViewModel.swift`](file:///Users/stefano/Documents/PROGRAMACION%20PADRE/SIDE%20B%20RUST%20BASED%20PROJECTO/SIDE%20B/apple/Sources/SideB/ViewModels/PlayerViewModel.swift), que consulta la playlist remota "LM" al inicializar o conectar el núcleo y puebla `likedVideoIds`.
  - En `toggleTrackLike` y `dislikeTrack`, se implementó reversión automática del estado optimista si la llamada `rateSong` remota falla, desplegando notificación de error legible en la UI.
  - Se expuso `clearAccountState()` para vaciar valoraciones locales al cerrar sesión.

### [A13] Paginación y Continuación de Cola en Playlists Extensas — ✅ RESUELTO
- **Prioridad:** P2
- **Estado:** ✅ Resuelto y verificado.
- **Solución Implementada:**
  - Se implementó `appendPlaylistTracks(_:nextContinuation:)` en [`QueueManager.swift`](file:///Users/stefano/Documents/PROGRAMACION%20PADRE/SIDE%20B%20RUST%20BASED%20PROJECTO/SIDE%20B/apple/Sources/SideB/Services/Player/QueueManager.swift).
  - Se añadió `extendPlaylistIfNeeded()` en [`PlayerViewModel.swift`](file:///Users/stefano/Documents/PROGRAMACION%20PADRE/SIDE%20B%20RUST%20BASED%20PROJECTO/SIDE%20B/apple/Sources/SideB/ViewModels/PlayerViewModel.swift) con llamada asíncrona a `core.getPlaylistContinuation(token:)`.
  - En `checkAutomixTrigger()` y `playNext()`, si el contexto es `.playlist` y `continuationToken` está presente, se prioriza la carga de las siguientes páginas de la playlist sobre las recomendaciones de radio Automix.

### [A23] Manejo de Duplicados en Cola (Identidad por Ocurrencia) y Modo Repetir — ✅ RESUELTO
- **Prioridad:** P3
- **Estado:** ✅ Resuelto y verificado.
- **Solución Implementada:**
  - En `QueueManager.moveTrack`, se reemplazó la búsqueda por `videoId` por ajuste aritmético de índices (`currentIndex`), impidiendo que mover una pista salte a la primera ocurrencia duplicada.
  - En `syncCurrentIndex`, si el elemento en `currentIndex` ya coincide con el `videoId`, se preserva el índice activo.
  - En `nextTrack(isManualSkip:)`, se diferenció el salto manual (que avanza a la siguiente canción) del fin de pista natural de audio (que reinicia la canción si `isRepeat` está activo).

### [A24] Limpieza de Metadatos de Artista/Álbum en Transiciones de Pista — ✅ RESUELTO
- **Prioridad:** P3
- **Estado:** ✅ Resuelto y verificado.
- **Solución Implementada:**
  - En `playSongNow`, `currentArtistBrowseId` y `currentAlbumBrowseId` se reinicializan atómicamente a `nil` si la pista entrante carece de IDs de procedencia, admitiendo overrides explícitos en `playWithRadio` y `playAlbum`.
  - En `playPlaylist`, los IDs de álbum y artista se limpian explícitamente al inicio.
  - En `PlayerBarView` y `FullscreenNowPlayingView`, las funciones de navegación utilizan fallback a búsqueda por nombre solo cuando no existe browseId activo, eliminando la navegación a metadatos de pistas anteriores.

---

## Sección 4: Búsqueda, Modal Spotlight y Navegación

Esta sección unifica las mejoras en el flujo de búsqueda, debounce, modales flotantes y enrutamiento entre ventanas y pantallas.

### [A03] Invalidación y Debounce de Resultados Rápidos en Búsqueda (Control por Generación) — ✅ RESUELTO
- **Prioridad:** P1
- **Estado:** ✅ Resuelto y verificado.
- **Solución Implementada:**
  - Se vinculó cada resultado rápido a su consulta exacta mediante `associatedQuickQuery: String` en [`SearchViewModel.swift`](file:///Users/stefano/Documents/PROGRAMACION%20PADRE/SIDE%20B%20RUST%20BASED%20PROJECTO/SIDE%20B/apple/Sources/SideB/ViewModels/SearchViewModel.swift).
  - En `onQueryChanged`, si la consulta cambia respecto a los resultados cacheados, se invalida `quickResults = nil` de inmediato, evitando que se muestren resultados de consultas anteriores al tipear rápido.
  - En `commitSearch`, se valida que `associatedQuickQuery == trimmed` antes de reutilizar resultados cacheados, forzando búsqueda fresca si la consulta discordaba.
  - En [`SpotlightSearchModal.swift`](file:///Users/stefano/Documents/PROGRAMACION%20PADRE/SIDE%20B%20RUST%20BASED%20PROJECTO/SIDE%20B/apple/Sources/SideB/Views/Search/SpotlightSearchModal.swift), se asegura que los resultados solo se renderizan si `associatedQuickQuery == trimmed` y se presenta `searchLoadingPlaceholder` durante búsquedas en vuelo.

### [A09] Aislamiento de Respuestas de Filtros y Pestañas en Búsqueda — ✅ RESUELTO
- **Prioridad:** P2
- **Estado:** ✅ Resuelto y verificado.
- **Solución Implementada:**
  - Se incorporaron tokens monotónicos de generación `filterGeneration: UInt` y `commitGeneration: UInt` en [`SearchViewModel.swift`](file:///Users/stefano/Documents/PROGRAMACION%20PADRE/SIDE%20B%20RUST%20BASED%20PROJECTO/SIDE%20B/apple/Sources/SideB/ViewModels/SearchViewModel.swift).
  - Al cambiar de filtro en `selectFilter`, se cancela `filterTask`, se limpia la lista de resultados previa para evitar flashes de tarjetas discordantes y se incrementa `filterGeneration`.
  - En `fetchFilteredSongs` y `fetchFilteredCards`, se verifica tras el `await` que `!Task.isCancelled`, que la generación sigue activa, que `self.selectedFilter == expectedFilter` y que `self.committedQuery == text`.

### [A20] Despliegue Incorrecto del Dropdown Flotante sobre la Vista de Resultados — ✅ RESUELTO
- **Prioridad:** P2
- **Estado:** ✅ Resuelto y verificado.
- **Solución Implementada:**
  - En [`SearchView.swift`](file:///Users/stefano/Documents/PROGRAMACION%20PADRE/SIDE%20B%20RUST%20BASED%20PROJECTO/SIDE%20B/apple/Sources/SideB/Views/Search/SearchView.swift), se conectó el `searchViewModel` compartido por ventana y se ató el dropdown topdown a `@FocusState private var isSearchBarFocused: Bool`.
  - La visualización del dropdown flotante solo se permite si `isSearchBarFocused && searchViewModel.isTopdownVisible && associatedQuickQuery == query.trimmed`.
  - Al presionar Enter (`.onSubmit`), seleccionar un ítem del dropdown o hacer clic en el fondo de la pantalla, se retira el foco y se oculta el dropdown.
  - En `onAppear`, si la búsqueda ya fue comprometida previamente, no se relanza búsqueda redundante ni debounce de búsqueda rápida.

### [A22] Adaptabilidad y Dimensiones del Modal de Búsqueda en Ventanas Compactas — ✅ RESUELTO
- **Prioridad:** P2
- **Estado:** ✅ Resuelto y verificado.
- **Solución Implementada:**
  - Se reemplazó el ancho estático fijo de `850pt` en [`SpotlightSearchModal.swift`](file:///Users/stefano/Documents/PROGRAMACION%20PADRE/SIDE%20B%20RUST%20BASED%20PROJECTO/SIDE%20B/apple/Sources/SideB/Views/Search/SpotlightSearchModal.swift) por un ancho adaptativo responsivo:
    `let modalWidth = min(max(proxy.size.width - 48, 360), 850)`.
  - El modal ahora mantiene márgenes simétricos seguros incluso en la ventana de tamaño mínimo de 960pt con barra lateral expandida.

### [A25] Consistencia en el Historial de Navegación y Menús Contextuales — ✅ RESUELTO
- **Prioridad:** P3
- **Estado:** ✅ Resuelto y verificado.
- **Solución Implementada:**
  - En [`NavigationRouter.swift`](file:///Users/stefano/Documents/PROGRAMACION%20PADRE/SIDE%20B%20RUST%20BASED%20PROJECTO/SIDE%20B/apple/Sources/SideB/Services/Navigation/NavigationRouter.swift), `navigate(to:)` descarta destinos idénticos al actual (`guard destination != currentPage else { return }`), impidiendo que clics repetidos en Inicio o cualquier pestaña acumulen pasos inútiles en la pila de historial.
  - En [`HistoryView.swift`](file:///Users/stefano/Documents/PROGRAMACION%20PADRE/SIDE%20B%20RUST%20BASED%20PROJECTO/SIDE%20B/apple/Sources/SideB/Views/History/HistoryView.swift), se inyectó `router: NavigationRouter?` y se pasaron `playerViewModel`, `router`, `rustCore`, `likedVideoIds` y los callbacks `onLikeTrack` / `onDislikeTrack` a `NativeTrackTableView`, habilitando todos los menús contextuales y la interactividad de favoritos.

### [A26] Gestión de Estado de Navegación por Ventana (Multi-Window Support) — ✅ RESUELTO
- **Prioridad:** P3
- **Estado:** ✅ Resuelto y verificado.
- **Solución Implementada:**
  - Se extrajo `WindowRootView` en [`SideBApp.swift`](file:///Users/stefano/Documents/PROGRAMACION%20PADRE/SIDE%20B%20RUST%20BASED%20PROJECTO/SIDE%20B/apple/Sources/SideB/SideBApp.swift), de modo que cada ventana de macOS es dueña de su propio `NavigationRouter`, `SearchViewModel`, estado de barra lateral y modal Spotlight.
  - Se añadió `.commands { CommandGroup(replacing: .newItem) {} }` para anular la duplicación de ventanas mediante ⌘N, manteniendo atajos estándar ⌘K y ⌘F para búsqueda.
  - Se protegió la restauración de sesión mediante `hasBootstrappedSession` para que ocurra una sola vez.

---

## Sección 5: Feed de Inicio, Catálogo y Vistas de Detalle

Esta sección resuelve inconsistencias de tipos de contenido en el feed de inicio, destinos de enlaces, botones no conectados y sincronización de librerías.

### [A05] Tipado Estricto de Ítems en Inicio («Forgotten Favorites» y Tipos Mixtos) — ✅ RESUELTO
- **Prioridad:** P1
- **Estado:** ✅ Resuelto y verificado.
- **Solución Implementada:**
  - En [`HomeFeedCollectionView.swift`](file:///Users/stefano/Documents/PROGRAMACION%20PADRE/SIDE%20B%20RUST%20BASED%20PROJECTO/SIDE%20B/apple/Sources/SideB/Views/Home/HomeFeedCollectionView.swift), se incorporaron los helpers estáticos `cleanArtistName(from:)`, `cleanAlbumName(from:)`, `isGenericTypePrefix(_:)` y `parseSubtitleComponents(_:)` en `HomeItemView`.
  - Se filtran prefijos genéricos de tipo de entidad (`"album"`, `"álbum"`, `"single"`, `"sencillo"`, `"ep"`, `"song"`, `"playlist"`, `"mix"`) del subtítulo.
  - Para ítems donde `record.kind == "album"`, el botón de álbum se oculta (`album.isHidden = true`) para no duplicar datos, y `artist` toma el ancho completo disponible en la celda (`bounds.width - 100`).
  - En `navigateArtist` y `navigateAlbum`, se usan `cleanArtistName` y `cleanAlbumName`, impidiendo búsquedas de la palabra literal "Album" o "Single".

### [A06] Enrutamiento Correcto de «Ver Todo» y Destinos No-Playlist (`moreParams` / Moods / Genres) — ✅ RESUELTO
- **Prioridad:** P1
- **Estado:** ✅ Resuelto y verificado.
- **Solución Implementada:**
  - En [`HomeFeedPresentation.swift`](file:///Users/stefano/Documents/PROGRAMACION%20PADRE/SIDE%20B%20RUST%20BASED%20PROJECTO/SIDE%20B/apple/Sources/SideB/Models/HomeFeedPresentation.swift), se conservó `moreParams: String?` en `HomeSectionPresentation` preservando los parámetros que devuelve `HomeSectionRecord` de Rust.
  - Se definió la propiedad calculada `isNavigableMore: Bool` para verificar que `moreBrowseId` exista y no sea un browse ID de sistema de categoría (`FEmusic...`).
  - En [`HomeFeedCollectionView.swift`](file:///Users/stefano/Documents/PROGRAMACION%20PADRE/SIDE%20B%20RUST%20BASED%20PROJECTO/SIDE%20B/apple/Sources/SideB/Views/Home/HomeFeedCollectionView.swift), el botón "Ver más" de `HomeSectionHeaderView` solo se habilita con `section.isNavigableMore`, y `navigateMore` descarta IDs con prefijo `FE` para evitar peticiones inválidas a playlists 404 con prefijo `VL`.

### [A07] Conexión de Acciones «Me gusta» / «No me gusta» en Tablas de Álbum, Playlist y Búsqueda — ✅ RESUELTO
- **Prioridad:** P1
- **Estado:** ✅ Resuelto y verificado.
- **Solución Implementada:**
  - Conectadas las acciones interactivas `likedVideoIds: playerViewModel.likedVideoIds`, `onLikeTrack: { playerViewModel.toggleTrackLike($0) }` y `onDislikeTrack: { playerViewModel.dislikeTrack($0) }` en:
    - [`AlbumDetailView.swift`](file:///Users/stefano/Documents/PROGRAMACION%20PADRE/SIDE%20B%20RUST%20BASED%20PROJECTO/SIDE%20B/apple/Sources/SideB/Views/Detail/AlbumDetailView.swift)
    - [`PlaylistDetailView.swift`](file:///Users/stefano/Documents/PROGRAMACION%20PADRE/SIDE%20B%20RUST%20BASED%20PROJECTO/SIDE%20B/apple/Sources/SideB/Views/Detail/PlaylistDetailView.swift)
    - [`SearchView.swift`](file:///Users/stefano/Documents/PROGRAMACION%20PADRE/SIDE%20B%20RUST%20BASED%20PROJECTO/SIDE%20B/apple/Sources/SideB/Views/Search/SearchView.swift)
  - Las pistas en todas las tablas reflejan inmediatamente su estado de favorito e interactúan directamente con la biblioteca remota y local.

### [A12] Estado Inicial de Membresía de Biblioteca en Vista de Playlist — ✅ RESUELTO
- **Prioridad:** P2
- **Estado:** ✅ Resuelto y verificado.
- **Solución Implementada:**
  - En [`PlaylistDetailViewModel.swift`](file:///Users/stefano/Documents/PROGRAMACION%20PADRE/SIDE%20B%20RUST%20BASED%20PROJECTO/SIDE%20B/apple/Sources/SideB/ViewModels/PlaylistDetailViewModel.swift), al cargar el detalle con `loadPlaylist`, se cruza el ID de la lista con `AppContextMenuFactory.cachedUserPlaylists`:
    `let isUserCached = AppContextMenuFactory.cachedUserPlaylists.contains(where: { $0.id == playlistId || $0.id == detail.id })`
    `self.inLibrary = detail.inLibrary || detail.owned || isUserCached`
  - Playlists guardadas por el usuario que InnerTube devuelve con `inLibrary == false` se reconocen de forma inmediata y consistente con el botón "En biblioteca".

### [A19] Manejo de Estado en Error de Refresco con Feed en Caché — ✅ RESUELTO
- **Prioridad:** P2
- **Estado:** ✅ Resuelto y verificado.
- **Solución Implementada:**
  - En [`HomeView.swift`](file:///Users/stefano/Documents/PROGRAMACION%20PADRE/SIDE%20B%20RUST%20BASED%20PROJECTO/SIDE%20B/apple/Sources/SideB/Views/Home/HomeView.swift), se reestructuró `statusBanner`: si `errorMessage != nil`, se le da prioridad sobre `isShowingSavedFeed`, mostrando un aviso no bloqueante ("No se pudo actualizar · Contenido guardado" o "Sin conexión · se muestran las últimas recomendaciones") junto con un botón interactivo "Reintentar" que ejecuta `refresh()`.

---

## Sección 6: Manejo Granular de Errores, Estados Vacíos y Resiliencia de UI

Esta sección mejora la resiliencia de la interfaz, evitando skeletons infinitos y diferenciando fallos de red de listas genuinamente vacías.

### [A15] Recuperación de Error en Perfil de Usuario (Evitar Skeleton Infinito) — ✅ RESUELTO
- **Prioridad:** P2
- **Estado:** ✅ Resuelto y verificado.
- **Solución Implementada:**
  - En [`SidebarProfileView.swift`](file:///Users/stefano/Documents/PROGRAMACION%20PADRE/SIDE%20B%20RUST%20BASED%20PROJECTO/SIDE%20B/apple/Sources/SideB/Views/Sidebar/SidebarProfileView.swift), cuando `accountViewModel.isLoggedIn == true` pero `account == nil` tras fallo de red (`errorMessage != nil || !accountViewModel.isLoading`), se renderiza `errorProfileButton(errorMessage:)` en lugar de caer perpetuamente en `loadingSkeleton`.
  - El botón expone un popover y menú contextual con opciones para "Reintentar conexión" (`fetchAccount`) y "Cerrar sesión" (`logout`), recuperando el control de la interfaz.

### [A16] Manejo Granular de Errores en Biblioteca, Historial y Búsqueda (Diferenciar Fallo de Vacío) — ✅ RESUELTO
- **Prioridad:** P2
- **Estado:** ✅ Resuelto y verificado.
- **Solución Implementada:**
  - En [`LibraryViewModel.swift`](file:///Users/stefano/Documents/PROGRAMACION%20PADRE/SIDE%20B%20RUST%20BASED%20PROJECTO/SIDE%20B/apple/Sources/SideB/ViewModels/LibraryViewModel.swift), se desacoplaron las tres cargas concurrentes (`getLibraryPlaylists()`, `getLibraryAlbums()`, `getHistory()`) en bloques independientes `Result<T, Error>`. Una falla en historial o álbumes ya no descarta las playlists existentes.
  - Se añadieron `isHistoryLoading` y `historyErrorMessage` en `LibraryViewModel`.
  - En [`HistoryView.swift`](file:///Users/stefano/Documents/PROGRAMACION%20PADRE/SIDE%20B%20RUST%20BASED%20PROJECTO/SIDE%20B/apple/Sources/SideB/Views/History/HistoryView.swift), se diferencia formalmente entre historial vacío y error de conexión, presentando `DetailErrorStateView` con botón de reintento.
  - En [`SidebarView.swift`](file:///Users/stefano/Documents/PROGRAMACION%20PADRE/SIDE%20B%20RUST%20BASED%20PROJECTO/SIDE%20B/apple/Sources/SideB/Views/Sidebar/SidebarView.swift), si la biblioteca falla al cargar estando vacía, se muestra un aviso sutil de error con botón de "Reintentar".

---

## Sección 7: Gestión de Recursos de Disco, Caché y Accesibilidad

Esta sección atiende la fuga de espacio en disco por la caché de imágenes y garantiza conformidad con los estándares de accesibilidad nativos de macOS.

### [A18] Evicción Activa y Monitoreo de la Caché de Imágenes en Disco
- **Prioridad:** P2
- **Archivos Afectados:**
  - [`apple/Sources/SideB/Utilities/ImageCache.swift`](file:///Users/stefano/Documents/PROGRAMACION%20PADRE/SIDE%20B%20RUST%20BASED%20PROJECTO/SIDE%20B/apple/Sources/SideB/Utilities/ImageCache.swift)
- **Diagnóstico:**
  `scheduleDiskEviction` solo se invoca en el `init` de `ImageCache`. Tras iniciarse, las llamadas a `saveToDisk` agregan archivos indefinidamente sin reprogramar la limpieza. En sesiones largas de reproducción y exploración, la caché excede ampliamente el límite configurado de 200 MB hasta el siguiente reinicio de la app.
- **Tareas Técnicas:**
  1. Registrar un contador de bytes escritos o escrituras acumuladas y disparar la evicción periódica fuera del hilo principal (`Task.detached(priority: .background)`).
  2. Implementar purga LRU basada en fecha de último acceso de archivos en disco cuando el volumen supere los 200 MB.
- **Verificación:**
  Escribir pruebas con múltiples descargas de carátulas simuladas; verificar que la carpeta de caché no supera el umbral límite configurado durante la sesión.

### [A21] Soporte de Accesibilidad Completa: Foco de Teclado, Sliders Nativos y VoiceOver
- **Prioridad:** P2
- **Archivos Afectados:**
  - [`apple/Sources/SideB/Views/Home/HomeFeedCollectionView.swift`](file:///Users/stefano/Documents/PROGRAMACION%20PADRE/SIDE%20B%20RUST%20BASED%20PROJECTO/SIDE%20B/apple/Sources/SideB/Views/Home/HomeFeedCollectionView.swift)
  - [`apple/Sources/SideB/Views/Components/PlayerBarView.swift`](file:///Users/stefano/Documents/PROGRAMACION%20PADRE/SIDE%20B%20RUST%20BASED%20PROJECTO/SIDE%20B/apple/Sources/SideB/Views/Components/PlayerBarView.swift)
- **Diagnóstico:**
  En el Home Feed, el botón «Más opciones» de las tarjetas solo se visibiliza bajo hover con el puntero, impidiendo el acceso a usuarios que navegan mediante teclado o tecnologías de asistencia. En el `PlayerBarView`, las barras de progreso y volumen se construyeron sobre gestos de arrastre en `GeometryReader` sin semántica de slider de accesibilidad.
- **Tareas Técnicas:**
  1. Proveer atajo de teclado / menú de accesibilidad contextual en las celdas de `HomeFeedCollectionView` para invocar el menú sin requerir puntero del mouse.
  2. Enriquecer las barras de progreso y volumen con modificadores `.accessibilityElement(children: .ignore)`, `.accessibilityLabel(...)`, `.accessibilityValue(...)` y `.accessibilityAdjustableAction(...)`.
- **Verificación:**
  Navegar el reproductor y el Home Feed utilizando exclusivamente teclado y VoiceOver activado; comprobar que el progreso y volumen se pueden regular con las teclas de flecha arriba/abajo de VoiceOver.

---

## Sección 8: Rendimiento del Home Feed y Optimización Medida de Scroll

Esta sección aborda la investigación específica sobre los tirones en los bordes de Inicio, aplicando las reglas de 2026 de medición antes de optimizar.

### [Rendimiento Inicio] Eliminación de Invalidaciones Redundantes (`prepareForReuse`) y Perfilado con Instruments
- **Prioridad:** P2 / Rendimiento
- **Archivos Afectados:**
  - [`apple/Sources/SideB/Views/Home/HomeFeedCollectionView.swift`](file:///Users/stefano/Documents/PROGRAMACION%20PADRE/SIDE%20B%20RUST%20BASED%20PROJECTO/SIDE%20B/apple/Sources/SideB/Views/Home/HomeFeedCollectionView.swift)
  - [`apple/Sources/SideB/Views/Home/HomeView.swift`](file:///Users/stefano/Documents/PROGRAMACION%20PADRE/SIDE%20B%20RUST%20BASED%20PROJECTO/SIDE%20B/apple/Sources/SideB/Views/Home/HomeView.swift)
- **Diagnóstico:**
  En `HomeFeedCollectionView.swift:600`, el método `HomeItemView.configure` ejecuta incondicionalmente:
  ```swift
  if representedID != nil { prepareForReuse() }
  ```
  Incluso cuando la celda ya representa exactamente el mismo ítem (`representedID == record.id`), se invocan `prepareForReuse()`, la cancelación de carga de imágenes y el desmontaje de estado visual. Cuando el usuario hace scroll hacia los bordes superior o inferior y se aplican actualizaciones de contenido, las celdas visibles se reinicializan provocando tirones (hitches).
- **Tareas Técnicas:**
  1. Comparar la identidad del registro antes de reiniciar:
     ```swift
     if representedID != nil && representedID != record.id {
         prepareForReuse()
     }
     ```
  2. Evitar recargar la imagen si la URL de la miniatura coincide con la que ya está cargada o en vuelo.
  3. Establecer protocolo de medición reproducible con Instruments (Time Profiler, SwiftUI View Body, Hitches) en configuración Release antes y después del cambio.
- **Verificación:**
  Grabar traza de Instruments antes del cambio y después del cambio en scroll rápido hacia el tope y hacia el pie de página («Cargar más recomendaciones»), documentando la reducción de hitches.

---

## Estrategia de Ejecución por Fases y Verificación

Siguiendo el principio de minimizar riesgos y resolver de forma progresiva:

```
┌─────────────────────────────────────────────────────────────┐
│ FASE 1: Aislamiento y Entorno Seguro de Pruebas             │
│ [A01] Aislamiento Bundle/Keychain | [A08] Tests Seguros     │
└──────────────────────────────┬──────────────────────────────┘
                               │
┌──────────────────────────────▼──────────────────────────────┐
│ FASE 2: Integridad de Sesión, Cuentas y Persistencia       │
│ [A02] Carreras Logout/Cuenta | [A14] Autoridad Persistencia │
│ [A17] Login Canónico y Saneamiento                          │
└──────────────────────────────┬──────────────────────────────┘
                               │
┌──────────────────────────────▼──────────────────────────────┐
│ FASE 3: Reproductor, Colas y Continuación                   │
│ [A04] Tokens Cola Radio | [A10] Transición Audio/UI         │
│ [A11] Likes Remotos | [A13] Paginación Playlist             │
│ [A23] Duplicados Cola / Siguiente | [A24] IDs Artista/Álbum │
└──────────────────────────────┬──────────────────────────────┘
                               │
┌──────────────────────────────▼──────────────────────────────┐
│ FASE 4: Búsqueda, Modal Spotlight y Navegación             │
│ [A03] Generaciones Quick Search | [A09] Filtros Aislados    │
│ [A20] Dropdown Oculto | [A22] Ancho Modal Spotlight         │
│ [A25] Historial Rutas | [A26] Estado Multi-Ventana          │
└──────────────────────────────┬──────────────────────────────┘
                               │
┌──────────────────────────────▼──────────────────────────────┐
│ FASE 5: Home Feed, Catálogo y Resiliencia de UI             │
│ [A05] Items Mixtos Home | [A06] Enrutamiento Ver Todo       │
│ [A07] Botones Like en Tablas | [A12] Guardar Playlist       │
│ [A19] Banner Error Feed | [A15] Skeleton Perfil             │
│ [A16] Errores Granulares Biblioteca/Historial               │
└──────────────────────────────┬──────────────────────────────┘
                               │
┌──────────────────────────────▼──────────────────────────────┐
│ FASE 6: Caché, Accesibilidad y Rendimiento Medido           │
│ [A18] Evicción Caché Disco | [A21] Teclado & VoiceOver      │
│ [Rendimiento Inicio] Optimización prepareForReuse y trazas  │
└─────────────────────────────────────────────────────────────┘
```

### Reglas de Validación durante la Implementación
1. Toda modificación que involucre contratos UniFFI en Rust (`core/`) requiere compilar el binario Rust, regenerar el XCFramework (`build_xcframework.sh`) y verificar la compilación Swift (`swift build`) en la misma tarea.
2. Ningún test automatizado debe depender de cookies reales en Keychain ni alterar datos del sistema.
3. Las afirmaciones de rendimiento se comprobarán mediante mediciones reproducibles con Instruments en Release, reportando datos tangibles.
