# PLAN-013: Side B para Windows con Tauri y Svelte

- **Fecha**: 2026-09-28
- **Estado**: Propuesto; todavía no hay implementación Windows
- **Objetivo**: Crear una app Windows rápida y visualmente fiel a Side B Mac, usando el **mismo core Rust del repo** como fuente de verdad.
- **Plataforma de desarrollo y validación**: PC Windows x64 del proyecto. macOS sirve para editar código y diseño, pero las pruebas de audio, WebView2, rendimiento e instalador se hacen en Windows.

## 1. Decisión de producto y arquitectura

Side B Windows nace en **este repositorio**. No es un fork de Limusic con otro aspecto. Limusic es una referencia de soluciones puntuales para Tauri, libmpv, sesiones y empaquetado; el backend de Side B sigue siendo `core/`.

```text
SIDE B/
├── core/                         # InnerTube, SQLite, catálogo, letras, Genius: compartido
│   └── crates/sideb-core/
├── apple/                        # SwiftUI/AppKit + AVPlayer + integraciones macOS
├── windows/                      # Nuevo proyecto Tauri 2 + Svelte + TypeScript
│   ├── src/                      # UI, router, stores de presentación, estilos
│   └── src-tauri/                # Adaptador Rust, audio, auth e integraciones Windows
└── documentation/
```

`windows/src-tauri` dependerá por `path = "../../core/crates/sideb-core"`. El crate ya produce `rlib`: Tauri puede llamar sus métodos Rust directamente. **UniFFI queda para Swift**; no hacen falta DLL ni llamadas FFI para comunicar Tauri con `sideb-core`. Los comandos Tauri expondrán DTO tipados a TypeScript y eventos de estado, sin hacer que Svelte conozca detalles internos de InnerTube.

| Responsabilidad | Dueño previsto |
| --- | --- |
| Red, InnerTube, búsqueda, Home, biblioteca, mutaciones, SQLite, letras, Genius y resolución de streams | `core/` compartido |
| Contratos `invoke`/eventos y DTO serializables | `windows/src-tauri/` |
| Ventana, login WebView2, credenciales Windows, libmpv, controles multimedia, instalador | shell Windows |
| Rutas, componentes, foco, interacción y estado visual | Svelte/TypeScript |
| AVPlayer, Keychain, AirPlay, controles y ventanas macOS | shell Apple |

**Límite actual de lo compartido:** la cola/automix, el snapshot de reproducción y parte de la presentación/caché de Inicio están hoy en Swift (`QueueManager`, `PlayerViewModel`, `PlaybackStateStore`, `HomeViewModel`). No afirmar que el backend se comparte *completamente* hasta migrar la lógica de dominio reutilizable a Rust. Los motores de audio y la integración con cada sistema seguirán siendo específicos de la plataforma.

## 2. Referencias verificadas

