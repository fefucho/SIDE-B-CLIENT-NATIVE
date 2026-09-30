#!/bin/bash
set -euo pipefail

# Colores para salida de terminal
BOLD='\033[1m'
GREEN='\033[0;32m'
CYAN='\033[0;36m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

echo ""
echo -e "${BOLD}${CYAN}======================================================${NC}"
echo -e "${BOLD}${CYAN}          🎵 Instalador Oficial de Side B             ${NC}"
echo -e "${BOLD}${CYAN}   Cliente nativo de YouTube Music para macOS         ${NC}"
echo -e "${BOLD}${CYAN}======================================================${NC}"
echo ""

# 1. Verificar sistema operativo
if [[ "$(uname -s)" != "Darwin" ]]; then
    echo -e "${RED}❌ Este instalador es exclusivo para macOS.${NC}"
    exit 1
fi

ARCH="$(uname -m)"
echo -e "🖥️  Arquitectura detectada: ${BOLD}${ARCH}${NC}"

# 2. Configurar repositorio y rutas
REPO="fefucho/SIDE-B-CLIENT-NATIVE"
APP_NAME="Side B.app"
DEST_PATH="/Applications/$APP_NAME"
TEMP_DIR=$(mktemp -d -t sideb_install_XXXXXX)

cleanup() {
    rm -rf "$TEMP_DIR"
}
trap cleanup EXIT

# 3. Obtener URL de descarga del último release
echo -e "🔍 Buscando la última versión en GitHub..."
DOWNLOAD_URL=$(curl -s "https://api.github.com/repos/$REPO/releases/latest" \
    | grep -o '"browser_download_url": *"[^"]*SideB-macOS\.zip"' \
    | head -n 1 \
    | cut -d '"' -f 4 || true)

if [[ -z "$DOWNLOAD_URL" ]]; then
    DOWNLOAD_URL="https://github.com/$REPO/releases/latest/download/SideB-macOS.zip"
fi

echo -e "⬇️  Descargando paquete desde GitHub Releases..."
ZIP_DEST="$TEMP_DIR/SideB-macOS.zip"
if ! curl -fL --progress-bar -o "$ZIP_DEST" "$DOWNLOAD_URL"; then
    echo -e "${RED}❌ Error al descargar el archivo desde $DOWNLOAD_URL${NC}"
    exit 1
fi

# 4. Descomprimir
echo -e "📦 Descomprimiendo paquete..."
EXTRACT_DIR="$TEMP_DIR/extracted"
mkdir -p "$EXTRACT_DIR"
ditto -x -k "$ZIP_DEST" "$EXTRACT_DIR"

FOUND_APP=$(find "$EXTRACT_DIR" -name "*.app" -maxdepth 2 | head -n 1)
if [[ -z "$FOUND_APP" || ! -d "$FOUND_APP" ]]; then
    echo -e "${RED}❌ No se encontró el bundle de la aplicación en el paquete descargado.${NC}"
    exit 1
fi

# 5. Cerrar instancia previa si está abierta
if pgrep -x "Side B" >/dev/null 2>&1 || pgrep -x "SideB" >/dev/null 2>&1; then
    echo -e "${YELLOW}⚠️  Cerrando instancia en ejecución de Side B...${NC}"
    pkill -x "Side B" 2>/dev/null || pkill -x "SideB" 2>/dev/null || true
    sleep 1
fi

# 6. Instalar en /Applications
echo -e "📂 Instalando en ${BOLD}/Applications/$APP_NAME${NC}..."
rm -rf "$DEST_PATH"
cp -R "$FOUND_APP" "$DEST_PATH"

# 7. Quitar atributo de cuarentena de Gatekeeper (¡Solución al bloqueo de macOS!)
echo -e "🛡️  Removiendo atributos de cuarentena de Gatekeeper (xattr)..."
xattr -cr "$DEST_PATH" 2>/dev/null || true

# 8. Refrescar LaunchServices para registrar el icono y nombre
LSREGISTER="/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"
if [[ -x "$LSREGISTER" ]]; then
    "$LSREGISTER" -f "$DEST_PATH" 2>/dev/null || true
fi

echo ""
echo -e "${BOLD}${GREEN}======================================================${NC}"
echo -e "${BOLD}${GREEN}🎉 ¡Side B se instaló correctamente en tu Mac!        ${NC}"
echo -e "${BOLD}${GREEN}======================================================${NC}"
echo -e "📍 Ubicación: ${BOLD}$DEST_PATH${NC}"
echo -e "✨ La aplicación está lista para abrirse sin advertencias de Gatekeeper."
echo ""

# 9. Abrir la aplicación
if [[ -t 0 ]]; then
    read -p "¿Deseas abrir Side B ahora? [S/n]: " -n 1 -r REPLY || REPLY="s"
    echo ""
    if [[ "$REPLY" =~ ^[Nn]$ ]]; then
        echo -e "Puedes abrirla en cualquier momento desde tu carpeta de Aplicaciones o Spotlight."
        exit 0
    fi
fi

echo -e "🚀 Abriendo Side B..."
open "$DEST_PATH"
