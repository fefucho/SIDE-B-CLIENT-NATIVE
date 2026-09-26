# 🔬 Archivo Histórico de Auditorías y Reportes Forenses

> **Nota de Gobernanza**: Los documentos contenidos en esta carpeta son **registros históricos de diagnósticos y pruebas de estrés** realizados en fechas puntuales del ciclo de desarrollo. Sirven como evidencia forense de la causa raíz de problemas pasados y de las decisiones técnicas adoptadas.
> Para conocer el código y los contratos vigentes, consultar el código en `apple/` y `core/`, así como [`UI_ARCHITECTURE.md`](../../UI_ARCHITECTURE.md) y [`FIXES_LOG.md`](../../FIXES_LOG.md).

---

## 📑 Registro Cronológico de Auditorías

| Fecha | Documento | Alcance y Objetivo | Planes y Fixes Resultantes |
|---|---|---|---|
| **2026-09-17** | [`2026-09-17-scrolling-performance.md`](2026-09-17-scrolling-performance.md) | Arquitectura de scroll ProMotion a 120Hz; introducción de `NativeTrackTableView` (AppKit) para listas masivas y pipeline de renderizado de miniaturas. | Base de diseño de PLAN-001 y PLAN-002. |
| **2026-09-18** | [`2026-09-18-ui-refinement-borders.md`](2026-09-18-ui-refinement-borders.md) | Refinamiento de estética Liquid Glass, esquinas concéntricas, radio de curvatura y paddings uniformes. | Refinamiento de PlayerBarView y Sidebar. |
| **2026-09-24** | [`2026-09-24-auditoria-integral-26-puntos.md`](2026-09-24-auditoria-integral-26-puntos.md) | Mega-auditoría integral del sistema tras la consolidación de `SIDE B/`. Identificó 26 problemas clave (A01 a A26) en seguridad, sesión, cola, búsqueda, catálogo y rendimiento. | Dio origen a [`PLAN-MASTER-correcciones-auditoria.md`](../../plans/PLAN-MASTER-correcciones-auditoria.md) y a las correcciones FIX-047/FIX-048. |
| **2026-09-24** | [`2026-09-24-ui-audit-report.md`](2026-09-24-ui-audit-report.md) | Auditoría exhaustiva sobre 38 archivos Swift; diagnóstico de 19 problemas de UI (paths SQLite temporales, overlays invisibles que bloqueaban clics, tokens de sistema). | Resuelto progresivamente a través de FIX-040 hasta FIX-056. |
| **2026-09-24** | [`2026-09-24-performance-home-feed.md`](2026-09-24-performance-home-feed.md) | Diagnóstico forense de regresión de FPS (de 120 FPS a ~45 FPS) provocada por la instanciación de menús contextuales en celdas de listas. | Dio origen a [`PLAN-006`](../../plans/PLAN-006-optimizacion_rendimiento_home_feed.md) y [`PLAN-008`](../../plans/PLAN-008-fix-acciones-menus-contextuales.md). |
| **2026-09-26** | [`2026-09-26-home-youtube-reference-report.md`](2026-09-26-home-youtube-reference-report.md) | Referencias visuales de YouTube Music y especificación de dos diseños para Inicio, con prioridades de carga y criterios de aceptación. | Informe para una implementación posterior. |
| **2026-09-26** | [`2026-09-26-home-fast-scroll.md`](2026-09-26-home-fast-scroll.md) | Traza de Instruments y revisión del scroll rápido de Inicio en la arquitectura actual de `NSCollectionView`, con separación de interferencia por accesibilidad. | Orden de medición y optimización propuesto; sin cambios de código. |
