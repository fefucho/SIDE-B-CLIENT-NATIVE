# 📋 Side B (v2) - Repositorio Oficial de las 5 Grandes Epics

> **Gobernanza Pragmática**: Todo el desarrollo de Side B v2 se organiza exclusivamente en torno a **5 Grandes Epics Estructurales**. Cada plan contiene su propio checklist vivo (`[ ]` / `[x]`) con división estricta de dominios (Core en Rust y Shell en Swift).  
> Se eliminan micro-planes intermediarios y debates ficticios: la ejecución es directa, incremental y verificable mediante compilaciones limpias y pruebas de runtime a 120 FPS.

---

## 📑 Las 5 Grandes Epics del Proyecto

| Epic ID | Documento del Plan | Alcance y Módulos Clave | Estado Actual |
|---|---|---|:---:|
| **PLAN-001** | [`PLAN-001: Motor de Audio y MVP Flotante`](PLAN-001-motor_audio_avplayer.md) | Resolución de streams AAC (itag 140/141), records UniFFI tipados, `AudioPlayerService` nativo (`AVPlayer`), Scrubber y primera barra flotante. | ✅ **Completado** |
| **PLAN-002** | [`PLAN-002: Shell de 4 Capas, Sidebar y Feed de Inicio`](PLAN-002-navegador_paginas_y_ui.md) | Shell de 4 capas, Sidebar colapsable, `NavigationRouter` con historial `⌘[`/`⌘]`, Home dinámico con chips y continuaciones, y Player Bar macOS 26. | ✅ **Completado** |
| **PLAN-003** | [`PLAN-003: Cola de Reproducción, Automix y Radio`](PLAN-003-cola_automix_radio.md) | `QueueManager`, avance automático de pistas, tabla de cola en Fullscreen a 120 FPS, automix continuo infinito y radio por canción. | 🟡 **En Progreso (~75%)** |
| **PLAN-004** | [`PLAN-004: Catálogo y Búsqueda Reactiva`](PLAN-004-catalogo_y_busqueda.md) | Detalle de Playlist y Álbum con `NativeTrackTableView`, paginación de listas largas, biblioteca, página de Artista y Búsqueda global por chips. | 🟡 **En Progreso (~65%)** |
| **PLAN-005** | [`PLAN-005: Modo Fullscreen y Letras Sincronizadas`](PLAN-005-fullscreen_y_letras.md) | Overlay cinematográfico `FullscreenNowPlayingView`, `ArtworkGlow` dinámico, selector de pestañas (Cola/Letras/Recomendados), letras interactivas a 120Hz y fallback LRCLIB. | ✅ **Completado (~90%)** |

---

## 🎯 Criterios de Calidad para Toda Epic
1. **Rendimiento 120 FPS ProMotion**: Listas largas gestionadas siempre mediante `NativeTrackTableView` (AppKit `NSTableView`) con reciclaje de memoria (~15 celdas activas) y miniaturas CDN de 96px.
2. **Audio Nativo Sin WebViews**: Todo el audio se reproduce a través de `AVPlayer` en Swift, consumiendo streams directos AAC (itag 140/141) provistos por Rust.
3. **Cero Código Zombie**: Ningún control, botón o pestaña se renderiza en la interfaz sin un endpoint funcional en Rust y un ViewModel cableado.
4. **Registro de Hitos**: Solo se actualiza `FIXES_LOG.md` y `PROJECT_STATE.md` al culminar tareas estructurales de una Epic o contratos UniFFI.
