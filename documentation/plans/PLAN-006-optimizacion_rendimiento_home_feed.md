# 📋 PLAN-006: Estabilización y Optimización de Rendimiento 120 FPS (Home Feed)

- **Fecha de inicio**: 2026-09-24
- **Alcance**: Optimización de Rendimiento / Re-estabilización ProMotion 120Hz
- **Estado**: `[Completado]`
- **Dominios**: Shell / UI en Swift (`HomeView.swift`, `ArtistDetailView.swift`, `NativeTrackTableView.swift`)

---

## 🎯 1. Objetivo y Alcance

Erradicar la regresión de rendimiento identificada en la auditoría forense ([`2026-09-24-performance-home-feed.md`](../docs/audits/2026-09-24-performance-home-feed.md)), restaurando el scroll del **Feed de Inicio** a **120 FPS ProMotion continuos** sin micro-tirones ni degradación térmica:

1. **Eliminar framebuffers Metal offscreen**: suprimir los `.drawingGroup()` residuales en tarjetas de mix y carruseles estándar.
2. **Restaurar la virtualización vertical**: asegurar que `LazyVStack` sea el hijo inmediato y directo de `ScrollView`, descartando `VStack` envolventes no perezosos.
3. **Aislar re-renders a 10Hz**: encapsular las celdas de canciones rápidas en una estructura `QuickPickSongCell: View, Equatable` para evitar que el ticker de reproducción re-evalúe el feed.
4. **Blindar identificadores de diffing**: prevenir colisiones de claves en `ForEach` ante canciones repetidas de la API.
5. **Completar downsampling de imágenes**: aplicar `ImageURLHelper.optimizedThumbnailURL` en tarjetas de discografía de artista.

---

## 🏗️ 2. Arquitectura de Rendimiento (Cumplimiento de [`2026-09-17-scrolling-performance.md`](../docs/audits/2026-09-17-scrolling-performance.md))

```
┌────────────────────────────────────────────────────────────────────────┐
│                   VStack Raíz (Header + Chips de Ánimo)                │
└───────────────────────────────────┬────────────────────────────────────┘
                                    │
                                    ▼
┌────────────────────────────────────────────────────────────────────────┐
│                              ScrollView                                │
│  ┌──────────────────────────────────────────────────────────────────┐  │
│  │     LazyVStack (Hijo directo, cálculo lazy bajo demanda)         │  │
│  │  • Bloque 1: Quick Picks (LazyHStack horizontal + QuickPickSongCell)│  │
│  │  • Bloque 2: Mixed For You (LazyHStack horizontal sin drawingGroup) │  │
│  │  • Bloque N: Carruseles (LazyHStack horizontal sin drawingGroup) │  │
│  │  • Footer: Centinela de paginación infinita                      │  │
│  └──────────────────────────────────────────────────────────────────┘  │
└────────────────────────────────────────────────────────────────────────┘
```

- **Cero `.drawingGroup()`**: el renderizado se delega al compositor nativo de macOS sin forzar asignaciones de memoria gráfica por tarjeta.
- **`Equatable` en celdas activas**: las mutaciones en `PlayerViewModel.currentTime` no atraviesan las celdas cuyo `isCurrentTrack` y `isPlaying` no hayan cambiado.

---

## 📋 3. Checklist de Tareas Vivas

### 🚀 A. Fixes Críticos Inmediatos (`HomeView.swift`)
- [x] **A.1. Erradicar `.drawingGroup()` de `mixCardView()`**:
  - Eliminado el modificador en la línea 374 del ZStack de portada, badge y botón play.
- [x] **A.2. Erradicar `.drawingGroup()` de `standardCardView()`**:
  - Eliminado el modificador en la línea 498 del ZStack de portada y botón play.
- [x] **A.3. Desempaquetar jerarquía y aplicar `LazyVStack` directo**:
  - Eliminado el `VStack` envolvente intermedio de chips y `ScrollView`.
  - Reemplazado el `VStack` plano interno del `ScrollView` por `LazyVStack(alignment: .leading, spacing: 32)`.
  - Mantenido padding inferior de 120pt para convivencia con la PlayerBar flotante.

### 🛡️ B. Aislamiento de Estado y Diffing Estable
- [x] **B.1. Extraer `QuickPickSongCell` como componente `Equatable`**:
  - Creada `struct QuickPickSongCell: View, Equatable` con comparación estricta de `item.id`, `title`, `subtitle`, `isCurrent` e `isPlaying` usando `nonisolated static func ==` y `MainActor.assumeIsolated`.
  - Aplicado modificador `.equatable()` al instanciarla en `quickPicksSection`.
- [x] **B.2. Estabilizar claves de `ForEach` en `quickPicksSection`**:
  - Reemplazado `ForEach(columns[colIndex], id: \.id)` por enumeración segura `ForEach(Array(columns[colIndex].enumerated()), id: \.offset)`.
- [x] **B.3. Robustecer `HomeFeedBlock.id`**:
  - Identificación estable por `baseIndex + index` preservada.

### 🎨 C. Optimización de Memoria Gráfica en Vistas de Detalle
- [x] **C.1. Downsampling CDN en `ArtistDetailView.swift`**:
  - Aplicado `ImageURLHelper.optimizedThumbnailURL(from:thumb, targetPixelSize: isVideo ? 400 : 288)` en `artistCardItem` para tarjetas de álbumes, singles y videos.
- [x] **C.2. Mutex de carga en `PlaylistDetailViewModel`**:
  - Verificado que `loadMore` cuenta con guardia atómica `!isLoadingMore` en `@MainActor`.

---

## 🧪 4. Criterio de Verificación y Aceptación

1. **Fluidez 120Hz ProMotion**: desplazamiento continuo con trackpad en Inicio sin caídas de cuadros por debajo de 115 FPS.
2. **Cero Framebuffers Parásitos**: verificar en Xcode View Hierarchy / Metal System Trace que no se crean texturas offscreen por cada tarjeta.
3. **Carga Progresiva del Feed**: el feed no bloquea la interfaz durante la carga inicial; los carruseles fuera de pantalla no consumen ciclos de cálculo previo.
4. **Reproducción a 10Hz Aislada**: verificar que el avance del scrubber en reproducción activa no gatilla redibujado de las canciones de inicio no reproducidas.
5. **Compilación sin advertencias ni regresiones en contratos UniFFI**.
6. **Registro en `FIXES_LOG.md` y actualización en `PROJECT_STATE.md`**.
