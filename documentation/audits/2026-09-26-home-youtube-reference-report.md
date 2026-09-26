# Inicio de Side B: informe de referencia y diseño

**Fecha:** 2026-09-26  
**Alcance:** análisis para una implementación posterior. No se modificó la interfaz ni el contrato del Core en esta tarea.

## Objetivo de producto

Mantener en Inicio las secciones de YouTube Music que más sirven para retomar y descubrir música, y representar cualquier sección recibida con **uno de dos componentes**: carátulas grandes o filas compactas de canciones. La sección explica *por qué* se recomienda el contenido; cada ítem indica *qué es* y a dónde lleva.

Este informe usa siete capturas de la interfaz oficial facilitadas por el usuario, el Inicio de Side B observado en ejecución y el código vigente. El mensaje describe una octava captura sobre otras categorías de canciones, pero solo llegaron siete archivos; esa descripción se recoge como requisito y queda pendiente la imagen si se desea una comparación visual exacta.

## Evidencia de las capturas

| Referencia | Lo que muestra | Presentación objetivo |
|---|---|---|
| [1. Vuelve a escucharlo](assets/2026-09-26-home-references/01-vuelve-a-escucharlo.png) | Canciones y otros medios en portadas cuadradas; debajo se lee tipo y artista. El artista puede ser enlace. | Grande |
| [2. Favoritos olvidados](assets/2026-09-26-home-references/02-favoritos-olvidados.png) | Álbumes con portada, título, «Álbum» y artista. | Grande |
| [3. Álbumes para ti](assets/2026-09-26-home-references/03-albumes-para-ti.png) | Álbumes con la misma gramática visual. | Grande |
| [4. De tu biblioteca](assets/2026-09-26-home-references/04-de-tu-biblioteca.png) | Álbumes y playlists guardadas en una misma fila; la metadata distingue ambos tipos. | Grande |
| [5. Hip-hop](assets/2026-09-26-home-references/05-hip-hop.png) | Canciones y álbumes de un género en una misma fila de portadas; el tipo se muestra bajo cada título. | Grande |
| [6. Selecciones rápidas](assets/2026-09-26-home-references/06-selecciones-rapidas.png) | Solo canciones en bloques de cuatro filas por columna; miniatura, título, artista y álbum, con enlaces separados para artista y álbum. Sin fondo ni contorno permanente. | Compacta |
| [7. Hover de canción](assets/2026-09-26-home-references/07-hover-cancion.png) | Énfasis sutil al pasar el mouse; aparecen reproducir, valoración y menú. | Estado de la fila compacta |

