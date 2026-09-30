# 🔬 Auditoría Forense de Rendimiento — Side B Home Feed & Detail Views

> **Fecha**: 2026-09-24  
> **Alcance**: `HomeView.swift`, `ArtistDetailView.swift`, `AlbumDetailView.swift`, `PlaylistDetailView.swift`, `AppContextMenuFactory.swift`, `NativeTrackTableView.swift`, `ImageCache.swift`.  
> **Objetivo**: Diagnosticar la causa de la regresión de fluidez y caídas de frames (de 120 FPS a ~45 FPS) producida tras la reorganización del inicio, páginas de detalle y menú contextual.

---

## 📌 1. Diagnóstico Ejecutivo

Las vistas de detalle (`PlaylistDetailView`, `AlbumDetailView`, `HistoryView`) se mantienen en **estado óptimo** gracias a la arquitectura nativa `NativeTrackTableView` (AppKit `NSTableView`) con reciclaje constante de ~15 celdas en memoria, cabeceras fijas a 180pt y hover desacoplado.

**La regresión crítica se concentra en `HomeView.swift`**, donde se reintrodujeron dos antipatrones severos que habían sido erradicados en `FIX-013` y `FIX-016`:
1. **`.drawingGroup()` reintroducido en tarjetas de carrusel** (líneas 374 y 498): cada tarjeta genera un framebuffer Metal offscreen independiente, saturando el ancho de banda GPU/CPU en scroll horizontal y vertical.
2. **`VStack` plano envolvente e interior dentro de `ScrollView`** (líneas 29 y 37): se destruyó la pereza de renderizado, forzando a SwiftUI a calcular la geometría e instanciar en memoria todos los bloques y carruseles simultáneamente al abrir Inicio.
3. **Re-renderizado en cascada a 10Hz en `quickPickSongCell`**: al acceder a `playerViewModel.isPlaying` y `currentTrack` dentro de una función en el cuerpo de `HomeView`, el ticker del scrubber (10Hz) invalida el bloque de elecciones rápidas completo.
4. **IDs potencialmente inestables en `quickPicksSection`**: el uso de `id: \.id` sobre `HomeItemRecord` puede provocar colisiones si la API devuelve temas repetidos, quebrando el diffing de SwiftUI.

---

## 🔍 2. Hallazgos Detallados por Componente

### 2.1. `HomeView.swift`

#### 🔴 Hallazgo 1 (Crítico): `.drawingGroup()` reintroducido
- **Ubicación**: Líneas 374 (`mixCardView`) y 498 (`standardCardView`).
- **Impacto**: Cada tarjeta de carrusel (156x156 y 140x140) aplica `.drawingGroup()`. En un feed con 5 carruseles de 10-15 tarjetas, se asignan decenas de framebuffers Metal offscreen. Durante el desplazamiento, el compositor de macOS entra en contención de memoria gráfica.
- **Acción**: Erradicar `.drawingGroup()` permitiendo composición nativa directa en el pipeline de ventanas de macOS.

#### 🔴 Hallazgo 2 (Crítico): Estructura `ScrollView` no perezosa
- **Ubicación**: Líneas 29-70.
- **Impacto**:
  ```swift
  VStack(alignment: .leading, spacing: 0) {       // VStack intermedio
      if !chips.isEmpty { chipsBarView }
      ScrollView {
          VStack(alignment: .leading, spacing: 32) {  // VStack plano interno
              // Todos los bloques se calculan de inmediato
          }
      }
  }
  ```
  Esto viola la directiva de `FIX-016`. El `VStack` plano destruye la virtualización, forzando a SwiftUI a instanciar 10-15 bloques con sus respectivos `LazyHStack` y vistas hijo antes de mostrar el primer fotograma.
- **Acción**: Desempaquetar el `VStack` intermedio y utilizar `LazyVStack(alignment: .leading, spacing: 32)` como hijo directo e inmediato del `ScrollView`.

