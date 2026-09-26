# PLAN-008: Corrección y Ejecución de Acciones en Menús Contextuales

- **Fecha**: 2026-09-25
- **Estado**: Completado y Verificado
- **Dependencias**: PLAN-007 (Menús contextuales por entidad y contexto)
- **Alcance**: `AppKitMenuAdapter.swift`, `AppContextMenuFactory.swift`, `MenuActionExecutor.swift`, `SwiftUIMenuAdapter.swift`

---

## 1. Diagnóstico del Problema

Tras completar la arquitectura de decisión y modelos de PLAN-007, los botones y opciones de los menús contextuales (clic secundario) y botones de opciones («…») no ejecutan ninguna acción al hacer clic sobre ellos.

### Causas Raíz Identificadas:

1. **Bug Crítico de Referencia Débil (`[weak executor]`) en `AppKitMenuAdapter.swift`**:
   - En `AppKitMenuAdapter.swift` (líneas 71-77 y 86-88), los closures de acción de cada `ActionMenuItem` capturan `[weak executor]`:
     ```swift
     let menuItem = ActionMenuItem(title: item.title, systemImageName: item.systemImage) { [weak executor] in
         executor?.execute(action: item.id, target: target, facts: facts)
     }
     ```
   - En `AppContextMenuFactory.swift`, las funciones constructoras (`buildSongNSMenu`, `buildAlbumNSMenu`, `buildPlaylistNSMenu`, `buildArtistNSMenu`) crean `let executor = MenuActionExecutor(...)` como variable local en el stack y retornan el `NSMenu`.
   - **Efecto**: `executor` se desasigna de memoria (`deinit`) inmediatamente al retornar la función constructora. Cuando el usuario hace clic en el menú que está en pantalla, `executor` ya es `nil`, por lo que **`executor?.execute(...)` no hace nada en ninguna tabla o vista AppKit (`NativeTrackTableView`, `HomeFeedCollectionView`)**.

2. **Validación de Menús y Responder Chain en AppKit**:
   - `NSMenuItemActionTarget` en `AppContextMenuFactory.swift` no conforma al protocolo `NSMenuItemValidation`.
   - En macOS, si el target de un menú no implementa `validateMenuItem:`, o si los submenús dinámicos no configuran `submenu.autoenablesItems = false`, AppKit puede omitir o cancelar el envío de la acción.

3. **Falta de Normalización de IDs Canónicos en `MenuActionExecutor.swift`**:
   - Al ejecutar acciones sobre playlists (como reproducir, encolar o reproducir siguiente), el ID puede llegar con prefijo de navegación web `VL...` (ej. `VLPL...` o `VLLM`).
   - Al invocar directamente `core.getPlaylist(playlistId: id)` sin despojar el prefijo `VL`, la llamada de Rust UniFFI falla y el `try?` la silencia, quedando sin efecto.

4. **Comportamiento de Reproducción de Canción Suelta**:
   - En `MenuActionExecutor.swift`, la acción `.play` invoca `player.playSongNow(song)`. Si la cola de reproducción está vacía (como al abrir la aplicación), `playSongNow` resuelve el stream pero no genera cola continua, a diferencia de `player.playWithRadio(song)`.

---

## 2. Tareas de Implementación

### Tarea 1: Corregir Retención y Submenús en `AppKitMenuAdapter.swift`
**Ruta**: `SIDE B/apple/Sources/SideB/UI/ContextMenu/AppKitMenuAdapter.swift`

1. En `makeMenuItem`:
   - Configurar `submenu.autoenablesItems = false` en el submenú de subitems.
   - Eliminar `[weak executor]` y capturar fuertemente `executor` tanto en los subitems como en el ítem principal:
     ```swift
     let menuItem = ActionMenuItem(title: item.title, systemImageName: item.systemImage) {
         executor.execute(action: item.id, target: target, facts: facts)
     }
     ```
   - Esto es seguro y libre de ciclos de retención porque `MenuActionExecutor` solo almacena referencias `weak` a `PlayerViewModel` y `NavigationRouter`.

