# 📋 PLAN-001: Pipeline de Audio Nativo y MVP de Barra Flotante

- **Fecha de inicio**: 2026-09-17
- **Alcance**: Epic 1 de 5
- **Estado**: `[Completado]`

---

## 🎯 Objetivo
Lograr el primer hito vertical de la aplicación: que Rust resuelva streams directos compatibles con macOS (AAC itag 140/141), que UniFFI exponga modelos tipados en memoria, que Swift reproduzca audio nativamente con `AVPlayer` y que una barra flotante de Liquid Glass permita pausar, reanudar y hacer seek de forma real.

---

## 📋 Checklist de Ejecución

### 🦀 1. Core en Rust (`innertube` & `sideb-core`)
- [x] Modificar `codec_score()` en `innertube/src/models/player.rs` y `rustypipe_fallback.rs` para priorizar `mp4a` (AAC) sobre `opus`.
- [x] Exportar `SongItemRecord` con `#[derive(uniffi::Record)]` en `sideb-core/src/lib.rs`.
- [x] Incorporar `search_songs` tipado (`Vec<SongItemRecord>`) en `sideb-core/src/lib.rs`.
- [x] Recompilar XCFramework con `sh build_xcframework.sh`.

### 🎨 2. Motor de Audio en Swift
- [x] Crear `AudioPlayerService.swift` encapsulando `AVPlayer` y observadores de tiempo.
- [x] Crear `PlayerViewModel.swift` conectando `SideBCore.resolveStream` con `AudioPlayerService`.

### 🏝️ 3. Barra Flotante Mínima (Liquid Glass)
- [x] Portar `AppleMusicScrubber.swift` con timestamps y arrastre fluido.
- [x] Crear `PlayerBarView.swift` con controles 100% operativos (Play/Pause, Scrubber de tiempo, Volumen, Track Info).
- [x] Integrar en `SideBApp.swift` con buscador reactivo tipado y disparador para validar con sonido real.

---

## 🧪 Criterio de Finalización
- [x] `swift build` completa con éxito (0.27s).
- [x] App empaquetada y ejecutada en macOS (`SideB.app`).
- [x] Registro de hito en `FIXES_LOG.md` y `PROJECT_STATE.md`.

