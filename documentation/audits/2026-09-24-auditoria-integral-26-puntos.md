# Auditoría integral de Side B — diagnóstico del 24 de septiembre de 2026

> **Estado al 25 de septiembre de 2026:** `Copia de SIDE B/` fue eliminada y `SIDE B/` es el proyecto final. Este documento se conservó como diagnóstico histórico: varios hallazgos recibieron cambios posteriores, registrados en [`FIXES_LOG.md`](../FIXES_LOG.md) (en particular FIX-047 y FIX-048). Las prioridades, referencias de línea y pasos de reproducción describen el estado auditado el 24 de septiembre; antes de tratar un punto como pendiente, contrastarlo con el código actual y repetir su prueba de aceptación. Este aviso no certifica los fixes ni el rendimiento.

**Fecha:** 24 de septiembre de 2026  
**Alcance:** `Copia de SIDE B/` (SwiftUI/AppKit, Rust/UniFFI, sesión, búsqueda, Inicio, biblioteca y reproducción). No se modificó `SIDE B/` ni `sideb OLD/`.  
**Propósito:** registrar fallos y mejoras funcionales y de interfaz para resolverlos por prioridad.

## Cómo se hizo y qué significa la evidencia

Se leyó el código vigente de la copia y se abrió su app para una prueba exploratoria de Inicio y búsqueda con la cuenta que ya estaba configurada. «Confirmado por código» significa que la ruta de ejecución es visible en el código; las carreras requieren además una prueba controlada con respuestas fuera de orden para cuantificar su frecuencia. «Observado en UI» significa que el resultado apareció en la app abierta. Esta no fue una prueba exhaustiva de todas las pantallas, VoiceOver, red caída ni macOS 15/26. Tampoco se midieron FPS, hitches o memoria con Instruments; ningún juicio de fluidez se basa en esta auditoría.

**Validación ejecutada:** `swift build -c release --arch arm64 --product SideB` terminó correctamente. La app de la copia estuvo abierta y se recorrieron Inicio y búsqueda; no se ejecutó la suite completa por el riesgo documentado en A08. La compilación no valida funcionalidad ni rendimiento.

**Prioridades:** P1 = afecta cuenta, datos, acción principal o muestra información equivocada; P2 = fallo funcional o de interacción relevante; P3 = coherencia, accesibilidad o mantenimiento con menor impacto inmediato. Las referencias son relativas a la raíz de esta copia.

## P1 — resolver primero

### A01. La copia usa la misma identidad y datos que la app original

**Confirmado por código y por la app abierta.** El bundle `com.fefucho.SideB` de la copia usa `Application Support/SideB`, la caché de imágenes normal y el servicio Keychain `com.fefucho.SideB.auth`. El modo aislado solo se activa con `SIDEB_HOME_LAB=1` o un bundle ID especial; la copia abierta no lo tiene. WebKit usa además `WKWebsiteDataStore.default()`. La copia puede leer o escribir la sesión y la base de datos de la app original. Evidencia: `apple/Sources/SideB/Services/HomeLabConfiguration.swift:5-29`, `apple/Sources/SideB/Services/Storage/CookieStorage.swift:9-10`, `apple/Sources/SideB/Views/Login/LoginWebView.swift:13-16`, `Scripts/build-app.sh:20`. **Propuesta:** asignar a la copia bundle ID, Application Support, caché, servicio Keychain y website data store propios de forma permanente; migrar solo datos que el usuario elija. **Verificar:** abrir original y copia con cuentas distintas, cerrar sesión en una y comprobar que la otra sigue intacta.

### A02. Una respuesta tardía puede devolver datos de la cuenta anterior

