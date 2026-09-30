#!/bin/bash
set -e

echo "=========================================="
echo "🚀 Compilando y Ejecutando SideB..."
echo "=========================================="

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR/../apple"

# Cargar configuración de versión y repositorio si existe
if [ -f "$SCRIPT_DIR/../version.env" ]; then
    source "$SCRIPT_DIR/../version.env"
fi
APP_VERSION="${MARKETING_VERSION:-1.0.0}"
APP_BUILD="${BUILD_NUMBER:-1}"
REPO_OWNER="${GITHUB_REPO_OWNER:-fefucho}"
REPO_NAME="${GITHUB_REPO_NAME:-side-b}"

# Nos aseguramos que el core esté generado si es necesario
if [ ! -d "SideBCore.xcframework" ]; then
    echo "⚠️ SideBCore.xcframework no encontrado. Generando..."
    sh build_xcframework.sh
fi

echo "📦 Compilando app con el SDK de Xcode..."
# El build system predeterminado de SwiftPM en Xcode 27 enlaza SideB con
# LC_BUILD_VERSION sdk=15.0 aunque compile contra el SDK 27. El build system
# nativo conserva macOS 15 como mínimo y registra el SDK realmente usado.
swift build --build-system native -c release --product SideB
BIN_DIR=$(swift build --build-system native -c release --show-bin-path)
SWIFT_BIN="$BIN_DIR/SideB"

BUILT_SDK=$(xcrun vtool -show-build "$SWIFT_BIN" | awk '$1 == "sdk" { print $2; exit }')
CURRENT_SDK=$(xcrun --sdk macosx --show-sdk-version)
if [ "$BUILT_SDK" != "$CURRENT_SDK" ]; then
    echo "❌ El ejecutable declara SDK $BUILT_SDK; Xcode usa SDK $CURRENT_SDK." >&2
    exit 1
fi

echo "📦 Creando Side B.app bundle..."
APP_NAME="Side B"
APP_DIR=".build/app/$APP_NAME.app"
MACOS_DIR="$APP_DIR/Contents/MacOS"
RESOURCES_DIR="$APP_DIR/Contents/Resources"
LSREGISTER="/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"

# Rebuild the bundle from scratch so removed resources cannot survive an update.
pkill -x "Side B" 2>/dev/null || pkill -x "SideB" 2>/dev/null || true
sleep 0.5
if [ -d "$APP_DIR" ] && [ -x "$LSREGISTER" ]; then
    "$LSREGISTER" -u "$APP_DIR" 2>/dev/null || true
fi
rm -rf "$APP_DIR"
mkdir -p "$MACOS_DIR" "$RESOURCES_DIR"

echo "📦 Copiando ejecutable Release (SDK $BUILT_SDK)..."
cp "$SWIFT_BIN" "$MACOS_DIR/$APP_NAME"

# Ícono: buscar AppIcon.icns en Resources/ junto al script
ICON_SRC="$SCRIPT_DIR/../apple/Resources/AppIcon.icns"
ICON_KEY=""
if [ -f "$ICON_SRC" ]; then
    cp "$ICON_SRC" "$RESOURCES_DIR/AppIcon.icns"
    ICON_KEY="    <key>CFBundleIconFile</key>
    <string>AppIcon</string>"
    echo "🎨 Ícono incluido: AppIcon.icns"
else
    echo "⚠️  Sin ícono: pon tu AppIcon.icns en apple/Resources/ para incluirlo."
fi

# Créditos de la app (Acerca de Side B)
CREDITS_SRC="$SCRIPT_DIR/../apple/Resources/Credits.rtf"
if [ -f "$CREDITS_SRC" ]; then
    cp "$CREDITS_SRC" "$RESOURCES_DIR/Credits.rtf"
fi

# Creamos un Info.plist básico
cat > "$APP_DIR/Contents/Info.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key>
    <string>${APP_NAME}</string>
    <key>CFBundleIdentifier</key>
    <string>com.fefucho.SideB.v2</string>
    <key>CFBundleName</key>
    <string>Side B</string>
    <key>CFBundleDisplayName</key>
    <string>Side B</string>
    <key>CFBundleDevelopmentRegion</key>
    <string>es</string>
    <key>CFBundleLocalizations</key>
    <array><string>es</string></array>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleVersion</key>
    <string>${APP_BUILD}</string>
    <key>CFBundleShortVersionString</key>
    <string>${APP_VERSION}</string>
    <key>GitHubRepoOwner</key>
    <string>${REPO_OWNER}</string>
    <key>GitHubRepoName</key>
    <string>${REPO_NAME}</string>
    <key>LSMinimumSystemVersion</key>
    <string>15.0</string>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>CFBundleIconName</key>
    <string>AppIcon</string>
$ICON_KEY
</dict>
</plist>
EOF

# Firmamos el bundle ad-hoc para que launchd y amfid en macOS lo acepten sin error
codesign --force --deep -s - "$APP_DIR" 2>/dev/null || true
if [ -x "$LSREGISTER" ]; then
    "$LSREGISTER" -f "$APP_DIR"
fi

echo "🏃 Ejecutando..."
open -n "$APP_DIR"
