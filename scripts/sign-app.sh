#!/usr/bin/env bash
set -euo pipefail

APP_PATH="${1:?Usage: sign-app.sh APP_PATH [BUNDLE_ID]}"
BUNDLE_ID="${2:-com.ocodista.sussurro}"
IDENTITY="${SUSSURRO_CODESIGN_IDENTITY:--}"

if ! command -v codesign >/dev/null 2>&1; then
  exit 0
fi

# Sign embedded Mach-O tools before sealing the outer bundle. `--deep` does
# not reliably replace existing signatures, and Developer ID bundles require
# each nested executable to be signed explicitly with the selected identity.
sign_embedded_tool() {
  local tool_path="$1"
  local identifier_suffix="$2"
  if [[ -f "$tool_path" ]]; then
    codesign \
      --force \
      --sign "$IDENTITY" \
      --identifier "$BUNDLE_ID.$identifier_suffix" \
      "$tool_path" >/dev/null
  fi
}

sign_embedded_tool "$APP_PATH/Contents/MacOS/sussurro-mcp" "mcp"
sign_embedded_tool "$APP_PATH/Contents/MacOS/whisper-cli" "whisper-cli"

if [[ "$IDENTITY" == "-" ]]; then
  codesign \
    --force \
    --sign "$IDENTITY" \
    --requirements "=designated => identifier \"$BUNDLE_ID\"" \
    "$APP_PATH" >/dev/null
else
  codesign \
    --force \
    --sign "$IDENTITY" \
    "$APP_PATH" >/dev/null
fi