**Confirmado por código; falta prueba de carrera.** `AccountViewModel.fetchAccount` y `LibraryViewModel.loadLibrary` aplican datos tras `await` sin generación de sesión ni comprobación de cuenta actual. `LibraryViewModel.clear()` tampoco vacía `AppContextMenuFactory.cachedUserPlaylists`. Un logout o cambio de cuenta durante una petición puede volver a mostrar el perfil, biblioteca o playlists de la cuenta previa y ofrecerlas en «Añadir a playlist». Evidencia: `apple/Sources/SideB/ViewModels/AccountViewModel.swift:31-57`, `apple/Sources/SideB/ViewModels/LibraryViewModel.swift:25-66`, `apple/Sources/SideB/UI/AppContextMenuFactory.swift:70-97`. **Propuesta:** identidad/generación de sesión única, invalidación de tareas al cambiarla y limpieza de toda caché por cuenta. **Verificar:** demorar artificialmente la respuesta de A, salir/entrar a B y comprobar perfil, sidebar y menús.

### A03. Búsqueda B puede mostrar los resultados rápidos de A

**Confirmado por código.** Al editar una consulta no vacía, `quickResults` no se limpia. `commitSearch` asigna `query = trimmed` y luego comprueba `query == trimmed`, condición siempre verdadera: Enter antes de terminar el debounce reutiliza los resultados de la consulta anterior y puede omitir la petición nueva. El modal incluso prioriza resultados viejos sobre el estado «buscando». Evidencia: `apple/Sources/SideB/ViewModels/SearchViewModel.swift:81-110,116-159`, `apple/Sources/SideB/Views/Search/SpotlightSearchModal.swift:126-146`. **Propuesta:** vincular cada resultado rápido a su texto normalizado y a una generación; invalidarlo al editar y aceptarlo solo si coincide. **Verificar:** buscar A, escribir B y pulsar Enter de inmediato con red lenta; nunca deben aparecer resultados de A bajo B.

### A04. Una radio antigua puede alterar la cola nueva

**Confirmado por código; falta prueba de carrera.** `fetchRadio`, `extendRadioIfNeeded` y `startRadioForCollection` esperan red y luego agregan o reemplazan canciones sin validar la semilla ni la generación de cola. Una respuesta de A que llegue después de iniciar B puede contaminar la cola B o volver a reproducir A. Evidencia: `apple/Sources/SideB/ViewModels/PlayerViewModel.swift:218-247,531-577,699-723`. **Propuesta:** token de contexto/cola para todas las consultas de radio, comprobación tras cada `await` y cancelación de tareas viejas; mantener los indicadores de carga ligados a ese token. **Verificar:** forzar respuestas A/B fuera de orden y revisar cola, pista y audio real.

### A05. Inicio interpreta álbumes como canciones en «Forgotten favorites»

**Observado en UI y confirmado por código.** En la copia abierta, esa sección contenía canciones y álbumes. Para un álbum la interfaz mostró «Ver artista: Album» y «Ver álbum: Kid Cudi»; otros mostraron «Ver álbum: Kendrick Lamar». El estilo `quickPicks` se decide por el título o por 75 % de canciones, pero la celda divide `subtitle` como si cada ítem fuera canción. Pulsar «Album» acaba buscando literalmente “Album”. Evidencia: `apple/Sources/SideB/Models/HomeFeedPresentation.swift:57-68`, `apple/Sources/SideB/Views/Home/HomeFeedCollectionView.swift:255-265,594-622`. **Propuesta:** renderizar y habilitar acciones según `record.kind`, usar IDs explícitos para artista/álbum y tratar ítems mixtos sin inferir identidad a partir del subtítulo. **Verificar:** feed mixto fijo con canciones, álbumes, mixes y IDs ausentes; comprobar etiquetas y destino de cada enlace.

### A06. «Ver todo» de algunas secciones navega a una playlist inválida

