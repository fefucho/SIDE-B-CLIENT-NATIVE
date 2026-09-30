# PLAN-007: Menús contextuales por entidad y contexto

- **Fecha**: 2026-09-25
- **Estado**: Completado / Implementado. Corrección de despacho de acciones documentada en PLAN-008.
- **Alcance**: Canciones, álbumes, playlists, mixes y artistas; clic secundario y botón «…»

## Objetivo

Definir una sola política de acciones por tipo de elemento y aplicar filtros según la ubicación, los datos disponibles, el estado de la cuenta y los permisos. AppKit y SwiftUI deben presentar las mismas acciones, en el mismo orden, con el mismo ejecutor. Ninguna acción debe apuntar a otro elemento ni parecer disponible cuando no puede ejecutarse.

## Estado actual relevante

- `UI/AppContextMenuFactory.swift` contiene implementaciones separadas de AppKit (`NSMenu`) y SwiftUI (`contextMenu`). Las cabeceras de `AlbumDetailView`, `PlaylistDetailView` y `ArtistDetailView` tienen terceros menús `Menu` parciales.
- `BrowseCardRecord` y `HomeItemRecord` no informan si una playlist es propia ni si un elemento está guardado. `PlaylistDetailRecord` aporta `owned`, `inLibrary`, `sortEditable` y `continuation`; `AlbumDetailRecord` aporta `browseId`, `playlistId`, `inLibrary` e `items`.
- Un mix dinámico puede llegar con `kind == "playlist"`. La insignia visual MIX de Inicio también usa el título o la sección; eso no basta para decidir las acciones. Los IDs `RD…` pueden llegar con prefijo de navegación `VL…`.
- Reproducir una playlist conserva su `continuation`, pero las acciones actuales de añadir toda la playlist a la cola o reproducirla a continuación solo usan la primera página cargada.

## 1. Contrato común

Crear un modelo tipado, separado de la UI:

- `MenuTarget`: `song`, `album`, `playlist`, `radioMix`, `artist`. Identidad y datos se capturan del elemento bajo el clic; nunca se vuelven a buscar por índice o título después.
- `MenuOrigin`: `home`, `search`, `album(browseId)`, `playlist(id)`, `artist(id)`, `library`, `history`, `queue(occurrenceIndex)`, `nowPlaying`, `sidebar`. La ubicación se pasa explícitamente desde la vista; `router.currentPage` puede servir como apoyo, pero no define por sí solo el contexto de un overlay.
- `MenuFacts`: IDs canónicos, sesión iniciada, estado de biblioteca conocido/desconocido, propiedad y permisos conocidos/desconocidos, canciones completas o continuación pendiente, `setVideoId` de una entrada, y callbacks de editar/eliminar/ordenar cuando corresponda.
- `MenuAction`: identificador estable para cada acción; `MenuSection`: grupos ordenados de acciones. Un `MenuPolicy` puro construye las secciones a partir de target, origin y facts. Un `MenuActionExecutor` único ejecuta las operaciones y presenta errores; dos adaptadores renderizan `NSMenu` y SwiftUI `Menu/contextMenu`.

Reglas generales:

1. Comparar IDs canónicos, nunca títulos, para decidir si «Ir a…» o «Ver…» ya es redundante.
2. Ocultar acciones sin datos suficientes o sin capacidad real. No asumir `inLibrary == false` ni `owned == false` cuando el dato es desconocido. Un estado desconocido puede resolverse al cargar detalle o biblioteca, sin bloquear la apertura del menú.
3. Mantener una acción de colección visible para canciones con `videoId`: «Añadir a lista de reproducción». Si falta sesión, esa acción abre el flujo de inicio de sesión. Si falta `videoId`, el registro no es una canción accionable.
4. Los comandos de «…» y clic secundario del mismo elemento usan la misma política; la presentación puede variar, el contenido no.
5. Una mutación remota debe informar error y revertir una actualización optimista fallida. Las acciones destructivas requieren confirmación y permisos verificados.
6. No usar título ni badge «MIX» para inferir que un elemento es una radio. Normalizar `VL`/`RD` y diferenciar una playlist finita llamada «Mix» de un mix dinámico real.

## 2. Catálogo y filtros

### Canción

**Catálogo**: Reproducir ahora, Iniciar mix, Reproducir a continuación, Añadir a la cola; Me gusta/Quitar Me gusta; Guardar/Quitar de Biblioteca cuando existe token; Añadir a lista de reproducción; Ir al álbum, Ir al artista; Compartir; Eliminar de esta playlist y Quitar de la cola cuando corresponda.

- En el álbum de esa canción, ocultar «Ir al álbum». En la página del artista correspondiente, ocultar «Ir al artista».
- En playlist propia, «Eliminar de esta playlist» solo si la entrada tiene `setVideoId` y hay callback de actualización. La acción de añadir a otra playlist permanece.
- En cola, «Quitar de la cola» usa el índice de la ocurrencia, nunca `videoId` (la canción puede repetirse). No ofrecerla para la pista activa si eso altera la reproducción sin una semántica definida.
- En Now Playing, «Reproducir ahora» y «Reproducir a continuación» para la misma pista activa son redundantes y se ocultan.

### Álbum

**Catálogo**: Reproducir, Aleatorio, Iniciar mix, Reproducir a continuación, Añadir a la cola; Guardar/Quitar de Biblioteca; Ver álbum, Ir al artista; Compartir.

- Ocultar «Ver álbum» en la página de ese álbum. Mostrar «Ir al artista» solo con `artistId` válido y fuera de su página.
- El detalle tiene `browseId` y `playlistId`: navegar con el primero; usar el segundo, si existe, para acciones de biblioteca, radio o URL que lo requieran. Una sola función resuelve esa identidad para tarjetas y detalle.
- El estado de biblioteca debe ser conocido antes de mostrar Guardar/Quitar; no inferirlo de que una tarjeta de Inicio no esté en la caché.
- «Añadir álbum a playlist» queda fuera de esta etapa: el Core actual expone alta de canciones individuales, no una operación por lote con resultado/rollback claros.