La sección de género es personalizada. La documentación de [YouTube Music](https://support.google.com/youtubemusic/answer/13401025?hl=en) indica que Inicio recomienda según historial de escucha, ánimo y actividad; no garantiza que siempre se llame «Hip-hop» ni explica la puntuación exacta que llevó a esa sección. Debe tratarse como «un género relevante recibido», conservando el nombre que envíe YouTube.

## Dos componentes de contenido

### A. Tarjeta grande de portada

- Portada cuadrada protagonista; artista circular cuando el ítem sea un artista. Sin borde o placa permanente alrededor del conjunto.
- Título con hasta dos líneas; debajo, una línea o dos de metadata legible: `Canción · Artista`, `Álbum · Artista`, `Sencillo · Artista`, `EP · Artista`, `Playlist · Creador`, `Mix` o `Radio` cuando el subtipo esté confirmado.
- El tipo es visible **siempre**, incluso en una sección llamada «Álbumes para ti». Indicador explícito si YouTube lo proporciona.
- El artista enlaza a su página cuando hay ID de artista. Si no hay ID fiable, se muestra como texto. Las playlists muestran creador y, si llega, cantidad de pistas.
- La portada/título abre o reproduce según el tipo actual; un botón de reproducción separado puede aparecer en hover y foco. Menú contextual y acciones actuales se conservan.
- Navegación horizontal con flechas y «Más» cuando el destino realmente se pueda abrir. Las tarjetas deben responder al ancho de ventana sin recortar metadata esencial.

**Secciones objetivo:** Vuelve a escucharlo, Favoritos olvidados, Álbumes para ti, De tu biblioteca, género recomendado y cualquier sección nueva con tarjetas de YouTube o con álbumes, artistas, playlists, mixes o radios.

### B. Fila compacta de canción

- Miniatura pequeña, título en una línea y segunda línea con **artista y álbum como enlaces independientes** cuando existan IDs. Reproducciones/duración pueden aparecer si el dato viene de YouTube y hay espacio; no se debe mostrar texto truncado como si fuera un enlace distinto.
- Sin fondo, contorno ni cápsula en reposo. En hover o foco: resaltado discreto, control de reproducir/pausar, valoración y menú. El teclado y VoiceOver deben poder alcanzar las mismas acciones sin hover.
- Bloques horizontales de cuatro canciones por columna como referencia de escritorio; adaptar el número de filas y el ancho en ventanas compactas. No asignar este diseño a un álbum o playlist aislado solo porque la sección tenga muchas canciones.

**Secciones objetivo:** Selecciones rápidas y estantes nuevos formados por filas de canciones. La descripción de la octava imagen sitúa aquí otras categorías exclusivamente de canciones, sujeto a comprobar la estructura real que envíe YouTube.

## Regla de asignación de diseño

1. Derivar en Rust una pista de formato para el estante a partir de sus nodos `musicTwoRowItemRenderer` (tarjeta) y `musicResponsiveListItemRenderer` (fila). Hoy `parse_carousel_item` conoce esa diferencia y después la pierde. Como el diseño se asigna a la sección, basta una pista tipada de sección; no hace falta ampliar cada `BrowseItem` global solo para este fin.
2. Usar el formato de origen y los tipos de los ítems para decidir el diseño de la sección: presencia de colecciones o tarjetas de dos líneas → **grande**; filas de canciones puras → **compacta**.
3. Para las secciones de referencia, aplicar una asignación semántica conocida: «Vuelve a escucharlo» y «Favoritos olvidados» son grandes aunque contengan canciones; «Selecciones rápidas» es compacta cuando sus ítems sean canciones. Esta asignación es respaldo, no un parser de tipos basado en títulos traducidos.
4. Si los datos contradicen la asignación —por ejemplo, un álbum dentro de Selecciones rápidas— priorizar la verdad del ítem: mostrarlo con tipo y acción correctos, preferiblemente pasando la sección a tarjetas grandes. Nunca dibujar un álbum como canción.
5. Ante una sección desconocida o una mezcla de renderers, usar tarjetas grandes como presentación segura. Registrar esa combinación en diagnósticos de desarrollo para afinar la regla con ejemplos reales.

## Orden y disponibilidad en la pantalla principal

**Prioridad propuesta en «Todos»:** 1) Vuelve a escucharlo, 2) Favoritos olvidados, 3) Álbumes para ti, 4) De tu biblioteca, 5) género recomendado cuando pueda identificarse con una señal fiable, 6) Selecciones rápidas, 7) demás secciones en el orden de YouTube. Mantener el orden de los ítems *dentro* de cada sección. Si no hay señal fiable para reconocer un género, conservar su posición original en vez de adivinarlo por una palabra del título.

«Siempre cargar» significa buscar y mostrar estas secciones en Inicio **cuando YouTube las proporcione**, aunque lleguen en una continuación en vez de la primera página. Hoy `HomeViewModel` carga la primera página y solo pide la continuación mediante «Cargar más recomendaciones». La implementación debería precargar en segundo plano un número acotado de continuaciones para buscar las secciones prioritarias, mostrar lo ya disponible sin esperar toda la red, evitar duplicados e invalidar peticiones al cambiar cuenta o chip.

No hay una garantía de que YouTube envíe cada sección para cada cuenta o sesión. Si una falta tras ese límite, no crear un estante vacío ni inventar recomendaciones. «De tu biblioteca» podría ofrecer un respaldo usando los endpoints propios de biblioteca, pero debe distinguirse de la sección personalizada de YouTube. El género recomendado debe seguir siendo dinámico: no fijar «Hip-hop» para todas las cuentas.

Los chips de ánimo/actividad filtran otro feed. El orden prioritario anterior corresponde a «Todos»; al elegir un chip, se mantiene el contenido y orden relevantes que YouTube entregue para ese filtro.

## Brecha concreta en el código actual

