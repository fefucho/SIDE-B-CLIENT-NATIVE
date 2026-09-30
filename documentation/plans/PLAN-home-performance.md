# Inicio de Side B: plan de rendimiento

Fecha: 24 de septiembre de 2026. Alcance: `SIDE B/apple/` y su Core actual. `sideb OLD` queda fuera.

## Estado comprobado

- Inicio usa `ScrollView` + `LazyVStack` vertical, carruseles horizontales, `CachedAsyncImage` y registros tipados de UniFFI. Los informes y `FIXES_LOG.md` describen intentos anteriores, pero sus cifras de FPS no sustituyen una medición de esta revisión.
- La restauración de sesión competía con la primera consulta del feed. La vista podía pedir recomendaciones de invitado antes de instalar la cookie. La vista también repetía un fallback de sesión que el Core Rust ya implementa.
- Cambiar de chip podía dejar que una respuesta anterior reemplazara la selección actual. El contenido desaparecía durante la espera. Los cambios de cuenta necesitaban invalidar consultas pendientes.
- Una traza de arranque de 12,99 s, tomada **después** de las primeras correcciones y sin hacer scroll, registró un hitch de 466,66 ms al crear y distribuir la ventana (4,48 s) y otro de 166,67 ms cuando apareció el feed (11,14 s). `HomeView.body` apareció cuatro veces, con unos 9,4 ms acumulados; el costo incluye layout y creación de vistas fuera de ese contador. La traza no mide fluidez al desplazarse ni establece una comparación anterior/posterior.
- En la ventana del segundo hitch, Time Profiler muestra trabajo de `ScrollViewLayoutComputer`, `LazyVStackLayout`, `QuickPickSongCell` y cálculo de regiones arrastrables de `NSWindow`. Son candidatos de investigación, no causas aisladas todavía.
- Dos trazas adicionales, con marcas de Core y una con layout detallado, registraron `HomeFeedFetch` de 1,65 s y 0,71 s, `HomeFeedCategorize` de 0,14 ms y 0,10 ms, y un hitch de 175 ms inmediatamente después de recibir el feed en ambos casos. La variación de red no eliminó el pico de presentación.
- En la traza de layout, el primer `LazyVStackLayout` del feed tardó 53,81 ms, dentro del cual el `LazyHStackLayout` de Quick Picks (contenido de 2406 pt) tardó 42,99 ms. Son intervalos anidados, por lo que no deben sumarse. `QuickPickSongCell` monta tanto un `Menu` por fila como `.songContextMenu`; pese a su nombre y a los informes anteriores, el modificador actual usa `.contextMenu` de SwiftUI.
- La biblioteca Rust enlazada contiene objetos construidos para macOS 27, mientras el paquete Swift declara macOS 15. `swift build` y las pruebas compilan, pero esas advertencias requieren una compilación del XCFramework con el deployment target correcto antes de validar macOS 15.

## Correcciones ya aplicadas

1. Instalar o limpiar la sesión antes de disparar la primera carga de Inicio.
2. Invalidar resultados de consultas anteriores al cambiar filtro o cuenta, mantener el contenido visible mientras se actualiza y guardar hasta cuatro feeds en memoria durante la sesión.
3. Evitar que una continuación de otro chip se agregue al feed actual; conservar el contenido en errores y esperar la carga real en `refreshable`.
4. Añadir intervalos `HomeFeedFetch`, `HomeFeedCategorize` y `HomeFeedContinuation` para separar espera del Core y procesamiento Swift en Instruments.
5. Cubrir con cuatro pruebas locales respuestas fuera de orden, cierre de sesión con solicitud pendiente, reutilización de caché y fallo de un chip nuevo. Pasan con `swift test -c debug --filter home`.
6. Sustituir Quick Picks por un `NSCollectionView` horizontal de tres filas, con celdas reutilizables, imágenes cancelables y un único menú nativo creado al solicitarlo. Las celdas visibles conservan reproducción, navegación a artista/álbum y etiquetas de accesibilidad. En una prueba de interfaz se verificaron el menú contextual, el desplazamiento horizontal, la navegación al artista y la reproducción/pausa.

## Medición tras cambiar Quick Picks

- La primera traza con el componente nuevo mostró el layout SwiftUI del `LazyVStack` del feed en 17,39 ms, frente a 53,81 ms de la traza anterior. El intervalo de 42,99 ms del `LazyHStack` de Quick Picks desapareció. El hitch de aparición del feed bajó de 175 a 150 ms.
- Una segunda traza con el componente nuevo mostró 16,15 ms para ese layout y un hitch de 133,33 ms alrededor de la llegada del feed. Sus datos y latencia de red fueron distintos; estas cifras orientan el siguiente perfilado, pero aún no representan una comparación controlada ni prueban fluidez sostenida.
- En Time Profiler todavía aparecen creación inicial de `NSCollectionView`, layout de la ventana y del `ScrollView` padre. Conviene medirlos por separado antes de seguir cambiando el estante.

## Siguiente trabajo, en orden

### 1. Medición reproducible

Registrar tres veces cada escenario en el mismo equipo y tamaño de ventana: apertura sin caché de imágenes, apertura con imágenes en disco, cambio de chip, regreso desde álbum y scroll vertical/horizontal rápido con reproducción activa. Usar SwiftUI, Time Profiler, Hitches y los intervalos nuevos. Guardar tiempo hasta primer contenido, duración de Core, layout, número y duración de hitches y memoria. La comparación debe repetir el mismo escenario y datos.

### 2. Fluidez del feed

Quick Picks ya usa `NSCollectionView`. Completar una comparación controlada con el mismo feed, tamaño de ventana y caché; comprobar activación por teclado y VoiceOver en una sesión manual. Después, aislar la observación del reproductor por estante y medir por separado la creación de la colección, el resto del `ScrollView` y las regiones arrastrables de la ventana. `NSTableView` de álbumes y playlists sirve para filas homogéneas; Inicio necesita un diseño distinto.

### 3. Primer contenido

La consulta del Core tarda entre 0,71 y 1,65 s en las dos trazas. Revisar la latencia en `get_home_page` y considerar una copia persistente del último feed por cuenta, con invalidación en logout y actualización en segundo plano. El contenido guardado debe mostrarse claramente como anterior hasta que llegue la respuesta actual; no reutilizar tokens de paginación de otra sesión.

### 4. Imágenes y compatibilidad

Medir descargas y decodificación simultáneas: `ImageCache` acota el prefetch, pero las solicitudes normales de celdas visibles no tienen un límite global. Si aparecen ráfagas, introducir prioridad visible y concurrencia acotada sin bloquear la UI. Reconstruir el Core para macOS 15 y probar en macOS 15, 26 y 27 antes de afirmar compatibilidad de lanzamiento.

## Criterio para cerrar el problema

Las pruebas funcionales deben seguir pasando. En los escenarios registrados, el primer contenido de una apertura con caché debe aparecer de forma inmediata para el usuario y las interacciones de Inicio no deben mostrar hitches repetidos perceptibles. El objetivo exacto de tiempo y frames se fija con las mediciones iniciales; no se declara 120 FPS solo por compilar o por usar `LazyVStack`.
