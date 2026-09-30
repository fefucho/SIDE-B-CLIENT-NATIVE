# UX-02 · Barra superior y ventana

## Decisión
Desactivar decoraciones nativas y dibujar una barra transparente sobre el contenido de Side B. Su transparencia es respecto del fondo de la app. Debe incluir Atrás, Adelante, sidebar y controles reales de minimizar/maximizar/cerrar. No dejar una ventana sin controles ni simular fullscreen sólo con CSS.

## Contrato
- `TitleBar.svelte`: callbacks `onBack`, `onForward`, `onToggleSidebar`; flags `canBack`, `canForward`, `sidebarCollapsed`. Altura 40 px; controles de ventana a la derecha con espacio reservado de 138 px. Región vacía arrastrable, botones excluidos; doble clic maximiza.
- Controller inyectable de ventana: `enterPlayerFullscreen()`, `exitPlayerFullscreen()`, `toggleNativeFullscreen()`. Al abrir fullscreen del reproductor recordar si la ventana ya estaba fullscreen; cerrar restaura sólo el cambio que hizo el reproductor. Escape cierra el reproductor. F11 alterna fullscreen nativo.
- Tauri `decorations:false`; permisos mínimos de la ventana main para close/minimize/toggle-maximize/start-dragging/set-fullscreen. Conservar permisos y comportamiento del login.
- Root reserva `--titlebar-height:40px` en vistas normales; el fondo fullscreen llega al borde superior y su contenido conserva margen seguro. Barra z-index por encima del reproductor.
- Referencia técnica: documentación oficial Tauri v2, Window customization; referencia visual: composición macOS.

## Propiedad y verificación
Agente de navegación: componentes shell/controller de ventana/config/capabilities; root integra en página. No editar Rust ni `+page.svelte` desde el agente.

Manual: arrastrar, doble clic, minimizar, maximizar/restaurar, cerrar, resize y Snap; entrar/salir fullscreen con Escape/F11 y verificar que siguen accesibles los controles.