- Código Mac vigente: `apple/Sources/SideB/SideBApp.swift` monta sidebar, navegación, fullscreen y barra flotante; `apple/Sources/SideB/UI/AppTheme.swift` define la paleta; `apple/Sources/SideB/Views/Home/HomeView.swift` usa `HomeFeedTableView` para el feed actual.
- Vista de la app abierta revisada el 2026-09-28: fondo carbón, acento rojo mate, sidebar colapsable, estantes horizontales con carátulas, cápsula de navegación, isla de reproducción y fullscreen de dos columnas. Las capturas de la sesión contienen datos de cuenta; **no se agregan al repo**.
- La copia local de Limusic en `/Users/stefano/Documents/PROGRAMACION PADRE/sideb recursos q usamos/limusic-master` declara **v0.7.2** en `Cargo.toml` y `src-tauri/tauri.conf.json`, sin historial Git. Es referencia congelada, no la última versión. El release oficial actual es [v1.0.0](https://github.com/SimoHypers/limusic/releases/tag/v1.0.0); consultar su código antes de adaptar un fix reciente.
- Limusic local muestra patrones útiles en `ui/src/lib/api.ts`, `src-tauri/src/commands.rs`, `crates/player/src/lib.rs`, `src-tauri/src/session.rs` y `docs/BUILD-PLATFORMS.md`. No copiar su identidad, URL/clave de updater, base de datos o árbol de UI completo.
- Side B declara `GPL-3.0-or-later` en `core/Cargo.toml`; registrar procedencia y licencia de cualquier código adaptado de Limusic.

## 3. Contrato de diseño Windows

Tomar la **jerarquía y comportamiento** de Side B Mac, adaptando elementos del sistema que no existen en Windows. La fuente de verdad es el código actual y una revisión visual en la app, no los valores de planes históricos.

- **Tokens**: fondo `#1B1B1E`, sidebar `#24242A`, acento `#A33D45`, acento claro `#D06C70`, superficies/bordes sutiles según `AppTheme.swift`. Crear variables CSS y componentes de diseño; usar una tipografía disponible y legible en Windows, sin asumir que SF Pro se puede distribuir.
- **Shell**: sidebar colapsable; contenido con ancho restante; cápsula Atrás/Adelante/Actualizar; barra flotante centrada **respecto del contenido**, incluso con sidebar abierta, ventana redimensionada o distintas escalas DPI.
- **Player bar**: referencia actual de `PlayerBarView.swift` (máximo aproximado 820 px, scrubber arriba, carátula/metadata, controles, volumen y acceso a fullscreen). Ajustar tamaño con breakpoints: nunca cortar controles en ventanas pequeñas.
- **Fullscreen**: carátula y metadata a la izquierda; Cola/Letras/Relacionado a la derecha; fondo derivado de portada, con límite de blur y actualización para no repintar toda la vista a cada tick. Genius entra después de reproducción y letras básicas.
- **Contenido**: Inicio con chips y estantes, Búsqueda/Spotlight, Biblioteca, Historial, detalles de álbum/artista/playlist, menús por entidad. Todos los controles visibles deben tener acción real y estados vacíos/de error.
- **Interacción**: teclado (incluidos Ctrl+K, Atrás/Adelante y controles de reproducción), foco visible, accesibilidad, menús contextuales, drag/reorder, contraste y opción de reducir movimiento. Las convenciones de Windows prevalecen en atajos e integraciones de ventana.
- **Rendimiento de UI**: virtualizar listas largas y limitar los elementos de estantes fuera de pantalla; miniaturas según tamaño visible, caché con límite, cancelación de solicitudes obsoletas y actualizaciones de progreso aisladas del feed. Evitar transiciones CSS globales y filtros caros aplicados a grandes áreas.

## 4. Ruta de implementación y criterios de salida

### M0 — Preparar el trabajo y fijar la línea de base

- [ ] Documentar la versión de Windows, CPU/GPU, RAM y escala DPI de la PC de prueba.
- [ ] Medir en esa PC Limusic **Release** como referencia: arranque frío/caliente hasta UI utilizable, RAM en reposo y reproduciendo, CPU, scroll de una playlist larga, salto de canción, seek y reanudación tras suspensión. Guardar método y resultados, no sólo impresiones.
- [ ] Definir un conjunto de datos de prueba sin cookies ni datos personales en el repo; comparar también el diseño y los flujos vigentes de Side B Mac.
- [ ] Confirmar identidad de app, ruta de datos, nombre de paquete e instalador de Side B Windows; mantenerla separada de Limusic.

**Salida:** escenarios repetibles y un presupuesto inicial de rendimiento basado en la PC real.

### M1 — Toolchain y ventana Tauri vacía en Windows

- [ ] Instalar desde fuentes oficiales: Microsoft C++ Build Tools con *Desktop development with C++*, Rust MSVC, Node LTS y pnpm. Verificar WebView2 (normalmente presente en Windows 11).
- [ ] Clonar **el repo Side B** en Windows; ejecutar `cargo test -p innertube` y `cargo test -p sideb-core` desde `core/`. Registrar incompatibilidades Windows concretas, especialmente `rustypipe-botguard`/V8 y SQLite.
- [ ] Crear `windows/` con `pnpm create tauri-app`, seleccionando Tauri 2, Svelte, TypeScript y pnpm. Configurar ID, iconos, permisos mínimos, scripts, lockfile y `tauri dev`.
- [ ] Agregar un README Windows con instrucciones reproducibles y CI de compilación en Windows x64.

**Salida:** una ventana Side B que abre en la PC y un build de core comprobado. Si el core falla en Windows, resolver eso antes de dibujar pantallas.

### M2 — Core compartido conectado y primer flujo real

- [ ] Agregar la dependencia `sideb-core` por ruta en `windows/src-tauri/Cargo.toml`; inicializar un único `Arc<SideBCore>` con la carpeta de datos de la app en Windows.
- [ ] Exponer comandos finos para `get_home_page`, `search_all`/`search_songs`, `get_album` y `resolve_stream`. Convertir records a DTO `serde::Serialize` con errores tipados y nombres de campos estables; generar o verificar tipos TypeScript. No devolver JSON crudo opaco para nuevos flujos.
- [ ] Probar `invoke` → core → respuesta → Svelte con datos reales, estado de carga, cancelación o identidad de petición y error visible. Nunca pasar cookies ni URL de stream firmadas a logs de UI.

**Salida:** la ventana puede buscar y abrir contenido real mediante nuestro core, sin backend Limusic.

### M3 — Audio Windows y primera canción reproducible

- [ ] Evaluar el crate existente `core/crates/player` como prototipo: hoy está fuera del workspace y no participa en la app Mac. Conectarlo, corregirlo o reemplazarlo sólo después de una prueba Windows con libmpv.
- [ ] Probar en la PC la compilación MSVC de `libmpv2`, su import library y el DLL distribuible. Tomar el procedimiento local de `limusic-master/docs/BUILD-PLATFORMS.md` como pista y verificarlo contra las versiones actuales.
- [ ] Conectar `resolve_stream` con `load/play/pause/seek/volume/EOF`, headers HTTP y expiración de URL; verificar AAC y Opus, fallbacks y errores. No asumir que todo cipher/PoToken está resuelto: hay caminos incompletos en `core/crates/sideb-core/src/cipher/mod.rs`.
- [ ] Mantener al reproductor en Rust y emitir eventos de estado a la UI; acotar frecuencia de `timeupdate`, tamaño de caché y número de procesos/tareas.

**Salida:** una canción real suena, se pausa, permite seek y termina correctamente en Windows. Si este gate falla, no avanzar a un gran rediseño.

### M4 — Shell visual y navegación Side B

- [ ] Implementar tokens, ventana, sidebar, área de contenido, cápsula de navegación y barra flotante con estados reales de la pista de M3.
- [ ] Replicar destinos vigentes (`home`, `search`, `album`, `artist`, `catalog`, `playlist`, `library`, `history`) y el historial atrás/adelante sin acumular páginas montadas.
- [ ] Construir componentes reutilizables: carátula, tarjeta grande/compacta, fila de canción, estado vacío/error, botones, menú, scrubber, modal y panel.
- [ ] Verificar la geometría de la isla con sidebar abierta/cerrada, ventana mínima, pantalla grande, DPI 100/125/150 %, teclado y foco.

**Salida:** estructura reconocible como Side B que navega con datos reales y reproduce sin interrupción.

### M5 — Inicio, búsqueda y catálogo

- [ ] Inicio: chips, orden/secciones, estantes, continuaciones, caché y carga gradual. El Mac actual usa `HomeFeedTableView` con reciclaje; diseñar virtualización equivalente en Svelte desde el principio.
- [ ] Búsqueda: modal rápido, debounce/cancelación por generación, resultados por tipo, página completa y navegación con teclado.
- [ ] Detalles: álbum, artista/catálogo, playlist, tablas virtualizadas, continuaciones y enlaces entre entidades.
- [ ] Menús contextuales por tipo de entidad; sólo mostrar acciones realmente conectadas.

**Salida:** explorar, buscar y empezar a escuchar desde las pantallas principales con scroll estable en listas largas.

### M6 — Cuenta, biblioteca y persistencia

- [ ] Implementar login en una ventana/perfil WebView2 aislado de la UI principal; gestionar cookies en Rust y credenciales con el mecanismo seguro de Windows. Revisar `SideBCore::set_cookie`, que actualmente persiste la cookie en SQLite, antes de prometer almacenamiento seguro o migrar perfiles.
- [ ] Aislar cachés, continuaciones y operaciones por identidad de cuenta; descartar respuestas tardías de una sesión anterior.
- [ ] Biblioteca, Me Gusta, historial y acciones de playlist: crear/editar/eliminar/reordenar, like y suscripción, con confirmaciones y errores reales.
- [ ] Persistir cola y posición por cuenta; reabrir pausado y resolver URLs vencidas al reanudar. Definir migraciones versionadas de datos Windows.

**Salida:** login y logout confiables, biblioteca real y datos que sobreviven a reinicio sin mezclar cuentas.

### M7 — Unificar la lógica de reproducción compartible

- [ ] Extraer a Rust las reglas de cola, shuffle/repeat, radio/automix y snapshot que hoy residen en Swift, con contratos de eventos y pruebas de transiciones. El motor AVPlayer/libmpv permanece específico de cada shell.
- [ ] Integrar primero el controlador Rust en Windows; migrar Mac mediante UniFFI en un cambio acotado, regenerando XCFramework y verificando Swift según `.agents/rules/10-backend.md`.
- [ ] Comprobar paridad de comportamiento: anterior/siguiente, reemplazar cola, insertar a continuación, fin de pista, fallo de stream, cambio de cuenta y restauración.

**Salida:** reglas de reproducción compartidas por las dos apps, sin duplicar su lógica de dominio en TypeScript y Swift.

### M8 — Fullscreen, letras y capacidades avanzadas

- [ ] Vista fullscreen de dos columnas, Cola/Letras/Relacionado, letras sincronizadas con seek, Genius y estados sin letra.
- [ ] Integración de teclas multimedia/SMTC, salida de audio, taskbar, notificaciones y suspensión/reanudación de Windows. Implementar cada función con APIs Windows, no copiando llamadas Apple.
- [ ] Ajustes, diagnósticos con datos sensibles redactados, actualización propia de Side B y recuperación ante base de datos corrupta.

**Salida:** experiencia diaria completa con controles del sistema y sin fugas de cookies/URLs firmadas en logs.

### M9 — Rendimiento, distribución y release

- [ ] Perfilar **Release** en la PC de M0: tiempo a primera interacción, RAM/CPU en reposo y reproduciendo, hitches de scroll, tiempo de búsqueda, cambio de pista, seek, suspensión/reanudación. Comparar con la línea de base de Limusic en los mismos escenarios.
- [ ] Corregir cuello de botella observado, distinguiendo red/core, IPC, imágenes, DOM/layout, WebView2 y audio. Repetir la misma medición después del fix.
- [ ] Construir instalador Windows (`pnpm tauri build`, NSIS primero; MSI si aporta valor), empaquetar `libmpv-2.dll` y licencias, probar instalación limpia, upgrade y desinstalación. CI x64 con artefacto verificable.
- [ ] Verificar smoke manual: login, búsqueda, reproducción, cola, biblioteca, letras, teclado, controles multimedia, audio tras suspensión y arranque sin red. Publicar sólo cuando el instalador se pruebe en la PC destino.

**Salida:** release Windows instalable y medido; la app Mac sigue pasando su build y pruebas tras cambios al core compartido.

## 5. Riesgos y decisiones técnicas a validar temprano

1. **Compatibilidad Windows del core:** compilar `rustypipe-botguard`/V8 y SQLite en MSVC antes de invertir en UI.
2. **Stream real:** el core prefiere AAC pero puede entregar otro formato; algunos caminos de deobfuscación están pendientes. Probar una muestra de pistas, seek y fallbacks en libmpv.
3. **Audio y headers:** entregar headers/cookies necesarios a mpv sin filtrar secretos a la UI o logs; controlar renovación de URLs y fin de pista.
4. **Backend compartido incompleto:** no duplicar silenciosamente cola, automix y restauración. M7 define su migración de Swift a Rust.
5. **UI extensa:** un clon visual que monta todos los estantes/listas puede perder la fluidez del Mac. Virtualización y caché limitada son requisitos de arquitectura.
6. **Versión de Limusic:** la carpeta local es 0.7.2; verificar fixes contra v1.0.0 antes de adaptarlos. Mantener trazabilidad de código y licencias.
7. **Rendimiento:** ningún framework garantiza baja RAM o 120 FPS por sí solo. Afirmar mejoras sólo con mediciones en la misma PC y escenario.

## 6. Primeras sesiones de trabajo: orden exacto

1. En la PC Windows, guardar la línea de base de Limusic y registrar hardware/Windows/DPI.
2. Clonar Side B, instalar prerequisitos [Tauri para Windows](https://v2.tauri.app/start/prerequisites/) y correr los tests del core con MSVC.
3. Crear `windows/` con el [template oficial Svelte + TypeScript](https://v2.tauri.app/start/create-project/), abrir una ventana con `pnpm tauri dev` y agregar la dependencia `sideb-core` por ruta.
4. Hacer una búsqueda real por comando Tauri; luego resolver y reproducir **una canción real**. Ese es el primer hito funcional.
5. Recién con audio validado, construir shell/sidebar/player bar de Side B y comparar visualmente con la app Mac.

Secuencia inicial en PowerShell, después de instalar Build Tools, Rust y Node desde sus fuentes oficiales:

```powershell
git clone https://github.com/fefucho/SIDE-B-CLIENT-NATIVE.git
cd SIDE-B-CLIENT-NATIVE
rustup default stable-msvc
cd core
cargo test -p innertube
cargo test -p sideb-core
cd ..
corepack enable
pnpm create tauri-app
```

En el asistente de Tauri, crear la carpeta **`windows`** y elegir **TypeScript / JavaScript → pnpm → Svelte → TypeScript**. Después:

```powershell
cd windows
pnpm install
pnpm tauri dev
```

El primer PR termina cuando esa ventana abre en Windows y la dependencia por ruta a `sideb-core` compila. El siguiente PR agrega búsqueda real; el tercero, reproducción real. No confundir `tauri dev` con una medición de rendimiento: esa se hace en Release.

No trasladar perfiles, cookies ni bases de datos de la cuenta Mac a Windows para acelerar pruebas. Usar login normal cuando llegue M6.

## 7. Cómo documentar y reportar el trabajo

- Este plan es el checklist vivo del port. Al cerrar cada hito, anotar la evidencia de salida y los bloqueos reales.
- `documentation/PROJECT_STATE.md`: actualizar arquitectura/estado vigente cuando exista un componente Windows funcional; no marcarlo completo por scaffold o build.
- `documentation/FIXES_LOG.md`: registrar hitos estructurales y cambios de contrato, como indica `.agents/rules/00-project_rules.md`; los bugs pequeños van en commits/issues y en la nota del hito.
- Para rendimiento, adjuntar a `documentation/audits/` escenario, hardware, build, método, antes/después y trazas; no inferir FPS o latencia por compilación o CPU baja.
- Cada cambio de core compartido: tests Rust, build Windows y build Swift/UniFFI cuando cambie el contrato Apple. Cada pantalla: prueba visual y funcional con estados normal, vacío, error, loading y teclado.

## 8. Fuentes de referencia

- Código activo: `core/crates/sideb-core/`, `apple/Sources/SideB/`, `.agents/AGENTS.md` y `.agents/rules/`.
- Limusic local 0.7.2: `/Users/stefano/Documents/PROGRAMACION PADRE/sideb recursos q usamos/limusic-master/` (consulta de solo lectura).
- [Limusic v1.0.0](https://github.com/SimoHypers/limusic/releases/tag/v1.0.0), [Tauri: requisitos Windows](https://v2.tauri.app/start/prerequisites/), [Tauri: crear proyecto](https://v2.tauri.app/start/create-project/) e [instalador Windows](https://v2.tauri.app/distribute/windows-installer/).
