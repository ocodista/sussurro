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
APP_MODELS="$ROOT/Models"
WHISPER_ARTIFACTS="$ROOT/.build/sussurro-whisper/artifacts"

cd "$ROOT"
if [[ "${SUSSURRO_SKIP_WHISPER_BUILD:-0}" != "1" ]]; then
  "$ROOT/scripts/build-whisper-cpp.sh"
elif [[ ! -x "$WHISPER_ARTIFACTS/whisper-cli" ]]; then
  echo "Warning: SUSSURRO_SKIP_WHISPER_BUILD=1 and no existing whisper-cli artifact was found; app will rely on a custom path." >&2
fi

swift build -c "$CONFIG"

rm -rf "$APP_DIR"
mkdir -p "$MACOS" "$RESOURCES"
cp "$ROOT/.build/$CONFIG/$APP_NAME" "$MACOS/$APP_NAME"
chmod +x "$MACOS/$APP_NAME"
cp "$APP_RESOURCES/Sussurro.icns" "$RESOURCES/Sussurro.icns"
cp "$APP_RESOURCES/sussurro-logo.png" "$RESOURCES/sussurro-logo.png"
if [[ -x "$WHISPER_ARTIFACTS/whisper-cli" ]]; then
  cp -fL "$WHISPER_ARTIFACTS/whisper-cli" "$MACOS/whisper-cli"
  chmod +x "$MACOS/whisper-cli"
  if [[ -d "$WHISPER_ARTIFACTS/resources" ]] && compgen -G "$WHISPER_ARTIFACTS/resources/*" >/dev/null; then
    mkdir -p "$RESOURCES/Whisper"
    cp -Rf "$WHISPER_ARTIFACTS/resources/"* "$RESOURCES/Whisper/"
  fi
elif [[ "${SUSSURRO_SKIP_WHISPER_BUILD:-0}" != "1" ]]; then
  echo "Missing bundled whisper-cli artifact at $WHISPER_ARTIFACTS/whisper-cli" >&2
  exit 1
fi
if compgen -G "$APP_MODELS/*.bin" >/dev/null; then
  mkdir -p "$RESOURCES/Models"
  cp -fL "$APP_MODELS"/*.bin "$RESOURCES/Models/"
fi

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
  <key>NSScreenCaptureUsageDescription</key>
  <string>Sussurro uses ScreenCaptureKit to capture local system audio for meeting transcription.</string>
  <key>NSAudioCaptureUsageDescription</key>
  <string>Sussurro captures system audio locally so meeting participants can be transcribed separately.</string>
</dict>
</plist>
PLIST

"$ROOT/scripts/sign-app.sh" "$APP_DIR" "$BUNDLE_ID"

echo "Built: $APP_DIR"
echo "Open it with: open '$APP_DIR'"
