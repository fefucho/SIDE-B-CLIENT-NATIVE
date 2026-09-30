# PLAN-010: Proporciones y alineación de tarjetas en Inicio

- **Fecha:** 2026-09-26
- **Estado:** Implementado; verificado en ventana amplia y con prueba de geometría estrecha. Pendiente revisión manual en ventana mínima y VoiceOver.
- **Depende de:** [PLAN-009](PLAN-009-inicio-dos-formatos.md), que ya implementó los dos formatos y los enlaces.
- **Alcance:** Solo la presentación de tarjetas grandes en `HomeFeedCollectionView.swift`. Conservar datos, orden de secciones, navegación, reproducción, menú, hover y enlaces.

## Evidencia visual

1. [Inicio actual de Side B](assets/PLAN-010-home-card-polish/01-side-b-home.png): las portadas de 184 puntos dominan cada estante; los títulos y la metadata tienen una escala excesiva respecto al espacio disponible.
2. [Detalle de dos canciones](assets/PLAN-010-home-card-polish/02-side-b-card-detail.png): el título de dos líneas empieza arriba y el de una línea aparece más abajo. Ambas metadata arrancan a la misma altura fija; «Canción» queda lejos del título corto.
3. [Referencia de YouTube Music](assets/PLAN-010-home-card-polish/03-youtube-music-reference.png): los títulos empiezan a la misma distancia de las portadas; la metadata sigue inmediatamente a cada título. Por eso queda más alta bajo un título de una línea que bajo uno de dos.

## Diagnóstico en el código actual

En `apple/Sources/SideB/Views/Home/HomeFeedCollectionView.swift`, el layout usa `cardWidth = 184` y `height = 286` en ventana normal (`148` y `230` bajo 760 puntos). `HomeItemView` fija `title.frame` a `art + 14` con **48 puntos de alto**, y `metadataY` a `art + 68`. El título es un `NSButton` con texto envolvente de 18 puntos. Su contenido se centra verticalmente en ese marco: una línea baja respecto a dos. La metadata nunca cambia de posición según las líneas que ocupó el título. El tipo, separador, artista y distintivo explícito se ubican con marcos independientes, por lo que sus líneas base pueden verse distintas.

La captura permite confirmar el efecto visual; el centrado del botón y las coordenadas fijas explican el patrón observado. No hace falta cambiar el parser ni los tipos de media para corregirlo.

## Trabajo propuesto

### 1. Reducir la escala de la tarjeta

- [x] Usar **160 puntos** de portada/tarjeta en ventana normal y **140 puntos** en ventana estrecha. Mantener portada cuadrada y respetar el radio actual.
- [x] Reducir el grupo de `NSCollectionLayoutSection` junto con la portada; el alto comparte una constante con la tarjeta y reserva dos líneas para título y detalle.
- [ ] Revisar manualmente el ritmo horizontal en ventana mínima y con barra lateral expandida. La geometría de 140 puntos y los límites de texto están cubiertos por prueba.

### 2. Poner todos los títulos arriba

- [x] Usar título de **14 puntos semibold** y una separación portada–título de **11 puntos**, revisados en la app abierta.
- [x] Sustituir el texto del botón por una etiqueta alineada arriba con botón transparente superpuesto; conservar acción, tooltip y etiqueta accesible.
- [x] Calcular una o dos líneas según el ancho y colocar ambos títulos a la misma altura; limitar la vista a dos líneas.

### 3. Hacer fluir y alinear la metadata

- [x] Ubicar la metadata **3 puntos después de la última línea visible del título**, en vez de usar una coordenada fija.
- [x] Usar metadata de **12 puntos** y alinear el distintivo `E`, el tipo, `·` y el artista/creador; conservar el enlace cuando existe un ID navegable.
- [x] Reservar hasta dos líneas de detalle dentro de la tarjeta y limitar su dibujo a ese marco.
- [x] Revisar visualmente canciones, álbumes y playlists con/sin `E` y títulos cortos/largos. Comprobar geometría estrecha con artista largo.

### 4. Cierre visual y funcional

- [x] Comparar la captura de Inicio enviada por el usuario con la app abierta a resolución amplia; comprobar el par de títulos de una y dos líneas.
- [ ] Completar revisión manual en ventana mínima, navegación por teclado y VoiceOver. Se compiló Release, se abrió Inicio y se comprobó el enlace de artista; las pruebas dirigidas cubren la alineación, el ancho estrecho y la tarjeta compacta.
- [x] Mantener la arquitectura de celdas y el contrato Core/UniFFI. No se observó un problema de fluidez que justifique una modificación adicional.

## Criterio de aceptación

En dos tarjetas contiguas con título de una y dos líneas, ambos títulos empiezan a la misma altura bajo las portadas; cada metadata queda inmediatamente debajo de su propio título. `E`, tipo, separador y artista comparten línea base. En Inicio caben más portadas que en la captura actual sin reducir la legibilidad, y ningún texto se corta o invade la sección siguiente. Las acciones y enlaces existentes funcionan igual.
