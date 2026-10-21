<p align="center">
  <img src="Sources/SussurroApp/Resources/sussurro-logo.png" alt="Sussurro logo" width="160">
</p>

# Sussurro

A small offline macOS speech-to-text app powered by [whisper.cpp](https://github.com/ggml-org/whisper.cpp) written in Swift.

**Contents**

- [Demo](#demo)
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

## Demo

![Sussurro demo](assets/sussurro-demo.gif)

## How to run

### Install

```bash
git clone https://github.com/ocodista/sussurro.git
cd sussurro
scripts/install-app.sh
```

`install-app.sh` builds bundled whisper.cpp, builds the app, and installs it to `/Applications/Sussurro.app` when possible. Otherwise, it installs to `~/Applications/Sussurro.app`. It signs source builds with a stable local ad-hoc requirement so macOS privacy grants survive rebuilds. Building from source requires Xcode command line tools, Git, and CMake; running the built app does not require Homebrew.

### Open

```bash
open -a Sussurro
```

Allow microphone access on first launch.

### Run without installing

```bash
scripts/run.sh
```

`run.sh` also builds the local bundled whisper.cpp CLI when needed.

## First-time setup

Open **Sussurro → Settings…** or click the gear button. The **Local readiness & privacy** card checks microphone, system-audio, model, local whisper.cpp, and bundled MCP availability, with recovery buttons for each failure. The check reads permission states and file availability only—it never opens recordings or transcripts.

Sussurro ships with bundled [`whisper.cpp`](https://github.com/ggml-org/whisper.cpp) and the recommended GGML Whisper model, so Homebrew is not required for transcription.

Advanced users can override the bundled CLI/model paths or download alternate models from Settings.

## How to use

1. Choose an input, or keep **Default system input**.
2. Choose **Dictation** for microphone-only notes, **Real-time** for live words every few seconds, or **Meeting** for a two-person call.
3. Press **Record** / **Start Live** / **Start Meeting**, space, or **⌘⌥M**.
4. Speak.
5. Press **Stop**, space, or **⌘⌥M**.
6. Wait for transcription. Sussurro copies the result to the clipboard.

Real-time mode records the microphone and transcribes short local chunks while you speak. The default update interval is 5 seconds, and you can change it in Settings. When you stop, Sussurro runs one final local Whisper pass over the full audio for the saved transcript and clipboard output.

Meeting mode records the microphone as **Person A** and local system audio as **Person B**, then merges the two local whisper.cpp transcripts chronologically without summarizing or rewriting the words. Use headphones to reduce speaker bleed between streams.

## Features

- floating recorder window with input picker, recording mode picker, and waveform
- real-time mode that shows live microphone transcription in configurable chunks
- meeting mode that captures microphone + system audio locally and labels a two-person call as Person A/Person B
- SQLite-backed audio and transcript history for reviewing and retrying failed or long transcriptions
- local transcription through bundled `whisper.cpp`
- bundled recommended Whisper model, with optional model download and path overrides
- transcription status, duration, and language display
- clipboard copy and diagnostic command logs

## Privacy and safety

- Transcription runs locally through bundled `whisper.cpp`; Sussurro does not send audio or transcripts to an app server.
- Real-time mode stores temporary chunk files only long enough to transcribe them, then removes them.
- Meeting mode captures microphone and system audio locally. System audio capture may require macOS System Audio Recording permission.
- Recordings are stored locally in `~/Library/Application Support/Sussurro/Recordings/` until you delete them.
- Successful transcripts are copied to the macOS clipboard, where other apps may be able to read them.
- Transcript history is stored locally in SQLite at `~/Library/Application Support/Sussurro/history.sqlite` so you can review and retry previous audio.
- Diagnostic logs intentionally omit transcript text. They keep command metadata and `whisper-cli` stderr for troubleshooting.

## Local MCP (Phase 1)

Sussurro includes a secure stdio MCP server—no listening network port is opened. Build it with `swift build --product sussurro-mcp`, then configure your MCP client to launch:

```bash
.build/debug/sussurro-mcp \
  --whisper-cli /absolute/path/to/whisper-cli \
  --model /absolute/path/to/ggml-model.bin \
  --language auto
```

The server exposes `transcribe_audio`, `structure_text`, `structure_audio`, and `get_last_transcription`. The app and server share the local Whisper command service and the last-transcription store at `~/Library/Application Support/Sussurro/last-transcription.json`.

Structured output is entirely local and deterministic. Phase 1 extracts `field: value` lines into object schemas and validates the common JSON Schema subset: `type`, `properties`, `required`, `additionalProperties`, `items`, `enum`, `const`, `default`, string/number/array bounds. Unsupported keywords fail closed rather than being ignored. This is extraction, not generative summarization or translation; offline translation is not included.

Wide events are disabled by default. To explicitly opt in to privacy-safe local JSONL events (event name, success, duration, timestamp only—never audio, transcript, schema, or file path), pass `--events-file /path/to/events.jsonl` or set `SUSSURRO_EVENTS_FILE`.

Run the deterministic local vertical-slice proof with:

```bash
scripts/prove-phase1.sh
# Force the release artifact path too:
SUSSURRO_PROOF_CONFIGURATION=release scripts/prove-phase1.sh
```

The proof drives real MCP stdio requests against a known fake-Whisper fixture and asserts transcription, schema-valid JSON, all four tools, persistence, and operation with poisoned outbound proxy settings. Real audio still requires a compatible local model and executable. Microphone recording requires macOS Microphone permission; meeting/system audio remains subject to macOS System Audio Recording/ScreenCaptureKit permission boundaries. MCP transcription of an existing readable file does not request recording permission.

## Models

Bundled default model: [`ggml-large-v3-turbo-q5_0.bin`](https://huggingface.co/ggerganov/whisper.cpp/blob/main/ggml-large-v3-turbo-q5_0.bin).

Model source: [`ggerganov/whisper.cpp` on Hugging Face](https://huggingface.co/ggerganov/whisper.cpp).

Presets:

- `turbo` — recommended quality/speed balance
- `base` — smallest and fastest, with lower accuracy
- `small` — middle ground

## Paths

- bundled whisper.cpp CLI: `Sussurro.app/Contents/MacOS/whisper-cli`
- bundled models: `Sussurro.app/Contents/Resources/Models/`
- downloaded models: `~/Library/Application Support/Sussurro/Models/`
- recordings: `~/Library/Application Support/Sussurro/Recordings/`
- history database: `~/Library/Application Support/Sussurro/history.sqlite`
- logs: `~/Library/Logs/Sussurro/`
- latest transcription log: `~/Library/Logs/Sussurro/whisper-last.log`

## Troubleshooting

Open the latest command log:

```bash
cat "$HOME/Library/Logs/Sussurro/whisper-last.log"
```

Common fixes when building from source:

```bash
scripts/install-deps.sh turbo
scripts/build-app.sh
```

If Meeting mode says System Audio Recording is missing while Sussurro is enabled, reset the stale macOS privacy grant and grant it again:

```bash
tccutil reset AudioCapture com.ocodista.sussurro
scripts/install-app.sh
```

## License

MIT. See [LICENSE](LICENSE).