- `HomePresentationFactory.style(for:)` elige `.quickPicks` por palabras del título o por un 75 % de canciones. Por eso «Forgotten favorites» y un género mayoritariamente musical pueden convertirse en filas compactas pese a que las capturas oficiales muestran tarjetas grandes. `HomeSectionStyle` ya tiene `.mixes`, pero este caso usa actualmente las mismas dimensiones de tarjeta que `.cards`.
- En `HomeItemView.configure`, el diseño compacto oculta `subtitle` y muestra un botón de artista calculado a partir del texto. Para un álbum, ese cálculo puede inventar un enlace o destino incorrecto. El contrato Home de UniFFI no conserva los `artist_runs` enlazados, `explicit`, `play_count` ni una pista de formato del estante que Rust podría derivar; las canciones de tarjeta pueden carecer además de `albumId`.
- El indicador «MIX» se deduce de texto, mientras el parser solo entrega `song`, `playlist`, `album` o `artist`. Hasta tener un subtipo fiable, mostrar «Playlist» es más honesto que atribuir «Mix» por una palabra del título.
- `HomePresentationFactory` solo prioriza Vuelve a escucharlo/Favoritos, Álbumes y Selecciones rápidas. «De tu biblioteca» y el género quedan donde lleguen. Su identidad de sección depende del título y su ocurrencia.
- «Más» se oculta para destinos `FE…`; esos enlaces de categorías necesitan una ruta tipada o deben permanecer ocultos. Las flechas de desplazamiento horizontal aún no están en la cabecera actual.
- El fixture de rendimiento tiene secciones homogéneas, por lo que no reproduce las mezclas de las capturas. Se necesita un fixture funcional con canción, álbum, playlist, mix y una canción sin `artistId`/`albumId`.

Rutas principales: `core/crates/innertube/src/models/browse.rs` (`parse_home`, `parse_carousel_item`), `core/crates/sideb-core/src/lib.rs` (`HomeItemRecord`), `apple/Sources/SideB/Models/HomeFeedPresentation.swift`, `apple/Sources/SideB/Views/Home/HomeFeedCollectionView.swift` y `apple/Sources/SideB/ViewModels/HomeViewModel.swift`.

## Secuencia sugerida para implementarlo

1. **Datos:** añadir al contrato los campos necesarios para tipo/formato, enlaces reales, explícito y origen visual; actualizar caché Home, binding UniFFI y consumidor Swift juntos. Definir subtipo de mix/radio solo con señal fiable.
2. **Clasificación:** reemplazar `style(for:)` por una decisión de dos diseños respaldada por renderer + tipos, con asignaciones conocidas y fallback grande. Ordenar las secciones prioritarias sin alterar el contenido de cada una.
3. **Interfaz:** implementar los dos componentes dentro del `NSCollectionView` actual, incluidos cabeceras, hover, foco, etiquetas de accesibilidad y acciones por tipo.
4. **Carga:** precarga acotada de continuaciones, estados parciales y deduplicación. Medir red, tiempo hasta primer contenido, desplazamiento y memoria antes/después en Release.
5. **Verificación:** fixture mixto; rutas de clic y enlaces; secciones faltantes y repetidas; cambio de cuenta/chip durante la carga; ventanas estrechas, teclado, VoiceOver, macOS 15 y macOS 26/27.

## Criterios de aceptación

- Las secciones de las capturas 1–5 aparecen como tarjetas grandes cuando YouTube las entrega; Selecciones rápidas aparece como filas compactas de canciones.
- Cada ítem mixto muestra su tipo real y abre la entidad correcta. Los enlaces a artista y álbum funcionan solo cuando existe un destino verificado.
- Las filas compactas no tienen placa permanente; hover y foco revelan controles equivalentes. El menú y las acciones ya existentes siguen disponibles.
- Una categoría nueva se representa con uno de los dos diseños sin agregar una regla por título para cada nombre nuevo.
- Las secciones prioritarias presentes en continuaciones se incorporan a Inicio automáticamente dentro de un presupuesto de carga definido, sin bloquear la primera pantalla ni duplicar estantes.
- Ninguna afirmación de fluidez se basa solo en capturas o compilación: se compara una traza reproducible antes y después.
