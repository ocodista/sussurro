# Feature request: Audio-reactive dog animation

## Context

Sussurro already has a clean floating recorder UI with waveform visualization and real-time recording feedback.

A small animated mascot could make the recorder feel more alive without adding much technical complexity.

## Proposal

Animate the Sussurro dog logo while audio is:

- recording
- playing back
- transcribing

The simplest version opens and closes the dog’s mouth based on waveform intensity or microphone amplitude.

A tiny two-frame animation would already make the interface feel more expressive.

## Why this matters

This adds:

- personality
- perceived responsiveness
- emotional feedback
- stronger product identity
- a more polished native macOS feel

Tiny motion details often make desktop apps feel memorable.

## Suggested behavior

### Recording

While recording:

- open and close the mouth with live microphone amplitude
- blink when silence is detected
- move more on louder peaks

### Playback

While replaying audio or transcripts:

- reuse the same mouth animation logic
- sync loosely with the output waveform

### Transcribing

While whisper.cpp is processing:

- show a subtle thinking or listening animation
- pulse the ears or tail slowly

## Recommended MVP

Use the current waveform amplitude and a threshold:

```swift
mouthOpen = amplitude > threshold
```

Update every `50ms–120ms`.

This is cheap, simple, and effective.

## Possible implementations

### SVG frame swap

Use two SVG states:

- `mouth-open.svg`
- `mouth-closed.svg`

### SwiftUI state animation

Use native SwiftUI transforms:

```swift
.scaleEffect()
.rotationEffect()
.opacity()
```

### Sprite animation

Use a tiny frame sequence.

### Audio-driven interpolation

Use RMS or FFT averages from:

- `AVAudioEngine`
- the existing waveform pipeline

## Future extensions

- blinking eyes
- tail movement
- sleeping idle state
- thinking animation during transcription
- emotion states based on confidence or language detection
- bouncing waveform synced with the mascot

## UX goal

The objective is not realism.

The goal is to make Sussurro feel alive and recognizable with small animation touches.
