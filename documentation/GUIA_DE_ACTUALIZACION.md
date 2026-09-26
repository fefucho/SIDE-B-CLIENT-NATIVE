# 🚀 Guía Rápida: Git y Lanzamiento de Actualizaciones en Side B

Esta guía resume en pasos concretos cómo sincronizar tu código y cómo publicar nuevas versiones para que la aplicación de los usuarios se actualice automáticamente.

---

## 📌 Escenario 1: Subir cambios normales de código (Día a día)

Usa estos comandos cuando hagas mejoras, corrijas errores o agregues funciones, pero **aún no quieras lanzar una versión pública**.

Abre tu terminal en la carpeta `SIDE B`:

```bash
cd "/Users/stefano/Documents/PROGRAMACION PADRE/SIDE B RUST BASED PROJECTO/SIDE B"

# 1. Ver qué archivos modificaste
git status

# 2. Agregar todos los cambios
git add .

# 3. Guardar el commit con una breve descripción
git commit -m "feat: describí qué cambiaste aquí"

# 4. Subir a GitHub
git push origin main
```

*(Esto actualiza tu repositorio en GitHub sin disparar descargas para los usuarios).*

---

## 📦 Escenario 2: Lanzar una nueva versión (Para que la app de la gente se actualice)

Sigue estos 3 pasos cada vez que quieras que a todos los usuarios les aparezca el aviso de **"Actualización disponible"** con el botón **"Actualizar ahora"**.

### Paso 1: Subir la versión en `version.env`
Abre el archivo [`version.env`](version.env) y aumenta los números:

```bash
# Ejemplo: pasando de la 1.0.0 a la 1.0.1
MARKETING_VERSION="1.0.1"
BUILD_NUMBER="2"
GITHUB_REPO_OWNER="fefucho"
GITHUB_REPO_NAME="SIDE-B-CLIENT-NATIVE"
```

### Paso 2: Guardar el cambio en Git
```bash
git commit -am "chore: release versión 1.0.1"
git push origin main
```

### Paso 3: Crear y subir el Tag de la versión
El tag es el **disparador automático**. Debe coincidir con la versión precedida por una `v`:

```bash
# Crear el tag
git tag v1.0.1

# Subir el tag a GitHub
git push origin v1.0.1
```

---

## ⚙️ ¿Qué ocurre automáticamente después?

1. **GitHub Actions se activa**:
   - Compila el Core de Rust (`aarch64-apple-darwin`).
   - Genera el binario nativo de Swift/macOS en modo Release.
   - Crea el paquete comprimido `SideB-macOS.zip`.
   - Publica el Release en GitHub con las notas de cambios automáticas.
2. **Los usuarios reciben la actualización**:
   - Al abrir Side B (o al tocar **Side B → Buscar actualizaciones…** en el menú superior), la app detecta la versión `1.0.1`.
   - Se abre la ventana con las notas de la versión.
   - El usuario hace clic en **"Actualizar ahora"**.
   - Side B se descarga en segundo plano con barra de progreso, reemplaza el ejecutable y se reinicia sola.

---

## 🛠️ Comandos de utilidad

- **Ver el progreso de compilación en GitHub**:
  ```bash
  gh run list
  ```
- **Si te equivocaste en un tag y quieres borrarlo**:
  ```bash
  # Borrar tag local y remoto
  git tag -d v1.0.1
  git push origin :refs/tags/v1.0.1
  ```
