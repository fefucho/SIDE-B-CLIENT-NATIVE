# Inicio: diagnóstico del desplazamiento rápido

**Fecha:** 26 de septiembre de 2026  
**Alcance:** Inicio de Side B en macOS, con el feed ya visible. Este documento registra hallazgos y propone cómo comprobar las correcciones; no cambia el comportamiento de la app.

## Resumen

El tirón al desplazar Inicio rápido es plausible y aparece en una captura de Instruments. La arquitectura actual ya usa un `NSCollectionView` vertical con celdas reutilizables y secciones horizontales; las auditorías anteriores sobre `ScrollView` y `LazyVStack` describen una versión anterior. En la captura, durante el desplazamiento rápido, el hilo principal dedica muestras a calcular el layout, incorporar secciones horizontales y preparar celdas nuevas. También hay trabajo de seguimiento del puntero y de imágenes. Que los datos del feed estén cargados no significa que todas las celdas, vistas e imágenes decodificadas estén listas para una pasada rápida.

La captura no permite asignar un porcentaje exacto del tirón a cada causa. En particular, la automatización que movió la app consultó su árbol de accesibilidad y contaminó parte de la traza. Una pausa de 325 ms coincide con esa consulta y **no debe citarse como un tirón causado por el scroll**.

## Evidencia reproducible

- App ejecutada en configuración Release, proceso `SideB` 16010, con `xctrace` y los instrumentos **Animation Hitches** y **Time Profiler** durante 18,96 s. Se desplazó Inicio seis páginas hacia abajo y seis hacia arriba con la interfaz de automatización.
- En la ventana de desplazamiento de aproximadamente 16,9 a 18,9 s, Instruments marcó 73 eventos de duración de cuadro; 24 alcanzaron al menos 16,67 ms y el mayor fue de 29,17 ms. Son eventos de la traza, **no** una medición de FPS promedio ni 73 pausas perceptibles. El propio mecanismo de automatización añade trabajo de accesibilidad, por lo que estas cifras son indicativas.
- Excluyendo muestras cuya pila contiene llamadas `AXXMIG`/`AXCopyAttribute`, en esa ventana quedaron 346 muestras del hilo principal. En 42 apareció `NSCollectionView` haciendo layout, en 39 actualizando las celdas visibles, en 31 preparando celdas, en 23 incorporando elementos de secciones horizontales y en 15 `HomeItemView.layout()`. Los recuentos se solapan porque una muestra puede contener varias funciones de la misma pila; **no son porcentajes ni tiempos exclusivos**.
- Se observaron también muestras de actualización de `NSImageView` y seguimiento de puntero. La captura no demuestra que la decodificación de imágenes sea la causa dominante.
- La pausa de 325 ms de ~6,7 s coincide con cientos de muestras de consultas de accesibilidad de `NSCollectionView`. Debe excluirse de cualquier afirmación sobre fluidez del gesto.

Comando usado para la captura: `xcrun xctrace record --template 'Animation Hitches' --instrument 'Time Profiler' --attach 16010 --time-limit 18s --output /tmp/sideb-home-fast-scroll-2026-09-26.trace --no-prompt`. La traza completa quedó en `/tmp` y puede desaparecer al limpiar archivos temporales.

## Hallazgos en el código actual

