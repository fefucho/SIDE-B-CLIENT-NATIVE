# PLAN-009: Inicio con tarjetas grandes y canciones compactas

- **Fecha:** 2026-09-26
- **Estado:** Implementado; pendiente de prueba manual y medición de rendimiento
- **Referencia visual y funcional:** [informe y siete capturas de YouTube Music](../audits/2026-09-26-home-youtube-reference-report.md)
- **Alcance:** Inicio en «Todos» y presentación de los feeds filtrados por chips. Mantener reproducción, navegación y menús existentes.

## Resultado esperado

Cada sección que envíe YouTube se muestra en uno de **dos diseños**: portada grande o fila compacta de canción. La elección pertenece a la sección; el tipo, texto, enlaces y acción pertenecen a cada ítem. Las secciones prioritarias recibidas se muestran en Inicio aunque lleguen en una continuación, sin retrasar la primera pantalla.

La regla de disponibilidad es explícita: YouTube puede omitir una sección. Side B no la inventa ni deja un encabezado vacío. «Hip-hop» es un ejemplo de género personalizado, no un nombre fijo.

## Límites de esta implementación

- Conservar `NSCollectionView` y el `HomeViewModel` actuales; no rediseñar otras páginas, sidebar, player, cola ni buscador en este plan.
- Mantener macOS 15 como mínimo y las acciones de menús existentes. No introducir reproducción web ni parseo JSON en las vistas.
- No clasificar tipos ni enlazar artistas por texto de título/subtítulo. Si falta un ID de destino fiable, mostrar texto sin enlace.
- `mix`/`radio` requieren una señal verificable del Core. Mientras no exista, presentar el elemento como playlist y conservar su acción real.
- Los cambios de contrato UniFFI incluyen el XCFramework, binding Swift, caché y compilación de ambos lados en la misma etapa.

## Paquetes de trabajo secuenciales

Cada paquete tiene un resultado comprobable y puede encargarse a Luna por separado. No iniciar el siguiente hasta validar el anterior. El agente debe leer `.agents/AGENTS.md`, las reglas aplicables y el informe de referencia antes de editar.

### 1. Datos del feed y contrato tipado

**Archivos principales:** `core/crates/innertube/src/models/browse.rs`, `core/crates/sideb-core/src/lib.rs`, `apple/Sources/SideB/Services/HomeFeedCacheStore.swift`, binding generado en `apple/SideBCore/`.

- [x] Derivar en `parse_home` una pista tipada por renderer de sección.
- [x] Pasar formato, indicador explícito y enlaces estructurados de artista al contrato Home. `play_count` no se muestra; los álbumes de canción reciben ID solo cuando el renderer trae un `MPRE…` navegable.
- [x] Preservar los campos nuevos en `HomeCachedPage`, subir a versión 2 y rechazar de forma segura la caché anterior.
- [x] Regenerar binding y XCFramework; compilar Rust y Swift contra el contrato nuevo.
- [x] Añadir fixture Rust mixto con canción de tarjeta, canción de fila, álbum y playlist; verificar formato, tipos y enlaces.

**Salida:** Swift recibe datos suficientes para dibujar ambas formas sin adivinar el tipo por un título.

### 2. Decisión de formato y orden

**Archivo principal:** `apple/Sources/SideB/Models/HomeFeedPresentation.swift`.

- [x] Reducir `HomeSectionStyle` a `largeCard` y `compactSong`.
- [x] Decidir con renderer y tipos; mezclas e incertidumbre usan tarjetas grandes.
- [x] Aplicar excepciones localizadas para Listen again, Forgotten favorites y Quick picks, compacta solo si todos los ítems son canciones.
- [x] Priorizar categorías reconocidas en «Todos», conservando el orden original cuando no hay señal fiable de género; los chips mantienen el orden de YouTube.
- [x] Usar destino y límites de contenido para identidad estable ante traducciones y continuaciones.
- [x] Probar orden, secciones prioritarias, identidad traducida y continuación.

**Salida:** una función de presentación determinista, separada de la vista, que asigna exactamente uno de los dos formatos a toda sección.

### 3. Tarjeta grande

**Archivo principal:** `apple/Sources/SideB/Views/Home/HomeFeedCollectionView.swift`.

