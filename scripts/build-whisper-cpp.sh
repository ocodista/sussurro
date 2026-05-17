#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
WORK_DIR="$ROOT/.build/sussurro-whisper"
SOURCE_DIR="$WORK_DIR/whisper.cpp"
BUILD_DIR="$WORK_DIR/build"
ARTIFACT_DIR="$WORK_DIR/artifacts"
REF="${SUSSURRO_WHISPER_CPP_REF:-v1.8.4}"
REPOSITORY_URL="${SUSSURRO_WHISPER_CPP_REPOSITORY:-https://github.com/ggml-org/whisper.cpp.git}"
PREBUILT_CLI="${SUSSURRO_WHISPER_CLI:-}"

mkdir -p "$ARTIFACT_DIR"

if [[ -n "$PREBUILT_CLI" ]]; then
  if [[ ! -x "$PREBUILT_CLI" ]]; then
    echo "SUSSURRO_WHISPER_CLI is not executable: $PREBUILT_CLI" >&2
    exit 1
  fi

  cp -fL "$PREBUILT_CLI" "$ARTIFACT_DIR/whisper-cli"
  chmod +x "$ARTIFACT_DIR/whisper-cli"
  echo "Using prebuilt whisper-cli: $ARTIFACT_DIR/whisper-cli"
  exit 0
fi

for tool in git cmake; do
  if ! command -v "$tool" >/dev/null 2>&1; then
    echo "$tool is required to build bundled whisper.cpp." >&2
    echo "Install $tool or set SUSSURRO_WHISPER_CLI to a prebuilt static whisper-cli executable." >&2
    exit 1
  fi
done

if [[ ! -d "$SOURCE_DIR/.git" ]]; then
  rm -rf "$SOURCE_DIR"
  git clone --depth 1 --branch "$REF" "$REPOSITORY_URL" "$SOURCE_DIR"
else
  git -C "$SOURCE_DIR" fetch --depth 1 origin "$REF"
  git -C "$SOURCE_DIR" checkout --detach FETCH_HEAD
fi

cmake_args=(
  -S "$SOURCE_DIR"
  -B "$BUILD_DIR"
  -DCMAKE_BUILD_TYPE=Release
  -DBUILD_SHARED_LIBS=OFF
  -DGGML_CCACHE=OFF
  -DGGML_NATIVE=OFF
  -DGGML_ACCELERATE=ON
  -DGGML_METAL=ON
  -DWHISPER_BUILD_TESTS=OFF
  -DWHISPER_BUILD_SERVER=OFF
  -DWHISPER_BUILD_EXAMPLES=ON
)

if [[ -n "${SUSSURRO_WHISPER_ARCHS:-}" ]]; then
  cmake_args+=("-DCMAKE_OSX_ARCHITECTURES=$SUSSURRO_WHISPER_ARCHS")
fi

cmake "${cmake_args[@]}"

jobs="${SUSSURRO_BUILD_JOBS:-}"
if [[ -z "$jobs" ]]; then
  jobs="$(sysctl -n hw.ncpu 2>/dev/null || printf '4')"
fi

if ! cmake --build "$BUILD_DIR" --config Release --target whisper-cli --parallel "$jobs"; then
  cmake --build "$BUILD_DIR" --config Release --target main --parallel "$jobs"
fi

cli=""
for candidate in \
  "$BUILD_DIR/bin/whisper-cli" \
  "$BUILD_DIR/examples/cli/whisper-cli" \
  "$BUILD_DIR/bin/main" \
  "$BUILD_DIR/examples/main/main"
do
  if [[ -x "$candidate" ]]; then
    cli="$candidate"
    break
  fi
done

if [[ -z "$cli" ]]; then
  cli="$(find "$BUILD_DIR" -type f \( -name whisper-cli -o -name main \) -perm -111 -print -quit)"
fi

if [[ -z "$cli" || ! -x "$cli" ]]; then
  echo "Could not find built whisper-cli under $BUILD_DIR" >&2
  exit 1
fi

rm -rf "$ARTIFACT_DIR"
mkdir -p "$ARTIFACT_DIR"
cp -f "$cli" "$ARTIFACT_DIR/whisper-cli"
chmod +x "$ARTIFACT_DIR/whisper-cli"

resource_dir="$ARTIFACT_DIR/resources"
while IFS= read -r resource; do
  mkdir -p "$resource_dir"
  cp -f "$resource" "$resource_dir/"
done < <(find "$SOURCE_DIR" "$BUILD_DIR" -type f \( -name 'ggml-metal*.metal' -o -name '*.metallib' \) -print 2>/dev/null)

if command -v otool >/dev/null 2>&1; then
  otool -L "$ARTIFACT_DIR/whisper-cli" > "$ARTIFACT_DIR/whisper-cli.otool.txt" || true
  if grep -E '/opt/homebrew|/usr/local/Cellar|@rpath/lib(whisper|ggml)' "$ARTIFACT_DIR/whisper-cli.otool.txt" >/dev/null 2>&1; then
    echo "Warning: bundled whisper-cli still references external whisper.cpp libraries:" >&2
    grep -E '/opt/homebrew|/usr/local/Cellar|@rpath/lib(whisper|ggml)' "$ARTIFACT_DIR/whisper-cli.otool.txt" >&2 || true
  fi
fi

echo "Built bundled whisper.cpp CLI: $ARTIFACT_DIR/whisper-cli"
