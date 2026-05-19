# Sussurro roadmap

## Goal

Sussurro should make developers' lives easier by turning long audio into text and putting that text where they are already working.

The core flow is simple:

1. Press a shortcut, such as **Option + T**.
2. Record or transcribe audio locally.
3. Copy or paste the transcript into the current app.
4. Optionally format the transcript with Qwen.

Sussurro should feel like a fast writing tool, not a transcription dashboard.

## Product principles

- **Stay out of the way.** The UI should shrink during recording and transcription.
- **Optimize for pasting.** The default result should land in the clipboard or active window.
- **Keep raw text available.** Users can choose raw Whisper output when they do not want formatting.
- **Make long audio reliable.** Long recordings should be resumable, visible in history, and safe to retry.
- **Prefer local processing.** Whisper transcription stays local. Qwen formatting should support local-first setups where possible.

## Target workflow

### Quick transcription

- User presses the global shortcut.
- Sussurro starts recording immediately.
- User presses the shortcut again to stop.
- Sussurro transcribes the audio.
- Sussurro copies the transcript to the clipboard.
- If enabled, Sussurro auto-pastes the text into the current focused application.

### Long audio transcription

- User drops or selects a long audio file.
- Sussurro shows duration, size, model, and progress.
- User can leave the app running.
- Sussurro saves audio and transcript history.
- User can retry transcription or formatting later.

### Optional formatting

Users can choose one of two output modes in Settings:

- **Raw transcription**: Whisper output with no rewriting.
- **Formatted transcription**: Qwen cleans up punctuation, paragraphs, and structure.

Formatting should preserve meaning. It should not summarize unless the user explicitly chooses a summary preset.

## Milestones

### 1. Fast capture

- Add configurable global shortcut.
- Default shortcut: **Option + T**.
- Shortcut starts and stops recording.
- Keep the compact waveform UI during recording.
- Keep a small stop control for mouse users.

### 2. Output destination

- Add clipboard output setting.
- Add auto-paste setting for the active window.
- Detect and preserve the previously focused application before Sussurro opens.
- Paste only after transcription succeeds.
- Show a toast: `Text copied to clipboard` or `Text pasted into <app>`.
- Keep manual copy available.

### 3. Transcript modes

- Add Settings toggle: **Raw** or **Formatted**.
- Keep raw transcript stored in history.
- Store formatted output separately.
- Add a per-transcription toggle to switch between raw and formatted text.

### 4. Qwen formatting

- Add Qwen provider configuration.
- Support local Qwen first.
- Add prompt presets:
  - clean dictation
  - developer note
  - bug report
  - pull request description
  - meeting notes
- Add a strict preservation mode for code, commands, URLs, and identifiers.
- Show formatting status separately from transcription status.

### 5. Long audio reliability

- Improve progress visibility for long files.
- Show audio duration and size before transcription starts.
- Save partial state when possible.
- Allow retry with another Whisper model.
- Keep transcript history searchable.
- Add actions to reveal audio, copy transcript, paste transcript, and reformat transcript.

### 6. Settings polish

- Global shortcut editor.
- Output destination: clipboard, auto-paste, or both.
- Transcript mode: raw or formatted.
- Qwen provider and model settings.
- Default formatting preset.
- Toggle for auto-minimize after successful paste/copy.

## Open questions

- Should auto-paste be enabled by default or opt-in?
- Should Qwen formatting run automatically or require confirmation for long transcripts?
- Which local Qwen runtime should Sussurro support first?
- How should Sussurro handle secure input fields where paste automation may fail?
- Should meeting mode format speakers differently from dictation mode?

## Definition of success

A developer can press **Option + T**, speak for several minutes, stop recording, and continue working in their editor, issue tracker, chat app, or browser with the transcript already pasted or ready in the clipboard.
