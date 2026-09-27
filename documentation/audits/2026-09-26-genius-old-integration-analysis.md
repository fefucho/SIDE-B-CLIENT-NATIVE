# Genius en Side B old: análisis para Side B v2

**Fecha:** 26 de septiembre de 2026  
**Alcance:** lectura del código, pruebas y documentación locales. No se cambió la app ni se verificaron respuestas actuales de Genius o MusicBrainz en red.

## Resumen

Side B old implementó un flujo completo: busca una canción en Genius, obtiene su historia, fecha y créditos, descarga anotaciones y construye una vista de letras con fragmentos enlazados. También intenta alinear anotaciones con letras sincronizadas de otra fuente. La idea de producto y varios modelos son aprovechables. Recomiendo **reimplementar el servicio y reutilizar selectivamente la lógica y los casos de prueba**, porque el código antiguo acopla red, parseo, caché y estado de UI, y depende de formatos concretos del sitio web.

Side B v2 ya tiene `SongItemRecord`, `PlayerViewModel.currentTrack`, `LyricsInfo`/`LyricLineInfo` del Core y `FullscreenNowPlayingView`. No tiene una integración Genius. La pestaña «Letras» muestra las letras del Core y el seguimiento por tiempo; Genius debe agregarse como información bajo demanda alrededor de ese flujo, sin sustituirlo automáticamente.

## Cómo funciona Side B old

| Etapa | Implementación observada | Datos obtenidos |
|---|---|---|
| Activación | `SideBApp.swift` inicia precarga al cambiar `videoId`: inmediata si Genius está activo, con 4 s de espera en otro caso. `GeniusSongInfoOverlay` y `GeniusLyricsDisplayView` también solicitan carga. | Pista actual y letras existentes. |
| Resolución | `GeniusService.runPipeline`: limpia título/artista, busca con hasta tres variantes y usa MusicBrainz como último intento. Puntúa título 70 % y artista 30 % con LCS de palabras. | ID de canción Genius y puntuación. |
| Búsqueda y detalle | `GET genius.com/api/search/multi?q=…`, seguido de `GET genius.com/api/songs/{id}`. | Título, artista, URL, portada, descripción, fecha, número de anotaciones, productores, compositores y otros créditos. |
| Anotaciones | `GET genius.com/api/referents?song_id=…&text_format=dom,plain&per_page=50&page=…`; lee hasta dos páginas. | Fragmento, explicación, imagen, votos, verificación, autor, contribuyentes y enlace. |
| Letras Genius | Descarga HTML de la canción. `GeniusLyricsExtractor` localiza `window.__PRELOADED_STATE__`, evalúa su asignación con `JavaScriptCore` y recorre el AST de letras. Una expresión regular adicional recoge enlaces de fragmentos. | Líneas, encabezados y `referentId` para abrir anotaciones. |
| Presentación | `GeniusLyricsDisplayView` usa el ID del referent directamente. `GeniusSongInfoOverlay` muestra historia y créditos; `GeniusAnnotationInspectorView` muestra la explicación y el enlace de origen. | Contexto de la canción y anotaciones seleccionables. |

Archivos principales de referencia: `sideb OLD/Sources/SideB/Services/Genius/{GeniusService,GeniusModels,GeniusLyricsExtractor,GeniusAnnotationMatcher}.swift`, `sideb OLD/Sources/SideB/Views/Genius/`, `sideb OLD/Sources/SideB/Views/GeniusLyricsDisplayView.swift` y `sideb OLD/Tests/SideBTests/GeniusServiceTests.swift`. El repositorio viejo es material de consulta de solo lectura.

## Hallazgos técnicos

