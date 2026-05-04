#!/usr/bin/env bash
set -euo pipefail

if ! command -v brew >/dev/null 2>&1; then
  echo "Homebrew is required: https://brew.sh" >&2
  exit 1
fi

if ! command -v whisper-cli >/dev/null 2>&1; then
  brew install whisper-cpp
else
  echo "whisper-cli already installed: $(command -v whisper-cli)"
fi

"$(dirname "$0")/download-model.sh" "${1:-turbo}"
