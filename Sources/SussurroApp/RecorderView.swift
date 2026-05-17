import AppKit
import SwiftUI

struct RecorderView: View {
    @StateObject private var recorder: AudioRecorder
    @StateObject private var transcriber: WhisperTranscriber
    @StateObject private var recordingHistory = RecordingHistoryStore()
    @ObservedObject private var settings: AppSettings
    @State private var recordingMode: RecordingMode = .dictation
    @State private var lastRecordingURL: URL?
    @State private var retryModelSelectionID = RetryModelOption.currentID
    @State private var showHistoryPopover = false
    @State private var copied = false
    @State private var historyError: String?
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
            AudioInputPicker(settings: settings, isDisabled: isRecorderConfigurationDisabled, compact: true)
            recordingModePicker
            WaveformView(levels: recorder.levels, isRecording: recorder.isRecording)
            controls
            transcriptionCard
            footer
        }
        .padding(.top, 28)
        .padding(.horizontal, 32)
        .padding(.bottom, 28)
        .frame(minWidth: 640, minHeight: 620)
        .background(Color(red: 0.065, green: 0.067, blue: 0.078))
        .preferredColorScheme(.dark)
        .onAppear {
            registerGlobalHotKey()
            recordingHistory.reload()
        }
        .task {
            _ = await recorder.requestMicrophoneAccess()
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            appLogo

            VStack(alignment: .leading, spacing: 2) {
                Text("Sussurro")
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.92))

                Text(statusText)
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.45))
            }

            Spacer()

            historyButton

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

    private var historyButton: some View {
        Button {
            recordingHistory.reload()
            showHistoryPopover.toggle()
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "clock.arrow.circlepath")
                    .font(.system(size: 12, weight: .semibold))
                Text("History")
                    .font(.caption.weight(.semibold))
                if !recordingHistory.recordings.isEmpty {
                    Text("\(recordingHistory.recordings.count)")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(.white.opacity(0.64))
                        .padding(.horizontal, 5)
                        .frame(height: 16)
                        .background(Color.white.opacity(0.08), in: Capsule(style: .continuous))
                }
            }
            .foregroundStyle(.white.opacity(0.62))
            .padding(.horizontal, 10)
            .frame(height: 28)
        }
        .buttonStyle(HeaderPillButtonStyle(isSelected: showHistoryPopover))
        .popover(isPresented: $showHistoryPopover, arrowEdge: .bottom) {
            RecentAudioPopover(
                recordings: recordingHistory.recordings,
                errorMessage: recordingHistory.errorMessage,
                retryModelOptions: retryModelOptions,
                retryModelSelectionID: $retryModelSelectionID,
                isRetryDisabled: isRetryDisabled,
                refresh: { recordingHistory.reload() },
                openFolder: { NSWorkspace.shared.open(AppPaths.recordingsDirectory) },
                reveal: { recording in NSWorkspace.shared.activateFileViewerSelecting([recording.url]) },
                retry: { recording in Task { await retryTranscription(recording) } }
            )
            .frame(width: 520, height: 520)
        }
        .pointingHandCursor()
    }

    @ViewBuilder
    private var appLogo: some View {
        if let logo = AppLogoImage.logo {
            Image(nsImage: logo)
                .resizable()
                .interpolation(.high)
                .scaledToFill()
                .frame(width: 34, height: 34)
                .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .stroke(Color.white.opacity(0.16), lineWidth: 1)
                )
                .overlay(alignment: .bottomTrailing) {
                    Circle()
                        .fill(statusColor)
                        .frame(width: 8, height: 8)
                        .overlay(Circle().stroke(Color(red: 0.065, green: 0.067, blue: 0.078), lineWidth: 1.5))
                        .shadow(color: statusColor.opacity(0.55), radius: recorder.isRecording ? 6 : 0)
                }
        } else {
            Circle()
                .fill(statusColor)
                .frame(width: 8, height: 8)
                .shadow(color: statusColor.opacity(0.55), radius: recorder.isRecording ? 6 : 0)
        }
    }

    private var recordingModePicker: some View {
        HStack(spacing: 10) {
            Image(systemName: recordingMode == .meeting ? "person.2.wave.2.fill" : "text.quote")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.white.opacity(0.50))

            Text("Mode")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.white.opacity(0.42))

            Picker("Recording mode", selection: $recordingMode) {
                ForEach(RecordingMode.allCases) { mode in
                    Text(mode.title).tag(mode)
                }
            }
            .labelsHidden()
            .pickerStyle(.segmented)
            .controlSize(.small)
            .frame(width: 190)
            .disabled(isRecorderConfigurationDisabled)

            Text(recordingMode.detail)
                .font(.caption2)
                .foregroundStyle(.white.opacity(0.38))
                .lineLimit(1)

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .frame(height: 38)
        .background(Color.white.opacity(recordingMode == .meeting ? 0.065 : 0.045), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color.white.opacity(recordingMode == .meeting ? 0.10 : 0.055), lineWidth: 1)
        )
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
                .frame(minWidth: recordingMode == .meeting ? 164 : 136, minHeight: 44)
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
                historyError = nil
                copied = false
            }
            .buttonStyle(MinimalButtonStyle())
            .disabled(transcriber.transcript.isEmpty && transcriber.errorMessage == nil)
            .pointingHandCursor(!(transcriber.transcript.isEmpty && transcriber.errorMessage == nil))
        }
    }

    private var transcriptionCard: some View {
        VStack(alignment: .leading, spacing: 14) {
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
                .frame(minHeight: 130)
        }
        .padding(20)
        .background(cardBackground)
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(Color.white.opacity(transcriber.status.isActive ? 0.14 : 0.08), lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.24), radius: 18, y: 8)
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
            .fill(Color.white.opacity(0.045))
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: 5) {
            if let errorMessage = recorder.errorMessage ?? transcriber.errorMessage ?? historyError ?? recordingHistory.errorMessage ?? hotKeyError {
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
                Text(idleFooterText)
                    .font(.caption2)
                    .foregroundStyle(.white.opacity(0.30))
            }
        }
        .frame(minHeight: 16, alignment: .leading)
    }

    private var idleFooterText: String {
        if recordingMode == .meeting {
            return "Meeting mode records mic + system audio locally. Use headphones to reduce speaker bleed."
        }
        return "Space or ⌘⌥M to start, stop, or cancel"
    }

    private var statusColor: Color {
        if recorder.isRecording { return .red }
        if transcriber.isTranscribing { return .blue }
        return .green.opacity(0.75)
    }

    private var statusText: String {
        if recorder.isRecording { return recordingMode == .meeting ? "Recording meeting" : "Recording" }
        if transcriber.isTranscribing { return "Transcribing locally with whisper.cpp" }
        return recordingMode == .meeting ? "Ready · meeting mode · local" : "Ready · whisper.cpp · ⌘⌥M"
    }

    private var recordButtonTitle: String {
        if recorder.isRecording { return "Stop" }
        if transcriber.isStoppingTranscription { return "Stopping" }
        if transcriber.isTranscribing { return "Stop" }
        return recordingMode == .meeting ? "Start Meeting" : "Record"
    }

    private var recordButtonIcon: String {
        if recorder.isRecording || transcriber.isTranscribing { return "stop.fill" }
        return recordingMode == .meeting ? "person.2.wave.2.fill" : "mic.fill"
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

    private var retryModelOptions: [RetryModelOption] {
        let currentModelPath = settings.expandedModelPath
        var options = [
            RetryModelOption(
                id: RetryModelOption.currentID,
                title: "Current · \(Self.modelName(for: currentModelPath))",
                modelPath: nil
            )
        ]

        for preset in WhisperModelPreset.allCases {
            let presetPath = AppPaths.modelURL(for: preset).path
            guard presetPath != currentModelPath else { continue }
            guard FileManager.default.fileExists(atPath: presetPath) else { continue }

            options.append(
                RetryModelOption(
                    id: presetPath,
                    title: preset.displayName,
                    modelPath: presetPath
                )
            )
        }

        return options
    }

    private var isRecorderConfigurationDisabled: Bool {
        recorder.isRecording || transcriber.isTranscribing || transcriber.isStoppingTranscription
    }

    private var isRetryDisabled: Bool {
        isRecorderConfigurationDisabled
    }

    private func openSettingsWindow() {
        SettingsWindowController.shared.show()
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
                let recordedAudio = try await recorder.stopRecording()
                lastRecordingURL = recordedAudio.primaryURL
                historyError = nil
                recordingHistory.reload()
                if await transcriber.transcribe(recording: recordedAudio) {
                    saveTranscriptionHistory(for: recordedAudio.primaryURL)
                    copyTranscript()
                } else {
                    saveTranscriptionHistory(for: recordedAudio.primaryURL)
                }
            } catch {
                recorder.errorMessage = error.localizedDescription
            }
        } else {
            historyError = nil
            if recordingMode == .meeting {
                guard MeetingPermissionPrompter.ensureScreenCapturePermission() else {
                    recorder.errorMessage = "Meeting mode needs Screen & System Audio Recording permission before it can capture system audio."
                    return
                }
            }

            await recorder.startRecording(mode: recordingMode)
            if recordingMode == .meeting, !recorder.isRecording, let errorMessage = recorder.errorMessage {
                MeetingPermissionPrompter.showSystemAudioRecoveryPrompt(details: errorMessage)
            }
            copied = false
        }
    }

    private func retryTranscription(_ recording: RecordingHistoryEntry) async {
        guard !isRetryDisabled else { return }
        historyError = nil
        copied = false

        guard FileManager.default.fileExists(atPath: recording.url.path) else {
            historyError = "That recording no longer exists. Refreshing recent audio."
            recordingHistory.reload()
            return
        }

        lastRecordingURL = recording.url
        let modelPathOverride = selectedRetryModelPathOverride()
        if await transcriber.transcribe(audioURL: recording.url, modelPathOverride: modelPathOverride) {
            saveTranscriptionHistory(for: recording.url)
            copyTranscript()
        } else {
            saveTranscriptionHistory(for: recording.url)
        }
    }

    private func saveTranscriptionHistory(for audioURL: URL) {
        let transcript = transcriber.status == .completed
            ? transcriber.transcript.trimmingCharacters(in: .whitespacesAndNewlines)
            : nil
        recordingHistory.updateTranscription(
            audioURL: audioURL,
            transcript: transcript,
            status: transcriber.status.historyStatus,
            modelPath: transcriber.lastUsedModelPath,
            languageCode: transcriber.detectedLanguageCode,
            errorMessage: transcriber.errorMessage
        )
    }

    private func selectedRetryModelPathOverride() -> String? {
        guard retryModelSelectionID != RetryModelOption.currentID else { return nil }
        return retryModelOptions.first { $0.id == retryModelSelectionID }?.modelPath
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

    private static func modelName(for path: String) -> String {
        guard !path.isEmpty else { return "GGML model" }
        return URL(fileURLWithPath: path).lastPathComponent
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

private struct RecentAudioPopover: View {
    let recordings: [RecordingHistoryEntry]
    let errorMessage: String?
    let retryModelOptions: [RetryModelOption]
    @Binding var retryModelSelectionID: String
    let isRetryDisabled: Bool
    let refresh: () -> Void
    let openFolder: () -> Void
    let reveal: (RecordingHistoryEntry) -> Void
    let retry: (RecordingHistoryEntry) -> Void

    private var visibleRecordings: [RecordingHistoryEntry] {
        Array(recordings.prefix(12))
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().overlay(Color.white.opacity(0.06))
            modelPicker
            Divider().overlay(Color.white.opacity(0.06))
            content
        }
        .background(Color(red: 0.075, green: 0.077, blue: 0.090))
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 10) {
            VStack(alignment: .leading, spacing: 3) {
                Text("Previous audio")
                    .font(.system(.subheadline, design: .rounded).weight(.semibold))
                    .foregroundStyle(.white.opacity(0.92))

                Text("Review transcripts and retry with another model.")
                    .font(.caption2)
                    .foregroundStyle(.white.opacity(0.42))
            }

            Spacer()

            Button(action: openFolder) {
                Image(systemName: "folder")
            }
            .buttonStyle(PopoverIconButtonStyle())
            .accessibilityLabel("Open recordings folder")
            .pointingHandCursor()

            Button(action: refresh) {
                Image(systemName: "arrow.clockwise")
            }
            .buttonStyle(PopoverIconButtonStyle())
            .accessibilityLabel("Refresh previous audio")
            .pointingHandCursor()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
    }

    private var modelPicker: some View {
        HStack(spacing: 10) {
            Text("Model")
                .font(.caption.weight(.medium))
                .foregroundStyle(.white.opacity(0.46))
                .frame(width: 46, alignment: .leading)

            Picker("Retry model", selection: $retryModelSelectionID) {
                ForEach(retryModelOptions) { option in
                    Text(option.title).tag(option.id)
                }
            }
            .labelsHidden()
            .pickerStyle(.menu)
            .controlSize(.small)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(Color.black.opacity(0.08))
    }

    @ViewBuilder
    private var content: some View {
        if let errorMessage {
            Text(errorMessage)
                .font(.caption)
                .foregroundStyle(.orange.opacity(0.95))
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(16)
        } else if visibleRecordings.isEmpty {
            VStack(spacing: 10) {
                Image(systemName: "waveform.badge.plus")
                    .font(.system(size: 24, weight: .medium))
                    .foregroundStyle(.white.opacity(0.36))

                Text("No saved recordings yet")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.70))

                Text("Once you stop a recording, its audio and transcript appear here for review and retrying.")
                    .font(.caption)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.white.opacity(0.42))
                    .frame(maxWidth: 300)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(24)
        } else {
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(visibleRecordings) { recording in
                        RecentAudioRow(
                            recording: recording,
                            isRetryDisabled: isRetryDisabled,
                            retry: { retry(recording) },
                            reveal: { reveal(recording) }
                        )
                        if recording.id != visibleRecordings.last?.id {
                            Divider().overlay(Color.white.opacity(0.05))
                                .padding(.leading, 58)
                        }
                    }
                }
            }
        }
    }
}