**Confirmado por contrato y código; depende de que llegue ese tipo de sección.** Rust parsea `moreBrowseId` junto con `moreParams`, incluidos destinos `FEmusic_moods_and_genres_category`. La presentación descarta `moreParams`; Inicio trata cualquier ID que no empiece por `MPRE` o `UC` como playlist, y Rust añade `VL` al ID al cargarla. Evidencia: `core/crates/innertube/src/models/browse.rs:338-345,1202,1283-1284`, `apple/Sources/SideB/Models/HomeFeedPresentation.swift:17-22,47-53`, `apple/Sources/SideB/Views/Home/HomeFeedCollectionView.swift:267-272`, `core/crates/sideb-core/src/lib.rs:445-458`. **Propuesta:** conservar endpoint tipado con parámetros y abrir la vista correcta según el contrato real; no convertir destinos desconocidos en playlist. **Verificar:** fixture `FEmusic...` con `params`, álbum y artista, y abrir cada «Ver todo».

### A07. Hay controles «Me gusta» y «No me gusta» que no hacen nada

**Confirmado por código.** `NativeTrackTableView` muestra los botones al pasar el cursor y sus acciones llaman closures opcionales. Las vistas de álbum, playlist y búsqueda no entregan esos callbacks, por lo que el clic no cambia nada. Evidencia: `apple/Sources/SideB/Views/Common/NativeTrackTableView.swift:589-614,706-732`, `apple/Sources/SideB/Views/Detail/AlbumDetailView.swift:42-53`, `apple/Sources/SideB/Views/Detail/PlaylistDetailView.swift:42-58`, `apple/Sources/SideB/Views/Search/SearchView.swift:418-435`. **Propuesta:** conectar las acciones y el estado real de valoración en todos los usos o no mostrar el botón donde todavía no funciona. **Verificar:** clic en ambos botones desde álbum, playlist y búsqueda; confirmar cambio visible y en la cuenta.

### A08. Una prueba automática modifica la cookie real del Keychain

**Confirmado por código.** `testLiveAccountAndLibraryWithKeychainCookie` lee el servicio de producción y ejecuta `SecItemUpdate` si decide “sanear” la cookie. Correr `swift test` completo en esta copia puede alterar la sesión de la app original. Evidencia: `apple/Tests/SideBTests/SideBTests.swift:97-149`. **Propuesta:** sacar ese diagnóstico de la suite normal, exigir opt-in explícito y credencial/Keychain aislados; los tests automáticos deben usar fixtures. `testGetHomeSections` también depende de red real (`apple/Tests/SideBTests/SideBTests.swift:49-58`) y no es determinista. **Verificar:** ejecutar la suite segura con Keychain de producción intacto.

## P2 — funcionalidad y coherencia

### A09. Los filtros de búsqueda aceptan respuestas de otra pestaña

**Confirmado por código; falta prueba de carrera.** Al cambiar Artistas → Playlists, se cancela la tarea anterior, pero `fetchFilteredCards` solo comprueba la consulta, no el filtro ni la cancelación. Una respuesta tardía puede poner artistas en Playlists; otra tarea antigua puede apagar el indicador de carga nuevo. Lo mismo ocurre con `commitSearch` y su `isCommittedLoading`. Evidencia: `apple/Sources/SideB/ViewModels/SearchViewModel.swift:138-210`. **Propuesta:** identidad de solicitud por consulta + filtro y un único estado de resultado/error por categoría. **Verificar:** alternar filtros rápido con latencias distintas.

### A10. Al cambiar de canción, audio e interfaz pueden describir pistas distintas

**Confirmado por código; falta prueba con fallo de red.** `playSongNow` cambia `currentTrack` y el índice de cola antes de resolver el stream, pero el reproductor anterior no se detiene hasta que llega la URL nueva. Si la resolución falla, la canción anterior puede seguir sonando mientras la UI muestra la nueva. El error se guarda en `errorMessage`, sin presentación visible en player. Evidencia: `apple/Sources/SideB/ViewModels/PlayerViewModel.swift:294-378`; búsqueda de usos de `playerViewModel.errorMessage` en `Views/` sin resultado. **Propuesta:** estado explícito de transición/fallo, pausar o retener identidad visual de la pista anterior de forma coherente, y mostrar Reintentar. **Verificar:** resolución lenta y error HTTP mientras suena otra canción; cotejar título, cola, Now Playing y audio.

