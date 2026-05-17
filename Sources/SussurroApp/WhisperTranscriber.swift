import Darwin
import Foundation

struct WhisperTranscriptionSegment: Sendable, Equatable {
    let start: TimeInterval
    let end: TimeInterval
    let text: String
}

struct MeetingTranscriptSource: Sendable, Equatable {
    let speakerName: String
    let startOffset: TimeInterval
    let segments: [WhisperTranscriptionSegment]
}

private struct MeetingTranscriptLine: Sendable, Equatable {
    let speakerName: String
    let start: TimeInterval
    let end: TimeInterval
    let text: String
}

enum TranscriptionStatus: Sendable {
    case idle
    case preparing
    case running
    case completed
    case failed
    case stopped

    var isActive: Bool {
        switch self {
        case .preparing, .running:
            return true
        case .idle, .completed, .failed, .stopped:
            return false
        }
    }
}

@MainActor
final class WhisperTranscriber: ObservableObject {
    @Published private(set) var isTranscribing = false
    @Published private(set) var isStoppingTranscription = false
    @Published private(set) var status: TranscriptionStatus = .idle
    @Published private(set) var transcriptionStartedAt: Date?
    @Published private(set) var detectedLanguageCode: String?
    @Published var transcript = ""
    @Published var errorMessage: String?
    @Published private(set) var currentTranscriptionElapsed: TimeInterval = 0
    @Published private(set) var lastTranscriptionDuration: TimeInterval?
    @Published private(set) var lastUsedModelPath: String?

    private let settings: AppSettings
    private let processController = TranscriptionProcessController()
    private var transcriptionTimer: Timer?

    init(settings: AppSettings) {
        self.settings = settings
    }

    var modelDescription: String {
        let modelPath = lastUsedModelPath ?? settings.expandedModelPath
        guard !modelPath.isEmpty else { return "GGML model" }
        return URL(fileURLWithPath: modelPath).lastPathComponent
    }

    var detectedLanguageDisplay: String? {
        guard let detectedLanguageCode else { return nil }
        return Self.languageDisplayCode(for: detectedLanguageCode)
    }

    nonisolated static func languageDisplayCode(for code: String) -> String {
        let normalizedCode = normalizedLanguageCode(code)
        switch normalizedCode {
        case "pt":
            return "PT-BR"
        case "en":
            return "EN-US"
        default:
            return normalizedCode.uppercased()
        }
    }

    nonisolated private static func normalizedLanguageCode(_ code: String) -> String {
        let normalizedCode = code.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        return normalizedCode.split { $0 == "-" || $0 == "_" }.first.map(String.init) ?? normalizedCode
    }

    func transcribe(recording: RecordedAudio, modelPathOverride: String? = nil) async -> Bool {
        guard recording.isMeetingRecording else {
            return await transcribe(audioURL: recording.microphoneURL, modelPathOverride: modelPathOverride)
        }

        return await transcribeMeeting(recording: recording, modelPathOverride: modelPathOverride)
    }

    func transcribe(audioURL: URL, modelPathOverride: String? = nil) async -> Bool {
        guard !isTranscribing else { return false }
        guard let request = makeWhisperRequest(modelPathOverride: modelPathOverride) else { return false }

        let startedAt = Date()
        processController.resetCancellation()
        isTranscribing = true
        isStoppingTranscription = false
        status = .preparing
        transcriptionStartedAt = startedAt
        currentTranscriptionElapsed = 0
        lastTranscriptionDuration = nil
        lastUsedModelPath = request.modelPath
        detectedLanguageCode = nil
        errorMessage = nil
        startTranscriptionTimer(startedAt: startedAt)
        defer {
            lastTranscriptionDuration = Date().timeIntervalSince(startedAt)
            currentTranscriptionElapsed = lastTranscriptionDuration ?? currentTranscriptionElapsed
            stopTranscriptionTimer()
            transcriptionStartedAt = nil
            isStoppingTranscription = false
            isTranscribing = false
        }

        do {
            let normalizedAudioURL = try await Task.detached(priority: .userInitiated) {
                try Self.normalizedWAVURL(for: audioURL, processController: self.processController)
            }.value
            defer { try? FileManager.default.removeItem(at: normalizedAudioURL) }

            guard !isStoppingTranscription else {
                status = .stopped
                errorMessage = "Transcription stopped."
                return false
            }

            status = .running
            let result = try await Task.detached(priority: .userInitiated) {
                try Self.runWhisper(audioURL: normalizedAudioURL, request: request, processController: self.processController)
            }.value

            detectedLanguageCode = result.languageCode
            transcript = result.transcript.trimmingCharacters(in: .whitespacesAndNewlines)
            status = .completed
            return !transcript.isEmpty
        } catch TranscriptionCancellation.cancelled {
            status = .stopped
            errorMessage = "Transcription stopped."
            return false
        } catch {
            status = .failed
            errorMessage = error.localizedDescription
            return false
        }
    }

