#!/usr/bin/env bash
set -euo pipefail

APP_SUPPORT_DIR="$HOME/Library/Application Support/Sussurro"
MODELS_DIR="${SUSSURRO_MODELS_DIR:-$APP_SUPPORT_DIR/Models}"
mkdir -p "$MODELS_DIR"

choice="${1:-turbo}"
case "$choice" in
  turbo)
    file="ggml-large-v3-turbo-q5_0.bin"
    url="https://huggingface.co/ggerganov/whisper.cpp/resolve/main/$file"
    ;;
  base)
    file="ggml-base.bin"
    url="https://huggingface.co/ggerganov/whisper.cpp/resolve/main/$file"
    ;;
  small)
    file="ggml-small.bin"
    url="https://huggingface.co/ggerganov/whisper.cpp/resolve/main/$file"
    ;;
  *)
    echo "Usage: $0 [turbo|base|small]" >&2
    exit 2
    ;;
esac

target="$MODELS_DIR/$file"
temporary_target="$target.tmp"

cleanup() {
  rm -f "$temporary_target"
}
trap cleanup EXIT

if [[ -f "$target" || -L "$target" ]]; then
  echo "Model already exists: $target"
  exit 0
fi

echo "Downloading $file to $target"
curl -L --fail --progress-bar "$url" -o "$temporary_target"

if [[ ! -s "$temporary_target" ]]; then
  echo "Downloaded model is empty: $temporary_target" >&2
  exit 1
fi

mv "$temporary_target" "$target"
trap - EXIT
echo "Done: $target"
