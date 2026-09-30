# 📋 PLAN-XXX: [Nombre de la Epic / Funcionalidad]

- **Fecha de inicio**: AAAA-MM-DD
- **Alcance**: Epic X de 5
- **Estado**: `[Propuesto | En Desarrollo | Completado]`

---

## 🎯 1. Objetivo y Alcance
Breve descripción del valor de usuario, flujo general y objetivo técnico.

---

## 🔗 2. Contrato Técnico (Rust ⟷ UniFFI ⟷ Swift)
- **Métodos UniFFI / Core**:
  - `SideBCore.metodo(...)`
- **Modelos de datos (`uniffi::Record`)**:
  - Tipos de datos en Rust exportados como structs nativos (sin strings JSON intermedias).
- **Compatibilidad de Audio / Streaming**:
  - Formato prioritario (AAC itag 140/141 para Apple `AVPlayer`).

---

## 📋 3. Checklist de Tareas Vivas

### 🦀 A. Core en Rust (`sideb-core` / `innertube`)
- [ ] Tarea backend 1
- [ ] Tarea backend 2

### 🎨 B. UI y Shell en Swift (`apple`)
- [ ] Tarea frontend 1
- [ ] Tarea frontend 2

### 🧪 C. Verificación y Calidad
- [ ] Compilación limpia (`cargo check` y `swift build`).
- [ ] Verificación en runtime (sonido real, respuesta a 120Hz, centrado en UI).
- [ ] Registro del hito en `FIXES_LOG.md` y `PROJECT_STATE.md`.
