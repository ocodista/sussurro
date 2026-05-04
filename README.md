# Custom STT SwiftUI

A small local macOS speech-to-text app:

- SwiftUI floating recorder window that stays above other windows
- live microphone waveform visualizer
- Linear-inspired dark floating UI
- local transcription through open-source `whisper.cpp` (`whisper-cli`)
- native macOS Settings window for model and `whisper-cli` paths
- live and final Whisper transcription duration
- records audio to the standard macOS app data folder
- writes the latest Whisper command log to the standard macOS logs folder
- copies each transcript to the clipboard after transcription

## App data paths

The app now uses macOS-standard user data locations instead of writing generated files into the project checkout:

- Models: `~/Library/Application Support/CustomSTT/Models/`
- Recordings: `~/Library/Application Support/CustomSTT/Recordings/`
- Logs: `~/Library/Logs/CustomSTT/`
- Latest Whisper log: `~/Library/Logs/CustomSTT/whisper-last.log`

## Installed pieces

This project expects:

- `/opt/homebrew/bin/whisper-cli` from Homebrew `whisper-cpp`
- a Whisper GGML model in `~/Library/Application Support/CustomSTT/Models/`

The app also checks a few existing local model locations as fallbacks, including `~/.whisper-models/` and the old project-local `Models/` folder.

## Install and run

```bash
cd ~/personal/custom-stt-swift_ui
scripts/install-app.sh
```

The app is installed to `/Applications/CustomSTT.app` when `/Applications` is writable, otherwise to `~/Applications/CustomSTT.app`.

Start it anytime with Spotlight, Launchpad, Finder, or:

```bash
open -a CustomSTT
```

macOS will ask for microphone access on first run. Allow it.

## Install or refresh dependencies

```bash
cd ~/personal/custom-stt-swift_ui
scripts/install-deps.sh turbo
```

Model choices:

- `turbo` — better accuracy, still fast on Apple Silicon
- `base` — smaller/faster, lower accuracy
- `small` — middle ground

## Use

1. Open the app.
2. Keep the floating window above whatever you are working on.
3. Press **Record**, space, or **⌘⌥M**.
4. Speak.
5. Press **Stop**, space, or **⌘⌥M**.
6. Wait for transcription; the result appears in the text box and is copied to the clipboard.

Click the gear button or use **CustomSTT → Settings…** to edit the `whisper-cli` and model paths.

## If transcription fails

Open the latest command log:

```bash
cat "$HOME/Library/Logs/CustomSTT/whisper-last.log"
```

Common fixes:

```bash
brew install whisper-cpp
scripts/download-model.sh turbo
```
