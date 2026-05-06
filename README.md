<p align="center">
  <img src="Sources/SussurroApp/Resources/sussurro-logo.png" alt="Sussurro logo" width="160">
</p>

<h1 align="center">Sussurro</h1>

A small local macOS speech-to-text app powered by `whisper.cpp`.

**Contents**

- [How to run](#how-to-run)
  - [Install](#install)
  - [Open](#open)
  - [Run without installing](#run-without-installing)
- [First-time setup](#first-time-setup)
- [How to use](#how-to-use)
- [Features](#features)
- [Privacy and safety](#privacy-and-safety)
- [Models](#models)
- [Paths](#paths)
- [Troubleshooting](#troubleshooting)
- [License](#license)

## How to run

### Install

```bash
git clone https://github.com/ocodista/sussurro.git
cd sussurro
scripts/install-app.sh
```

`install-app.sh` builds the app and installs it to `/Applications/Sussurro.app` when possible. Otherwise, it installs to `~/Applications/Sussurro.app`.

### Open

```bash
open -a Sussurro
```

Allow microphone access on first launch.

### Run without installing

```bash
scripts/run.sh
```

## First-time setup

Open **Sussurro → Settings…** or click the gear button.

Sussurro checks for:

- `whisper-cli` from Homebrew `whisper-cpp`
- a GGML Whisper model in `~/Library/Application Support/Sussurro/Models/`

Install both with:

```bash
scripts/install-deps.sh turbo
```

You can also download a model from Settings.

## How to use

1. Choose an input, or keep **Default system input**.
2. Press **Record**, space, or **⌘⌥M**.
3. Speak.
4. Press **Stop**, space, or **⌘⌥M**.
5. Wait for transcription. Sussurro copies the result to the clipboard.

## Features

- floating recorder window with input picker and waveform
- local transcription through `whisper.cpp`
- model download and path settings
- transcription status, duration, and language display
- clipboard copy and diagnostic command logs

## Privacy and safety

- Transcription runs locally through `whisper.cpp`; Sussurro does not send audio or transcripts to an app server.
- Recordings are stored locally in `~/Library/Application Support/Sussurro/Recordings/` until you delete them.
- Successful transcripts are copied to the macOS clipboard, where other apps may be able to read them.
- Diagnostic logs intentionally omit transcript text. They keep command metadata and `whisper-cli` stderr for troubleshooting.

## Models

Default model: `ggml-large-v3-turbo-q5_0.bin`.

Presets:

- `turbo` — recommended quality/speed balance
- `base` — smallest and fastest, with lower accuracy
- `small` — middle ground

## Paths

- models: `~/Library/Application Support/Sussurro/Models/`
- recordings: `~/Library/Application Support/Sussurro/Recordings/`
- logs: `~/Library/Logs/Sussurro/`
- latest transcription log: `~/Library/Logs/Sussurro/whisper-last.log`

## Troubleshooting

Open the latest command log:

```bash
cat "$HOME/Library/Logs/Sussurro/whisper-last.log"
```

Common fixes:

```bash
brew install whisper-cpp
scripts/download-model.sh turbo
```

## License

MIT. See [LICENSE](LICENSE).
