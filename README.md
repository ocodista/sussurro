# Custom STT SwiftUI

A small local macOS speech-to-text app:

- SwiftUI floating recorder window that stays above other windows
- live microphone waveform visualizer
- Linear-inspired dark floating UI
- parallel model race after each recording: `whisper.cpp` and optional `faster-whisper`
- two side-by-side real-time timer/result cards to compare speed and output
- stop/cancel button while transcription is running
- native macOS Settings window for model and executable paths
- live and final transcription duration per model
- records audio to the standard macOS app data folder
- writes transcription command logs to the standard macOS logs folder
- copies all transcripts, or one model's transcript, to the clipboard
- source links beside each model: GitHub repo and Hugging Face model page

## App data paths

The app uses macOS-standard user data locations instead of writing generated files into the project checkout:

- GGML models: `~/Library/Application Support/CustomSTT/Models/`
- faster-whisper models: `~/Library/Application Support/CustomSTT/Models/FasterWhisper/`
- Recordings: `~/Library/Application Support/CustomSTT/Recordings/`
- Logs: `~/Library/Logs/CustomSTT/`
- Caches: `~/Library/Caches/CustomSTT/`
- Latest transcription log: `~/Library/Logs/CustomSTT/whisper-last.log`
- Latest whisper.cpp log: `~/Library/Logs/CustomSTT/whisper-cpp-last.log`
- Latest faster-whisper log: `~/Library/Logs/CustomSTT/faster-whisper-last.log`

## Installed pieces

For whisper.cpp, this project expects:

- `/opt/homebrew/bin/whisper-cli` from Homebrew `whisper-cpp`
- source: <https://github.com/ggml-org/whisper.cpp>
- GGML models: <https://huggingface.co/ggerganov/whisper.cpp>
- a Whisper GGML model in `~/Library/Application Support/CustomSTT/Models/`

For faster-whisper comparison, this project expects:

- an app-managed Python environment at `~/Library/Application Support/CustomSTT/faster-whisper-venv/`
- source: <https://github.com/SYSTRAN/faster-whisper>
- default `large-v3-turbo` model currently resolves through faster-whisper to <https://huggingface.co/mobiuslabsgmbh/faster-whisper-large-v3-turbo>
- a faster-whisper model name like `large-v3-turbo`, a Hugging Face model ID, or a local CTranslate2 model folder

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

whisper.cpp only:

```bash
cd ~/personal/custom-stt-swift_ui
scripts/install-deps.sh turbo
```

whisper.cpp plus faster-whisper:

```bash
cd ~/personal/custom-stt-swift_ui
scripts/install-deps.sh turbo --with-faster-whisper
```

Or install only the faster-whisper backend:

```bash
scripts/install-faster-whisper.sh
```

GGML model choices for whisper.cpp:

- `turbo` — better accuracy, still fast on Apple Silicon
- `base` — smaller/faster, lower accuracy
- `small` — middle ground

## Use

1. Open the app.
2. Keep the floating window above whatever you are working on.
3. Press **Record**, space, or **⌘⌥M**.
4. Speak.
5. Press **Stop**, space, or **⌘⌥M**.
6. The app normalizes the audio once, then runs the configured models in parallel.
7. Compare the side-by-side timer/result cards.

Use **Copy all** to copy all completed model outputs, or **Copy** on a card to copy one result.

Click the gear button or use **CustomSTT → Settings…** to edit paths and include/exclude faster-whisper from the model race.

To include faster-whisper:

1. Run `scripts/install-faster-whisper.sh`.
2. Open Settings.
3. Turn on **Include faster-whisper in the model race**.
4. Keep model as `large-v3-turbo`, or set another faster-whisper model name, Hugging Face ID, or local CTranslate2 model folder.

The selected faster-whisper model downloads on first transcription into `~/Library/Application Support/CustomSTT/Models/FasterWhisper/`. The first faster-whisper run can take longer while that model downloads; press **Stop** to cancel it.

## If transcription fails

Open the latest command logs:

```bash
cat "$HOME/Library/Logs/CustomSTT/whisper-last.log"
cat "$HOME/Library/Logs/CustomSTT/whisper-cpp-last.log"
cat "$HOME/Library/Logs/CustomSTT/faster-whisper-last.log"
```

Common fixes:

```bash
brew install whisper-cpp
scripts/download-model.sh turbo
scripts/install-faster-whisper.sh
```
