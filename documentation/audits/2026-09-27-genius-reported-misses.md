# Corpus inicial: canciones que Genius no identificó al primer intento

Fecha: 2026-09-27. Reportadas por el usuario. Este corpus es una lista de regresión, no una medición de cobertura general. Los IDs de Genius proceden de consultas puntuales a `/api/search/song` y, cuando se indica álbum, de `/api/songs/{id}`. Durante la última comprobación el proveedor respondió HTTP 403, por lo que la verificación de extremo a extremo sigue pendiente.

| Pista reportada | Metadatos observados en Side B | Candidato de Genius observado | Decisión segura | Causa o trabajo pendiente |
| --- | --- | --- | --- | --- |
| Les — Childish Gambino | Título visto previamente como `Les`; ID de video no registrado | `L.E.S.` (`57158`) | Automática si no aparece otra ficha equivalente | La puntuación separaba `L.E.S.` en tres letras y no equivalía a `Les`. |
| luther — Kendrick Lamar | `luther` / `Kendrick Lamar & SZA` / `GNX`; video `XVveECQmiAk` | `luther` (`11146175`), crédito completo `Kendrick Lamar & SZA` | Automática | El buscador guardaba solo el artista principal de Genius y la primera consulta con ambos artistas devolvía traducciones. La consulta de respaldo debe usar Kendrick Lamar. |
| OFF — BULLY DELUXE | Álbum referido por el usuario; falta capturar título/artista/ID exactos de Side B | No apareció una ficha `OFF` de Kanye West en las variantes consultadas | Sin atribución automática; búsqueda manual | Salieron pistas distintas como `Off The Grid` y `Lift Off`. La ausencia en esas consultas no prueba que Genius no tenga la canción. |
| SISTERS AND BROTHERS — Kanye West | `SISTERS AND BROTHERS` / `Kanye West & Ye` / `BULLY - DELUXE`; video `47ARDMcGhXQ` | `SISTERS AND BROTHERS` (`13302050`); también `Listening Party Version` | Automática para el título base; comprobar edición del álbum con el usuario | Side B repite dos alias del mismo artista. Genius etiqueta la ficha base con `BULLY`, mientras Side B dice `BULLY - DELUXE`; no se comprobó si la grabación difiere. |
| HIGHS AND LOWS — Kanye West | Falta capturar metadatos exactos de Side B | `HIGHS AND LOWS` (`11307322`); además `HIGHS AND LOWS 2` y otra versión | Automática solo para título base y créditos compatibles | No confundir secuela, referencia ni versión V1 con la pista base. |
| I CAN'T WAIT — Kanye West | Falta capturar metadatos exactos y álbum de Side B | `I CAN’T WAIT` (`12883010`, `BULLY`) y `I CAN’T WAIT` (`13356920`, `BULLY - DELUXE`, con Lauryn Hill) | Ambigua; elección manual hasta verificar álbum/versión | Dos fichas comparten título y artista principal. El álbum podría desambiguar, pero requiere cotejar datos del proveedor y la pista reproducida. |
| CIRCLES — Kanye West | Falta capturar metadatos exactos de Side B | `CIRCLES` (`11513838`); también versión V1 | Automática solo para título base y créditos compatibles | Preservar diferencia entre versión publicada y V1. |
| BEAUTY AND THE BEAST — Kanye West | Falta capturar metadatos exactos de Side B | `BEAUTY AND THE BEAST` (`10932236`); también versión V15 | Automática solo para título base y créditos compatibles | Preservar diferencia entre versión publicada y V15. |

## Ajustes implementados

- El resultado de búsqueda usa `artist_names` de Genius, con respaldo en `primary_artist.name`; no necesita otra solicitud HTTP.
- El artista principal de la consulta de respaldo se separa en `&` y se reconoce explícitamente el crédito redundante `Kanye West & Ye`.
- Las iniciales punteadas equivalen al título compacto solo cuando son 2 a 5 letras individuales. Para títulos de tres caracteres o menos se exige equivalencia exacta antes de elegir automáticamente o presentar candidatos de la búsqueda automática.
- Dos fichas con título equivalente y el mismo artista principal quedan ambiguas aunque sus colaboraciones difieran. Esto conserva la elección manual para `I CAN’T WAIT`.
- La búsqueda deduplica IDs y puntúa hasta 30 resultados de las secciones antes de devolver los 10 mejores. La clave de caché de coincidencias incorpora versión de reglas para reevaluar resultados anteriores; las elecciones manuales se mantienen.

## Validación restante

1. Repetir estas ocho reproducciones en la app con el proveedor accesible y anotar estado, ID elegido y número de solicitudes. Confirmar los metadatos exactos de las seis pistas sin ID de video registrado.
2. Para `SISTERS AND BROTHERS` e `I CAN'T WAIT`, comparar la edición reproducida con las fichas de Genius antes de ampliar la selección por álbum.
3. Incorporar los casos al corpus etiquetado de al menos 100 pistas del plan de aceptación y comprobar cero atribuciones automáticas incorrectas antes de habilitar por defecto cualquier regla nueva.

## Reportes desde la app

La pantalla de coincidencia ambigua o sin resultado ofrece «Guardar esta pista para revisar». Cada pulsación crea o actualiza una fila en `genius_miss_reports` dentro de la base local `~/Library/Application Support/SideB/sideb.db`. La fila contiene título, artistas, álbum, duración, estado (`ambiguous`/`not_found`), IDs de hasta diez candidatos y número de reportes. El identificador de reproducción se guarda solo como hash; no se guardan rutas locales, cookies ni letras.

Para analizar la lista después:

```sql
SELECT title, artists, album, status, candidate_ids, report_count, last_reported_at
FROM genius_miss_reports
ORDER BY last_reported_at DESC;
```
