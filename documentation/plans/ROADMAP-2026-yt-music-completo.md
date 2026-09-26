# Side B: plan para completar la experiencia de YouTube Music en macOS

- Fecha: 2026-09-25
- Estado: propuesto; este documento no implica que las funciones estén implementadas.
- Alcance: biblioteca, playlists, subidas, video musical, descubrimiento, restauración de sesión y extensiones de producto.

## Objetivo y límites

Ofrecer los flujos musicales principales de YouTube Music en una app nativa para macOS, conservando el shell SwiftUI/AppKit, AVPlayer para la reproducción y Rust para InnerTube, persistencia y contratos UniFFI. La versión mínima sigue siendo macOS 15. Inicio, búsqueda, radio, cola, letras, historial, favoritos, AirPlay y controles multimedia existentes deben seguir funcionando.

El trabajo se entrega por etapas verticales: endpoint/parseo en Rust, record y error UniFFI, estado Swift, interfaz y verificación del recorrido real. Ningún botón aparece antes de tener acción operativa. Los cambios de YouTube y la disponibilidad de formatos son riesgos externos; cada etapa tiene una condición de salida verificable, no una promesa de ausencia absoluta de fallos.

## Estado inicial comprobado en el código

| Área | Ya existe | Falta para el flujo completo |
| --- | --- | --- |
| Playlists | Lectura, continuación, guardar, añadir y quitar pistas en `SideBCore`; crear, editar, ordenar por criterio y borrar en `innertube/endpoints.rs` | Exponer operaciones de escritura restantes por UniFFI; UI de creación/edición/borrado; reordenamiento manual persistente; permisos y refresco coherente |
| Biblioteca | Playlists, álbumes e historial en `LibraryViewModel`; InnerTube puede leer artistas y álbumes subidos | Página `.library` efectiva, canciones guardadas, artistas, subidas, clasificación y paginación donde aplique |
| Metadatos de pista | `innertube::SongItem` conserva `is_upload`, `is_video` y estado de biblioteca | `SongItemRecord` pierde esos campos; Swift llama `resolveStream(... isUpload: false)` |
| Video | `orchestrator.resolve_video` interno | Contrato UniFFI, pareja canción/video, formato comprobado para AVPlayer y vista de video |
| Continuidad | Cola y posición en memoria; `settings` SQLite en Rust | Persistencia y restauración de la sesión de reproducción en el shell activo |
| Explorar | Inicio con chips y búsqueda filtrada | Ruta y feed específico de descubrimiento |

Los planes antiguos y `FIXES_LOG.md` sirven como historia. Los nombres y capacidades de arriba se comprobaron contra el código actual.

## Etapa 0: contratos y cimientos compartidos

1. Definir una identidad estable de cuenta y una generación de sesión para todas las peticiones y cachés nuevas. Al cambiar de cuenta o cerrar sesión, cancelar tareas pendientes y descartar resultados de la sesión anterior.
2. Ampliar los records UniFFI sin volver a parsear JSON en Swift: `SongItemRecord` con `isUpload`, `isVideo` y estado/acción de biblioteca cuando el origen lo provea; `PlaylistDetailRecord` con privacidad, permiso de edición, estado colaborativo y orden disponible. Mantener una conversión única desde los modelos InnerTube.
3. Distinguir `Me gusta` de `Guardar en Biblioteca`: InnerTube ya distingue el feedback de biblioteca de la calificación. Exponer un comando tipado para guardar o quitar canciones, con actualización después de confirmación y manejo de token vencido.
4. Definir estados comunes de interfaz: cargando, vacío, sesión requerida, no disponible y error recuperable. No interpretar una lista vacía como éxito cuando la petición falló.
5. Para cada modificación UniFFI: actualizar Rust, generar XCFramework, compilar el consumidor Swift y comprobar que el símbolo se usa desde la app. No dar por válida una build que reutilice un binario viejo.

**Salida:** los nuevos campos llegan a Swift desde una pista real; el cambio de cuenta no cruza resultados ni estado entre usuarios; la app sigue compilando para macOS 15+.

## Etapa 1: playlists editables

**Rust.** Envolver `create_playlist`, `playlist_edit_details`, `delete_playlist` y `playlist_set_sort` ya presentes en InnerTube. Añadir la operación de *mover una pista* en el servidor: investigarla y validarla con la identidad de fila `setVideoId` antes de prometer arrastrar y soltar. Exponer errores diferenciables de sesión vencida, permiso insuficiente, rechazo y red. No habilitar edición basándose solo en que la playlist esté guardada; usar la capacidad que devuelve el servidor.

**Swift.** Añadir «Nueva playlist» en Biblioteca y en el menú «Añadir a playlist»; formulario de nombre, descripción y privacidad; menú de editar/eliminar solo para listas propias; confirmación al borrar; ordenamiento donde el servidor lo permita; arrastrar filas para orden manual cuando el endpoint funcione. Tras una escritura confirmada, refrescar detalle, sidebar y caché de playlists; preservar canción/cola activa. Si falla, mostrar el error y restaurar la vista previa.