    private func transcribeMeeting(recording: RecordedAudio, modelPathOverride: String?) async -> Bool {
        guard !isTranscribing else { return false }
        guard let request = makeWhisperRequest(modelPathOverride: modelPathOverride) else { return false }

        let startedAt = Date()
        processController.resetCancellation()
        isTranscribing = true
        isStoppingTranscription = false
        status = .preparing
        transcriptionStartedAt = startedAt
        currentTranscriptionElapsed = 0
        lastTranscriptionDuration = nil
        lastUsedModelPath = request.modelPath
        detectedLanguageCode = nil
        errorMessage = nil
        startTranscriptionTimer(startedAt: startedAt)
        defer {
            lastTranscriptionDuration = Date().timeIntervalSince(startedAt)
            currentTranscriptionElapsed = lastTranscriptionDuration ?? currentTranscriptionElapsed
            stopTranscriptionTimer()
            transcriptionStartedAt = nil
            isStoppingTranscription = false
            isTranscribing = false
        }

        let sourceStartedAt = [recording.microphoneStartedAt, recording.systemAudioStartedAt]
            .compactMap { $0 }
            .min() ?? recording.microphoneStartedAt
        let sources = meetingAudioSources(for: recording, relativeTo: sourceStartedAt)
        var completedSources: [MeetingTranscriptSource] = []

        do {
            for source in sources {
                try processController.checkCancellation()
                guard !isStoppingTranscription else {
                    status = .stopped
                    errorMessage = "Transcription stopped."
                    return false
                }

                status = .preparing
                let normalizedAudioURL = try await Task.detached(priority: .userInitiated) {
                    try Self.normalizedWAVURL(for: source.audioURL, processController: self.processController)
                }.value
                defer { try? FileManager.default.removeItem(at: normalizedAudioURL) }

                guard !isStoppingTranscription else {
                    status = .stopped
                    errorMessage = "Transcription stopped."
                    return false
                }

                status = .running
                let result = try await Task.detached(priority: .userInitiated) {
                    try Self.runWhisper(
                        audioURL: normalizedAudioURL,
                        request: request,
                        processController: self.processController,
                        diagnosticSource: source.diagnosticSource
                    )
                }.value

                if detectedLanguageCode == nil {
                    detectedLanguageCode = result.languageCode
                }

                let segments = Self.segments(for: result)
                completedSources.append(MeetingTranscriptSource(
                    speakerName: source.speakerName,
                    startOffset: source.startOffset,
                    segments: segments
                ))

                let partialTranscript = Self.meetingTranscript(from: completedSources)
                if !partialTranscript.isEmpty {
                    transcript = partialTranscript
                }
            }

            transcript = Self.meetingTranscript(from: completedSources).trimmingCharacters(in: .whitespacesAndNewlines)
            status = .completed
            return !transcript.isEmpty
        } catch TranscriptionCancellation.cancelled {
            status = .stopped
            errorMessage = "Transcription stopped."
            return false
        } catch {
            status = .failed
            errorMessage = error.localizedDescription
            return false
        }
    }

