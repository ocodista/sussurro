#!/usr/bin/env bash
set -euo pipefail

APP_SUPPORT_DIR="$HOME/Library/Application Support/CustomSTT"
VENV_DIR="$APP_SUPPORT_DIR/faster-whisper-venv"
PYTHON_BIN="${PYTHON:-}"

if [[ -z "$PYTHON_BIN" ]]; then
  if command -v python3 >/dev/null 2>&1; then
    PYTHON_BIN="$(command -v python3)"
  elif command -v brew >/dev/null 2>&1; then
    brew install python
    PYTHON_BIN="$(command -v python3)"
  else
    echo "python3 is required. Install Python or Homebrew first." >&2
    exit 1
  fi
fi

mkdir -p "$APP_SUPPORT_DIR"
"$PYTHON_BIN" -m venv "$VENV_DIR"
"$VENV_DIR/bin/python" -m pip install --upgrade pip
"$VENV_DIR/bin/python" -m pip install --upgrade faster-whisper

cat <<EOF
Installed faster-whisper for CustomSTT.

Python path:
  $VENV_DIR/bin/python

In CustomSTT Settings:
  1. Turn on "Use faster-whisper"
  2. Set Python executable to the path above
  3. Use model: large-v3-turbo

The model downloads on first transcription to:
  $APP_SUPPORT_DIR/Models/FasterWhisper
EOF
