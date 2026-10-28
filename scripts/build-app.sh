#!/usr/bin/env bash
# Builds Organizador.app into ./dist so it can be dragged into /Applications.
set -euo pipefail

cd "$(dirname "$0")/.."

APP_NAME="Organizador"
BUNDLE_ID="io.github.joaoliveirarruda.organizador"
VERSION="${VERSION:-0.1.0}"
APP_DIR="dist/${APP_NAME}.app"

swift build -c release --product "$APP_NAME"
BIN_DIR="$(swift build -c release --show-bin-path)"

rm -rf "$APP_DIR"
mkdir -p "$APP_DIR/Contents/MacOS" "$APP_DIR/Contents/Resources"
cp "$BIN_DIR/$APP_NAME" "$APP_DIR/Contents/MacOS/$APP_NAME"

cat > "$APP_DIR/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key><string>${APP_NAME}</string>
    <key>CFBundleDisplayName</key><string>${APP_NAME}</string>
    <key>CFBundleIdentifier</key><string>${BUNDLE_ID}</string>
    <key>CFBundleExecutable</key><string>${APP_NAME}</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>${VERSION}</string>
    <key>CFBundleVersion</key><string>${VERSION}</string>
    <key>LSMinimumSystemVersion</key><string>14.0</string>
    <key>NSHighResolutionCapable</key><true/>
    <key>CFBundleDevelopmentRegion</key><string>pt-BR</string>
    <key>NSCalendarsFullAccessUsageDescription</key><string>O Organizador cria um evento para cada sessão cronometrada, para o seu calendário mostrar de que horas a que horas você trabalhou em cada coisa.</string>
    <key>NSCalendarsUsageDescription</key><string>O Organizador cria um evento para cada sessão cronometrada no seu calendário.</string>
    <key>NSUserNotificationsUsageDescription</key><string>O Organizador avisa no máximo uma vez por dia quando algum objetivo está parado.</string>
</dict>
</plist>
PLIST

# Ad-hoc signature so macOS runs it locally. Not notarized.
codesign --force --sign - "$APP_DIR"

echo "Pronto: $APP_DIR"
