import AppKit
import SwiftUI

struct RecorderView: View {
    @StateObject private var recorder: AudioRecorder
    @StateObject private var transcriber: WhisperTranscriber
    @State private var lastRecordingURL: URL?
    @State private var copied = false
    @State private var hotKey: GlobalHotKey?
    @State private var hotKeyError: String?

    init(recorder: AudioRecorder, transcriber: WhisperTranscriber) {
        _recorder = StateObject(wrappedValue: recorder)
        _transcriber = StateObject(wrappedValue: transcriber)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            header
            WaveformView(levels: recorder.levels, isRecording: recorder.isRecording)
            controls
            transcriptBox
            footer
        }
        .padding(.top, 28)
        .padding(.horizontal, 24)
        .padding(.bottom, 22)
        .frame(minWidth: 440, minHeight: 360)
        .background(Color(red: 0.065, green: 0.067, blue: 0.078))
        .preferredColorScheme(.dark)
        .onAppear(perform: registerGlobalHotKey)
        .task {
            _ = await recorder.requestMicrophoneAccess()
        }
    }

    private var header: some View {
        HStack(spacing: 10) {
            Circle()
                .fill(statusColor)
                .frame(width: 8, height: 8)
                .shadow(color: statusColor.opacity(0.55), radius: recorder.isRecording ? 6 : 0)

            VStack(alignment: .leading, spacing: 2) {
                Text("Custom STT")
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.92))

                Text(statusText)
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.45))
            }

            Spacer()

            Button {
                openSettingsWindow()
            } label: {
                Image(systemName: "gearshape")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.white.opacity(0.45))
                    .frame(width: 28, height: 28)
            }
            .buttonStyle(.plain)
        }
    }

    private var controls: some View {
        HStack(spacing: 10) {
            Button {
                Task { await toggleRecording() }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: recorder.isRecording ? "stop.fill" : "mic.fill")
                    Text(recordButtonTitle)
                }
                .font(.system(.body, design: .rounded).weight(.semibold))
                .foregroundStyle(.white)
                .frame(minWidth: 112, minHeight: 38)
                .background(recordButtonColor, in: RoundedRectangle(cornerRadius: 11, style: .continuous))
            }
            .buttonStyle(.plain)
            .keyboardShortcut(.space, modifiers: [])
            .disabled(transcriber.isTranscribing)
            .opacity(transcriber.isTranscribing ? 0.55 : 1)

            Text(timingText)
                .font(.system(.caption, design: .monospaced).weight(.medium))
                .foregroundStyle(.white.opacity(0.48))

            Spacer()

            Button(copied ? "Copied" : "Copy") {
                copyTranscript()
            }
            .buttonStyle(MinimalButtonStyle())
            .disabled(transcriber.transcript.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

            Button("Clear") {
                transcriber.clearTranscript()
                copied = false
            }
            .buttonStyle(MinimalButtonStyle())
            .disabled(transcriber.transcript.isEmpty)
        }
    }

    private var transcriptBox: some View {
        TextEditor(text: $transcriber.transcript)
            .font(.system(.body, design: .rounded))
            .foregroundStyle(.white.opacity(0.88))
            .scrollContentBackground(.hidden)
            .padding(10)
            .background(Color.black.opacity(0.18), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(Color.white.opacity(0.055), lineWidth: 1)
            )
            .frame(minHeight: 112)
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: 5) {
            if let errorMessage = recorder.errorMessage ?? transcriber.errorMessage ?? hotKeyError {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundStyle(.red.opacity(0.95))
                    .fixedSize(horizontal: false, vertical: true)
            } else if let lastRecordingURL {
                Text(lastRecordingURL.lastPathComponent)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .font(.caption2)
                    .foregroundStyle(.white.opacity(0.30))
            } else {
                Text("Space or ⌘⌥M to start or stop")
                    .font(.caption2)
                    .foregroundStyle(.white.opacity(0.30))
            }
        }
        .frame(minHeight: 16, alignment: .leading)
    }

    private var statusColor: Color {
        if recorder.isRecording { return .red }
        if transcriber.isTranscribing { return .blue }
        return .green.opacity(0.75)
    }

    private var statusText: String {
        if recorder.isRecording { return "Recording" }
        if transcriber.isTranscribing { return "Transcribing" }
        return "Ready · ⌘⌥M"
    }

    private var recordButtonTitle: String {
        if recorder.isRecording { return "Stop" }
        if transcriber.isTranscribing { return "Wait" }
        return "Record"
    }

    private var recordButtonColor: Color {
        if recorder.isRecording { return .red.opacity(0.92) }
        return Color.white.opacity(0.105)
    }

    private var timingText: String {
        if transcriber.isTranscribing {
            return "whisper \(Self.formatSeconds(transcriber.currentTranscriptionElapsed))"
        }

        if let lastTranscriptionDuration = transcriber.lastTranscriptionDuration {
            return "record \(Self.formatClock(recorder.elapsedSeconds))  ·  whisper \(Self.formatSeconds(lastTranscriptionDuration))"
        }

        return "record \(Self.formatClock(recorder.elapsedSeconds))"
    }

    private func openSettingsWindow() {
        NSApplication.shared.activate(ignoringOtherApps: true)
        if !NSApplication.shared.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil) {
            NSApplication.shared.sendAction(Selector(("showPreferencesWindow:")), to: nil, from: nil)
        }
    }

    private func registerGlobalHotKey() {
        guard hotKey == nil else { return }

        let shortcut = GlobalHotKey {
            Task { await toggleRecording() }
        }

        do {
            try shortcut.registerCommandOptionM()
            hotKey = shortcut
        } catch {
            hotKeyError = error.localizedDescription
        }
    }

    private func toggleRecording() async {
        if recorder.isRecording {
            do {
                let audioURL = try recorder.stopRecording()
                lastRecordingURL = audioURL
                await transcriber.transcribe(audioURL: audioURL)
                copyTranscript()
            } catch {
                recorder.errorMessage = error.localizedDescription
            }
        } else {
            await recorder.startRecording()
            copied = false
        }
    }

    private func copyTranscript() {
        let text = transcriber.transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        copied = true
    }

    private static func formatClock(_ seconds: TimeInterval) -> String {
        let totalSeconds = max(0, Int(seconds.rounded(.down)))
        return String(format: "%02d:%02d", totalSeconds / 60, totalSeconds % 60)
    }

    private static func formatSeconds(_ seconds: TimeInterval) -> String {
        if seconds < 60 {
            return String(format: "%.1fs", seconds)
        }
        let minutes = Int(seconds / 60)
        let remainingSeconds = seconds - Double(minutes * 60)
        return String(format: "%d:%04.1f", minutes, remainingSeconds)
    }
}

private struct MinimalButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.caption.weight(.medium))
            .foregroundStyle(.white.opacity(0.58))
            .padding(.horizontal, 8)
            .frame(height: 28)
            .background(configuration.isPressed ? Color.white.opacity(0.08) : Color.clear, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}
