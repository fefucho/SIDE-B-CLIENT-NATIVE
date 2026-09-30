# Pendientes Windows

Única lista activa de producto Windows. Mantener objetivos verificables; usar el diff/commit para explicar la implementación. Un pendiente se cierra con evidencia de su comportamiento, no por el estado de un plan antiguo.

## Base disponible

Inicio con chips/continuaciones; búsqueda de canciones y álbumes; álbum/artista/catálogos; login persistente; biblioteca, likes, playlists e historial; reproducción, pausa, seek, volumen, next/previous y fullscreen con cola compartida. El usuario confirmó audio y el recorrido básico de Inicio → álbum → artista → Atrás antes de esta reorganización.

## Próximo trabajo

| Prioridad | Resultado | Criterio de cierre |
|---|---|---|
| 1 | Edición de cola | Agregar, quitar y reordenar ocurrencias sin desincronizar barra/fullscreen; conservar pista actual y duplicados |
| 1 | Shuffle/repeat persistentes | Estado explícito de ambos modos; next, previous y EOF coherentes, también tras cambiar de vista |
| 1 | Radio continua | Pedir continuaciones con deduplicación por ocurrencia y reintento acotado; seguir reproduciendo al final del bloque |
| 2 | Restauración de reproducción | Persistir cola, pista, posición y modos; volver a abrir sin reproducir por sorpresa |
| 2 | Acciones de playlists/menús | Agregar/quitar pistas, editar listas propias y completar menús según permisos; estados pendientes/error recuperables |
| 2 | Paridad visual por pantalla | Comparar capturas Mac/Windows con ventana y sidebar equivalentes; resize/DPI, foco, teclado y navegación sin regresiones |
| 2 | Letras y recomendados | Sustituir las vistas básicas/placeholders por datos y acciones reales, manteniendo el alcance por pantalla |
| 3 | Distribución Windows | Instalador con DLL, licencias y WebView2 resueltos; probar en máquina limpia, firma/actualización según decisión de producto |

## Cómo elegir una tarea

Elegir un resultado de la tabla y acotar archivos/contratos. Si requiere varios agentes, repartir dominios sin compartir archivos o usar worktrees; un integrador revisa el diff y los gates. Sólo escribir un diseño adicional si hay una decisión nueva que no pueda explicarse brevemente en el encargo. El backlog no es un registro de cada ajuste visual.
