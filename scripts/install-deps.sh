#!/usr/bin/env bash
set -euo pipefail

MODEL_CHOICE="${1:-turbo}"
case "$MODEL_CHOICE" in
  turbo|base|small)
    ;;
  *)
    echo "Usage: $0 [turbo|base|small]" >&2
    exit 2
    ;;
esac

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
