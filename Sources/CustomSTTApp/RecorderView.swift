import AppKit
import SwiftUI

struct RecorderView: View {
    @StateObject private var recorder: AudioRecorder
    @StateObject private var transcriber: WhisperTranscriber
    @ObservedObject private var settings: AppSettings
    @State private var lastRecordingURL: URL?
    @State private var copied = false
    @State private var hotKey: GlobalHotKey?
    @State private var hotKeyError: String?

    init(recorder: AudioRecorder, transcriber: WhisperTranscriber, settings: AppSettings) {
        _recorder = StateObject(wrappedValue: recorder)
        _transcriber = StateObject(wrappedValue: transcriber)
        _settings = ObservedObject(wrappedValue: settings)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            header
            WaveformView(levels: recorder.levels, isRecording: recorder.isRecording)
            controls
            transcriptionCard
            footer
        }
        .padding(.top, 52)
        .padding(.horizontal, 40)
        .padding(.bottom, 34)
        .frame(minWidth: 600, minHeight: 520)
        .background(Color(red: 0.065, green: 0.067, blue: 0.078))
        .preferredColorScheme(.dark)
        .onAppear(perform: registerGlobalHotKey)
        .task {
            _ = await recorder.requestMicrophoneAccess()
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
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
            .pointingHandCursor()
        }
    }

    private var controls: some View {
        HStack(spacing: 14) {
            Button {
                Task { await handlePrimaryAction() }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: recordButtonIcon)
                    Text(recordButtonTitle)
                }
                .font(.system(.body, design: .rounded).weight(.semibold))
                .foregroundStyle(.white)
                .frame(minWidth: 136, minHeight: 44)
                .background(recordButtonColor, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
            .buttonStyle(.plain)
            .keyboardShortcut(.space, modifiers: [])
            .disabled(transcriber.isStoppingTranscription)
            .opacity(transcriber.isStoppingTranscription ? 0.55 : 1)
            .pointingHandCursor(!transcriber.isStoppingTranscription)

            Text(timingText)
                .font(.system(.caption, design: .monospaced).weight(.medium))
                .foregroundStyle(.white.opacity(0.48))

            Spacer()

            Button(copied ? "Copied" : "Copy") {
                copyTranscript()
            }
            .buttonStyle(MinimalButtonStyle())
            .disabled(transcriber.transcript.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            .pointingHandCursor(!transcriber.transcript.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

            Button("Clear") {
                transcriber.clearTranscript()
                copied = false
            }
            .buttonStyle(MinimalButtonStyle())
            .disabled(transcriber.transcript.isEmpty && transcriber.errorMessage == nil)
            .pointingHandCursor(!(transcriber.transcript.isEmpty && transcriber.errorMessage == nil))
        }
    }

    private var transcriptionCard: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .top, spacing: 14) {
                ZStack {
                    Circle()
                        .fill(Color(red: 0.72, green: 0.50, blue: 1.0).opacity(0.16))
                    Image(systemName: "cpu")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Color(red: 0.72, green: 0.50, blue: 1.0))
                }
                .frame(width: 36, height: 36)

                VStack(alignment: .leading, spacing: 4) {
                    Text("whisper.cpp")
                        .font(.system(.subheadline, design: .rounded).weight(.semibold))
                        .foregroundStyle(.white.opacity(0.92))

                    HStack(spacing: 6) {
                        Text(transcriber.modelDescription)
                            .font(.caption2)
                            .foregroundStyle(.white.opacity(0.36))
                            .lineLimit(1)
                            .truncationMode(.middle)

                        SourceLinkButton(
                            kind: .github,
                            url: SourceLinks.whisperCppGitHubURL,
                            help: "Open whisper.cpp source on GitHub"
                        )

                        SourceLinkButton(
                            kind: .huggingFace,
                            url: SourceLinks.whisperCppHuggingFaceURL,
                            help: "Open whisper.cpp GGML models on Hugging Face"
                        )
                    }
                }

                Spacer()

                if let detectedLanguageDisplay = transcriber.detectedLanguageDisplay {
                    languagePill(detectedLanguageDisplay)
                }

                statusPill
            }

            HStack(alignment: .firstTextBaseline, spacing: 8) {
                TranscriptionTimerText(
                    startedAt: transcriber.transcriptionStartedAt,
                    elapsed: transcriber.currentTranscriptionElapsed,
                    finalDuration: transcriber.lastTranscriptionDuration,
                    isActive: transcriber.isTranscribing
                )

                Text(transcriber.status.isActive ? "live" : transcriber.status.statusLabel)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(transcriber.status.statusColor)

                Spacer()
            }

            TextEditor(text: $transcriber.transcript)
                .font(.system(.body, design: .rounded))
                .foregroundStyle(.white.opacity(0.88))
                .scrollContentBackground(.hidden)
                .padding(14)
                .background(Color.black.opacity(0.18), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(Color.white.opacity(0.055), lineWidth: 1)
                )
                .frame(minHeight: 150)
        }
        .padding(24)
        .background(cardBackground)
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(Color(red: 0.72, green: 0.50, blue: 1.0).opacity(transcriber.status.isActive ? 0.34 : 0.16), lineWidth: 1)
        )
        .shadow(color: Color(red: 0.72, green: 0.50, blue: 1.0).opacity(transcriber.status.isActive ? 0.16 : 0.06), radius: 18, y: 8)
    }

    private func languagePill(_ text: String) -> some View {
        Text(text)
            .font(.caption2.weight(.semibold))
            .foregroundStyle(.white.opacity(0.70))
            .padding(.horizontal, 10)
            .frame(height: 24)
            .background(Color.white.opacity(0.08), in: Capsule(style: .continuous))
    }

    private var statusPill: some View {
        HStack(spacing: 5) {
            Circle()
                .fill(transcriber.status.statusColor)
                .frame(width: 6, height: 6)
            Text(transcriber.status.statusLabel)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(transcriber.status.statusColor)
        }
        .padding(.horizontal, 10)
        .frame(height: 24)
        .background(transcriber.status.statusColor.opacity(0.11), in: Capsule(style: .continuous))
    }

    private var cardBackground: some View {
        RoundedRectangle(cornerRadius: 20, style: .continuous)
            .fill(
                LinearGradient(
                    colors: [
                        Color(red: 0.72, green: 0.50, blue: 1.0).opacity(0.13),
                        Color.white.opacity(0.045),
                        Color.black.opacity(0.10)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: 5) {
            if let errorMessage = recorder.errorMessage ?? transcriber.errorMessage ?? hotKeyError {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundStyle(transcriber.isStoppingTranscription ? .white.opacity(0.48) : .red.opacity(0.95))
                    .fixedSize(horizontal: false, vertical: true)
            } else if let lastRecordingURL {
                Text(lastRecordingURL.lastPathComponent)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .font(.caption2)
                    .foregroundStyle(.white.opacity(0.30))
            } else {
                Text("Space or ⌘⌥M to start, stop, or cancel")
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
        if transcriber.isTranscribing { return "Transcribing with whisper.cpp" }
        return "Ready · whisper.cpp · ⌘⌥M"
    }

    private var recordButtonTitle: String {
        if recorder.isRecording { return "Stop" }
        if transcriber.isStoppingTranscription { return "Stopping" }
        if transcriber.isTranscribing { return "Stop" }
        return "Record"
    }

    private var recordButtonIcon: String {
        if recorder.isRecording || transcriber.isTranscribing { return "stop.fill" }
        return "mic.fill"
    }

    private var recordButtonColor: Color {
        if recorder.isRecording || transcriber.isTranscribing { return .red.opacity(0.92) }
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

    private func handlePrimaryAction() async {
        if transcriber.isTranscribing {
            transcriber.stopTranscription()
            return
        }

        await toggleRecording()
    }

    private func toggleRecording() async {
        if transcriber.isTranscribing {
            transcriber.stopTranscription()
            return
        }

        if recorder.isRecording {
            do {
                let audioURL = try recorder.stopRecording()
                lastRecordingURL = audioURL
                if await transcriber.transcribe(audioURL: audioURL) {
                    copyTranscript()
                }
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

private struct TranscriptionTimerText: View {
    let startedAt: Date?
    let elapsed: TimeInterval
    let finalDuration: TimeInterval?
    let isActive: Bool

    var body: some View {
        TimelineView(.periodic(from: startedAt ?? .now, by: 0.1)) { timeline in
            Text(formatRunSeconds(elapsed(at: timeline.date)))
                .font(.system(size: 34, weight: .bold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(.white.opacity(0.96))
        }
    }

    private func elapsed(at date: Date) -> TimeInterval {
        if isActive, let startedAt {
            return max(0, date.timeIntervalSince(startedAt))
        }
        return finalDuration ?? elapsed
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

private extension TranscriptionStatus {
    var statusLabel: String {
        switch self {
        case .idle:
            return "Ready"
        case .preparing:
            return "Preparing"
        case .running:
            return "Running"
        case .completed:
            return "Done"
        case .failed:
            return "Failed"
        case .stopped:
            return "Stopped"
        }
    }

    var statusColor: Color {
        switch self {
        case .idle:
            return .white.opacity(0.48)
        case .preparing:
            return .yellow.opacity(0.90)
        case .running:
            return .blue.opacity(0.92)
        case .completed:
            return .green.opacity(0.90)
        case .failed:
            return .orange.opacity(0.95)
        case .stopped:
            return .white.opacity(0.54)
        }
    }
}

private func formatRunSeconds(_ seconds: TimeInterval) -> String {
    if seconds < 60 {
        return String(format: "%.1fs", seconds)
    }
    let minutes = Int(seconds / 60)
    let remainingSeconds = seconds - Double(minutes * 60)
    return String(format: "%d:%04.1f", minutes, remainingSeconds)
}
