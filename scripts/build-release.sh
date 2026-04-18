#!/bin/bash
set -e

cd "$(dirname "$0")/.."
PROJECT_DIR=$(pwd)

echo "🔨 Building release..."
swift build -c release

echo "📦 Creating app bundle..."
APP_NAME="ZMK Keymap Viewer"
APP_BUNDLE="${PROJECT_DIR}/${APP_NAME}.app"
rm -rf "$APP_BUNDLE"

mkdir -p "${APP_BUNDLE}/Contents/MacOS"
mkdir -p "${APP_BUNDLE}/Contents/Resources"

cp .build/release/ZMKKeymapViewer "${APP_BUNDLE}/Contents/MacOS/"

# Extract version from source file
APP_VERSION=$(grep 'let appVersion =' ZMKKeymapViewer.swift | cut -d '"' -f 2)
if [ -z "$APP_VERSION" ]; then
    echo "⚠️ Warning: Could not extract appVersion. Defaulting to 1.0.0"
    APP_VERSION="1.0.0"
fi

# Create Info.plist
cat > "${APP_BUNDLE}/Contents/Info.plist" << EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key>
    <string>ZMK Keymap Viewer</string>
    <key>CFBundleDisplayName</key>
    <string>ZMK Keymap Viewer</string>
    <key>CFBundleIdentifier</key>
    <string>com.sebietter.zmk-keymap-viewer</string>
    <key>CFBundleVersion</key>
    <string>${APP_VERSION}</string>
    <key>CFBundleShortVersionString</key>
    <string>${APP_VERSION}</string>
    <key>CFBundleExecutable</key>
    <string>ZMKKeymapViewer</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>LSMinimumSystemVersion</key>
    <string>13.0</string>
    <key>LSUIElement</key>
    <true/>
    <key>NSHighResolutionCapable</key>
    <true/>
</dict>
</plist>
EOF

# Ad-hoc code sign (avoids "damaged app" error, allows right-click → Open)
echo "🔏 Code signing..."
codesign --force --deep --sign - "$APP_BUNDLE"

echo "💿 Creating DMG..."
DMG_NAME="ZMK-Keymap-Viewer"
DMG_PATH="${PROJECT_DIR}/${DMG_NAME}.dmg"
rm -f "$DMG_PATH"

# Create temporary directory for DMG contents
DMG_TEMP="${PROJECT_DIR}/.dmg-temp"
rm -rf "$DMG_TEMP"
mkdir -p "$DMG_TEMP"

cp -R "$APP_BUNDLE" "$DMG_TEMP/"
ln -s /Applications "$DMG_TEMP/Applications"

# Create DMG
hdiutil create -volname "$DMG_NAME" -srcfolder "$DMG_TEMP" -ov -format UDZO "$DMG_PATH"

# Cleanup
rm -rf "$DMG_TEMP"

echo ""
echo "✅ Build complete!"
echo "   App: ${APP_BUNDLE}"
echo "   DMG: ${DMG_PATH}"