### Tarea 2: Implementar `NSMenuItemValidation` en `AppContextMenuFactory.swift`
**Ruta**: `SIDE B/apple/Sources/SideB/UI/AppContextMenuFactory.swift`

1. Modificar `NSMenuItemActionTarget` (alrededor de la línea 264):
   - Conformar al protocolo `NSMenuItemValidation`.
   - Asegurar la firma de acción `@objc func onAction(_ sender: Any?)`.
   - Implementar `validateMenuItem`:
     ```swift
     final class NSMenuItemActionTarget: NSObject, NSMenuItemValidation {
         let action: () -> Void

         init(action: @escaping () -> Void) {
             self.action = action
             super.init()
         }

         @objc func onAction(_ sender: Any?) {
             action()
         }

         func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
             return menuItem.isEnabled
         }
     }
     ```

### Tarea 3: Normalización de IDs y Trazas en `MenuActionExecutor.swift`
**Ruta**: `SIDE B/apple/Sources/SideB/UI/ContextMenu/MenuActionExecutor.swift`

1. En el método `execute(action:target:facts:)`:
   - Añadir print de depuración al inicio para verificar trazabilidad en consola:
     ```swift
     print("[MenuActionExecutor] Ejecutando acción: \(action) sobre \(target)")
     ```
2. En `executePlay`, `executeShuffle`, `executeStartMix`, `executePlayNext`, `executeAddToQueue`:
   - Para `.playlist(let id, ...)`: sanitizar el ID con `MenuIDNormalizer.canonicalPlaylistId(id)` antes de invocar `core.getPlaylist(playlistId: targetId)`.
3. En `executePlay(target:)`:
   - Para `.song(let song)`: si la cola está vacía (`player.queueManager.tracks.isEmpty`), llamar a `player.playWithRadio(song)` para iniciar la canción y cargar la radio continua automáticamente. Si ya hay una cola en curso, llamar a `player.playSongNow(song)`.

### Tarea 4: Asegurar Captura de Closures en `SwiftUIMenuAdapter.swift`
**Ruta**: `SIDE B/apple/Sources/SideB/UI/ContextMenu/SwiftUIMenuAdapter.swift`

1. En `MenuItemRowView`:
   - Garantizar que el closure del `Button` capture `executor`, `target` y `facts` de forma directa sin ambigüedad en SwiftUI para macOS.

---

## 3. Plan de Verificación

### Paso 1: Pruebas Unitarias
Ejecutar la suite de tests de contexto:
```bash
swift test --package-path "SIDE B/apple" --filter ContextMenuPolicyTests
```
Verificar que los 12 tests pasen al 100%.

### Paso 2: Compilación Release
Compilar el paquete en modo release:
```bash
swift build -c release --package-path "SIDE B/apple"
```

### Paso 3: Empaquetar y Ejecutar
Lanzar la app empaquetada:
```bash
sh "SIDE B/Scripts/compile_and_run.sh"
```

### Paso 4: Pruebas Manuales Obligatorias
1. Clic derecho en una pista en Inicio / Búsqueda $\rightarrow$ seleccionar «Reproducir ahora» $\rightarrow$ verificar que el audio comience a sonar de inmediato.
2. Clic derecho en una pista $\rightarrow$ «Me gusta» $\rightarrow$ verificar que el icono de corazón se actualice.
3. Clic derecho en una pista $\rightarrow$ «Compartir» $\rightarrow$ verificar que se copie la URL al portapapeles y se abra el selector de compartir nativo de macOS.
4. Clic derecho en una pista dentro de un álbum $\rightarrow$ «Ir al artista» $\rightarrow$ verificar navegación inmediata a la vista del artista.
5. Botón «…» en la PlayerBar inferior $\rightarrow$ seleccionar «Iniciar mix» $\rightarrow$ verificar que cargue la radio en la cola.