private struct RecentAudioRow: View {
    let recording: RecordingHistoryEntry
    let isRetryDisabled: Bool
    let retry: () -> Void
    let reveal: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color.white.opacity(0.055))
                Image(systemName: "waveform")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.50))
            }
            .frame(width: 34, height: 34)

            VStack(alignment: .leading, spacing: 5) {
                Text(recording.fileName)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.84))
                    .lineLimit(1)
                    .truncationMode(.middle)

                Text(metadataText)
                    .font(.caption2)
                    .foregroundStyle(.white.opacity(0.36))
                    .lineLimit(1)

                Text(transcriptionText)
                    .font(.caption)
                    .foregroundStyle(transcriptionColor)
                    .lineLimit(recording.hasTranscript ? 4 : 2)
                    .textSelection(.enabled)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Button("Retry", action: retry)
                .buttonStyle(PopoverRetryButtonStyle())
                .disabled(isRetryDisabled)
                .pointingHandCursor(!isRetryDisabled)

            Button(action: reveal) {
                Image(systemName: "arrow.up.forward.square")
            }
            .buttonStyle(PopoverIconButtonStyle())
            .accessibilityLabel("Show \(recording.fileName) in Finder")
            .pointingHandCursor()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .accessibilityElement(children: .combine)
    }

    private var metadataText: String {
        var parts = [
            Self.formatHistoryDate(recording.createdAt),
            Self.formatFileSize(recording.byteCount),
            recording.status.displayTitle
        ]

        if let languageCode = recording.languageCode {
            parts.append(WhisperTranscriber.languageDisplayCode(for: languageCode))
        }

        if let modelPath = recording.modelPath {
            parts.append(Self.formatModelName(modelPath))
        }

        return parts.joined(separator: " · ")
    }

    private var transcriptionText: String {
        let transcript = recording.transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        if !transcript.isEmpty {
            return transcript
        }

        if let errorMessage = recording.errorMessage?.trimmingCharacters(in: .whitespacesAndNewlines), !errorMessage.isEmpty {
            return errorMessage
        }

        return "No transcript saved yet. Retry to generate one."
    }

    private var transcriptionColor: Color {
        if recording.hasTranscript { return .white.opacity(0.62) }
        if recording.status == .failed { return .orange.opacity(0.86) }
        return .white.opacity(0.34)
    }

    private static func formatHistoryDate(_ date: Date) -> String {
        date.formatted(date: .abbreviated, time: .shortened)
    }

    private static func formatFileSize(_ byteCount: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: byteCount, countStyle: .file)
    }

    private static func formatModelName(_ path: String) -> String {
        URL(fileURLWithPath: path).lastPathComponent
    }
}