### A11. «Me gusta» del reproductor no refleja la cuenta ni revierte errores

**Confirmado por código.** `likedVideoIds` vive solo en RAM; al cargar una pista se consulta ese set, no su valoración remota. Una canción ya guardada puede mostrar corazón vacío, y un fallo de `rateSong` solo se imprime sin revertir el cambio optimista. Evidencia: `apple/Sources/SideB/ViewModels/PlayerViewModel.swift:75-77,305-315,420-431,475-484`. **Propuesta:** hidratar la valoración/LM por cuenta, actualizarla tras cada acción y revertir con mensaje si el servidor rechaza la petición. **Verificar:** canción previamente guardada, reinicio, like/unlike y error de red.

### A12. «Guardar» playlist arranca en estado incorrecto

**Confirmado por código.** `PlaylistDetailViewModel.inLibrary` empieza en `false` y nunca se inicializa al cargar. El contrato `PlaylistDetailRecord` expone `owned` pero no `inLibrary`; una playlist ajena ya guardada aparece como «Guardar» y el clic manda `like: true` de nuevo. Evidencia: `apple/Sources/SideB/ViewModels/PlaylistDetailViewModel.swift:8-26,45-53`, `apple/Sources/SideB/Views/Detail/PlaylistDetailView.swift:220-237`, `apple/SideBCore/Sources/SideBCore/sideb_core.swift:2882-2903`. **Propuesta:** consultar/correlacionar membresía de biblioteca por ID antes de mostrar la acción; incluir un estado «cargando» o «desconocido». **Verificar:** playlist ajena guardada/no guardada y cambio de cuenta.

### A13. Reproducir una playlist larga no continúa su cola

**Confirmado por código; verificar el límite de página real.** La vista de playlist puede pedir páginas adicionales, pero el token pasado al `QueueManager` no se consume al terminar la primera tanda. El reproductor intenta extender por radio, así que la cola puede saltar a recomendaciones antes de reproducir canciones restantes de la playlist. Evidencia: `apple/Sources/SideB/ViewModels/PlaylistDetailViewModel.swift:29-42,56-70`, `apple/Sources/SideB/Services/Player/QueueManager.swift:38,130`, `apple/Sources/SideB/ViewModels/PlayerViewModel.swift:393-399,694-718`. **Propuesta:** continuación específica del contexto playlist y append a la misma cola, invalidada al cambiar de contexto. **Verificar:** playlist mayor que una página, reproducción cerca del final de la primera tanda, orden y shuffle.

### A14. La persistencia de sesión tiene varias fuentes que pueden divergir

**Confirmado por código.** Rust escribe cookie en SQLite además del Keychain de Swift. Cuando `getHomePage` detecta `SessionExpired`, limpia la de Rust pero no el Keychain que `restoreSession` reinstala al próximo arranque. Las cookies rotadas por el transporte quedan en memoria y no se vuelcan a los almacenes persistentes. El fallback de archivo puede permanecer tras una escritura correcta a Keychain y reaparecer si este falla. Evidencia: `core/crates/sideb-core/src/lib.rs:340-346,619-624`, `core/crates/sideb-core/src/db.rs:84-87`, `apple/Sources/SideB/ViewModels/AccountViewModel.swift:15-27`, `apple/Sources/SideB/Services/Storage/CookieStorage.swift:54-76`, `core/crates/innertube/src/transport.rs:187-210`. **Propuesta:** una sola autoridad de credenciales, invalidación persistente ante expiración y propagación de rotaciones; eliminar fallback obsoleto al guardar. **Verificar:** cookie expirada, rotada, fallo de Keychain y relanzamiento.

### A15. El perfil puede quedar en skeleton permanente

