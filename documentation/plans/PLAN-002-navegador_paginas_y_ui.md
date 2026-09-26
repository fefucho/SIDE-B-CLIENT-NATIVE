# 📋 PLAN-002: Shell de 4 Capas, Sidebar y Feed de Inicio Dinámico

- **Alcance**: Epic 2 de 5
- **Estado**: `[Completado]`
- **Dominios**: Shell (Swift 6 & SwiftUI) + Core (Rust & UniFFI)

---

## 🎯 1. Objetivo y Alcance
Construir el esqueleto estructural y la experiencia base de navegación de la aplicación para macOS:
1. El sistema de 4 capas definido en `UI_ARCHITECTURE.md`.
2. La barra lateral (*Sidebar*) nativa colapsable con perfil de usuario y acceso a la biblioteca.
3. El router de navegación web (*Back / Forward*) con atajos de teclado (`⌘[` y `⌘]`).
4. El feed de Inicio 100% dinámico de YouTube Music con barra de chips de ánimo (*Relax*, *Energize*, etc.), grilla de 3 filas para canciones rápidas (*Listen again* / *Quick picks*), carruseles destacados para mixes y continuaciones infinitas.
5. El rediseño de la Player Bar Liquid Glass estilo Apple Music macOS 26.

*(Nota: La Cola se gestiona en PLAN-003, las Vistas de Detalle/Búsqueda en PLAN-004 y el Modo Fullscreen en PLAN-005).*

---

## 📋 2. Checklist de Tareas Ejecutadas

### 🦀 A. Core en Rust & UniFFI (`sideb-core`)
- [x] Records tipados: `HomeChipRecord`, `HomePageRecord`, `HomeSectionRecord`, `HomeItemRecord`, `AccountInfoRecord`.
- [x] Endpoints tipados: `get_home_page(chip_params:)`, `get_home_continuation(token:)`, `get_account_info()`.
- [x] Resiliencia de sesión: limpieza automática de cookie expirada con fallback anónimo inmediato ante errores 401/SessionExpired.
- [x] Empaquetado en `SideBCore.xcframework` vía `build_xcframework.sh`.

### 🧭 B. Shell, Sidebar y Navegador de Páginas (Capa 0 y Capa 1)
- [x] `NavigationRouter.swift`: Pila de historial web-like (`history`, `currentIndex`, `canGoBack`, `canGoForward`).
- [x] `FloatingNavigationCapsule.swift`: Cápsula Liquid Glass flotante en Capa 1 con botones Atrás (`◀`), Adelante (`▶`), refresco y reapertura de Sidebar.
- [x] `SidebarView.swift`: Ancho nativo de 220px, colapso fluido a 0px con animación spring, sección Inicio, switcher de biblioteca y perfil de usuario (`SidebarProfileView`).
- [x] Persistencia de credenciales con Apple Keychain (`CookieStorage.swift`) y ventana de autenticación Google (`LoginSheet.swift`).
- [x] `HomeView.swift`: Feed modular clasificado por `HomeFeedBlock` con barra de chips de estado de ánimo, carruseles horizontales, grillas de 3 filas y scroll infinito por centinela.

### 🏝️ C. Player Bar Apple Music macOS 26 (Capa 3)
- [x] Rediseño de `PlayerBarView.swift` con controles de transporte a la izquierda (`Shuffle`, `Prev`, `Play/Pause`, `Next`, `Repeat`).
- [x] Sub-cápsula de vidrio derecha dedicada exclusivamente al Slider de Volumen + Altavoz.
- [x] Barra superior sutil `topScrubberBar` con arrastre y seek milimétrico.
- [x] Centrado geométrico obligatorio respecto al Área de Contenido (sin incluir la Sidebar).

---

## 🧪 3. Criterio de Finalización
- [x] Navegación histórica operativa con `⌘[` y `⌘]`.
- [x] Carga de sesión de usuario y modo invitado sin pantallas de error.
- [x] Home Feed 100% dinámico con chips y continuaciones sin bloqueo de UI.
- [x] Barra flotante de Liquid Glass centrada milimétricamente en el área de contenido.
- [x] Hito consolidado en `FIXES_LOG.md` (FIX-009, FIX-010, FIX-011, FIX-019, FIX-020) y `PROJECT_STATE.md`.
