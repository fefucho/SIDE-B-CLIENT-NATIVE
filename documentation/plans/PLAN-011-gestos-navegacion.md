# PLAN-011: Navegación con trackpad y botones laterales del mouse

- **Fecha:** 2026-09-26
- **Estado:** Implementado en código; pendiente validación en hardware real.
- **Alcance:** Entrada nativa macOS en Swift/AppKit. Sin animación de página.

## Objetivo

El gesto horizontal de dos dedos y los botones laterales deben ejecutar las mismas acciones del `NavigationRouter` que la cápsula superior. El scroll horizontal de tarjetas y chips tiene prioridad mientras pueda desplazarse. Al llegar al borde, el desplazamiento adicional puede navegar. El scroll vertical no debe activar navegación.

## Implementación actual

- [x] `WindowNavigationCoordinator` escucha eventos solo de su ventana y se retira con ella. Respeta la preferencia del sistema `NSEvent.isSwipeTrackingFromScrollEventsEnabled`.
- [x] `NavigationSwipeTracker` decide si la secuencia es horizontal o vertical. Los eventos verticales y los eventos de scroll horizontal con espacio disponible siguen llegando al `NSScrollView` nativo.
- [x] En el borde horizontal, acumula el desplazamiento adicional y navega una vez al soltar si alcanza el umbral. Un gesto cancelado o la inercia no navegan. También acepta el primer evento `.changed` si macOS no entregó `.began`.
- [x] Botones laterales 3 y 4 llaman a Atrás y Adelante; el clic central y otros botones siguen su curso. No se bloquean atajos de teclado por tiempo.
- [x] Se ignoran entradas mientras hay una hoja, modal o reproductor fullscreen. No se añadió indicador visual ni animación.
- [x] `swift build` completado el 2026-09-26, sin errores del cambio.

## Validación pendiente en hardware

- [ ] Trackpad: swipe en página con scroll vertical, en estante horizontal a mitad de recorrido y en ambos bordes, en chips y en Artista. Confirmar sentido Atrás/Adelante con scroll natural y tradicional.
- [ ] Trackpad: gesto corto, cancelado, diagonal y con inercia. Confirmar que cada gesto navega como máximo una vez y que el scroll vertical no se interrumpe.
- [ ] Mouse: botones laterales en ambas direcciones y dos ventanas abiertas. Confirmar el mapeo 3/4 del dispositivo real.
- [ ] Cápsula y atajos `⌘[` / `⌘]` siguen funcionando.

La transición interactiva tipo Safari queda para una etapa posterior.
