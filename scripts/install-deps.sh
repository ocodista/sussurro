#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
MODEL_CHOICE="${1:-turbo}"
case "$MODEL_CHOICE" in
  turbo|base|small)
    ;;
  *)
    echo "Usage: $0 [turbo|base|small]" >&2
    exit 2
    ;;
esac

"$ROOT/scripts/build-whisper-cpp.sh"
"$ROOT/scripts/download-model.sh" "$MODEL_CHOICE"