**Confirmado por código.** Si `fetchAccount` falla mientras `core.isLoggedIn()` sigue verdadero, queda `account == nil`, `isLoading == false`, `isLoggedIn == true`; `SidebarProfileView` muestra siempre `loadingSkeleton`, sin cuenta, reintento ni logout. Evidencia: `apple/Sources/SideB/ViewModels/AccountViewModel.swift:31-48`, `apple/Sources/SideB/Views/Sidebar/SidebarProfileView.swift:15-27`. **Propuesta:** estado de error con Reintentar y acceso a cerrar sesión. **Verificar:** fallo de `getAccountInfo` con cookie aún válida.

### A16. Los fallos de biblioteca, historial y búsqueda parecen resultados vacíos

**Confirmado por código.** `loadLibrary` reúne playlists, álbumes e historial en un único `try await`, de modo que el fallo de una sección descarta todas; el sidebar no muestra `errorMessage` y dice «No tienes playlists»/«No tienes álbumes guardados». `loadHistory` usa `try?` y la vista enseña «No hay reproducciones recientes». La búsqueda completa también silencia errores. Evidencia: `apple/Sources/SideB/ViewModels/LibraryViewModel.swift:25-58`, `apple/Sources/SideB/Views/Sidebar/SidebarView.swift:155-209`, `apple/Sources/SideB/Views/History/HistoryView.swift:39-51`, `apple/Sources/SideB/ViewModels/SearchViewModel.swift:138-159`. **Propuesta:** resultados y errores por sección, conservar datos válidos, mostrar error y Reintentar. **Verificar:** hacer fallar una sola llamada por vez y comprobar mensajes/acciones.

### A17. El login puede comportarse distinto antes y después del reinicio

**Confirmado por código.** `LoginSheet` guarda la cookie saneada, pero inyecta al Core la cadena original. Si incluía duplicados o claves descartadas, la sesión actual y la restaurada usan valores distintos. En caso de fallo al guardar, solo imprime el error aunque `LoginWebView` ya marcó que extrajo cookies. El WebView usa el data store persistente y logout no lo limpia, por lo que cambiar de cuenta puede reutilizar la sesión web anterior. Evidencia: `apple/Sources/SideB/Views/Login/LoginSheet.swift:29-46`, `apple/Sources/SideB/Views/Login/LoginWebView.swift:13-16,77-89`, `apple/Sources/SideB/ViewModels/AccountViewModel.swift:50-57`. **Propuesta:** pasar exactamente la cookie canónica guardada, ofrecer fallo/reintento visible y definir limpieza de sesión WebKit por cuenta. **Verificar:** cookie con duplicados, fallo de guardado y logout/login con dos cuentas.

### A18. El límite de 200 MB de la caché de imágenes solo se revisa al iniciar

**Confirmado por código.** `scheduleDiskEviction` se llama en `init`, pero `saveToDisk` no la vuelve a programar; los contadores de escrituras no se usan. La caché puede crecer durante sesiones largas hasta el siguiente arranque. Evidencia: `apple/Sources/SideB/Utilities/ImageCache.swift:14-28,55-57,214-261`. **Propuesta:** programar evicción por umbral de escrituras/tamaño, con I/O fuera del hilo principal, y medir crecimiento real. **Verificar:** muchas imágenes nuevas en una sesión, tamaño de disco tras cada lote y al relanzar.

### A19. Inicio mantiene un mensaje de «actualizando» tras fallar el refresh

**Confirmado por código.** Si hay feed guardado y falla la red, `statusBanner` comprueba `isShowingSavedFeed` antes de `errorMessage`, así anuncia «Recomendaciones guardadas · actualizando» incluso después de terminar el intento. Evidencia: `apple/Sources/SideB/Views/Home/HomeView.swift:96-112`. **Propuesta:** priorizar error, separar `saved` de `refreshing` y ofrecer Reintentar. **Verificar:** feed guardado + red caída + refresco.

### A20. La lista flotante de búsqueda puede quedar encima de los filtros