**Casos de salida:** crear una lista privada, agregar y quitar canciones, renombrar, cambiar privacidad, mover una canción y verla en el mismo orden al reabrir, y borrar con confirmación. Una playlist ajena o colaborativa no muestra acciones que el usuario no puede ejecutar. Una lista larga conserva paginación y evita confundir pistas repetidas con el mismo `videoId`.

## Etapa 2: Biblioteca como página principal de colección

**Rust.** Reutilizar los endpoints existentes de playlists, álbumes y artistas. Incorporar canciones guardadas y separación de subidas mediante respuestas reales de la cuenta; guardar fixtures de las variantes de respuesta antes de fijar browse IDs o filtros. Devolver páginas tipadas con continuación, orden y errores por sección. La caché se identifica por cuenta.

**Swift.** Implementar `LibraryView` para la ruta `.library`, hoy declarada pero no representada en el switch principal. Usar pestañas Canciones, Playlists, Álbumes y Artistas; Subidas tendrá filtro propio tras la etapa 3. La sidebar puede seguir mostrando accesos rápidos, pero la colección completa vive en la página. Conectar guardar/quitar canción, búsqueda dentro de la biblioteca si el volumen lo requiere, orden y estados vacíos. Reutilizar la tabla nativa para listas de pistas.

**Casos de salida:** una canción guardada aparece en Canciones sin exigir `Me gusta`; un álbum guardado y un artista aparecen en sus categorías; al quitar elementos se actualizan detalle y Biblioteca; atrás/adelante vuelve a la pestaña correcta; una sección fallida no borra otras secciones ya cargadas.

## Etapa 3: música subida por el usuario

**3A — reproducir y organizar.** Llevar `is_upload` desde InnerTube hasta `SongItemRecord` y pasar ese valor a `resolveStream`. Exponer álbumes subidos, añadir lectura de canciones subidas y su búsqueda, y mostrar el filtro Subidas dentro de Biblioteca. Conservar la ruta de resolución autenticada ya implementada en el orquestador. No guardar cookies ni URLs temporales en la cola persistida; al restaurar, resolver nuevamente. Gestionar sesión vencida y URL rechazada con un error claro.

**3B — subir archivos desde la Mac.** Investigar y validar el protocolo real de subida de música antes de dibujar el control. La subida de portadas de playlists ya implementada usa otro flujo y no prueba que la de canciones funcione. Si se confirma el protocolo, agregar selector/drag and drop nativo para formatos admitidos, progreso, cancelación, límite de concurrencia, resultados parciales, actualización de Biblioteca y deduplicación informada por el servidor. Si no se confirma, dejar 3B bloqueada como capacidad explícita; no simular una subida local que nunca llega a YouTube Music.

**Casos de salida:** una pista propia se reproduce completa, en cola y tras reabrir; una sesión ajena no ve ni reproduce la subida; si 3B se habilita, un archivo aceptado aparece luego en la biblioteca remota y los fallos quedan identificados por archivo.

## Etapa 4: modo canción/video

1. Encontrar la pareja real entre versión de audio y video para cada pista; una marca `isVideo` sola no identifica la otra versión. El contrato tipado debe expresar disponibilidad y IDs de ambas versiones. Si no hay pareja, ocultar el selector.
2. Adaptar `resolve_video` a macOS. Hoy el selector interno prioriza VP9 sin audio; comprobar los formatos reales con AVFoundation y elegir un formato que `AVPlayer` reproduzca en macOS 15–27, con una alternativa cuando no exista. No usar WKWebView para reproducción.
3. Mostrar el video con `AVPlayerView` dentro de `FullscreenNowPlayingView`. Mantener un único origen audible: el `AudioPlayerService` actual; el video va silenciado y sigue play/pause, seek, avance y cambios de pista. Sincronizar con un reloj maestro y corregir desvíos perceptibles; al cerrar el panel, liberar la carga de video sin interrumpir el audio.
4. Al cambiar canción/video, conservar cola, posición, favoritos e historial. Si el video falla o no es reproducible, volver a la carátula y mantener el audio.

**Casos de salida:** cambio durante reproducción y pausa sin audio doble; seek y cambio de canción coherentes; pantalla completa, ventana redimensionada y AirPlay no interrumpen la música; fallback limpio cuando no hay video o formato compatible.

## Etapa 5: Explorar y retomar la escucha

**Explorar.** Añadir `.explore` al router y una pantalla alimentada por secciones reales de lanzamientos, géneros y listas. Parsear enlaces y continuaciones como destinos tipados; evitar tarjetas estáticas. Conectar desde la sidebar sin alterar Inicio ni la búsqueda. La selección regional sale de la respuesta/sesión, no de una lista fija inventada.

