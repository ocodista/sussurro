#!/usr/bin/env bash
set -euo pipefail

MODEL_CHOICE="turbo"
INSTALL_FASTER_WHISPER="false"

for arg in "$@"; do
  case "$arg" in
    --with-faster-whisper)
      INSTALL_FASTER_WHISPER="true"
      ;;
    turbo|base|small)
      MODEL_CHOICE="$arg"
      ;;
    *)
      echo "Usage: $0 [turbo|base|small] [--with-faster-whisper]" >&2
      exit 2
      ;;
  esac
done

if ! command -v brew >/dev/null 2>&1; then
  echo "Homebrew is required: https://brew.sh" >&2
  exit 1
fi

if ! command -v whisper-cli >/dev/null 2>&1; then
  brew install whisper-cpp
else
  echo "whisper-cli already installed: $(command -v whisper-cli)"
fi

"$(dirname "$0")/download-model.sh" "$MODEL_CHOICE"

if [[ "$INSTALL_FASTER_WHISPER" == "true" ]]; then
  "$(dirname "$0")/install-faster-whisper.sh"
else
  echo "Optional: run scripts/install-faster-whisper.sh or pass --with-faster-whisper to install the faster-whisper backend."
fi