    private func meetingAudioSources(for recording: RecordedAudio, relativeTo referenceDate: Date) -> [MeetingAudioSource] {
        var sources = [
            MeetingAudioSource(
                audioURL: recording.microphoneURL,
                speakerName: "Person A",
                diagnosticSource: "person_a_microphone",
                startOffset: max(0, recording.microphoneStartedAt.timeIntervalSince(referenceDate))
            )
        ]

        if let systemAudioURL = recording.systemAudioURL {
            sources.append(MeetingAudioSource(
                audioURL: systemAudioURL,
                speakerName: "Person B",
                diagnosticSource: "person_b_system_audio",
                startOffset: max(0, (recording.systemAudioStartedAt ?? referenceDate).timeIntervalSince(referenceDate))
            ))
        }

        return sources
    }

    func stopTranscription() {
        guard isTranscribing else { return }
        isStoppingTranscription = true
        errorMessage = "Stopping transcription…"
        processController.cancel()
    }

    func appendToTranscript(_ text: String) {
        let cleanText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanText.isEmpty else { return }

        if transcript.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            transcript = cleanText
        } else {
            transcript += "\n\n" + cleanText
        }
    }

    func clearTranscript() {
        transcript = ""
        errorMessage = nil
        lastTranscriptionDuration = nil
        currentTranscriptionElapsed = 0
        detectedLanguageCode = nil
        transcriptionStartedAt = nil
        lastUsedModelPath = nil
        status = .idle
    }

    private func makeWhisperRequest(modelPathOverride: String?) -> WhisperRequest? {
        let modelPath: String
        if let modelPathOverride {
            let expandedOverride = AppPaths.expandedPath(modelPathOverride.trimmingCharacters(in: .whitespacesAndNewlines))
            modelPath = expandedOverride.isEmpty ? settings.expandedModelPath : expandedOverride
        } else {
            modelPath = settings.expandedModelPath
        }
        let whisperCLIPath = settings.expandedWhisperCLIPath

        guard !modelPath.isEmpty else {
            errorMessage = "Missing Whisper model. Run scripts/download-model.sh or set a model path."
            status = .failed
            return nil
        }
        guard FileManager.default.fileExists(atPath: modelPath) else {
            errorMessage = "Whisper model not found at \(modelPath)."
            status = .failed
            return nil
        }
        guard !whisperCLIPath.isEmpty else {
            errorMessage = "whisper-cli was not found. Install it with: brew install whisper-cpp"
            status = .failed
            return nil
        }
        guard FileManager.default.isExecutableFile(atPath: whisperCLIPath) else {
            errorMessage = "whisper-cli not found or not executable at \(whisperCLIPath)."
            status = .failed
            return nil
        }

        return WhisperRequest(whisperCLIPath: whisperCLIPath, modelPath: modelPath)
    }

    private func startTranscriptionTimer(startedAt: Date) {
        transcriptionTimer?.invalidate()
        transcriptionTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.currentTranscriptionElapsed = Date().timeIntervalSince(startedAt)
            }
        }
    }

    private func stopTranscriptionTimer() {
        transcriptionTimer?.invalidate()
        transcriptionTimer = nil
    }

    nonisolated private static func runWhisper(
        audioURL: URL,
        request: WhisperRequest,
        processController: TranscriptionProcessController,
        diagnosticSource: String = "audio"
    ) throws -> WhisperResult {
        let executableURL = URL(fileURLWithPath: request.whisperCLIPath)
        let modelURL = URL(fileURLWithPath: request.modelPath)
        let outputBaseURL = FileManager.default.temporaryDirectory.appendingPathComponent("sussurro-whisper-\(UUID().uuidString)")
        let jsonOutputURL = outputBaseURL.appendingPathExtension("json")
        defer { try? FileManager.default.removeItem(at: jsonOutputURL) }

        let process = Process()
        process.executableURL = executableURL
        process.arguments = [
            "-m", modelURL.path,
            "-f", audioURL.path,
            "-l", "auto",
            "-nt",
            "-np",
            "-oj",
            "-of", outputBaseURL.path
        ]

        var environment = ProcessInfo.processInfo.environment
        environment["GGML_METAL_PATH_RESOURCES"] = "/opt/homebrew/lib"
        process.environment = environment

        let processResult = try processController.run(process)
        let jsonResult = decodedJSONResult(from: jsonOutputURL)
        let languageCode = jsonResult?.result?.language
        let segments = jsonResult.map { Self.transcriptionSegments(from: $0) } ?? []
        let commandLine = commandDisplayLine(executableURL: executableURL, arguments: process.arguments ?? [])
        writeWhisperLog(
            commandLine: commandLine,
            processResult: processResult,
            languageCode: languageCode,
            diagnosticSource: diagnosticSource
        )

        if processResult.wasCancelled {
            throw TranscriptionCancellation.cancelled
        }
        guard processResult.terminationStatus == 0 else {
            throw TranscriptionError.processFailed(commandName: "whisper-cli", status: processResult.terminationStatus, stderr: processResult.stderrText)
        }

        return WhisperResult(transcript: processResult.stdoutText, languageCode: languageCode, segments: segments)
    }

    nonisolated private static func normalizedWAVURL(for inputURL: URL, processController: TranscriptionProcessController) throws -> URL {
        try processController.checkCancellation()

        let outputName = inputURL.deletingPathExtension().lastPathComponent + "-whisper.wav"
        let outputURL = inputURL.deletingLastPathComponent().appendingPathComponent(outputName)
        try? FileManager.default.removeItem(at: outputURL)

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/afconvert")
        process.arguments = [
            "-f", "WAVE",
            "-d", "LEI16@16000",
            "-c", "1",
            inputURL.path,
            outputURL.path
        ]

        let processResult = try processController.run(process)
        if processResult.wasCancelled {
            throw TranscriptionCancellation.cancelled
        }
        guard processResult.terminationStatus == 0 else {
            throw AudioConversionError.failed(status: processResult.terminationStatus, stderr: processResult.stderrText)
        }

        return outputURL
    }

    nonisolated private static func decodedJSONResult(from url: URL) -> WhisperJSONResult? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(WhisperJSONResult.self, from: data)
    }

    nonisolated private static func transcriptionSegments(from json: WhisperJSONResult) -> [WhisperTranscriptionSegment] {
        (json.transcription ?? []).compactMap { segment in
            let text = (segment.text ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { return nil }

            let start = timestampInterval(segment.timestamps?.from)
                ?? offsetInterval(segment.offsets?.from)
                ?? 0
            let end = timestampInterval(segment.timestamps?.to)
                ?? offsetInterval(segment.offsets?.to)
                ?? start

            return WhisperTranscriptionSegment(start: start, end: max(start, end), text: text)
        }
    }

    nonisolated private static func segments(for result: WhisperResult) -> [WhisperTranscriptionSegment] {
        if !result.segments.isEmpty {
            return result.segments
        }

        let transcript = result.transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !transcript.isEmpty else { return [] }
        return [WhisperTranscriptionSegment(start: 0, end: 0, text: transcript)]
    }

    nonisolated static func meetingTranscript(from sources: [MeetingTranscriptSource]) -> String {
        let lines = sources.flatMap { source in
            source.segments.compactMap { segment -> MeetingTranscriptLine? in
                let text = segment.text.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !text.isEmpty else { return nil }
                let start = max(0, source.startOffset + segment.start)
                let end = max(start, source.startOffset + segment.end)
                return MeetingTranscriptLine(speakerName: source.speakerName, start: start, end: end, text: text)
            }
        }
        .sorted { lhs, rhs in
            if lhs.start == rhs.start {
                return lhs.speakerName < rhs.speakerName
            }
            return lhs.start < rhs.start
        }

        return lines
            .map { "[\(formatMeetingTimestamp($0.start))] \($0.speakerName): \($0.text)" }
            .joined(separator: "\n")
    }

    nonisolated private static func timestampInterval(_ value: String?) -> TimeInterval? {
        guard let value else { return nil }
        let normalizedValue = value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: ",", with: ".")
        guard !normalizedValue.isEmpty else { return nil }

        let components = normalizedValue.split(separator: ":").map(String.init)
        guard components.count == 2 || components.count == 3 else { return nil }

        let hours: Double
        let minutes: Double
        let seconds: Double
        if components.count == 3 {
            guard let parsedHours = Double(components[0]),
                  let parsedMinutes = Double(components[1]),
                  let parsedSeconds = Double(components[2])
            else { return nil }
            hours = parsedHours
            minutes = parsedMinutes
            seconds = parsedSeconds
        } else {
            guard let parsedMinutes = Double(components[0]),
                  let parsedSeconds = Double(components[1])
            else { return nil }
            hours = 0
            minutes = parsedMinutes
            seconds = parsedSeconds
        }

        return hours * 3600 + minutes * 60 + seconds
    }

    nonisolated private static func offsetInterval(_ value: Int?) -> TimeInterval? {
        guard let value else { return nil }
        return TimeInterval(value) / 1000
    }

    nonisolated private static func formatMeetingTimestamp(_ seconds: TimeInterval) -> String {
        let totalSeconds = max(0, Int(seconds.rounded(.down)))
        let hours = totalSeconds / 3600
        let minutes = (totalSeconds % 3600) / 60
        let remainingSeconds = totalSeconds % 60

        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, remainingSeconds)
        }
        return String(format: "%02d:%02d", minutes, remainingSeconds)
    }

    nonisolated private static func writeWhisperLog(
        commandLine: String,
        processResult: ProcessRunResult,
        languageCode: String?,
        diagnosticSource: String
    ) {
        let cancellationText = processResult.wasCancelled ? "yes" : "no"
        let languageText = languageCode ?? "unknown"
        let stdoutByteCount = processResult.stdoutText.lengthOfBytes(using: .utf8)
        let stderrText = redactedDiagnosticText(processResult.stderrText)
        let log = """
        backend: whisper.cpp
        source: \(diagnosticSource)
        cancelled: \(cancellationText)
        language: \(languageText)
        command: \(commandLine)
        transcript_logged: no
        stdout_bytes: \(stdoutByteCount)

        STDOUT
        <redacted: whisper stdout contains transcript text>

        STDERR
        \(stderrText)
        """
        do {
            try log.write(to: AppPaths.whisperLogURL, atomically: true, encoding: .utf8)
        } catch {
            NSLog("Sussurro: could not write Whisper log to %@: %@", AppPaths.whisperLogURL.path, error.localizedDescription)
        }
    }

    nonisolated private static func redactedDiagnosticText(_ text: String) -> String {
        let homePath = FileManager.default.homeDirectoryForCurrentUser.path
        guard !homePath.isEmpty else { return text }
        return text.replacingOccurrences(of: homePath, with: "~")
    }

    nonisolated private static func commandDisplayLine(executableURL: URL, arguments: [String]) -> String {
        ([executableURL.path] + arguments)
            .map(commandDisplayArgument(_:))
            .joined(separator: " ")
    }

    nonisolated private static func commandDisplayArgument(_ argument: String) -> String {
        let displayArgument = argument.hasPrefix("/") ? AppPaths.abbreviatedPath(URL(fileURLWithPath: argument)) : argument
        guard displayArgument.rangeOfCharacter(from: .whitespacesAndNewlines) != nil else {
            return displayArgument
        }

        let escapedArgument = displayArgument
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        return "\"\(escapedArgument)\""
    }

    nonisolated static func defaultWhisperCLIURL() -> URL? {
        AppPaths.defaultWhisperCLIURL()
    }

    nonisolated static func defaultModelURL() -> URL? {
        AppPaths.defaultModelURL()
    }
}