**Observado en UI y explicado por el código.** Después de «Ver todos los resultados», la página completa se abrió pero el dropdown rápido volvió a aparecer y tapó la barra de filtros. En `SearchView.onAppear`, asignar `query` inicia `onQueryChanged`; `commitSearch` oculta el dropdown, pero la búsqueda rápida diferida vuelve a poner `isTopdownVisible = true`. Evidencia: `apple/Sources/SideB/Views/Search/SearchView.swift:79-104,126-133`, `apple/Sources/SideB/ViewModels/SearchViewModel.swift:97-106,116-122`. **Propuesta:** cancelar/invalidate la búsqueda rápida al confirmar o navegar, y no mostrar dropdown mientras haya una búsqueda confirmada sin edición nueva. **Verificar:** abrir búsqueda desde el modal y esperar más que el debounce.

### A21. Varias acciones no tienen equivalencia clara con teclado y VoiceOver

**Confirmado por código; falta prueba real con VoiceOver.** Las tarjetas de Inicio ocultan «Más opciones» si no hay hover; la interacción de teclado del ítem solo cubre activación. Progreso y volumen del player son gestos sobre `GeometryReader`, sin semántica de slider/valor ajustable. Evidencia: `apple/Sources/SideB/Views/Home/HomeFeedCollectionView.swift:699-716`, `apple/Sources/SideB/Views/Components/PlayerBarView.swift:59-105,370-405`. **Propuesta:** menú contextual por teclado/AX y controles ajustables nativos o acciones de accesibilidad equivalentes. **Verificar:** navegación completa con Tab, menú contextual y VoiceOver, sin mouse.

### A22. La ventana compacta recorta el modal de búsqueda

**Confirmado por dimensiones del código; falta prueba de resize.** El modal fija 850 puntos de ancho, mientras la ventana mínima es 960 y el sidebar abierto ocupa alrededor de 230; el área de contenido disponible es menor que el modal. Evidencia: `apple/Sources/SideB/Views/Search/SpotlightSearchModal.swift:52-57`, `apple/Sources/SideB/SideBApp.swift:218`, `apple/Sources/SideB/Views/Sidebar/SidebarView.swift:265`. **Propuesta:** ancho basado en el contenedor con margen mínimo, y comprobar ambas posiciones de sidebar. **Verificar:** tamaño mínimo, sidebar abierto/cerrado, pantalla pequeña.

## P3 — coherencia y mantenimiento

### A23. La cola confunde repeticiones del mismo tema y el botón Siguiente repite el mismo

**Confirmado por código.** `syncCurrentIndex` y parte del reordenamiento identifican pistas por `videoId`, que no distingue dos ocurrencias; puede saltar a la primera. `nextTrack` devuelve la pista actual cuando está activo repetir uno, incluso para el botón manual «Siguiente». Evidencia: `apple/Sources/SideB/Services/Player/QueueManager.swift:89-95,207-217,244-250`, `apple/Sources/SideB/ViewModels/PlayerViewModel.swift:393-396`. **Propuesta:** ID de ocurrencia de cola y separar avance automático al terminar de salto manual. **Verificar:** misma canción dos veces en cola, mover la segunda y pulsar Siguiente con repetir uno.

### A24. Enlaces de artista/álbum pueden conservar IDs de la pista anterior

**Confirmado por código.** `playSongNow` solo reemplaza `currentArtistBrowseId`/`currentAlbumBrowseId` cuando la nueva pista trae ID. Si la pista nueva carece de ellos, los enlaces y recomendaciones pueden usar los de la anterior. Evidencia: `apple/Sources/SideB/ViewModels/PlayerViewModel.swift:305-314,599-600`, `apple/Sources/SideB/Views/Components/PlayerBarView.swift:466-489`, `apple/Sources/SideB/Views/Fullscreen/FullscreenNowPlayingView.swift:524-544`. **Propuesta:** limpiar procedencia al cambiar pista y usar fallback solo ligado al videoId actual. **Verificar:** pista A con IDs seguida de Quick Pick B sin IDs; abrir artista/álbum de B.