- [x] Portada cuadrada, título de hasta dos líneas y metadata persistente; Álbum/Sencillo/EP solo con etiqueta recibida.
- [x] Artista enlazado únicamente con ID estructurado; las acciones siguen el tipo del ítem.
- [x] Mantener menú y reproducción; añadir etiquetas accesibles y foco visible por teclado.
- [ ] Comparar con las capturas 1–5 a ancho normal y mínimo de ventana, sin copiar píxeles ni depender de un solo tamaño de pantalla.

**Salida:** Listen again, Forgotten favorites, Albums for you, From your library y un género mixto se entienden sin hover.

### 4. Canción compacta y cabecera

**Archivo principal:** `apple/Sources/SideB/Views/Home/HomeFeedCollectionView.swift`.

- [x] Miniatura, título y enlaces independientes de artista/álbum solo con sus IDs.
- [x] Cuatro filas por columna, adaptables al ancho y sin marco en reposo.
- [x] Reproducción y menú activos; hover, selección por teclado y etiquetas accesibles disponibles. No se muestra valoración porque no hay una acción real conectada.
- [x] Flechas horizontales y «Ver todo» solo para destinos navegables; `FE…` no se trata como playlist.
- [ ] Comparar con las capturas 6–7, incluidos reposo y hover/foco.

**Salida:** Quick picks y secciones de canciones en filas tienen el diseño compacto y enlaces correctos.

### 5. Carga de secciones prioritarias

**Archivos principales:** `apple/Sources/SideB/ViewModels/HomeViewModel.swift` y, si hace falta, la capa Core de continuaciones.

- [x] Publicar la primera página antes de la precarga. Presupuesto: hasta 3 continuaciones y 12 s acumulados; intervalo instrumentado como `HomePriorityPrefetch`.
- [x] Deduplicar por destino y límites de contenido; conservar el siguiente token válido.
- [x] Invalidar por cambio de sesión, chip o refresh; guardar por identidad de cuenta y precargar solo «Todos».
- [x] Probar sección encontrada después, token repetido, fallo de red y cambio de chip con respuesta pendiente.
- [ ] Añadir pruebas de sección ausente, token vacío, refresh y cambio de cuenta durante precarga.

**Salida:** las secciones prioritarias que YouTube entregue dentro del presupuesto aparecen automáticamente en Inicio; las ausentes no bloquean ni producen huecos.

## Puerta de integración y validación

- [x] Ejecutar pruebas dirigidas Rust y Swift; compilar Core, regenerar XCFramework y compilar/abrir Side B en Release con el contrato nuevo.
- [ ] Verificar manualmente una canción, un álbum y una playlist desde estantes mixtos; enlaces de artista/álbum, menú, hover, foco y VoiceOver. Comprobar ventana mínima, macOS 15 y 26/27 cuando estén disponibles.
- [ ] Medir tiempo hasta primera sección, número de peticiones de continuación, hitches de scroll y memoria en un escenario Release reproducible. No atribuir 120 FPS a la compilación.
- [x] Revisar el diff: cambios de producto limitados a Inicio/Core, más el script de binding y los registros del plan.

**Nota sobre pruebas existentes (fuera del alcance de PLAN-009):** compilar y abrir la app con `Scripts/compile_and_run.sh` no ejecuta tests. Para este plan bastan pruebas dirigidas de Inicio y la comprobación manual indicada arriba. La suite completa (`swift test --package-path apple`) incluye un diagnóstico en vivo, `testLiveAccountAndLibraryWithKeychainCookie`, que puede reescribir la cookie de la sesión en Keychain. Conocer ese efecto antes de elegir ejecutar toda la suite; corregir o aislar esa prueba es una tarea independiente y **no bloquea** este rediseño.

## Instrucción breve para iniciar cada paquete con Luna

> Implementá **solo el paquete N** de `documentation/plans/PLAN-009-inicio-dos-formatos.md`. Leé primero `.agents/AGENTS.md`, sus reglas y el informe visual enlazado. Respetá los límites del plan y el código vigente. Terminá con los tests dirigidos de ese paquete, la compilación necesaria y un resumen de archivos cambiados, evidencia y pendientes. No marques otros paquetes como completos ni conviertas problemas ajenos a Inicio en tareas de este paquete.

El paquete 1 necesita especial revisión de integración porque cruza Rust, UniFFI, caché y Swift. Los paquetes 2–4 son trabajos de UI más acotados. El paquete 5 afecta carga y estado de sesión; revisarlo junto con sus pruebas de carreras antes de dar por terminada la función.