| Prioridad | Lugar | Qué pasa | Impacto probable y grado de certeza |
|---|---|---|---|
| Alta | `HomeFeedCollectionView.swift`, `layoutSection(at:)` y proveedor de celdas | Cada sección visible usa un scroller horizontal ortogonal. Al cruzar varias secciones en una sola aceleración, AppKit incorpora scrollers, resuelve layout y crea/reutiliza celdas en el hilo principal. | **Confirmado como trabajo durante el gesto** por las pilas; el costo exacto por operación queda pendiente. |
| Media | `HomeFeedCollectionView.swift`, `clipBoundsChanged` → `updateHover` | Cada cambio del viewport vertical recorre las celdas visibles para localizar la que queda bajo el puntero. Los scrollers horizontales también notifican cambios de límites. | **Trabajo extra confirmado por el código**, aún sin tiempo exclusivo medido. Puede evitarse si el puntero no está dentro de Inicio o localizarse por índice/área sin recorrer todas las celdas. |
| Media | `HomeItemView.layout()` | En cada layout se vuelve a medir texto, se ajustan múltiples subvistas y se llama a `invalidateCursorRects(for:)` sin comprobar si cambiaron los rectángulos. | **Trabajo extra confirmado por el código**; la traza contiene layout de estas vistas y actualización de áreas de tracking. Falta medir el ahorro de una modificación concreta. |
| Media | `HomeItemView.configure` e `ImageCache` | Cada celda que entra configura texto, botones y portada. La caché RAM hace el acierto sincrónico, pero un fallo crea tarea para disco/red y decodificación. El límite de cuatro solicitudes es para `prefetch`; las solicitudes de celdas visibles no comparten ese límite. Cancelar la tarea de la celda no garantiza cancelar la tarea interna ya iniciada en la caché. | **Posible amplificador** en pasadas rápidas, sobre todo la primera vez o si `NSCache` expulsó imágenes. No se demostró como causa principal en esta traza. |
| Baja, condicionada | `HomeViewModel.apply(records:)` → `HomeFeedCollectionView.applyContent()` | Las continuaciones prioritarias pueden incrementar `contentRevision` y aplicar de nuevo un snapshot completo; después se reconfiguran todas las celdas visibles. | Puede causar un salto mientras todavía llegan secciones, pero **no explica por sí solo** el problema persistente con el feed estable. Hay que medirlo aparte. |

Cada `HomeItemView` construye una jerarquía de botones, etiquetas e imágenes incluso cuando algunas subvistas quedan ocultas para el formato de canción compacta. Esto da flexibilidad y enlaces accesibles, pero aumenta el trabajo de preparación y layout cuando un gesto rápido revela muchas celdas nuevas. No conviene simplificarla a ciegas: hay que conservar los enlaces de artista/álbum, controles y accesibilidad.

## Orden de trabajo propuesto

1. **Medición controlada antes de tocar el diseño.** Repetir la traza sin consultas de accesibilidad durante el intervalo medido. Usar el mismo feed, tamaño de ventana y recorrido en Release; comparar una primera pasada con una segunda pasada de caché caliente. Registrar intervalos de cuadros, tiempos de hilo principal y contadores por sección de celdas configuradas, layouts, invalidaciones de cursor y aciertos/fallos de imagen.
2. **Quitar trabajo repetido del gesto.** Evitar la invalidación incondicional de cursores y el barrido de celdas visibles en cada notificación de scroll. Actualizar hover solo cuando cambie la celda bajo el puntero o cuando sea necesario redibujarla. Medir de nuevo; si no mejora, revertir el cambio.
3. **Reducir el costo de las celdas que entran.** Guardar mediciones de texto por contenido/ancho, omitir configuración redundante al reutilizar el mismo registro y revisar si conviene separar las jerarquías de tarjeta grande y canción compacta. Mantener la alineación y los enlaces logrados en el pulido visual.
4. **Preparar las portadas próximas.** Prefetch acotado para elementos por delante del desplazamiento, con el mismo URL y tamaño que usa la celda; medir aciertos RAM y evitar acumular decodificaciones de elementos que ya salieron del viewport. No aumentar indiscriminadamente los límites de memoria.
5. **Evaluar la composición de secciones.** Si aún hay tirones, instrumentar el costo de los scrollers ortogonales y comparar una variante de layout con menos trabajo al entrar a una sección. Mantener el comportamiento horizontal y la presentación de las dos tarjetas como requisitos.

**Criterio de aceptación:** en un recorrido repetible con caché caliente y sin inspección de accesibilidad simultánea, no debe haber ráfagas de actualizaciones del hilo principal que sobrepasen el presupuesto del monitor durante el desplazamiento rápido; la segunda pasada no debe sentirse peor que la primera. Comparar la distribución de duraciones de cuadro y el peor tramo, además de revisar visualmente la respuesta al scroll y al hover. No usar solo un FPS promedio.

## Límites de este diagnóstico

Es una muestra breve de un equipo y una sesión. El instrumento, la automatización y el trabajo de accesibilidad alteran el resultado. No se ejecutó aún una prueba A/B de cambios ni se estableció un presupuesto numérico final para este hardware. Las prioridades anteriores indican dónde medir primero; no equivalen a una causa raíz cerrada.
