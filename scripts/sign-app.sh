#!/usr/bin/env bash
set -euo pipefail

APP_PATH="${1:?Usage: sign-app.sh APP_PATH [BUNDLE_ID]}"
BUNDLE_ID="${2:-com.ocodista.sussurro}"
IDENTITY="${SUSSURRO_CODESIGN_IDENTITY:--}"

if ! command -v codesign >/dev/null 2>&1; then
  exit 0
fi

if [[ "$IDENTITY" == "-" ]]; then
  codesign \
    --force \
    --deep \
    --sign "$IDENTITY" \
    --requirements "=designated => identifier \"$BUNDLE_ID\"" \
    "$APP_PATH" >/dev/null
else
  codesign \
    --force \
    --deep \
    --sign "$IDENTITY" \
    "$APP_PATH" >/dev/null
fi
