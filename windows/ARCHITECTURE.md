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
| Reproductor UI | `src/lib/player/controller.ts` | Comandos y eventos; snapshot de transporte publicado para barra/fullscreen |
| Contratos frontend | `src/lib/types.ts`, `account/types.ts` | DTOs del bridge; estado de cuenta adicional tipado |
| Integración nativa | `src-tauri/src/lib.rs` | Inicialización, estado compartido, autenticación, eventos y registro Tauri |
| Bridge | `src-tauri/src/dto.rs`, `commands/` | Conversión de records y comandos de catálogo/cuenta/reproducción |
| Cola | `src-tauri/src/queue.rs` | Pistas por ocurrencia, índice y revisión; límites de next/previous |
| Sesión | `src-tauri/src/session.rs`, `session_store.rs` | Login WebView2, cancelación, restauración y protección de credenciales |
| Core | `../core/crates/sideb-core`, `innertube`, `player` | Proveedor/red/persistencia/streams y wrapper libmpv |

## Flujo de datos

Los controladores TypeScript reciben RPC/listeners y publican snapshots a Svelte. La inyección permite probar respuestas y eventos sin Tauri, red ni una cuenta real. Los componentes reciben datos y callbacks; no vuelven a consultar el proveedor por su cuenta.

La cola autoritativa está en Rust. Los eventos `playback-state-changed` y `playback-progress` actualizan tanto barra como fullscreen. `entryId` identifica una ocurrencia, `generation` una carga de audio y `queue.revision` una modificación de cola. Una canción repetida conserva dos entradas. El frontend descarta estados anteriores; Rust valida las operaciones retrasadas y el avance por EOF.

Home y catálogo invalidan solicitudes al cambiar contexto; búsqueda y cuenta vacían datos/cachés privados al cambiar de cuenta. El historial de navegación conserva snapshots y scroll, limitado a 40 destinos. Atrás invalida las cargas abandonadas y restaura el destino; puede repetir una carga que se dejó pendiente.

Autenticación y almacenamiento sensible permanecen en el runtime. Los DTOs no incluyen cookies ni URLs firmadas. Las vistas muestran sólo el estado público de la sesión.

## Cambiar un contrato

Actualizar el comando/DTO Rust y su tipo/consumidor TypeScript juntos. Si cambia un record del core, revisar también el consumidor UniFFI macOS. Agregar pruebas cuando haya una regla o regresión observable: identidad de cola, respuesta tardía, reset de cuenta, paginación, error recuperable. Una extracción mecánica no requiere duplicar pruebas por cada función.

## Build

`scripts/windows.ps1` resuelve el repositorio desde su propia ubicación, prepara MSVC 2022, fija la dependencia libmpv y ejecuta comandos iguales en local y CI. La build standalone incluye frontend compilado y DLL junto al ejecutable. `dev` usa Vite; un binario de `cargo build` directo con configuración debug puede seguir apuntando al servidor de desarrollo y no equivale a esa build standalone.

La CI Windows verifica tipos, pruebas frontend y Rust, y compila el standalone. Instalador, firma, audibilidad y comparación visual en macOS son verificaciones distintas; ver [BACKLOG.md](BACKLOG.md).