### Playlist propia o ajena

**Catálogo común**: Reproducir, Aleatorio, Iniciar mix, Reproducir a continuación, Añadir a la cola; Ver playlist; Compartir.

- Ajena y con estado de biblioteca conocido: Guardar/Quitar de Biblioteca. La propiedad y el guardado son conceptos distintos.
- Propia y con `PlaylistDetailRecord.owned == true`: Editar detalles y Eliminar playlist con confirmación. «Ordenar» solo cuando `sortEditable == true`; sus opciones actuales deben conservarse. No ofrecer acciones de edición en tarjetas cuya propiedad se desconoce.
- Ocultar «Ver playlist» en su propia página. Normalizar ID de navegación (`VL…`) y de escritura antes de invocar Core; no construir URLs o llamadas de edición concatenando prefijos en las vistas.
- Para playlists paginadas, Reproducir conserva `continuation`. Aleatorio, Reproducir a continuación y Añadir a la cola **no deben** incluir silenciosamente solo la primera página: resolver todas las páginas necesarias con progreso/cancelación o dejar esas acciones ocultas hasta que exista esa operación. No cambiar la semántica visible según qué páginas se hayan cargado por scroll.

### Mix dinámico / radio

**Catálogo inicial**: Reproducir mix (radio continua); Ver mix si el ID admite página de detalle; Compartir si hay URL canónica verificable. Guardar/Quitar solo si el servicio confirma que ese mix concreto admite biblioteca y conocemos el estado.

- «Iniciar mix» dentro de un mix es redundante. «Aleatorio», «Reproducir a continuación» y «Añadir a la cola» no representan una radio potencialmente infinita: se omiten. Una futura acción «Añadir próximas N canciones» exigiría nombre y límite explícitos.
- Distinguir `RD…`, `VLRD…` y otros IDs de radio de una playlist finita con «Mix» en el título. Para la radio, usar el ID normalizado directamente en `startRadioForCollection`/`getNext`; nunca formar `RDAMPLVLRD…`.
- Una playlist finita llamada «Mix» recibe las reglas de playlist, no las de radio.

### Artista (para completar la fuente común)

**Catálogo**: Iniciar mix, Ver artista, Suscribirse/Cancelar suscripción si se conoce el estado, Compartir. Ocultar «Ver artista» en su propia página. Migrar el menú de cabecera existente a la misma política.

## 3. Orden visual de los menús

1. Reproducción.
2. Guardar, Me gusta y playlists.
3. Navegación.
4. Compartir.
5. Editar, quitar o eliminar al final, con rol destructivo cuando corresponda.

Separadores solo entre grupos presentes. «Añadir a lista de reproducción» es un submenú con playlists del usuario y «Nueva playlist…». El orden no cambia entre AppKit, SwiftUI, clic secundario y «…». No fijar un número artificial de opciones: el catálogo es amplio, pero el filtro evita menús largos e incoherentes.

## 4. Ejecución cuando se retome el trabajo

1. Crear los tipos `MenuTarget`, `MenuOrigin`, `MenuFacts`, `MenuAction` y la normalización de IDs. Antes de migrar vistas, enumerar casos reales de `kind`/ID para mix, playlist y álbum con datos disponibles en el proyecto.
2. Implementar `MenuPolicy` y `MenuActionExecutor`, compartiendo operaciones de radio, cola, biblioteca, compartir y navegación. Eliminar `try?` que silencian errores en mutaciones de menú.
3. Crear adaptadores AppKit y SwiftUI a partir de las mismas `MenuSection`. Migrar primero canciones y `NativeTrackTableView`; después tarjetas de Inicio, búsqueda, Biblioteca y sidebar; después cabeceras de detalle; finalmente fullscreen, cola y reproductor.
4. Conectar `MenuOrigin` explícito en cada superficie. Para la cabecera de playlist, pasar callbacks de abrir editor/confirmación de borrado y datos de orden. Para listas, pasar identidad exacta de la fila seleccionada.
5. Resolver la paginación de playlists antes de habilitar acciones de lote; resolver la identidad de mixes antes de ofrecer acciones de biblioteca/radio en ellos.
6. Retirar constructores y menús duplicados cuando todos los puntos de entrada usen la política común.

## 5. Criterios de aceptación

- Una canción ofrece «Añadir a lista de reproducción» desde Inicio, búsqueda, álbum, playlist, artista, cola y reproductor; la acción afecta al `videoId` del elemento clicado.
- En el álbum actual, una canción no muestra «Ir al álbum». Las reglas equivalentes funcionan para playlist y artista sin depender del título.
- Clic secundario y «…» del mismo elemento presentan acciones equivalentes y ejecutan el mismo código.
- Una playlist ajena no muestra Editar/Ordenar/Eliminar; una propia sí los muestra cuando los datos y permisos lo justifican. Borrar pide confirmación.
- Un mix de radio no se interpreta como playlist finita ni produce `RDAMPLVLRD…`; una playlist finita llamada «Mix» conserva menú de playlist.
- Las acciones de playlist larga no agregan únicamente la primera página sin avisar. Fallos de mutación muestran error y no dejan el estado visual invertido.
- Verificación al implementar: compilación Release y revisión manual de menús en cada superficie con casos de álbum, playlist propia/ajena, mix dinámico, canción repetida en cola y sesión cerrada. Sin mediciones de rendimiento ni pruebas amplias salvo que aparezca un riesgo concreto.