### A25. Navegación e historial no son consistentes entre pantallas

**Confirmado por código.** `NavigationRouter.navigate` agrega el destino aunque sea el actual, así varios clics en Inicio crean pasos Atrás sin cambio visible. Historial crea la tabla de canciones sin `playerViewModel`, `router` ni `rustCore`, por lo que faltan acciones de menú disponibles en otras tablas. Evidencia: `apple/Sources/SideB/Services/Navigation/NavigationRouter.swift:36-43`, `apple/Sources/SideB/Views/History/HistoryView.swift:53-66`, `apple/Sources/SideB/Views/Common/NativeTrackTableView.swift:339-348`. **Propuesta:** no apilar destino idéntico y estandarizar acciones de tabla según contexto. **Verificar:** clicar Inicio repetidamente y comparar menú de una misma pista desde Historial/Álbum/Búsqueda.

### A26. Estado de navegación compartido entre ventanas

**Confirmado por estructura del código; comprobar con segunda ventana.** `router`, sidebar, búsqueda e Inicio viven como `@State` del `App` dentro de un `WindowGroup`; nuevas ventanas comparten estado y cada `.task` vuelve a restaurar sesión/preparar Inicio. Evidencia: `apple/Sources/SideB/SideBApp.swift:13-20,34-35,238-251`. **Propuesta:** estado de navegación por ventana o ventana única explícita, según producto. **Verificar:** abrir dos ventanas, navegar y cambiar chips en una, observar la otra.

## Rendimiento de Inicio: investigación específica

El usuario observa tirones al llegar arriba y abajo de Inicio. Esta auditoría no permite atribuirlos a una línea concreta. Hay una **hipótesis para perfilar**: al aplicar contenido, las celdas visibles se reconfiguran y `HomeItemView.configure` llama `prepareForReuse()` incluso si ya representa el mismo ítem, cancelando imágenes y rehaciendo estado (`apple/Sources/SideB/Views/Home/HomeFeedCollectionView.swift:148-169,594-640`). Medir con Time Profiler, Hitches, Core Animation y memoria en Release, tanto al tocar el borde superior como al mostrar «Cargar más recomendaciones» abajo. Registrar tres recorridos comparables con caché fría/caliente, música activa y tamaño de ventana fijo antes de optimizar. No afirmar mejoras de FPS solo porque compile o se vea bien.

## Orden de trabajo sugerido

1. **Aislamiento y seguridad de pruebas:** A01, A08; después ejecutar una suite segura. Esto evita que el trabajo en la copia afecte la app original.
2. **Integridad de cuenta y reproducción:** A02, A04, A10, A14, A17; añadir pruebas de respuestas fuera de orden y cambios de cuenta.
3. **Acciones visibles y datos correctos:** A03, A05, A06, A07, A09, A11–A13. Crear fixtures pequeños para feed mixto, búsqueda rápida y playlist paginada.
4. **Estados de error e interfaz:** A15, A16, A19–A22, A25. Probar teclado, VoiceOver y ventana mínima.
5. **Pulido y rendimiento medido:** A18, A23, A24, A26 e investigación de Inicio. Comparar trazas antes/después.

## Pendientes de validación manual

- Prueba completa de login/logout entre dos cuentas, incluidas cookies rotadas y expiradas.
- Reproducción real con red lenta/fallida, AirPlay, sleep/wake, letras, cola larga y varias ventanas.
- Recorrido de todas las vistas con teclado y VoiceOver en macOS 27 y pruebas de compatibilidad en macOS 15/26.
- Perfilado de los tirones en los bordes de Inicio; este reporte no contiene mediciones de rendimiento nuevas.

**Nota sobre documentos previos:** `FIXES_LOG.md` y `audits/` son antecedentes. Este reporte usa el código y contratos presentes como fuente principal; los informes anteriores pueden mencionar componentes ya reemplazados.
