# Informe de Arquitectura de Rendimiento: Scroll a 120 FPS en Side B

> **Fecha**: 17 de Septiembre, 2026  
> **Área**: UI / Shell (Swift & AppKit)  
> **Objetivo**: Eliminar definitivamente los tirones (micro-stutters), acumulación de memoria y caídas de frames en listas masivas (Tus Me Gusta, Playlists, Álbumes, Cola e Historial) en pantallas ProMotion a 120Hz de macOS.

---

## 1. Diagnóstico Forense: Por qué fallaba SwiftUI puro (`ScrollView + LazyVStack`)

En las versiones previas, la interfaz utilizaba `ScrollView` y `LazyVStack` nativos de SwiftUI junto con filas compuestas (`TrackRowView` / `CachedAsyncImage`). Aunque en papel `LazyVStack` se denomina "lazy" (perezoso), en macOS adolece de tres limitaciones estructurales insalvables para listas largas:

1. **Inexistencia de Reciclaje Físico de Celdas (*Cell Reuse*)**:
   - En SwiftUI, `LazyVStack` retarda la instanciación de un elemento hasta que aparece en el viewport. Sin embargo, **cuando el elemento sale de pantalla por arriba o por abajo, la vista NO se destruye ni se recicla en una cola de memoria constante**.
   - En una lista como *Tus Me Gusta* (100 a 2.000 canciones), conforme el usuario hace scroll inercial rápido, SwiftUI sigue instanciando miles de structs de vista, nodos de jerarquía y layers de CoreAnimation, disparando el consumo de memoria y saturando el recolector de basura de la runtime de SwiftUI.

2. **Tormenta de Mutaciones `@State` en el Hilo Principal**:
   - Cada celda gestionaba su propia carga de imagen asíncrona mediante `@State private var image: NSImage?` y `@State private var isLoaded: Bool`.
   - Durante un scroll rápido a 120 FPS, decenas de imágenes terminaban de descargarse o descodificarse simultáneamente en milisegundos distintos, mutando variables `@State`.
   - Cada cambio de `@State` obligaba a SwiftUI a reevaluar el `body` de las vistas en el hilo principal y disparar transiciones de CoreAnimation (`.animation(.easeIn)`). Esto congelaba el frame rate de 120 FPS a 30-40 FPS (*frame drops* perceptibles como tartamudeo).

3. **Cálculo Dinámico de Alturas en el Layout Pass**:
   - Si los elementos dentro del scroll carecen de dimensiones fijas e inmutables a nivel de sistema operativo, el motor de layout debe re-medir las vistas en cada frame de desplazamiento, provocando oscilaciones visuales (*layout thrashing*).

---

## 2. La Solución Estructural: El Paradigma AppKit `NSTableView` (Estilo Apple Music y Limusic)

Para lograr la misma respuesta ultra-fluida de Apple Music nativo y Limusic, trasladamos el renderizado de listas largas a `NSTableView` de AppKit a través del puente `NativeTrackTableView: NSViewRepresentable`.

### Pilares Técnicos de la Implementación:

```
┌─────────────────────────────────────────────────────────────┐
│                      SwiftUI Layout                         │
│  - Cabecera fija compacta (Artwork 180x180 + Metadatos)     │
│  - Divider()                                                │
└──────────────────────────────┬──────────────────────────────┘
                               │
┌──────────────────────────────▼──────────────────────────────┐
│        NativeTrackTableView (NSViewRepresentable)           │
│                                                             │
│  ┌───────────────────────────────────────────────────────┐  │
│  │ NSScrollView (autoresizingMask = [.width, .height])   │  │
│  │                                                       │  │
│  │  ┌─────────────────────────────────────────────────┐  │  │
│  │  │ NativeTrackTableViewInternal (NSTableView)       │  │  │
│  │  │  • Altura de fila fija: 52.0 pt                 │  │  │
│  │  │  • Pool de celdas activas: ~15 en RAM           │  │  │
│  │  │  • makeView(withIdentifier:owner:) (Reciclaje)  │  │  │
│  │  │  • Fuente única de Hover (hoveredRowIndex)      │  │  │
│  │  └─────────────────────────────────────────────────┘  │  │
│  └───────────────────────────────────────────────────────┘  │
└─────────────────────────────────────────────────────────────┘
```

1. **Reciclaje Estricto de Memoria (*Cell Recycling*)**:
   - `NSTableView` mantiene en memoria exclusivamente las filas visibles en pantalla más un pequeño margen superior e inferior (~15 a 18 instancias de `NativeTrackCellView`).
   - Cuando una canción sale por arriba, esa misma vista física se reasigna a la nueva canción que entra por abajo (`prepareForReuse` limpia el estado y `configure` asigna los nuevos textos). La memoria de interfaz se mantiene **plana e invariable**, ya haya 50 o 50.000 canciones.