private struct HeaderPillButtonStyle: ButtonStyle {
    let isSelected: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(backgroundColor(isPressed: configuration.isPressed), in: Capsule(style: .continuous))
            .overlay(
                Capsule(style: .continuous)
                    .stroke(Color.white.opacity(isSelected ? 0.14 : 0.07), lineWidth: 1)
            )
    }

    private func backgroundColor(isPressed: Bool) -> Color {
        if isPressed || isSelected {
            return Color.white.opacity(0.075)
        }
        return Color.white.opacity(0.035)
    }
}

private struct PopoverIconButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(.white.opacity(0.58))
            .frame(width: 26, height: 26)
            .background(configuration.isPressed ? Color.white.opacity(0.09) : Color.white.opacity(0.035), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .stroke(Color.white.opacity(0.06), lineWidth: 1)
            )
    }
}

private struct PopoverRetryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.caption.weight(.semibold))
            .foregroundStyle(.white.opacity(0.78))
            .padding(.horizontal, 10)
            .frame(height: 26)
            .background(configuration.isPressed ? Color.white.opacity(0.13) : Color.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .stroke(Color.white.opacity(0.08), lineWidth: 1)
            )
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

private struct RetryModelOption: Identifiable, Equatable {
    static let currentID = "current"

    let id: String
    let title: String
    let modelPath: String?
}

private extension TranscriptionStatus {
    var historyStatus: RecordingTranscriptionStatus {
        switch self {
        case .completed:
            return .completed
        case .failed:
            return .failed
        case .stopped:
            return .stopped
        case .idle, .preparing, .running:
            return .notTranscribed
        }
    }

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