#### 🟡 Hallazgo 3 (Moderado): Inconformidad `Equatable` en celdas de Quick Picks
- **Ubicación**: Líneas 208-296 (`quickPickSongCell`).
- **Impacto**: `quickPickSongCell` es una función `(HomeItemRecord) -> some View` declarada dentro de `HomeView`. Cuando `playerViewModel.currentTime` se actualiza cada 100ms (10Hz), SwiftUI reevalúa la vista y todas las celdas invocadas.
- **Acción**: Extraer la celda como `struct QuickPickSongCell: View, Equatable` con implementación personalizada de `==` que solo compare `item.id`, `isCurrentTrack` e `isPlaying`.

#### 🟡 Hallazgo 4 (Moderado): Claves de ForEach duplicables en Quick Picks
- **Ubicación**: Línea 190 (`ForEach(columns[colIndex], id: \.id)`).
- **Impacto**: Si YouTube Music entrega una canción repetida en los estantes rápidos, `id: \.id` colisiona, provocando hitches de 100-200ms en el motor de diffing de SwiftUI.
- **Acción**: Utilizar indexación estable mediante enumeración (`Array(columns[colIndex].enumerated()), id: \.offset`).

---

### 2.2. `ArtistDetailView.swift`

- **Estado**: Mayormente saludable. Emplea `LazyHStack` para discografía y carruseles.
- **Oportunidad de optimización**: En la línea 480 (`artistCardItem`), las miniaturas se cargan con `CachedAsyncImage` pero no usan `ImageURLHelper.optimizedThumbnailURL(from:targetPixelSize:)`, consumiendo miniaturas de 544px en lugar de la versión optimizada de 280px para tarjetas de 140x140.

---

### 2.3. `AlbumDetailView.swift` y `PlaylistDetailView.swift`

- **Estado**: **100% Óptimo**.
- Ambos componentes conservan `NativeTrackTableView` (AppKit), cabeceras bloqueadas a 180pt, reciclaje de celdas en RAM (~15 celdas activas) y hovering desacoplado de `@State`. No presentan regresión.

---

### 2.4. `AppContextMenuFactory.swift`

- **Estado**: Seguro respecto al hilo principal (no bloquea el scroll).
- Las acciones pesadas se despachan a `Task { }` asíncronas. El único detalle detectado es que el submenú de añadir a playlist se puebla de forma asíncrona tras la apertura.

---

## 📊 3. Matriz Comparativa contra `SCROLLING_PERFORMANCE_REPORT.md`

| Directriz de Rendimiento | Estado en Código Actual | Diagnóstico |
|---|---|---|
| Cero `.drawingGroup()` en elementos repetitivos | ❌ Violado en `HomeView:374,498` | **Regresión directa introducida** |
| `ScrollView` con `LazyVStack` como hijo directo | ❌ Violado en `HomeView:37` (`VStack` plano) | **Regresión directa introducida** |
| Aislamiento de re-renders con `Equatable` | ⚠️ Ausente en celdas Quick Picks | Causa sobrecarga a 10Hz en reproducción |
| Listas con `NativeTrackTableView` (AppKit) | ✅ Cumplido en Playlists, Álbumes y Fullscreen | Sin regresión en detalle |
| Downsampling de imágenes CDN a 96-280px | ⚠️ Parcial: falta en cards de artista | Desperdicio de RAM/ancho de banda |
| Hover por fuente única de verdad sin `@State` | ✅ Cumplido en tablas nativas | Sin layout thrashing |

---

## 🛠️ 4. Conclusión Técnica

La regresión se produjo por la reescritura visual de `HomeView` (al integrar los bloques de mix y carruseles estándar) sin arrastrar las restricciones de Metal y layout lazy ya conquistadas en `FIX-013` y `FIX-016`. La solución requiere un plan dedicado de re-estabilización enfocado en el feed de inicio.