private struct WhisperRequest: Sendable {
    let whisperCLIPath: String
    let modelPath: String
}

private struct WhisperResult: Sendable {
    let transcript: String
    let languageCode: String?
    let segments: [WhisperTranscriptionSegment]
}

private struct MeetingAudioSource {
    let audioURL: URL
    let speakerName: String
    let diagnosticSource: String
    let startOffset: TimeInterval
}

private struct WhisperJSONResult: Decodable {
    let result: Result?
    let transcription: [Segment]?

    struct Result: Decodable {
        let language: String?
    }

    struct Segment: Decodable {
        let text: String?
        let timestamps: Timestamps?
        let offsets: Offsets?
    }

    struct Timestamps: Decodable {
        let from: String?
        let to: String?
    }

    struct Offsets: Decodable {
        let from: Int?
        let to: Int?
    }
}

private enum TranscriptionCancellation: Error {
    case cancelled
}

private struct ProcessRunResult: Sendable {
    let stdoutText: String
    let stderrText: String
    let terminationStatus: Int32
    let wasCancelled: Bool
}

private final class TranscriptionProcessController: @unchecked Sendable {
    private let lock = NSLock()
    private var currentProcess: Process?
    private var cancellationRequested = false

    func resetCancellation() {
        lock.lock()
        cancellationRequested = false
        currentProcess = nil
        lock.unlock()
    }