**Restauración.** Persistir en SQLite, por cuenta y con versión de esquema, IDs y metadatos de cola, índice, contexto, shuffle/repeat, pista y posición. Guardar al cambiar pista/cola y con escritura acotada al actualizar posición; no persistir stream URLs, cookies ni tokens temporales. Al abrir, restaurar **pausado**; validar límites e IDs, resolver el stream solo cuando el usuario reanude y descartar snapshots corruptos o de otra cuenta. No hacer que un resultado viejo reemplace una cola recién creada.

**Casos de salida:** cerrar/reabrir conserva la cola y la posición sin autoplay inesperado; logout y cambio de cuenta aíslan snapshots; un stream vencido se resuelve otra vez; Explorar navega a álbum, artista o playlist reales y respeta atrás/adelante.

## Etapa 6: amplitud de producto

### 6A. Podcasts

Introducir records tipados de programa y episodio, con duración, fecha, identidad y progreso propio. Añadir lectura de biblioteca y detalle de programa en Rust, más búsqueda y navegación en Swift. La cola puede compartir el motor de audio, pero el avance, la posición guardada y los controles de episodio necesitan reglas explícitas distintas de una canción. Empezar por podcasts del catálogo; RSS necesita importación, errores del feed y distinción visible porque YouTube limita algunas acciones en episodios RSS. **Salida:** seguir un programa, reproducir episodios en orden y retomar uno a mitad sin afectar favoritos musicales.

### 6B. Ajustes

Crear preferencias tipadas y persistidas para calidad de audio y autoplay. Hoy `resolve_stream` fija `AudioQuality::High`; el ajuste debe llegar al orquestador, aplicarse a la siguiente resolución y mostrar el valor efectivo. Añadir después preferencias de contenido o filtros solo si se puede comprobar su efecto real. Separar preferencias por cuenta de las globales de interfaz. **Salida:** cambiar calidad modifica la selección de stream cuando hay varias opciones, persiste al reiniciar y no interrumpe la pista activa.

### 6C. Google Cast

Hacer primero una prueba de viabilidad técnica del SDK/protocolo disponible para macOS y del modo de autenticar/controlar el receptor. Si es viable, definir una sesión remota tipada con dispositivo, estado, cola, volumen, errores y reconexión; después ofrecer selector de dispositivo y traspaso desde reproducción local. Mantener AirPlay existente. **Salida:** iniciar, pausar, cambiar pista y desconectar desde Side B sin dos reproducciones simultáneas ni estados de cola divergentes. Si la integración no es viable, no mostrar un botón Cast inerte.

### 6D. Escucha sin conexión

Evaluar al final la viabilidad de derechos, acceso, caducidad y protección del contenido. YouTube documenta esta capacidad principalmente para apps móviles. Si existe una vía válida para esta app, diseñar descargas verificables por cuenta, control de espacio, renovación y borrado al cerrar sesión. La caché temporal de URLs nunca debe presentarse como descarga offline. **Salida:** solo declarar la función disponible cuando una pista autorizada pueda reproducirse sin red tras reiniciar y deje de estar disponible cuando corresponda.

## Orden de ejecución y condiciones generales de entrega

`0 → 1 → 2 → 3A → 4 → 5`; después `3B` y las extensiones de la etapa 6 según viabilidad. La página Biblioteca precede a la carga de archivos, pero las subidas existentes deben poder escucharse antes de ofrecer el botón de subir.

Para cada etapa:

1. Confirmar la forma de las respuestas con fixtures pequeños y una cuenta de prueba apropiada. Los endpoints privados pueden cambiar.
2. Hacer un corte vertical completo Rust → UniFFI → Swift → interfaz. Si falta una capa, no presentar el control.
3. Verificar solo los escenarios que protegen ese cambio: éxito, sesión vencida, error de red, cuenta distinta y permisos cuando aplique. Una compilación de Rust/XCFramework/Swift es obligatoria al cambiar el contrato. No usar tests de rendimiento ni afirmar fluidez sin medición reproducible.
4. Revisar la app abierta en macOS 27 y la compatibilidad de API con macOS 15; probar ventana estrecha, sidebar visible/oculta, teclado y VoiceOver en controles nuevos. Preservar la jerarquía de cuatro capas y los controles de ventana nativos.
5. No avanzar una función de escritura remota hasta que el estado local se actualice después de confirmación o pueda revertirse con seguridad; el usuario siempre debe ver el error y poder reintentar.

## Referencias de producto

- [Biblioteca y categorías de YouTube Music](https://support.google.com/youtubemusic/answer/6313542?hl=en)
- [Crear, editar y ordenar playlists en ordenador](https://support.google.com/youtubemusic/answer/7205933?hl=en-GB)
- [Subir música personal desde ordenador](https://support.google.com/youtubemusic/answer/9716522?hl=en)
- [Explorar música y podcasts](https://support.google.com/youtubemusic/answer/13401025?hl=es)
- [Podcasts mediante RSS](https://support.google.com/youtubemusic/answer/13946190?hl=en)
- [AVPlayerView en macOS](https://developer.apple.com/documentation/avkit/avplayerview)
- [Dispositivos compatibles y alcance de la escucha sin conexión](https://support.google.com/youtubemusic/answer/6308244?hl=en)
