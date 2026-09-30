---
trigger: glob
globs: ["windows/**/*"]
---

# Side B Windows — shell Tauri

- Leer `documentation/plans/PLAN-013-side-b-windows-tauri.md` y `.agents/WORKFLOW_WINDOWS.md`; implementar sólo el paquete asignado.
- `windows/src-tauri/` usa `sideb-core` por dependencia Rust de ruta. Mantener InnerTube, persistencia y resolución de streams en `core/`; UniFFI sigue siendo el puente de Apple.
- Contratos Tauri y TypeScript tipados, con errores visibles y sin cookies, tokens ni URL firmadas en logs o estado persistido de la UI.
- Las vistas y controles visibles requieren datos y acciones reales; comprobar teclado, foco y estados de carga, vacío y error. No afirmar rendimiento por el framework o por un build de desarrollo.
- Validar audio, WebView2, DPI y empaquetado en Windows real. Registrar comandos, resultados y límites de cada verificación. Si una tarea cambia `core/`, aplicar también `.agents/rules/10-backend.md`.
