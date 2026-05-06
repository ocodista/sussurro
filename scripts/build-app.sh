#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP_NAME="Sussurro"
BUNDLE_ID="com.ocodista.sussurro"
CONFIG="release"
APP_DIR="$ROOT/dist/$APP_NAME.app"
CONTENTS="$APP_DIR/Contents"
MACOS="$CONTENTS/MacOS"
RESOURCES="$CONTENTS/Resources"
APP_RESOURCES="$ROOT/Sources/SussurroApp/Resources"

cd "$ROOT"
swift build -c "$CONFIG"

rm -rf "$APP_DIR"
mkdir -p "$MACOS" "$RESOURCES"
cp "$ROOT/.build/$CONFIG/$APP_NAME" "$MACOS/$APP_NAME"
chmod +x "$MACOS/$APP_NAME"
cp "$APP_RESOURCES/Sussurro.icns" "$RESOURCES/Sussurro.icns"
cp "$APP_RESOURCES/sussurro-logo.png" "$RESOURCES/sussurro-logo.png"

cat > "$CONTENTS/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleExecutable</key>
  <string>$APP_NAME</string>
  <key>CFBundleIdentifier</key>
  <string>$BUNDLE_ID</string>
  <key>CFBundleName</key>
  <string>$APP_NAME</string>
  <key>CFBundleDisplayName</key>
  <string>Sussurro</string>
  <key>CFBundleIconFile</key>
  <string>Sussurro</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>CFBundleShortVersionString</key>
  <string>0.1.0</string>
  <key>CFBundleVersion</key>
  <string>1</string>
  <key>LSMinimumSystemVersion</key>
  <string>13.0</string>
  <key>NSHighResolutionCapable</key>
  <true/>
  <key>NSMicrophoneUsageDescription</key>
  <string>Sussurro records microphone audio locally so whisper.cpp can transcribe it into text.</string>
</dict>
</plist>
PLIST

if command -v codesign >/dev/null 2>&1; then
  codesign --force --deep --sign - "$APP_DIR" >/dev/null
fi

echo "Built: $APP_DIR"
echo "Open it with: open '$APP_DIR'"
