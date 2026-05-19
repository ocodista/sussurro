#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP_NAME="Sussurro.app"
BUNDLE_ID="com.ocodista.sussurro"
SOURCE_APP="$ROOT/dist/$APP_NAME"

"$ROOT/scripts/build-app.sh"

if [[ -w /Applications ]]; then
  INSTALL_DIR="/Applications"
else
  INSTALL_DIR="$HOME/Applications"
  mkdir -p "$INSTALL_DIR"
fi

TARGET_APP="$INSTALL_DIR/$APP_NAME"

osascript -e 'tell application "Sussurro" to quit' >/dev/null 2>&1 || true
rm -rf "$TARGET_APP"
cp -R "$SOURCE_APP" "$TARGET_APP"

"$ROOT/scripts/sign-app.sh" "$TARGET_APP" "$BUNDLE_ID"

echo "Installed: $TARGET_APP"
echo "Start it with: open -a Sussurro"
open "$TARGET_APP"
