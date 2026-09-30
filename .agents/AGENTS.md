# Side B: instrucciones para agentes

El código activo está en la raíz de este repositorio: `core/` (Rust compartido), `apple/` (app macOS) y, cuando exista, `windows/` (app Windows). `documentation/` contiene planes y registros. Las rutas antiguas con prefijo `SIDE B/` en documentos históricos no describen este checkout.

Antes de editar, leer `.agents/rules/00-project_rules.md`. Para Rust compartido, leer `.agents/rules/10-backend.md`; para Swift/macOS, `.agents/rules/20-frontend.md` y `.agents/skills/swiftui-pro/SKILL.md`; para Windows, `.agents/rules/40-windows.md`. Consultar `.agents/rules/30-advisors.md` sólo al usar referencias antiguas.

Para el port Windows, seguir `documentation/plans/PLAN-013-side-b-windows-tauri.md` y el protocolo `.agents/WORKFLOW_WINDOWS.md`. Ejecutar únicamente el paquete asignado. Si el código contradice un plan, comprobar el contrato actual y reportar la diferencia antes de ampliar el alcance.

Los planes, auditorías y `documentation/FIXES_LOG.md` son historia, no prueba del comportamiento actual. Una compilación o un test funcional no prueban fluidez: respaldar afirmaciones de FPS, memoria o latencia con mediciones reproducibles.
