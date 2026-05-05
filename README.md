<p align="center">
  <img src="https://encrypted-tbn0.gstatic.com/images?q=tbn:ANd9GcS5vU-0oLtYWp0BIXcd1y7LuCbJ1rv8UCUgrg&s" alt="Sussurro" width="160">
</p>

<h1 align="center">Sussurro</h1>

A small local macOS speech-to-text app powered by `whisper.cpp`.

## Features

- SwiftUI floating recorder window that stays above other windows
- live microphone waveform visualizer
- Linear-inspired dark floating UI
- fast local transcription through `whisper.cpp` (`whisper-cli`)
- first-time setup UI for `whisper-cli` and GGML model configuration
- in-app GGML model download for recommended/base/small presets
- stop/cancel button while transcription is running
- native macOS Settings window for input device, model, and executable paths
- live and final transcription duration
- detected language pill with flags for Portuguese, English, and Spanish
- records audio to the standard macOS app data folder
- writes the latest transcription command log to the standard macOS logs folder
- copies transcripts to the clipboard after transcription
- source links for whisper.cpp on GitHub and GGML models on Hugging Face

## Why the default model is `ggml-large-v3-turbo-q5_0`

Sussurro defaults to `ggml-large-v3-turbo-q5_0.bin` because it is a strong local-dictation trade-off:

- `large-v3-turbo` keeps much of Whisper large-v3's multilingual quality while running faster than the full large model.
- `q5_0` is a 5-bit quantized GGML build. It uses much less disk/RAM than full precision while preserving good accuracy.
- The model works well for Portuguese, English, Spanish, mixed-language speech, and less-than-perfect microphone audio.
- On Apple Silicon, `whisper.cpp` can use Metal acceleration, so this model is still practical for a floating desktop recorder.

Other presets are available in Settings:

- `base` — smallest/fastest, useful for tests, lower accuracy
- `small` — middle ground
- `large-v3-turbo-q5_0` — recommended quality/speed balance

## App data paths

Sussurro uses macOS-standard user data locations instead of writing generated files into the project checkout:

- GGML models: `~/Library/Application Support/Sussurro/Models/`
- Recordings: `~/Library/Application Support/Sussurro/Recordings/`
- Logs: `~/Library/Logs/Sussurro/`
- Latest transcription log: `~/Library/Logs/Sussurro/whisper-last.log`

The app also checks a few existing local GGML model locations as fallbacks, including the old `CustomSTT` app data folder.

## Install and run

```bash
git clone git@github.com:ocodista/sussurro.git
cd sussurro
scripts/install-app.sh
```

The app is installed to `/Applications/Sussurro.app` when `/Applications` is writable, otherwise to `~/Applications/Sussurro.app`.

Start it anytime with Spotlight, Launchpad, Finder, or:

```bash
open -a Sussurro
```

macOS will ask for microphone access on first run. Allow it.

## First-time setup

Open **Sussurro → Settings…** or click the gear button.

The setup panel checks:

1. `whisper-cli` from Homebrew `whisper-cpp`
2. a GGML Whisper model in the Sussurro models folder

You can download a model directly from Settings. For the CLI dependency, use **Copy Setup Command** or run:

```bash
scripts/install-deps.sh turbo
```

Model choices:

- `turbo` — recommended; better accuracy, still fast on Apple Silicon
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

## If transcription fails

Open the latest command log:

```bash
cat "$HOME/Library/Logs/Sussurro/whisper-last.log"
```

Common fixes:

```bash
brew install whisper-cpp
scripts/download-model.sh turbo
```
