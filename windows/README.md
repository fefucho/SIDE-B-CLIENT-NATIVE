# Side B (Windows)

Shell de escritorio para Windows de **Side B**, basado en **Tauri 2**, **Svelte 5** y **TypeScript**. Se conecta mediante dependencias de ruta directas a [`core/crates/sideb-core`](../core/crates/sideb-core/) y [`core/crates/player`](../core/crates/player/), ejecutando una instancia única de `SideBCore` y un motor nativo de audio impulsado por **libmpv**.

- **Identificador de paquete:** `com.fefucho.sideb.windows`
- **Nombre de producto:** `Side B`
- **Capacidades actuales (W07):**
  - **Transición limpia entre pistas (A → B):** Al seleccionar una pista B (desde búsqueda o detalle de álbum), la pista A se detiene de inmediato mediante `Player::stop()` y limpieza de lista de reproducción antes de resolver y anunciar B. La interfaz muestra de inmediato el estado de carga (`isLoading: true`) en posición `0:00`.
  - **Aislamiento generacional contra eventos obsoletos:** Cada cambio de pista incrementa un identificador monotónico de generación (`generation: u64`) tanto en Rust como en el frontend. Los eventos de progreso, duración, fin o fallo de libmpv emitidos con una generación anterior o mientras una nueva pista está resolviendo se descartan estrictamente, impidiendo que el fin o progreso de la pista A mute el estado visible de B.
  - **Recuperación y reintento de errores:** Si la resolución de stream o la carga de libmpv falla, el audio previo queda completamente detenido, la UI presenta una insignia de error clara y un botón interactivo de "Reintentar", permitiendo reintentar la misma pista o seleccionar otra inmediatamente sin dejar audio oculto ni bloqueos en el reproductor.
  - **Guardias estrictas de transporte:** Las acciones de pausa, reanudación y seek se rechazan si el reproductor está inactivo (`loaded_generation` nulo), cargando o en estado de error, evitando estados ficticios de `isPlaying = true`.
  - **Reproducción de audio nativa:** Conexión de `SideBCore::resolve_stream` con `player::Player` (libmpv). Reproducción real de canciones desde resultados de búsqueda y desde el detalle de pistas de álbum.
  - **Controles de transporte:** Play/pausa reactivo, seek absoluto con barra de progreso interactiva, ajuste de volumen (0–100%) y reinicio coherente tras fin de pista (`isEnded`).
  - **Eventos y telemetría segura:** Emisión de eventos `playback-state-changed` y `playback-progress` (con tasa limitada a ~5 Hz). Las URLs firmadas y cabeceras de red permanecen estrictamente internas en Rust y nunca se exponen al frontend, DOM, almacenamiento web ni logs.
  - **Feed de Inicio:** Secciones y chips de estado de ánimo públicos reales (`get_home_page`).
  - **Búsqueda pública:** Canciones (`search_songs`), álbumes (`search_albums`) y detalle de pistas (`get_album`).
  - **Navegación completa:** Cambio fluido entre Inicio, Buscar (canciones/álbumes) y Detalle de álbum con botón Atrás.
- **Límites vigentes:**
  - Sin cola automática, automix ni lookahead gapless (la selección de pistas es interactiva individual A → B).
  - Sin inicio de sesión ni acceso a biblioteca de usuario (modo anónimo/público).

## Prerrequisitos

Para compilar y ejecutar en Windows x64:

1. **Microsoft Visual Studio Build Tools 2022**
   - Carga de trabajo: *Desarrollo para el escritorio con C++* (Desktop development with C++).
   - Componentes clave: MSVC v143 (x86/x64) y Windows 10/11 SDK.
2. **Rust (MSVC toolchain)**
   - Versión recomendada: Rust 1.98+ x64 MSVC:
     ```powershell
     rustup default stable-x86_64-pc-windows-msvc
     ```
3. **Node.js y pnpm**
   - Node.js LTS (v20+ o v24).
   - pnpm:
     ```powershell
     corepack enable
     ```
