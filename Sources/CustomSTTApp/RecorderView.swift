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
        VStack(alignment: .leading, spacing: 16) {
            header
            WaveformView(levels: recorder.levels, isRecording: recorder.isRecording)
            controls
            comparisonView
            footer
        }
        .padding(.top, 28)
        .padding(.horizontal, 24)
        .padding(.bottom, 22)
        .frame(minWidth: 680, minHeight: 520)
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
                Text(settings.useFasterWhisper ? "race · 2 models" : "race · cpp only")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(settings.useFasterWhisper ? .blue.opacity(0.92) : .white.opacity(0.50))
                    .padding(.horizontal, 10)
                    .frame(height: 24)
                    .background(Color.white.opacity(settings.useFasterWhisper ? 0.10 : 0.04), in: Capsule(style: .continuous))
                    .overlay(
                        Capsule(style: .continuous)
                            .stroke(Color.white.opacity(settings.useFasterWhisper ? 0.14 : 0.06), lineWidth: 1)
                    )
            }
            .buttonStyle(.plain)
            .disabled(transcriber.isTranscribing)
            .opacity(transcriber.isTranscribing ? 0.55 : 1)
            .help("Open Settings to choose comparison models")

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
                Task { await handlePrimaryAction() }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: recordButtonIcon)
                    Text(recordButtonTitle)
                }
                .font(.system(.body, design: .rounded).weight(.semibold))
                .foregroundStyle(.white)
                .frame(minWidth: 112, minHeight: 38)
                .background(recordButtonColor, in: RoundedRectangle(cornerRadius: 11, style: .continuous))
            }
            .buttonStyle(.plain)
            .keyboardShortcut(.space, modifiers: [])
            .disabled(transcriber.isStoppingTranscription)
            .opacity(transcriber.isStoppingTranscription ? 0.55 : 1)

            Text(timingText)
                .font(.system(.caption, design: .monospaced).weight(.medium))
                .foregroundStyle(.white.opacity(0.48))

            Spacer()

            Button(copied ? "Copied" : "Copy all") {
                copyTranscript()
            }
            .buttonStyle(MinimalButtonStyle())
            .disabled(!transcriber.runs.contains { $0.hasTranscript })

            Button("Clear") {
                transcriber.clearTranscript()
                copied = false
            }
            .buttonStyle(MinimalButtonStyle())
            .disabled(!transcriber.runs.contains { $0.hasTranscript } && transcriber.errorMessage == nil)
        }
    }

    private var comparisonView: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "timer")
                    .foregroundStyle(.white.opacity(0.45))
                Text("Model race")
                    .font(.system(.subheadline, design: .rounded).weight(.semibold))
                    .foregroundStyle(.white.opacity(0.88))
                Text("parallel transcription after you stop recording")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.34))

                Spacer()

                if transcriber.isTranscribing {
                    ProgressView()
                        .controlSize(.small)
                        .scaleEffect(0.72)
                }
            }

            LazyVGrid(columns: comparisonGridColumns, alignment: .leading, spacing: 12) {
                ForEach(transcriber.runs) { run in
                    TranscriptionRunCard(run: run) {
                        copyRun(run)
                    }
                }
            }
        }
    }

    private var comparisonGridColumns: [GridItem] {
        let count = max(1, min(2, transcriber.runs.count))
        return Array(repeating: GridItem(.flexible(), spacing: 12, alignment: .top), count: count)
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
        if transcriber.isTranscribing { return "Transcribing · model race" }
        return settings.useFasterWhisper ? "Ready · compare cpp + faster · ⌘⌥M" : "Ready · cpp · ⌘⌥M"
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
            return "race \(Self.formatSeconds(transcriber.currentTranscriptionElapsed))"
        }

        if let lastTranscriptionDuration = transcriber.lastTranscriptionDuration {
            return "record \(Self.formatClock(recorder.elapsedSeconds))  ·  race \(Self.formatSeconds(lastTranscriptionDuration))"
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
        let text = transcriber.combinedTranscript().trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        copied = true
    }

    private func copyRun(_ run: TranscriptionRun) {
        let text = transcriber.copyText(for: run.id)
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

private struct TranscriptionRunCard: View {
    let run: TranscriptionRun
    let copyAction: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 10) {
                ZStack {
                    Circle()
                        .fill(run.backend.tintColor.opacity(0.16))
                    Image(systemName: run.backend.symbolName)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(run.backend.tintColor)
                }
                .frame(width: 30, height: 30)

                VStack(alignment: .leading, spacing: 3) {
                    Text(run.title)
                        .font(.system(.subheadline, design: .rounded).weight(.semibold))
                        .foregroundStyle(.white.opacity(0.92))
                    HStack(spacing: 6) {
                        Text(run.modelDescription)
                            .font(.caption2)
                            .foregroundStyle(.white.opacity(0.36))
                            .lineLimit(1)
                            .truncationMode(.middle)

                        SourceLinkButton(
                            kind: .github,
                            url: run.backend.repositoryURL,
                            help: "Open \(run.title) source on GitHub"
                        )

                        if let huggingFaceURL = run.huggingFaceURL {
                            SourceLinkButton(
                                kind: .huggingFace,
                                url: huggingFaceURL,
                                help: "Open \(run.modelDescription) on Hugging Face"
                            )
                        }
                    }
                }

                Spacer()

                statusPill
            }

            HStack(alignment: .firstTextBaseline, spacing: 8) {
                RunTimerText(run: run)

                Text(run.status.isActive ? "live" : run.status.statusLabel)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(run.status.statusColor)

                Spacer()
            }

            transcriptPreview

            HStack {
                if run.status == .completed, run.hasTranscript {
                    Label("Done", systemImage: "checkmark.circle.fill")
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(.green.opacity(0.85))
                } else if run.status == .running || run.status == .preparing {
                    Label("Running", systemImage: "bolt.horizontal.circle.fill")
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(run.backend.tintColor.opacity(0.92))
                } else if run.status == .failed {
                    Label("Needs attention", systemImage: "exclamationmark.triangle.fill")
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(.orange.opacity(0.92))
                }

                Spacer()

                Button("Copy") {
                    copyAction()
                }
                .buttonStyle(MinimalButtonStyle())
                .disabled(!run.hasTranscript)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, minHeight: 250, alignment: .topLeading)
        .background(cardBackground)
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(run.backend.tintColor.opacity(run.status.isActive ? 0.34 : 0.16), lineWidth: 1)
        )
        .shadow(color: run.backend.tintColor.opacity(run.status.isActive ? 0.16 : 0.06), radius: 18, y: 8)
    }

    private var statusPill: some View {
        HStack(spacing: 5) {
            Circle()
                .fill(run.status.statusColor)
                .frame(width: 6, height: 6)
            Text(run.status.statusLabel)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(run.status.statusColor)
        }
        .padding(.horizontal, 8)
        .frame(height: 22)
        .background(run.status.statusColor.opacity(0.11), in: Capsule(style: .continuous))
    }

    private var transcriptPreview: some View {
        ScrollView {
            Text(previewText)
                .font(.system(.body, design: .rounded))
                .foregroundStyle(previewColor)
                .frame(maxWidth: .infinity, alignment: .leading)
                .textSelection(.enabled)
        }
        .frame(minHeight: 92, maxHeight: 120)
        .padding(10)
        .background(Color.black.opacity(0.16), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color.white.opacity(0.055), lineWidth: 1)
        )
    }

    private var previewText: String {
        if run.hasTranscript {
            return run.transcript
        }

        if let errorMessage = run.errorMessage, !errorMessage.isEmpty {
            return errorMessage
        }

        switch run.status {
        case .idle:
            return "Ready to race this model after your next recording."
        case .preparing:
            return "Preparing audio…"
        case .running:
            return "Listening to the recording and transcribing…"
        case .completed:
            return "No speech detected."
        case .failed:
            return "No result."
        case .stopped:
            return "Stopped before this model finished."
        }
    }

    private var previewColor: Color {
        if run.hasTranscript { return .white.opacity(0.84) }
        if run.status == .failed { return .orange.opacity(0.92) }
        if run.status == .stopped { return .white.opacity(0.45) }
        return .white.opacity(0.38)
    }

    private var cardBackground: some View {
        RoundedRectangle(cornerRadius: 20, style: .continuous)
            .fill(
                LinearGradient(
                    colors: [
                        run.backend.tintColor.opacity(0.13),
                        Color.white.opacity(0.045),
                        Color.black.opacity(0.10)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
    }
}

private struct RunTimerText: View {
    let run: TranscriptionRun

    var body: some View {
        TimelineView(.periodic(from: run.startedAt ?? .now, by: 0.1)) { timeline in
            Text(formatRunSeconds(elapsed(at: timeline.date)))
                .font(.system(size: 34, weight: .bold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(.white.opacity(0.96))
                .animation(.linear(duration: 0.08), value: elapsed(at: timeline.date))
        }
    }

    private func elapsed(at date: Date) -> TimeInterval {
        if let duration = run.duration, !run.status.isActive {
            return duration
        }

        if run.status.isActive, let startedAt = run.startedAt {
            return max(0, date.timeIntervalSince(startedAt))
        }

        return run.elapsed
    }
}

private enum SourceLinkKind {
    case github
    case huggingFace

    var foregroundColor: Color {
        switch self {
        case .github:
            return .white.opacity(0.84)
        case .huggingFace:
            return Color(red: 1.0, green: 0.80, blue: 0.24)
        }
    }
}

private struct SourceLinkButton: View {
    let kind: SourceLinkKind
    let url: URL
    let help: String

    var body: some View {
        Button {
            NSWorkspace.shared.open(url)
        } label: {
            icon
                .frame(width: 24, height: 20)
                .background(Color.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .stroke(Color.white.opacity(0.10), lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
        .help(help)
    }

    @ViewBuilder
    private var icon: some View {
        switch kind {
        case .github:
            GitHubMark()
                .fill(kind.foregroundColor)
                .frame(width: 13, height: 13)
        case .huggingFace:
            Text("🤗")
                .font(.system(size: 12))
        }
    }
}

private struct GitHubMark: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let width = rect.width
        let height = rect.height
        let centerX = rect.midX
        let headRadius = min(width, height) * 0.38
        let headCenter = CGPoint(x: centerX, y: rect.minY + height * 0.53)

        path.addEllipse(in: CGRect(
            x: headCenter.x - headRadius,
            y: headCenter.y - headRadius,
            width: headRadius * 2,
            height: headRadius * 2
        ))

        path.move(to: CGPoint(x: rect.minX + width * 0.20, y: rect.minY + height * 0.36))
        path.addLine(to: CGPoint(x: rect.minX + width * 0.28, y: rect.minY + height * 0.05))
        path.addLine(to: CGPoint(x: rect.minX + width * 0.48, y: rect.minY + height * 0.25))
        path.closeSubpath()

        path.move(to: CGPoint(x: rect.maxX - width * 0.20, y: rect.minY + height * 0.36))
        path.addLine(to: CGPoint(x: rect.maxX - width * 0.28, y: rect.minY + height * 0.05))
        path.addLine(to: CGPoint(x: rect.maxX - width * 0.48, y: rect.minY + height * 0.25))
        path.closeSubpath()

        path.addRoundedRect(in: CGRect(
            x: centerX - width * 0.15,
            y: rect.maxY - height * 0.26,
            width: width * 0.30,
            height: height * 0.22
        ), cornerSize: CGSize(width: width * 0.07, height: height * 0.07))

        return path
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

private extension TranscriptionBackend {
    var tintColor: Color {
        switch self {
        case .whisperCpp:
            return Color(red: 0.72, green: 0.50, blue: 1.0)
        case .fasterWhisper:
            return Color(red: 0.25, green: 0.66, blue: 1.0)
        }
    }

    var symbolName: String {
        switch self {
        case .whisperCpp:
            return "cpu"
        case .fasterWhisper:
            return "bolt.fill"
        }
    }

    var repositoryURL: URL {
        switch self {
        case .whisperCpp:
            return URL(string: "https://github.com/ggml-org/whisper.cpp")!
        case .fasterWhisper:
            return URL(string: "https://github.com/SYSTRAN/faster-whisper")!
        }
    }
}

private extension TranscriptionRun {
    var huggingFaceURL: URL? {
        switch backend {
        case .whisperCpp:
            return URL(string: "https://huggingface.co/ggerganov/whisper.cpp")
        case .fasterWhisper:
            return fasterWhisperHuggingFaceURL
        }
    }

    private var fasterWhisperHuggingFaceURL: URL? {
        let model = modelDescription.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !model.isEmpty, !model.hasPrefix("/"), !model.hasPrefix("./"), !model.hasPrefix("../") else {
            return URL(string: "https://huggingface.co/Systran")
        }

        let repoID: String
        if model.contains("/") {
            repoID = model
        } else {
            repoID = Self.fasterWhisperModelRepos[model] ?? "Systran/faster-whisper-\(model)"
        }

        return URL(string: "https://huggingface.co/\(repoID)")
    }

    private static let fasterWhisperModelRepos = [
        "tiny": "Systran/faster-whisper-tiny",
        "tiny.en": "Systran/faster-whisper-tiny.en",
        "base": "Systran/faster-whisper-base",
        "base.en": "Systran/faster-whisper-base.en",
        "small": "Systran/faster-whisper-small",
        "small.en": "Systran/faster-whisper-small.en",
        "medium": "Systran/faster-whisper-medium",
        "medium.en": "Systran/faster-whisper-medium.en",
        "large-v1": "Systran/faster-whisper-large-v1",
        "large-v2": "Systran/faster-whisper-large-v2",
        "large-v3": "Systran/faster-whisper-large-v3",
        "large": "Systran/faster-whisper-large-v3",
        "distil-large-v3": "Systran/faster-distil-large-v3",
        "large-v3-turbo": "mobiuslabsgmbh/faster-whisper-large-v3-turbo",
        "turbo": "mobiuslabsgmbh/faster-whisper-large-v3-turbo"
    ]
}

private extension TranscriptionRunStatus {
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