1. **La selección de canción necesita mayor precisión.** `runPipeline` acepta al final una coincidencia de 0,40 aunque su umbral principal sea 0,65. No contrasta duración, álbum, versión en vivo/remix ni `videoId` con el candidato de Genius. Quitar «live» o «remastered» del título ayuda a buscar, pero puede confundir grabaciones distintas. La clave de caché solo usa título y artista. Conviene conservar candidatos y puntuaciones hasta validar el detalle y pedir una coincidencia más fuerte antes de mostrar anotaciones como propias de esa pista.
2. **Los fallos de red y la ausencia de resultados se mezclan.** `searchAndFetch` puede devolver `.error`, pero `runPipeline` solo conserva `.matched` y termina en `.notFound`. `geniusSearch` y `fetchReferentsPage` convierten respuestas HTTP distintas de 200 en resultados vacíos. La UI no puede distinguir «no existe», «falló Genius» y «se agotó el tiempo»; tampoco hay tratamiento explícito de respuestas de limitación de solicitudes.
3. **La caché evita algunos viajes, pero crece sin límite y deja huecos.** Hay tres diccionarios en memoria, sin expiración ni presupuesto. `fetchAnnotationsAndLyrics` solo responde desde caché cuando existen *ambas* entradas; una página sin anotaciones o un HTML que no produjo letras vuelve a provocar solicitudes. Tampoco guarda resultados negativos. La precarga a los 4 s puede descargar detalle, anotaciones y HTML aunque el usuario nunca abra Genius.
4. **El parseo del HTML es el punto más frágil.** Una expresión regular exige la forma exacta `window.__PRELOADED_STATE__ = JSON.parse('…');`; otra busca enlaces con una estructura HTML específica. `JavaScriptCore` evalúa una sentencia extraída de contenido remoto. Los tests comprueban una muestra fabricada de esa forma, pero no variantes reales, límites de tamaño, caracteres escapados o cambios de estructura. El proyecto v2 además indica que no se use `WKWebView` para parsear DOM; el diseño nuevo debería preferir datos estructurados y aislar cualquier extracción web opcional, sin ejecutar código remoto.
5. **El estado de carga tiene una carrera concreta.** `ensureLoaded` cancela la tarea anterior y crea otra al cambiar de pista, pero el `defer` de la tarea anterior asigna `isLoading = false` incondicionalmente. Si esa tarea termina después de comenzar la nueva, puede ocultar el indicador de carga de la pista nueva. Los resultados sí tienen guardia de `currentTrackKey` y cancelación antes de publicarse, lo cual es útil como patrón, pero la publicación de *todo* el estado debe llevar la misma identidad.
6. **El alineador difuso no sostiene hoy la UI Genius antigua.** `GeniusAnnotationMatcher` crea `lineAnnotationMap` para letras sincronizadas, pero la vista Genius visible busca `annotationLookup` usando IDs del AST de Genius. No se encontró lectura de `lineAnnotationMap` en las vistas. Además, `matchMultiLineClusters` puede marcar todas las líneas de un bloque si solo coincide el 60 %, incluidas líneas que no coinciden; la comparación por contención/palabras puede dar falsos positivos en frases repetitivas. Puede servir como fallback, con confianza por línea y casos negativos, después del enlace directo por ID.
7. **El costo de CPU se concentra en el actor principal.** `GeniusService` es `@MainActor` y hace limpieza, scoring, decodificación, extracción de HTML y alineación desde sus métodos. La red es asíncrona, pero el trabajo posterior puede bloquear la UI al abrir una canción con muchas anotaciones. La página 2 solo se solicita si hay exactamente 50 anotaciones *válidas* tras `compactMap`, y el límite total es 100; eso no equivale necesariamente al total disponible.

## Qué reutilizar y qué rediseñar

**Reutilizar como especificación:** modelos de canción, créditos y anotación; extracción recursiva de texto desde el DOM JSON cuando la respuesta realmente lo incluya; limpieza moderada de títulos; vistas de historia y explicación con enlace de atribución; pruebas de decodificación mixta y de estrofas repetidas. Ajustar los modelos a las necesidades de la UI actual.

**Rediseñar:** cliente de red con respuestas tipadas y errores explícitos; política de búsqueda y verificación de versión; caché acotada con TTL y resultados negativos; carga bajo demanda; cancelación y deduplicación por identidad de pista; parseo aislado con límites; mapeo entre anotaciones y líneas. No copiar los `@available(macOS 26.0, *)` de las vistas como única presentación: v2 admite macOS 15+.

## Propuesta para Side B v2

1. **Primer corte: contexto de canción.** Añadir una acción «Sobre esta canción» en Fullscreen para mostrar historia, créditos, fecha y enlace a Genius. Solicitar datos cuando se abra; separar «sin coincidencia» de «error» y mostrar fuente/atribución. Esto entrega valor sin depender del HTML de letras.
2. **Segundo corte: anotaciones.** Al abrir el modo Genius, pedir referents para el ID ya verificado. Mostrar fragmentos y explicaciones en una lista o inspector. Añadir paginación real, deduplicación por ID y soporte para cancelar al cambiar de pista.
3. **Tercer corte: vínculo con letras.** Priorizar un ID de referent procedente de una respuesta estructurada, si está disponible. Si no, usar un alineador local sobre `LyricsInfo.lines` con umbral conservador y dejar sin anotación las líneas ambiguas. Mantener el seguimiento y seek de las letras actuales; tratar una vista de letras Genius sin tiempos como modo de lectura separado si se justifica.
4. **Validación antes de implementar los parsers.** Probar las respuestas actuales de los endpoints de manera de solo lectura, con ejemplos sanitizados de canciones normales, colaboraciones, directos, remasters, letras ausentes y muchos referents. Medir solicitudes, latencia, memoria y tiempo de parseo; establecer límites de tamaño/concurrencia y comprobar la atribución y condiciones de uso aplicables.

El lugar natural para orquestar la identidad y cancelación es el ciclo de `PlayerViewModel.currentTrack` (`videoId`), mientras que una capa dedicada de Genius debe poseer el estado y la caché. La elección de Swift frente a Rust para la red de Genius puede decidirse al diseñar el contrato: los modelos de presentación solo los usa macOS hoy, y no hay necesidad demostrada de ampliar UniFFI para el primer corte. Si se decide compartir la obtención o persistencia en el Core, exportar records tipados y registrar el cambio de contrato.

## Pruebas y límites de este informe

`GeniusServiceTests.swift` cubre limpieza, puntuación, decodificación, parseo de un HTML sintético y alineación positiva. No demuestra disponibilidad actual de los endpoints, tasas de falso positivo, errores HTTP, cancelación/carreras, límites de caché ni rendimiento. Este informe es análisis estático; no se compiló ni se ejecutó Side B old ni Side B v2, y no se hicieron mediciones de red o UI. Las reglas y contratos de v2 prevalecen sobre las instrucciones incluidas en la copia antigua.
