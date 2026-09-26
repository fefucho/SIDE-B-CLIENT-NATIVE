---
trigger: always_on
---

# Side B v2 — reglas generales (2026)

- Comunicar hallazgos y cambios al usuario en español.
- Trabajar en `SIDE B/`. `sideb OLD/` y `limusic-master/` son material de consulta de solo lectura.
- La app es nativa de macOS: SwiftUI/AppKit y AVPlayer en el shell; InnerTube, persistencia y contratos UniFFI en Rust. No introducir WKWebView para reproducción o parseo del DOM.
- Mantener la arquitectura de navegación y capas de `SIDE B/UI_ARCHITECTURE.md`, verificando los nombres y componentes contra el código vigente. Los controles visibles deben tener datos y acciones reales.
- La versión mínima declarada por `SIDE B/apple/Package.swift` es macOS 15. El entorno de desarrollo actual usa macOS 27, Xcode 27 y Swift 6.4. Las APIs de macOS 26/27 requieren comprobación de disponibilidad y comportamiento razonable en versiones admitidas; no subir la versión mínima sin una decisión explícita del producto.
- Consultar código, pruebas y SDK antes de repetir afirmaciones de planes, auditorías o `FIXES_LOG.md`. Esos documentos registran decisiones históricas, no mediciones vigentes ni prohibiciones universales.
- Evaluar rendimiento con escenarios reproducibles e Instruments. No declarar “120 FPS”, “0 ms” o “sin hitches” por compilar, pasar pruebas o ver CPU baja en reposo.
- Mantener los planes y registros existentes como historia. Registrar hitos estructurales o cambios de contrato; evitar agregar entradas por cada ajuste menor.
