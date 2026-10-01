# Arquitectura Windows

## Responsabilidades

| Capa | Código | Responsabilidad |
|---|---|---|
| Composición | `src/routes/+page.svelte` | Shell, navegación, historial de vistas y conexión entre dominios |
| Presentación | `src/lib/components/`, `styles/tokens.css` | Vistas y controles; referencia visual en `apple/Sources/SideB/Views/` |
| Home | `src/lib/home/controller.ts`, `presentation.ts` | Carga/chips/continuaciones; identidad y orden de estantes |
| Búsqueda | `src/lib/search/controller.ts` | Consultas por modo, caché de sesión e invalidación |
| Catálogo | `src/lib/catalog/controller.ts` | Álbum, artista, grillas, snapshots y solicitudes pendientes |
| Cuenta | `src/lib/account/controller.ts` | Biblioteca, likes, playlists e historial; cambios y paginación por cuenta |
| Navegación/ventana | `src/lib/navigation/history.ts`, `window/controller.ts`, `components/shell/TitleBar.svelte` | Atrás/Adelante, snapshots y controles Tauri; F11 alterna fullscreen nativo |
| Menús | `src/lib/menu/{types,policy,hooks,executor}.ts`, `components/menu/ContextMenu.svelte` | Política común de macOS, clic derecho/Más, disponibilidad y ejecución por controller |
| Reproductor UI | `src/lib/player/controller.ts` | Comandos y eventos; snapshot de transporte publicado para barra/fullscreen |
| Contratos frontend | `src/lib/types.ts`, `account/types.ts` | DTOs del bridge; estado de cuenta adicional tipado |
| Integración nativa | `src-tauri/src/lib.rs` | Inicialización, estado compartido, autenticación, eventos y registro Tauri |
| Bridge | `src-tauri/src/dto.rs`, `commands/` | Conversión de records y comandos de catálogo/cuenta/reproducción |
| Cola | `src-tauri/src/queue.rs` | Pistas por ocurrencia, índice y revisión; límites de next/previous |
| Sesión | `src-tauri/src/session.rs`, `session_store.rs` | Login WebView2, cancelación, restauración y protección de credenciales |
| Core | `../core/crates/sideb-core`, `innertube`, `player` | Proveedor/red/persistencia/streams y wrapper libmpv |

## Flujo de datos

Los controladores TypeScript reciben RPC/listeners y publican snapshots a Svelte. La inyección permite probar respuestas y eventos sin Tauri, red ni una cuenta real. Los componentes reciben datos y callbacks; no vuelven a consultar el proveedor por su cuenta.

La cola autoritativa está en Rust. Los eventos `playback-state-changed` y `playback-progress` actualizan tanto barra como fullscreen. `entryId` identifica una ocurrencia, `generation` una carga de audio y `queue.revision` una modificación de cola. Selecciones retrasadas usan entryId, no un índice que pudo cambiar. Una canción repetida conserva dos entradas. El frontend descarta estados anteriores; Rust valida las operaciones retrasadas y el avance por EOF.

Una canción de Inicio inicia radio: carga audio y agrega recomendaciones del core sin reiniciar la pista. El epoch de propietario de cola y la generación de sesión descartan recomendaciones obsoletas; un solo request continúa cuando quedan pocas pistas. Se deduplican recomendaciones por videoId, conservando duplicados de playlists y del encolado manual. El error de radio es recuperable e independiente del audio.

Home y catálogo invalidan solicitudes al cambiar contexto; búsqueda y cuenta vacían datos/cachés privados al cambiar de cuenta. El historial conserva snapshots y scroll en pasado/futuro, limitado a 40 entradas por pila. Una visita nueva descarta el futuro; Atrás/Adelante invalidan cargas abandonadas y restauran el destino. Los cambios de cuenta vacían ambas pilas.

Las acciones masivas de playlist resuelven continuaciones antes de reproducir/encolar y conservan setVideoId por ocurrencia. Edición/eliminación/orden validan permisos en el backend y los diálogos sólo cierran tras éxito. Los menús usan los mismos comandos que los botones. La barra superior reemplaza decoraciones Windows. Como en macOS, el reproductor expandido ocupa el área de contenido sin cambiar el tamaño de ventana; conserva sidebar, controles superiores y scroll sólo en la lista derecha. F11 controla por separado el fullscreen del sistema. La cápsula mantiene medidas fijas de controles y portada; sólo la metadata se trunca, y el volumen se despliega sin alterar el layout. La ventana conserva el mínimo macOS de 960×640. Aleatorio, repetición, Genius y selección de salida tienen su espacio visual, pero permanecen deshabilitados hasta contar con implementación Windows.

Autenticación y almacenamiento sensible permanecen en el runtime. Los DTOs no incluyen cookies ni URLs firmadas. Las vistas muestran sólo el estado público de la sesión.

## Cambiar un contrato

Actualizar el comando/DTO Rust y su tipo/consumidor TypeScript juntos. Si cambia un record del core, revisar también el consumidor UniFFI macOS. Agregar pruebas cuando haya una regla o regresión observable: identidad de cola, respuesta tardía, reset de cuenta, paginación, error recuperable. Una extracción mecánica no requiere duplicar pruebas por cada función.

## Build

`scripts/windows.ps1` resuelve el repositorio desde su propia ubicación, prepara MSVC 2022, fija la dependencia libmpv y ejecuta comandos iguales en local y CI. La build standalone incluye frontend compilado y DLL junto al ejecutable. `dev` usa Vite; un binario de `cargo build` directo con configuración debug puede seguir apuntando al servidor de desarrollo y no equivale a esa build standalone.

La CI Windows verifica tipos, pruebas frontend y Rust, y compila el standalone. Instalador, firma, audibilidad y comparación visual en macOS son verificaciones distintas; ver [BACKLOG.md](BACKLOG.md).
