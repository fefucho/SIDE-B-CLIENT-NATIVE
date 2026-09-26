# Side B — YouTube Music Native macOS Client

Cliente nativo de YouTube Music para macOS de alto rendimiento, diseñado con **SwiftUI / AppKit** en el frontend y un núcleo nativo en **Rust** (InnerTube, persistencia SQLite y UniFFI).

## Estructura del Repositorio

- **[`SIDE B/`](SIDE%20B/)**: Código fuente activo de la versión 2 (v2).
  - [`SIDE B/apple/`](SIDE%20B/apple/): Shell nativo de macOS (Swift 6, SwiftUI, AppKit, AVPlayer).
  - [`SIDE B/core/`](SIDE%20B/core/): Motor Rust (crates `innertube` y `sideb-core`).
  - [`SIDE B/plans/`](SIDE%20B/plans/): Registro y seguimiento de Epics y planes de implementación.
  - [`SIDE B/docs/`](SIDE%20B/docs/): Auditorías históricas y reportes forenses de rendimiento y UI.
  - [`SIDE B/FIXES_LOG.md`](SIDE%20B/FIXES_LOG.md): Bitácora técnica continua de correcciones y mejoras.
  - [`SIDE B/GUIA_DE_ACTUALIZACION.md`](SIDE%20B/GUIA_DE_ACTUALIZACION.md): Guía de Git y publicación de actualizaciones vía GitHub Releases.
- **[`.agents/`](.agents/)**: Reglas automáticas y skills para asistentes de desarrollo (`swiftui-pro`).
- **[`AGENTS.md`](AGENTS.md)**: Instrucciones de gobernanza y pautas obligatorias para agentes.
- **`sideb OLD/`** y **`limusic-master/`**: Referencias históricas pasivas (solo lectura).

Para instrucciones de compilación y ejecución, consulta el [**README de Side B**](SIDE%20B/README.md).
