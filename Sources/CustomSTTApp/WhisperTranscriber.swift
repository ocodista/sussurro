import Foundation

@MainActor
final class WhisperTranscriber: ObservableObject {
    @Published private(set) var isTranscribing = false
    @Published var transcript = ""
    @Published var errorMessage: String?
    @Published private(set) var currentTranscriptionElapsed: TimeInterval = 0
    @Published private(set) var lastTranscriptionDuration: TimeInterval?

    private let settings: AppSettings
    private var transcriptionTimer: Timer?

    init(settings: AppSettings) {
        self.settings = settings
    }

    func transcribe(audioURL: URL) async {
        guard !isTranscribing else { return }

        let modelPath = settings.expandedModelPath
        let whisperCLIPath = settings.expandedWhisperCLIPath

        guard !modelPath.isEmpty else {
            errorMessage = "Missing Whisper model. Run scripts/download-model.sh or set a model path."
            return
        }
        guard FileManager.default.fileExists(atPath: modelPath) else {
            errorMessage = "Whisper model not found at \(modelPath)."
            return
        }
        guard !whisperCLIPath.isEmpty else {
            errorMessage = "whisper-cli was not found. Install it with: brew install whisper-cpp"
            return
        }
        guard FileManager.default.isExecutableFile(atPath: whisperCLIPath) else {
            errorMessage = "whisper-cli not found or not executable at \(whisperCLIPath)."
            return
        }

        let startedAt = Date()
        isTranscribing = true
        currentTranscriptionElapsed = 0
        lastTranscriptionDuration = nil
        errorMessage = nil
        startTranscriptionTimer(startedAt: startedAt)
        defer {
            lastTranscriptionDuration = Date().timeIntervalSince(startedAt)
            currentTranscriptionElapsed = lastTranscriptionDuration ?? currentTranscriptionElapsed
            stopTranscriptionTimer()
            isTranscribing = false
        }

        do {
            let result = try await runWhisper(audioURL: audioURL, whisperCLIPath: whisperCLIPath, modelPath: modelPath)
            transcript = result.trimmingCharacters(in: .whitespacesAndNewlines)
        } catch {
            errorMessage = error.localizedDescription
        }
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

    private func runWhisper(audioURL: URL, whisperCLIPath: String, modelPath: String) async throws -> String {
        let executableURL = URL(fileURLWithPath: whisperCLIPath)
        let modelURL = URL(fileURLWithPath: modelPath)

        return try await Task.detached(priority: .userInitiated) {
            let normalizedAudioURL = try Self.normalizedWAVURL(for: audioURL)

            let process = Process()
            process.executableURL = executableURL
            process.arguments = [
                "-m", modelURL.path,
                "-f", normalizedAudioURL.path,
                "-l", "auto",
                "-nt",
                "-np"
            ]

            var environment = ProcessInfo.processInfo.environment
            environment["GGML_METAL_PATH_RESOURCES"] = "/opt/homebrew/lib"
            process.environment = environment

            let stdout = Pipe()
            let stderr = Pipe()
            process.standardOutput = stdout
            process.standardError = stderr

            try process.run()
            process.waitUntilExit()

            let stdoutText = String(data: stdout.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
            let stderrText = String(data: stderr.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""

            let logURL = AppPaths.whisperLogURL
            let log = "command: \(executableURL.path) \(process.arguments?.joined(separator: " ") ?? "")\n\nSTDOUT\n\(stdoutText)\n\nSTDERR\n\(stderrText)\n"
            do {
                try log.write(to: logURL, atomically: true, encoding: .utf8)
            } catch {
                NSLog("CustomSTT: could not write Whisper log to %@: %@", logURL.path, error.localizedDescription)
            }

            guard process.terminationStatus == 0 else {
                throw TranscriptionError.processFailed(status: process.terminationStatus, stderr: stderrText)
            }

            return stdoutText
        }.value
    }

    nonisolated private static func normalizedWAVURL(for inputURL: URL) throws -> URL {
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

        let stderr = Pipe()
        process.standardError = stderr
        try process.run()
        process.waitUntilExit()

        guard process.terminationStatus == 0 else {
            let stderrText = String(data: stderr.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
            throw AudioConversionError.failed(status: process.terminationStatus, stderr: stderrText)
        }

        return outputURL
    }

    nonisolated static func defaultWhisperCLIURL() -> URL? {
        AppPaths.defaultWhisperCLIURL()
    }

    nonisolated static func defaultModelURL() -> URL? {
        AppPaths.defaultModelURL()
    }
}

enum TranscriptionError: LocalizedError {
    case processFailed(status: Int32, stderr: String)

    var errorDescription: String? {
        switch self {
        case let .processFailed(status, stderr):
            let details = stderr.trimmingCharacters(in: .whitespacesAndNewlines)
            if details.isEmpty {
                return "whisper-cli failed with exit code \(status). See \(AppPaths.abbreviatedPath(AppPaths.whisperLogURL))."
            }
            return "whisper-cli failed with exit code \(status): \(details)"
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
