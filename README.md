# Custom STT SwiftUI

A small local macOS speech-to-text app:

- SwiftUI floating recorder window that stays above other windows
- live microphone waveform visualizer
- Linear-inspired dark floating UI
- fast local transcription through `whisper.cpp` (`whisper-cli`)
- stop/cancel button while transcription is running
- native macOS Settings window for input device, model, and executable paths
- live and final transcription duration
- detected language pill with flags for Portuguese, English, and Spanish
- records audio to the standard macOS app data folder
- writes the latest transcription command log to the standard macOS logs folder
- copies transcripts to the clipboard after transcription
- source links for whisper.cpp on GitHub and GGML models on Hugging Face

## App data paths

The app uses macOS-standard user data locations instead of writing generated files into the project checkout:

- GGML models: `~/Library/Application Support/CustomSTT/Models/`
- Recordings: `~/Library/Application Support/CustomSTT/Recordings/`
- Logs: `~/Library/Logs/CustomSTT/`
- Latest transcription log: `~/Library/Logs/CustomSTT/whisper-last.log`

## Installed pieces

This project expects:

- `/opt/homebrew/bin/whisper-cli` from Homebrew `whisper-cpp`
- source: <https://github.com/ggml-org/whisper.cpp>
- GGML models: <https://huggingface.co/ggerganov/whisper.cpp>
- a Whisper GGML model in `~/Library/Application Support/CustomSTT/Models/`

The app also checks a few existing local GGML model locations as fallbacks, including `~/.whisper-models/` and the old project-local `Models/` folder.

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

GGML model choices:

- `turbo` — better accuracy, still fast on Apple Silicon
- `base` — smaller/faster, lower accuracy
- `small` — middle ground

## Use

1. Open the app.
2. Keep the floating window above whatever you are working on.
3. Choose an input from the **Input** menu, or keep **Default system input**.
4. Press **Record**, space, or **⌘⌥M**.
5. Speak.
6. Press **Stop**, space, or **⌘⌥M**.
7. Wait for whisper.cpp transcription; the result appears in the text box and is copied to the clipboard.

Click the gear button or use **CustomSTT → Settings…** to edit paths.

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
