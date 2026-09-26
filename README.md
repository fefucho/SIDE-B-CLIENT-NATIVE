# Side B

> Cliente nativo de YouTube Music para macOS diseñado en SwiftUI, AppKit y Rust.

## Características
- **Audio de alto rendimiento**: Integración nativa con `AVPlayer` y motor de stream optimizado en Rust.
- **Diseño macOS 26/27**: Estilo Liquid Glass, tipografía SF Pro adaptativa y paleta refinada.
- **Colección y reproducción**: Cola dinámica, radios continuas, historial y sincronización de biblioteca.
- **Auto-actualizaciones**: Integración directa con GitHub Releases para recibir nuevas versiones dentro de la app con un solo clic.

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
