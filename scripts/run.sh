#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
if [[ "${SUSSURRO_SKIP_WHISPER_BUILD:-0}" != "1" ]]; then
  "$ROOT/scripts/build-whisper-cpp.sh"
fi
swift run Sussurro
