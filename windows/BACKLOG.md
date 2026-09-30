# Pendientes Windows

Única lista activa de producto Windows. Mantener objetivos verificables; usar el diff/commit para explicar la implementación. Un pendiente se cierra con evidencia de su comportamiento, no por el estado de un plan antiguo.

## Base disponible

Inicio con chips/continuaciones; búsqueda de canciones y álbumes; álbum/artista/catálogos; login persistente; biblioteca, likes, playlists e historial; reproducción, pausa, seek, volumen, next/previous y fullscreen con cola compartida. El usuario confirmó audio y el recorrido básico de Inicio → álbum → artista → Atrás antes de esta reorganización.

## Próximo trabajo

### Reparaciones en curso (pedido del usuario)

| Plan | Responsable / dependencia | Resultado |
|---|---|---|
| [UX-01](plans/UX-01-navigation.md) | Navegación + integración root | Atrás/Adelante entre todas las vistas |
| [UX-02](plans/UX-02-titlebar.md) | Navegación, junto a UX-01 | Barra superior y fullscreen nativo |
| [UX-03](plans/UX-03-playlists.md) | Backend primero, UI segunda ola | Botones, edición, orden y acciones de playlist |
| [UX-04](plans/UX-04-radio-queue.md) | Backend + controller root | Radios de Inicio y edición segura de cola |
| [UX-05](plans/UX-05-context-menus.md) | Segunda ola, usa UX-03/04 | Clic derecho y Más con política macOS |
| [UX-06](plans/UX-06-player-fullscreen.md) | UI primera ola + integración root | Barra y fullscreen con scroll independiente |

Root revisa contratos antes de delegar e integra `+page.svelte`; agentes no comparten archivos activos. Pruebas manuales a cargo del usuario mientras esté presente. Los planes se cierran con evidencia y luego se archivan, sin convertirse en otra lista de estado.

Implementación de los seis planes integrada en `windows/ux-controls-and-menus`. Gates locales: frontend 51/51 pruebas y tipos sin errores/advertencias; bridge Tauri 13/13 pruebas y cargo check aprobado. Falta confirmar en la app nueva el comportamiento visual y las operaciones con la cuenta; la aprobación anterior del usuario corresponde al baseline. Letras/Relacionado conservan sus placeholders.

| Prioridad | Resultado | Criterio de cierre |
|---|---|---|
| 1 | Reordenar cola | Extender agregar/quitar de UX-04 con movimientos por entryId; conservar pista actual y duplicados |
| 1 | Shuffle/repeat persistentes | Estado explícito de ambos modos; next, previous y EOF coherentes, también tras cambiar de vista |
| 1 | Validar radio continua | UX-04 implementa continuación/deduplicación por videoId/reintento; confirmar con reproducción real el final de bloque y cambio de canción durante carga |
| 2 | Restauración de reproducción | Persistir cola, pista, posición y modos; volver a abrir sin reproducir por sorpresa |
| 2 | Acciones de playlists/menús | Agregar/quitar pistas, editar listas propias y completar menús según permisos; estados pendientes/error recuperables |
| 2 | Paridad visual por pantalla | Comparar capturas Mac/Windows con ventana y sidebar equivalentes; resize/DPI, foco, teclado y navegación sin regresiones |
| 2 | Letras y recomendados | Sustituir las vistas básicas/placeholders por datos y acciones reales, manteniendo el alcance por pantalla |
| 3 | Distribución Windows | Instalador con DLL, licencias y WebView2 resueltos; probar en máquina limpia, firma/actualización según decisión de producto |

## Cómo elegir una tarea

Elegir un resultado de la tabla y acotar archivos/contratos. Si requiere varios agentes, repartir dominios sin compartir archivos o usar worktrees; un integrador revisa el diff y los gates. Sólo escribir un diseño adicional si hay una decisión nueva que no pueda explicarse brevemente en el encargo. El backlog no es un registro de cada ajuste visual.
