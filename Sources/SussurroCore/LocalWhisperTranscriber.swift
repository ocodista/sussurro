import Foundation

public enum LocalTranscriptionError: LocalizedError {
    case missingAudio(String)
    case missingModel(String)
    case missingExecutable(String)
    case processFailed(command: String, status: Int32, stderr: String)
    case emptyTranscript

    public var errorDescription: String? {
        switch self {
        case let .missingAudio(path): return "Audio file not found at \(path)."
        case let .missingModel(path): return "Whisper model not found at \(path)."
        case let .missingExecutable(path): return "whisper-cli not found or not executable at \(path)."
        case let .processFailed(command, status, stderr):
            let detail = stderr.trimmingCharacters(in: .whitespacesAndNewlines)
            return detail.isEmpty ? "\(command) failed with exit code \(status)." : "\(command) failed with exit code \(status): \(detail)"
        case .emptyTranscript: return "Whisper returned an empty transcription."
        }
    }
}

public struct LocalWhisperTranscriber: AudioTranscribing, Sendable {
    public let whisperCLIURL: URL
    public let modelURL: URL
    public let language: String

    public init(whisperCLIURL: URL, modelURL: URL, language: String = "auto") {
        self.whisperCLIURL = whisperCLIURL
        self.modelURL = modelURL
        self.language = language
    }

    public func transcribe(audioURL: URL) throws -> TranscriptionRecord {
        guard FileManager.default.fileExists(atPath: audioURL.path) else {
            throw LocalTranscriptionError.missingAudio(audioURL.path)
        }
        guard FileManager.default.fileExists(atPath: modelURL.path) else {
            throw LocalTranscriptionError.missingModel(modelURL.path)
        }
        guard FileManager.default.isExecutableFile(atPath: whisperCLIURL.path) else {
            throw LocalTranscriptionError.missingExecutable(whisperCLIURL.path)
        }

        let normalizedURL = try normalizedAudioURL(for: audioURL)
        let removesNormalizedAudio = normalizedURL != audioURL
        defer {
            if removesNormalizedAudio { try? FileManager.default.removeItem(at: normalizedURL) }
        }

        let outputBaseURL = FileManager.default.temporaryDirectory.appendingPathComponent("sussurro-mcp-whisper-\(UUID().uuidString)")
        let jsonURL = outputBaseURL.appendingPathExtension("json")
        defer { try? FileManager.default.removeItem(at: jsonURL) }

        let result = try Self.run(
            executableURL: whisperCLIURL,
            arguments: WhisperCommand.arguments(
                modelPath: modelURL.path,
                audioPath: normalizedURL.path,
                language: language,
                outputBasePath: outputBaseURL.path
            )
        )
        guard result.status == 0 else {
            throw LocalTranscriptionError.processFailed(command: "whisper-cli", status: result.status, stderr: result.stderr)
        }

        let text = result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { throw LocalTranscriptionError.emptyTranscript }
        let detectedLanguage = Self.detectedLanguage(at: jsonURL)
        return TranscriptionRecord(text: text, language: detectedLanguage, audioPath: audioURL.path)
    }

    private func normalizedAudioURL(for audioURL: URL) throws -> URL {
        if audioURL.pathExtension.lowercased() == "wav" { return audioURL }
        let outputURL = FileManager.default.temporaryDirectory.appendingPathComponent("sussurro-mcp-audio-\(UUID().uuidString).wav")
        let result = try Self.run(
            executableURL: URL(fileURLWithPath: "/usr/bin/afconvert"),
            arguments: ["-f", "WAVE", "-d", "LEI16@16000", "-c", "1", audioURL.path, outputURL.path]
        )
        guard result.status == 0 else {
            throw LocalTranscriptionError.processFailed(command: "afconvert", status: result.status, stderr: result.stderr)
        }
        return outputURL
    }

    private static func detectedLanguage(at url: URL) -> String? {
        guard let data = try? Data(contentsOf: url),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let result = object["result"] as? [String: Any]
        else { return nil }
        return result["language"] as? String
    }

    private static func run(executableURL: URL, arguments: [String]) throws -> (stdout: String, stderr: String, status: Int32) {
        let process = Process()
        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.executableURL = executableURL
        process.arguments = arguments
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe
        try process.run()

        let group = DispatchGroup()
        var stdoutData = Data()
        var stderrData = Data()
        group.enter()
        DispatchQueue.global(qos: .userInitiated).async {
            stdoutData = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
            group.leave()
        }
        group.enter()
        DispatchQueue.global(qos: .userInitiated).async {
            stderrData = stderrPipe.fileHandleForReading.readDataToEndOfFile()
            group.leave()
        }
        process.waitUntilExit()
        group.wait()
        return (
            String(data: stdoutData, encoding: .utf8) ?? "",
            String(data: stderrData, encoding: .utf8) ?? "",
            process.terminationStatus
        )
    }
}

public enum WhisperCommand {
    public static func arguments(modelPath: String, audioPath: String, language: String, outputBasePath: String) -> [String] {
        [
            "-m", modelPath,
            "-f", audioPath,
            "-l", language,
            "-nt", "-np", "-mc", "0", "-oj", "-of", outputBasePath
        ]
    }
}