4. **Dependencia local de libmpv (x64)**
   - Se utiliza el build x64 GPL de libmpv procedente de [mpv-player/mpv git-release](https://github.com/mpv-player/mpv/releases/tag/git-release).
   - Archivo base: `libmpv-v0.41.0-dev-gb4b5d69a4-36603357422-x86_64-w64-mingw32-gpl.zip` (SHA-256: `e3a25841283d44590cac772e0e9cf027f14e4294705f08885437f57b0585480c`).
   - El ZIP incluye `libmpv-2.dll`, `libmpv.dll.a` y cabeceras en `include/mpv/`. En esta PC se generaron `mpv.def` y `mpv.lib` con `dumpbin`/`lib` de MSVC para enlazar desde Rust MSVC.
   - **Ruta configurable:** Se puede configurar la variable de entorno `SIDEB_MPV_DIR` apuntando al directorio con `mpv.lib` y `libmpv-2.dll` (en esta máquina de prueba: `S:\sideb-deps\mpv-gb4b5d69a4-x64-gpl`). `build.rs` enlaza automáticamente la librería e instala `libmpv-2.dll` junto al ejecutable.
5. **WebView2 Runtime** (incluido por defecto en Windows 11).

## Arquitectura

```text
SIDE-B-CLIENT-NATIVE/
├── core/                         # Motor compartido Rust
│   └── crates/
│       ├── innertube/            # Cliente HTTP y contratos con YouTube Music
│       ├── sideb-core/           # Base de datos, orquestador, resolución de streams
│       └── player/               # Wrapper de libmpv con bucle de eventos y controles
└── windows/                      # Shell Tauri 2 para Windows
    ├── src/                      # UI Svelte 5 + TypeScript + Vite
    ├── src-tauri/                # Host Tauri conectando con `sideb-core` y `player`
    │   └── icons/                # Iconos Windows (Appx, .ico, .icns, .png)
    └── static/                   # Recursos estáticos web (favicon.png, logo.png)
```

## Acceso a YouTube Music en Windows (prototipo W12)

El botón **Entrar** del perfil abre una ventana WebView2 separada con `ServiceLogin`; **Cancelar** cierra esa ventana si el acceso no avanza. Tras el retorno a YouTube Music, Rust lee sólo las cookies del dominio YouTube, valida la cuenta mediante InnerTube y guarda la sesión cifrada con DPAPI para el usuario de Windows. El frontend recibe únicamente estado y datos visibles del perfil. **Salir** borra la sesión de DPAPI y memoria, detiene la reproducción y limpia las cookies Google/YouTube del perfil WebView2 de la app. El core Windows no restaura ni escribe cookies en SQLite; al abrir una base anterior, limpia la cookie legacy y compacta SQLite/WAL.

Este flujo de sesión web no es una API oficial de Google y todavía requiere una prueba de login, reinicio y logout con una cuenta real en esta PC. No pegar cookies ni contraseñas en la terminal, logs o informes. La Biblioteca y las demás pantallas autenticadas siguen pendientes.

## Comandos de desarrollo

Todos los comandos se ejecutan desde el directorio `windows/`:

### 1. Instalar dependencias web
```powershell
corepack pnpm install --frozen-lockfile
```

### 2. Configuración de libmpv y entorno de compilación Visual Studio
Definir la variable de entorno explícita `SIDEB_MPV_DIR` con la ruta donde residen `mpv.lib` y `libmpv-2.dll`:
```powershell
$env:SIDEB_MPV_DIR = "S:\sideb-deps\mpv-gb4b5d69a4-x64-gpl"
```
`build.rs` copiará automáticamente `libmpv-2.dll` junto al binario generado (`target/debug/sideb-windows.exe`), permitiendo que el ejecutable resuelva la biblioteca dinámica de forma autocontenida sin requerir rutas hardcodeadas ni configuraciones globales.

Si en la terminal convencional Rust o `link.exe` no encuentran las herramientas de MSVC, inicializar el entorno de Build Tools 2022 y la variable en una sola instrucción:
```powershell
$vsEnv = cmd.exe /c 'call "C:\Program Files (x86)\Microsoft Visual Studio\2022\BuildTools\Common7\Tools\VsDevCmd.bat" -arch=amd64 -host_arch=amd64 && set'; foreach ($line in $vsEnv) { if ($line -match '^([^=]+)=(.*)$') { [System.Environment]::SetEnvironmentVariable($matches[1], $matches[2], 'Process') } }; $env:SIDEB_MPV_DIR = "S:\sideb-deps\mpv-gb4b5d69a4-x64-gpl"
```

### 3. Verificación de tipos y build frontend
```powershell
corepack pnpm check
corepack pnpm build
```

### 4. Ejecutar en modo desarrollo
Inicia Vite con HMR y lanza la ventana Tauri nativa con el motor de audio enlazado:
```powershell
corepack pnpm tauri dev
```

Para probar el ejecutable sin mantener Vite abierto, con el mismo entorno de Visual Studio y `SIDEB_MPV_DIR`:
```powershell
corepack pnpm tauri build --debug --no-bundle
```
El binario de prueba queda en `src-tauri/target/debug/sideb-windows.exe` con `libmpv-2.dll` a su lado. Esto no crea un instalador.

### 5. Compilar binario de producción
```powershell
corepack pnpm tauri build
```

## Pruebas de Rust
Para verificar los tests unitarios del reproductor y del core:
```powershell
cd ../core
cargo test -p player
cargo test -p innertube
cargo test -p sideb-core
```
