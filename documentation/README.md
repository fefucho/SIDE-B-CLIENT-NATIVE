# Side B

> Cliente nativo de YouTube Music para macOS diseñado en SwiftUI, AppKit y Rust.

## Características
- **Audio de alto rendimiento**: Integración nativa con `AVPlayer` y motor de stream optimizado en Rust.
- **Diseño macOS 26/27**: Estilo Liquid Glass, tipografía SF Pro adaptativa y paleta refinada (ver [`UI_ARCHITECTURE.md`](UI_ARCHITECTURE.md)).
- **Colección y reproducción**: Cola dinámica, radios continuas, historial y sincronización de biblioteca.
- **Auto-actualizaciones**: Integración directa con GitHub Releases para recibir nuevas versiones dentro de la app con un solo clic. Consulta la [**Guía de Actualizaciones y Lanzamiento**](GUIA_DE_ACTUALIZACION.md).

## Requisitos
- macOS 15.0 o superior (compatible con Apple Silicon e Intel).

## Compilación local
Para compilar y ejecutar en modo Release:
```bash
sh Scripts/compile_and_run.sh
```

## Pruebas
```bash
swift test --package-path apple
```

## Documentación del Proyecto
- [**Estado del Proyecto**](PROJECT_STATE.md): Resumen de arquitectura, hitos y componentes vigentes.
- [**Planes y Epics**](plans/README.md): Registro oficial de epics estructurales y roadmaps de producto.
- [**Registro de Fixes**](FIXES_LOG.md): Bitácora técnica continua de correcciones y mejoras.
- [**Auditorías y Reportes**](docs/audits/README.md): Archivo histórico de optimizaciones de scroll y diagnósticos forenses.
