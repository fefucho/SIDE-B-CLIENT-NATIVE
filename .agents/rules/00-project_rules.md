---
trigger: always_on
---

# Side B v2 — reglas generales (2026)

- Comunicar hallazgos y cambios al usuario en español.
- Trabajar en `core/`, `apple/` o `windows/` según la tarea. Las referencias antiguas citadas en documentos históricos pueden no estar presentes en este checkout; si existen, son de solo lectura.
- La app macOS usa SwiftUI/AppKit y AVPlayer; el port Windows sigue `documentation/plans/PLAN-013-side-b-windows-tauri.md`. InnerTube y persistencia residen en Rust. No introducir WebViews para reproducción o parseo del DOM.
- En macOS, mantener la arquitectura de navegación y capas de `documentation/UI_ARCHITECTURE.md`, verificando nombres y componentes contra el código vigente. En ambas plataformas, los controles visibles deben tener datos y acciones reales.
- La versión mínima declarada por `apple/Package.swift` es macOS 15. Las APIs más nuevas requieren comprobación de disponibilidad; no subir la versión mínima sin una decisión explícita del producto.
- Consultar código, pruebas y SDK antes de repetir afirmaciones de planes, auditorías o `FIXES_LOG.md`. Esos documentos registran decisiones históricas, no mediciones vigentes ni prohibiciones universales.
- Evaluar rendimiento con escenarios reproducibles e Instruments. No declarar “120 FPS”, “0 ms” o “sin hitches” por compilar, pasar pruebas o ver CPU baja en reposo.
- Mantener los planes y registros existentes como historia. Registrar hitos estructurales o cambios de contrato; evitar agregar entradas por cada ajuste menor.
- Para encargos del port Windows entre Codex y Antigravity, seguir `.agents/WORKFLOW_WINDOWS.md` y reportar evidencia verificable por paquete.
