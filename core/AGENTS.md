# Rust compartido

Consultar `../.agents/rules/10-backend.md`. Red, parseo, persistencia y resolución de streams permanecen aquí; la integración de ventana y sistema pertenece a cada shell.

Usar `cargo test --locked --manifest-path core/Cargo.toml -p innertube -p sideb-core` desde la raíz para pruebas sin cuenta. `player` usa libmpv y su verificación Windows está incluida en `windows/scripts/windows.ps1 -Action verify`.

Si cambia un record/API compartido, actualizar sus consumidores y verificar cada plataforma disponible. En Windows se puede verificar Tauri; no afirmar que Swift compila sin hacerlo en macOS. Los tests en vivo ignorados no son una condición para trabajar sin sesión de usuario.