    func cancel() {
        lock.lock()
        cancellationRequested = true
        let process = currentProcess
        lock.unlock()

        guard let process else { return }
        terminate(process)
    }

    func checkCancellation() throws {
        if isCancellationRequested() {
            throw TranscriptionCancellation.cancelled
        }
    }

    func run(_ process: Process) throws -> ProcessRunResult {
        try checkCancellation()

        let stdout = Pipe()
        let stderr = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr

        lock.lock()
        currentProcess = process
        lock.unlock()

        do {
            try checkCancellation()
            try process.run()
            if isCancellationRequested() {
                terminate(process)
            }
            process.waitUntilExit()
        } catch {
            clearCurrentProcess(process)
            throw error
        }

        let stdoutText = String(data: stdout.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        let stderrText = String(data: stderr.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        let wasCancelled = isCancellationRequested()
        let terminationStatus = process.terminationStatus
        clearCurrentProcess(process)

        return ProcessRunResult(stdoutText: stdoutText, stderrText: stderrText, terminationStatus: terminationStatus, wasCancelled: wasCancelled)
    }

    private func clearCurrentProcess(_ process: Process) {
        lock.lock()
        if currentProcess === process {
            currentProcess = nil
        }
        lock.unlock()
    }

    private func isCancellationRequested() -> Bool {
        lock.lock()
        let isCancelled = cancellationRequested
        lock.unlock()
        return isCancelled
    }

    private func terminate(_ process: Process) {
        guard process.isRunning else { return }

        let processID = process.processIdentifier
        process.terminate()

        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 2) {
            guard process.isRunning else { return }
            kill(processID, SIGKILL)
        }
    }
}

enum TranscriptionError: LocalizedError {
    case processFailed(commandName: String, status: Int32, stderr: String)

    var errorDescription: String? {
        switch self {
        case let .processFailed(commandName, status, stderr):
            let details = stderr.trimmingCharacters(in: .whitespacesAndNewlines)
            if details.isEmpty {
                return "\(commandName) failed with exit code \(status). See \(AppPaths.abbreviatedPath(AppPaths.whisperLogURL))."
            }
            return "\(commandName) failed with exit code \(status): \(details)"
        }
    }
}

enum AudioConversionError: LocalizedError {
    case failed(status: Int32, stderr: String)

    var errorDescription: String? {
        switch self {
        case let .failed(status, stderr):
            let details = stderr.trimmingCharacters(in: .whitespacesAndNewlines)
            if details.isEmpty {
                return "Could not convert the recording to 16 kHz mono WAV. afconvert exited with \(status)."
            }
            return "Could not convert the recording to 16 kHz mono WAV: \(details)"
        }
    }
}