2. **Carga Asíncrona Desacoplada del Árbol de SwiftUI**:
   - Las carátulas de 40x40 pt se inyectan directamente en el `NSImageView` nativo (`artworkImageView.image = loaded`) fuera del ciclo de vida de SwiftUI.
   - Si la imagen ya está en la memoria RAM del `ImageCache`, la asignación es sincrónica inmediata (0 ms).
   - Si requiere descarga en red o lectura de disco, corre en un `Task(priority: .utility)` y se cancela instantáneamente al reciclarse la celda (`imageFetchTask?.cancel()`).

3. **Renderizado Directo en GPU**:
   - `NativeTrackRowView` delega el resaltado de fondo (hover y pista activa) directamente a `drawBackground(in:)` usando primitivas de CoreGraphics sobre capas respaldadas por Metal (`wantsLayer = true`), sin sub-vistas decorativas innecesarias.

---

## 3. Resolución de Bugs Visuales Reportados

### Bug A: Espacio vacío gigante en la cabecera
- **Causa**: En `PlaylistDetailView` y `AlbumDetailView`, el bloque de metadatos (`VStack`) utilizaba un `Spacer(minLength: 16)` sin restricción de altura máxima. Al insertarse en un contenedor con espacio vertical disponible, el `Spacer` se expandía greedymente, alejando los botones de *Reproducir* y *Aleatorio* hacia el centro de la pantalla y empujando la tabla hacia abajo.
- **Solución**: Se delimitó rígidamente la altura del `VStack` de metadatos a `.frame(height: 180, alignment: .leading)`, igualando exactamente los 180 pt del artwork contiguo. El `Spacer(minLength: 8)` ahora solo expande hasta la línea base de la carátula, logrando una estética compacta idéntica a Apple Music macOS.

### Bug B: Múltiples filas marcadas con hover persistente al scrollear
- **Causa**: Cada fila (`NativeTrackRowView`) gestionaba un `NSTrackingArea` individual. Durante el scroll inercial continuo con el trackpad, las filas pasaban bajo el cursor disparando `mouseEntered`, pero AppKit no enviaba `mouseExited` a las vistas desplazadas si el ratón permanecía quieto. Al ser recicladas por `NSTableView`, las celdas conservaban `isHovered = true`, pintando decenas de filas de gris.
- **Solución**: Arquitectura de **Fuente Única de Verdad**:
  1. Se eliminaron todos los `NSTrackingArea` individuales de las filas.
  2. Se implementó una subclase `NativeTrackTableViewInternal: NSTableView` con un único `NSTrackingArea` global para toda la tabla.
  3. Se controla una variable central `hoveredRowIndex: Int`.
  4. Se escucha `NSView.boundsDidChangeNotification` en el `NSClipView` del scroll: cada vez que el usuario hace scroll, se reevalúa `row(at: mouseLocation)`, actualizando el hover de forma reactiva instantánea.
  5. En todo momento, **exactamente una fila** (o ninguna) puede estar en estado hover.

---

## 4. Cobertura en toda la Aplicación

Esta arquitectura de alto rendimiento se extendió a todos los menús y vistas scrolleables de Side B:

| Vista | Archivo | Implementación |
| :--- | :--- | :--- |
| **Tus Me Gusta / Playlists** | `PlaylistDetailView.swift` | `NativeTrackTableView` con paginación predictiva (`onNearBottom`) e insets de 120pt para la PlayerBar. |
| **Álbumes** | `AlbumDetailView.swift` | `NativeTrackTableView` con cabecera bloqueada a 180pt y selección instantánea de pista. |
| **Cola de Reproducción** | `FullscreenNowPlayingView.swift` | `NativeTrackTableView` en `queuePanel` con insets reducidos (24pt) y sincronización con `queueManager`. |
| **Historial** | `HistoryView.swift` | `NativeTrackTableView` aplanando las reproducciones recientes de InnerTube sin lags en `TrackRowView`. |
| **Búsqueda en Inicio** | `HomeView.swift` | Transición a `NativeTrackTableView` al haber resultados de búsqueda activos, manteniendo el buscador fijo. |

---

## 5. Directrices para Futuros Componentes

Para mantener el estándar de 120 FPS en cualquier futura vista que involucre más de 20 elementos:

1. **Nunca** utilizar `ScrollView { LazyVStack { ... } }` para colecciones de pistas o elementos repetitivos con imágenes.
2. **Siempre** utilizar `NativeTrackTableView` o adaptar una especialización de `NSTableView` con `makeView(withIdentifier:owner:)`.
3. **Respetar el sistema de insets**: Toda tabla que conviva con la barra flotante de reproducción debe especificar `contentInsets = NSEdgeInsets(top: 0, left: 0, bottom: 120, right: 0)`.
4. **Desacoplar imágenes del `@State` de SwiftUI**: Nunca almacenar imágenes descargadas en `@State` dentro de celdas repetitivas; inyectarlas sincrónicamente desde caché o mediante handlers asíncronos directamente a la vista de renderizado.
