# PLAN-012 — Información de Genius en Side B v2

## Alcance implementado

- El Core de Rust resuelve candidatos de `/api/search/song`, distingue coincidencia, ambigüedad, ausencia y errores de transporte, y conserva los marcadores de versión al puntuar. Una elección manual se liga a `videoId` y a una huella de título, artistas, álbum y duración.
- Detalle, créditos, referents y letras se obtienen por métodos UniFFI independientes. Las letras se extraen del DOM HTML sin ejecutar JavaScript; el documento se limita a 2 MB y no se guarda completo.
- SQLite guarda coincidencias, elecciones y contenido estructurado con TTL de 30 días para coincidencia/detalle/anotaciones, 7 días para letras y 24 horas para ausencias. Las elecciones manuales no caducan. La caché se limita por uso reciente y 100 MB.
- Swift muestra caché disponible al comenzar la pista. La consulta en segundo plano se lanza un segundo después de invocar `play` cuando el usuario activa «Buscar automáticamente al reproducir»; abrir Genius la adelanta siempre. La opción queda desactivada por defecto hasta pasar las puertas de precisión y rendimiento. Las publicaciones se protegen con la identidad de reproducción. El panel funcional muestra letras sin tiempos, historia, créditos, anotaciones, candidatos, búsqueda y actualización; las letras sincronizadas siguen en su modo separado.
- Las solicitudes comparten el cliente HTTP del Core, se serializan y se espacian al menos 250 ms. Se reintentan una vez los fallos temporales, se respeta `Retry-After`, y un 403 abre un corte temporal de cinco minutos para evitar solicitudes repetidas. Las métricas de sesión solo contienen contadores agregados y latencia hasta cabeceras.

## Verificación realizada

- `cargo test -p sideb-core`: 71 pruebas pasan, 7 pruebas externas ignoradas por defecto. Las pruebas locales de Genius cubren versiones, empate de candidatos, tildes, limpieza de metadatos, huella, detalle/créditos, paginación con filas malformadas, DOM de letras, repetición con caché sin red y expulsión al superar 500 canciones.
- `swift test --package-path apple`: 61 pruebas existentes pasan.
- Build Release del XCFramework y compilación Swift completados; la app actualizada se abrió y verificó tras los cambios del Core y de Swift.
- Las respuestas del proveedor variaron durante la sesión: una prueba recibió HTTP 403 y las pruebas posteriores del Core recibieron respuestas 200. La prueba completa de una canción obtuvo historia, créditos, 7 anotaciones, 64 líneas y 11 líneas enlazadas a anotaciones. Una segunda lectura de resolución, anotaciones y letras hizo cero solicitudes adicionales. Una matriz en vivo de ocho casos atribuyó seis pistas comunes y dejó dos versiones específicas como ambiguas. Esto es diagnóstico puntual, no una medición de cobertura general.
- La validación en la app detectó una cabecera de página dentro del contenedor de letras de una canción. Se ajustó el recorrido DOM para omitir `data-exclude-from-selection="true"`; el fixture y una prueba con HTML real confirman que la primera línea extraída es el encabezado de la estrofa.
- Con la búsqueda automática activada y el panel Genius abierto, la transición de «Pink + White» a «gloria» resolvió la segunda pista y cargó letras sin actualización manual. El siguiente salto a «L.E.S.» mostró candidatos ambiguos. Se corrigió la referencia a la tarea cancelada que impedía iniciar la consulta de la pista nueva.

## Puertas de aceptación pendientes antes de distribución

- Etiquetar y ejecutar un corpus de al menos 100 pistas reales, incluidos fallos conocidos de Side B old. Exigir cero atribuciones automáticas incorrectas y medir cobertura automática y recuperación manual por separado. Las seis pruebas actuales son fixtures de lógica, no sustituyen ese corpus.
- Repetir la prueba con el proveedor accesible y fixtures de 429/403/5xx, paginación real, HTML variante, saltos rápidos y fallo de letras con historia disponible.
- Comparar en el mismo Mac y recorrido las builds Release con y sin carga automática. Umbral: incremento p95 del inicio de audio menor de 30 ms y sin pausas de UI mayores de 50 ms atribuibles al parseo. Si no se cumple, dejar solo caché al reproducir y hacer red al abrir Genius.
- Revisar permiso de uso de los endpoints y del contenido de Genius antes de distribuir. La API oficial requiere autorización y los términos de Genius restringen la extracción automatizada sin permiso.

La implementación es una integración funcional en desarrollo. La disponibilidad del proveedor, el corpus de precisión, la medición de rendimiento y el permiso de distribución siguen siendo condiciones explícitas de lanzamiento.
