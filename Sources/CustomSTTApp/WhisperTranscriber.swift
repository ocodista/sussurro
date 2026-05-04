import Darwin
import Foundation

@MainActor
final class WhisperTranscriber: ObservableObject {
    @Published private(set) var isTranscribing = false
    @Published private(set) var isStoppingTranscription = false
    @Published var transcript = ""
    @Published var errorMessage: String?
    @Published private(set) var currentTranscriptionElapsed: TimeInterval = 0
    @Published private(set) var lastTranscriptionDuration: TimeInterval?

    private let settings: AppSettings
    private let processController = TranscriptionProcessController()
    private var transcriptionTimer: Timer?

    init(settings: AppSettings) {
        self.settings = settings
    }

    func transcribe(audioURL: URL) async -> Bool {
        guard !isTranscribing else { return false }

        let request: TranscriptionRequest
        if settings.useFasterWhisper {
            guard let fasterWhisperRequest = fasterWhisperRequest() else { return false }
            request = fasterWhisperRequest
        } else {
            guard let whisperCppRequest = whisperCppRequest() else { return false }
            request = whisperCppRequest
        }

        let startedAt = Date()
        processController.resetCancellation()
        isTranscribing = true
        isStoppingTranscription = false
        currentTranscriptionElapsed = 0
        lastTranscriptionDuration = nil
        errorMessage = nil
        startTranscriptionTimer(startedAt: startedAt)
        defer {
            lastTranscriptionDuration = Date().timeIntervalSince(startedAt)
            currentTranscriptionElapsed = lastTranscriptionDuration ?? currentTranscriptionElapsed
            stopTranscriptionTimer()
            isStoppingTranscription = false
            isTranscribing = false
        }

        do {
            let result: String
            switch request {
            case let .whisperCpp(whisperCLIPath, modelPath):
                result = try await runWhisperCpp(audioURL: audioURL, whisperCLIPath: whisperCLIPath, modelPath: modelPath)
            case let .fasterWhisper(pythonPath, model, device):
                result = try await runFasterWhisper(audioURL: audioURL, pythonPath: pythonPath, model: model, device: device)
            }
            transcript = result.trimmingCharacters(in: .whitespacesAndNewlines)
            return true
        } catch TranscriptionCancellation.cancelled {
            errorMessage = "Transcription stopped."
            return false
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
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
    }

    private func whisperCppRequest() -> TranscriptionRequest? {
        let modelPath = settings.expandedModelPath
        let whisperCLIPath = settings.expandedWhisperCLIPath

        guard !modelPath.isEmpty else {
            errorMessage = "Missing Whisper model. Run scripts/download-model.sh or set a model path."
            return nil
        }
        guard FileManager.default.fileExists(atPath: modelPath) else {
            errorMessage = "Whisper model not found at \(modelPath)."
            return nil
        }
        guard !whisperCLIPath.isEmpty else {
            errorMessage = "whisper-cli was not found. Install it with: brew install whisper-cpp"
            return nil
        }
        guard FileManager.default.isExecutableFile(atPath: whisperCLIPath) else {
            errorMessage = "whisper-cli not found or not executable at \(whisperCLIPath)."
            return nil
        }

        return .whisperCpp(whisperCLIPath: whisperCLIPath, modelPath: modelPath)
    }

    private func fasterWhisperRequest() -> TranscriptionRequest? {
        let pythonPath = settings.expandedFasterWhisperPythonPath
        let model = settings.resolvedFasterWhisperModel
        let device = settings.fasterWhisperDevice.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "auto" : settings.fasterWhisperDevice

        guard !model.isEmpty else {
            errorMessage = "Missing faster-whisper model. Use a model name like large-v3-turbo or a local CTranslate2 model folder."
            return nil
        }
        if Self.isLocalPath(model), !FileManager.default.fileExists(atPath: model) {
            errorMessage = "faster-whisper model folder not found at \(model)."
            return nil
        }
        guard !pythonPath.isEmpty else {
            errorMessage = "Missing Python executable. Run scripts/install-faster-whisper.sh or set a Python path."
            return nil
        }
        guard FileManager.default.isExecutableFile(atPath: pythonPath) else {
            errorMessage = "Python executable not found at \(pythonPath). Run scripts/install-faster-whisper.sh."
            return nil
        }

        return .fasterWhisper(pythonPath: pythonPath, model: model, device: device)
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

    private func runWhisperCpp(audioURL: URL, whisperCLIPath: String, modelPath: String) async throws -> String {
        let executableURL = URL(fileURLWithPath: whisperCLIPath)
        let modelURL = URL(fileURLWithPath: modelPath)
        let processController = processController

        return try await Task.detached(priority: .userInitiated) {
            let normalizedAudioURL = try Self.normalizedWAVURL(for: audioURL, processController: processController)

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

            let processResult = try processController.run(process)
            let commandLine = "\(executableURL.path) \(process.arguments?.joined(separator: " ") ?? "")"
            Self.writeWhisperLog(backend: "whisper.cpp", commandLine: commandLine, processResult: processResult)

            if processResult.wasCancelled {
                throw TranscriptionCancellation.cancelled
            }
            guard processResult.terminationStatus == 0 else {
                throw TranscriptionError.processFailed(commandName: "whisper-cli", status: processResult.terminationStatus, stderr: processResult.stderrText)
            }

            return processResult.stdoutText
        }.value
    }

    private func runFasterWhisper(audioURL: URL, pythonPath: String, model: String, device: String) async throws -> String {
        let executableURL = URL(fileURLWithPath: pythonPath)
        let computeType = device == "cuda" ? "float16" : "int8"
        let processController = processController

        return try await Task.detached(priority: .userInitiated) {
            let normalizedAudioURL = try Self.normalizedWAVURL(for: audioURL, processController: processController)

            let process = Process()
            process.executableURL = executableURL
            process.arguments = [
                "-c", Self.fasterWhisperPythonScript,
                "--audio", normalizedAudioURL.path,
                "--model", model,
                "--device", device,
                "--compute-type", computeType
            ]

            var environment = ProcessInfo.processInfo.environment
            environment["CUSTOM_STT_FASTER_WHISPER_DOWNLOAD_ROOT"] = AppPaths.fasterWhisperModelsDirectory.path
            environment["HF_HOME"] = AppPaths.huggingFaceCacheDirectory.path
            environment["XDG_CACHE_HOME"] = AppPaths.cacheDirectory.path
            environment["TOKENIZERS_PARALLELISM"] = "false"
            process.environment = environment

            let processResult = try processController.run(process)
            let commandLine = "\(executableURL.path) -c <faster-whisper transcriber> --audio \(normalizedAudioURL.path) --model \(model) --device \(device) --compute-type \(computeType)"
            Self.writeWhisperLog(backend: "faster-whisper", commandLine: commandLine, processResult: processResult)

            if processResult.wasCancelled {
                throw TranscriptionCancellation.cancelled
            }
            guard processResult.terminationStatus == 0 else {
                throw TranscriptionError.processFailed(commandName: "faster-whisper", status: processResult.terminationStatus, stderr: processResult.stderrText)
            }

            return processResult.stdoutText
        }.value
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

    nonisolated private static func writeWhisperLog(backend: String, commandLine: String, processResult: ProcessRunResult) {
        let logURL = AppPaths.whisperLogURL
        let cancellationText = processResult.wasCancelled ? "yes" : "no"
        let log = "backend: \(backend)\ncancelled: \(cancellationText)\ncommand: \(commandLine)\n\nSTDOUT\n\(processResult.stdoutText)\n\nSTDERR\n\(processResult.stderrText)\n"
        do {
            try log.write(to: logURL, atomically: true, encoding: .utf8)
        } catch {
            NSLog("CustomSTT: could not write Whisper log to %@: %@", logURL.path, error.localizedDescription)
        }
    }

    nonisolated private static func isLocalPath(_ model: String) -> Bool {
        model.hasPrefix("/") || model.hasPrefix("./") || model.hasPrefix("../")
    }

    nonisolated static func defaultWhisperCLIURL() -> URL? {
        AppPaths.defaultWhisperCLIURL()
    }

    nonisolated static func defaultModelURL() -> URL? {
        AppPaths.defaultModelURL()
    }

    nonisolated private static let fasterWhisperPythonScript = """
import argparse
import os
import sys

try:
    from faster_whisper import WhisperModel
except Exception as error:
    print("faster-whisper Python package is not installed for this Python executable.", file=sys.stderr)
    print("Install it with: scripts/install-faster-whisper.sh", file=sys.stderr)
    print(f"Import error: {error}", file=sys.stderr)
    raise SystemExit(127)

parser = argparse.ArgumentParser(description="Transcribe audio with faster-whisper for CustomSTT.")
parser.add_argument("--audio", required=True)
parser.add_argument("--model", required=True)
parser.add_argument("--device", default="auto")
parser.add_argument("--compute-type", default="default")
args = parser.parse_args()

download_root = os.environ.get("CUSTOM_STT_FASTER_WHISPER_DOWNLOAD_ROOT") or None
model = WhisperModel(
    args.model,
    device=args.device,
    compute_type=args.compute_type,
    download_root=download_root,
)
segments, _ = model.transcribe(args.audio, language=None, beam_size=5, vad_filter=True)

for segment in segments:
    text = segment.text.strip()
    if text:
        print(text, flush=True)
"""
}

private enum TranscriptionRequest {
    case whisperCpp(whisperCLIPath: String, modelPath: String)
    case fasterWhisper(pythonPath: String, model: String, device: String)
}

private enum TranscriptionCancellation: Error {
    case cancelled
}

private struct ProcessRunResult {
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
