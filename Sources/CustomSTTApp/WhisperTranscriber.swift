import Darwin
import Foundation

enum TranscriptionBackend: String, CaseIterable, Identifiable, Sendable {
    case whisperCpp
    case fasterWhisper

    var id: String { rawValue }

    var title: String {
        switch self {
        case .whisperCpp:
            return "whisper.cpp"
        case .fasterWhisper:
            return "faster-whisper"
        }
    }

    var shortTitle: String {
        switch self {
        case .whisperCpp:
            return "cpp"
        case .fasterWhisper:
            return "faster"
        }
    }

    var logFileName: String {
        switch self {
        case .whisperCpp:
            return "whisper-cpp-last.log"
        case .fasterWhisper:
            return "faster-whisper-last.log"
        }
    }
}

enum TranscriptionRunStatus: Sendable {
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

struct TranscriptionRun: Identifiable, Sendable {
    let id: UUID
    let backend: TranscriptionBackend
    let title: String
    let modelDescription: String
    var status: TranscriptionRunStatus
    var elapsed: TimeInterval
    var duration: TimeInterval?
    var transcript: String
    var errorMessage: String?
    var startedAt: Date?

    var hasTranscript: Bool {
        !transcript.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}

@MainActor
final class WhisperTranscriber: ObservableObject {
    @Published private(set) var isTranscribing = false
    @Published private(set) var isStoppingTranscription = false
    @Published private(set) var runs: [TranscriptionRun]
    @Published var transcript = ""
    @Published var errorMessage: String?
    @Published private(set) var currentTranscriptionElapsed: TimeInterval = 0
    @Published private(set) var lastTranscriptionDuration: TimeInterval?

    private let settings: AppSettings
    private var activeControllers: [UUID: TranscriptionProcessController] = [:]
    private var transcriptionTimer: Timer?
    private var overallTranscriptionStartedAt: Date?

    init(settings: AppSettings) {
        self.settings = settings
        runs = Self.idleRuns(settings: settings)
    }

    func transcribe(audioURL: URL) async -> Bool {
        guard !isTranscribing else { return false }

        let preparedAt = Date()
        let plan = comparisonPlan(startedAt: preparedAt)
        runs = plan.runs
        transcript = ""
        errorMessage = nil

        guard !plan.requests.isEmpty else {
            errorMessage = "No transcription backend is ready. Check Settings."
            return false
        }

        isTranscribing = true
        isStoppingTranscription = false
        currentTranscriptionElapsed = 0
        lastTranscriptionDuration = nil
        activeControllers = [:]

        let overallStartedAt = Date()
        overallTranscriptionStartedAt = overallStartedAt
        startTranscriptionTimer()
        defer {
            lastTranscriptionDuration = Date().timeIntervalSince(overallStartedAt)
            currentTranscriptionElapsed = lastTranscriptionDuration ?? currentTranscriptionElapsed
            refreshElapsed()
            stopTranscriptionTimer()
            overallTranscriptionStartedAt = nil
            activeControllers.removeAll()
            isStoppingTranscription = false
            isTranscribing = false
        }

        let normalizedAudioURL: URL
        let preparationController = TranscriptionProcessController()
        activeControllers[UUID()] = preparationController

        do {
            normalizedAudioURL = try await Task.detached(priority: .userInitiated) {
                try Self.normalizedWAVURL(for: audioURL, processController: preparationController)
            }.value
            activeControllers = activeControllers.filter { $0.value !== preparationController }
        } catch TranscriptionCancellation.cancelled {
            markActiveRunsAsStopped()
            errorMessage = "Transcription stopped."
            return false
        } catch {
            markActiveRunsAsFailed(error.localizedDescription)
            errorMessage = error.localizedDescription
            return false
        }

        guard !isStoppingTranscription else {
            markActiveRunsAsStopped()
            errorMessage = "Transcription stopped."
            return false
        }

        let modelStartedAt = Date()
        markRequestsAsRunning(plan.requests, startedAt: modelStartedAt)

        await withTaskGroup(of: TranscriptionJobOutcome.self) { group in
            for request in plan.requests {
                let controller = TranscriptionProcessController()
                activeControllers[request.id] = controller
                if isStoppingTranscription {
                    controller.cancel()
                }

                group.addTask {
                    Self.run(request: request, audioURL: normalizedAudioURL, processController: controller)
                }
            }

            for await outcome in group {
                activeControllers[outcome.id] = nil
                apply(outcome)
            }
        }

        let hasSuccessfulTranscript = runs.contains { $0.status == .completed && $0.hasTranscript }
        if !hasSuccessfulTranscript, errorMessage == nil {
            errorMessage = runs.compactMap(\.errorMessage).first
        }
        return hasSuccessfulTranscript
    }

    func stopTranscription() {
        guard isTranscribing else { return }
        isStoppingTranscription = true
        errorMessage = "Stopping transcription…"
        for controller in activeControllers.values {
            controller.cancel()
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
        overallTranscriptionStartedAt = nil
        runs = Self.idleRuns(settings: settings)
    }

    func copyText(for runID: UUID) -> String {
        guard let run = runs.first(where: { $0.id == runID }) else { return "" }
        return run.transcript.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func combinedTranscript() -> String {
        runs
            .filter(\.hasTranscript)
            .map { run in
                "[\(run.title) · \(run.modelDescription)]\n\(run.transcript.trimmingCharacters(in: .whitespacesAndNewlines))"
            }
            .joined(separator: "\n\n")
    }

    private func comparisonPlan(startedAt: Date) -> TranscriptionPlan {
        var requests: [PreparedTranscriptionRequest] = []
        var plannedRuns: [TranscriptionRun] = []

        let whisperCppValidation = makeWhisperCppRequest()
        plannedRuns.append(whisperCppValidation.run(startedAt: startedAt))
        if case let .ready(request) = whisperCppValidation {
            requests.append(request)
        }

        if settings.useFasterWhisper {
            let fasterWhisperValidation = makeFasterWhisperRequest()
            plannedRuns.append(fasterWhisperValidation.run(startedAt: startedAt))
            if case let .ready(request) = fasterWhisperValidation {
                requests.append(request)
            }
        }

        return TranscriptionPlan(requests: requests, runs: plannedRuns)
    }

    private func makeWhisperCppRequest() -> RequestValidation {
        let modelPath = settings.expandedModelPath
        let whisperCLIPath = settings.expandedWhisperCLIPath
        let modelDescription = Self.modelDescription(forPath: modelPath, fallback: "GGML model")

        guard !modelPath.isEmpty else {
            return .unavailable(backend: .whisperCpp, modelDescription: modelDescription, message: "Missing Whisper model. Run scripts/download-model.sh or set a model path.")
        }
        guard FileManager.default.fileExists(atPath: modelPath) else {
            return .unavailable(backend: .whisperCpp, modelDescription: modelDescription, message: "Whisper model not found at \(modelPath).")
        }
        guard !whisperCLIPath.isEmpty else {
            return .unavailable(backend: .whisperCpp, modelDescription: modelDescription, message: "whisper-cli was not found. Install it with: brew install whisper-cpp")
        }
        guard FileManager.default.isExecutableFile(atPath: whisperCLIPath) else {
            return .unavailable(backend: .whisperCpp, modelDescription: modelDescription, message: "whisper-cli not found or not executable at \(whisperCLIPath).")
        }

        return .ready(PreparedTranscriptionRequest(
            id: UUID(),
            backend: .whisperCpp,
            modelDescription: modelDescription,
            payload: .whisperCpp(whisperCLIPath: whisperCLIPath, modelPath: modelPath)
        ))
    }

    private func makeFasterWhisperRequest() -> RequestValidation {
        let pythonPath = settings.expandedFasterWhisperPythonPath
        let model = settings.resolvedFasterWhisperModel
        let device = settings.fasterWhisperDevice.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "auto" : settings.fasterWhisperDevice
        let computeType = device == "cuda" ? "float16" : "int8"
        let modelDescription = model.isEmpty ? AppPaths.defaultFasterWhisperModelName : model

        guard !model.isEmpty else {
            return .unavailable(backend: .fasterWhisper, modelDescription: modelDescription, message: "Missing faster-whisper model. Use a model name like large-v3-turbo or a local CTranslate2 model folder.")
        }
        if Self.isLocalPath(model), !FileManager.default.fileExists(atPath: model) {
            return .unavailable(backend: .fasterWhisper, modelDescription: modelDescription, message: "faster-whisper model folder not found at \(model).")
        }
        guard !pythonPath.isEmpty else {
            return .unavailable(backend: .fasterWhisper, modelDescription: modelDescription, message: "Missing Python executable. Run scripts/install-faster-whisper.sh or set a Python path.")
        }
        guard FileManager.default.isExecutableFile(atPath: pythonPath) else {
            return .unavailable(backend: .fasterWhisper, modelDescription: modelDescription, message: "Python executable not found at \(pythonPath). Run scripts/install-faster-whisper.sh.")
        }

        return .ready(PreparedTranscriptionRequest(
            id: UUID(),
            backend: .fasterWhisper,
            modelDescription: modelDescription,
            payload: .fasterWhisper(pythonPath: pythonPath, model: model, device: device, computeType: computeType)
        ))
    }

    private func markRequestsAsRunning(_ requests: [PreparedTranscriptionRequest], startedAt: Date) {
        for request in requests {
            guard let index = runs.firstIndex(where: { $0.id == request.id }) else { continue }
            runs[index].status = .running
            runs[index].startedAt = startedAt
            runs[index].elapsed = 0
            runs[index].duration = nil
            runs[index].errorMessage = nil
        }
    }

    private func markActiveRunsAsStopped() {
        for index in runs.indices where runs[index].status.isActive {
            runs[index].status = .stopped
            runs[index].duration = runs[index].elapsed
            runs[index].errorMessage = "Stopped"
        }
        updateCombinedTranscript()
    }

    private func markActiveRunsAsFailed(_ message: String) {
        for index in runs.indices where runs[index].status.isActive {
            runs[index].status = .failed
            runs[index].duration = runs[index].elapsed
            runs[index].errorMessage = message
        }
        updateCombinedTranscript()
    }

    private func apply(_ outcome: TranscriptionJobOutcome) {
        guard let index = runs.firstIndex(where: { $0.id == outcome.id }) else { return }

        switch outcome.result {
        case let .success(text, duration):
            runs[index].status = .completed
            runs[index].duration = duration
            runs[index].elapsed = duration
            runs[index].transcript = text.trimmingCharacters(in: .whitespacesAndNewlines)
            runs[index].errorMessage = nil
        case let .failure(message, duration):
            runs[index].status = .failed
            runs[index].duration = duration
            runs[index].elapsed = duration
            runs[index].errorMessage = message
        case let .stopped(duration):
            runs[index].status = .stopped
            runs[index].duration = duration
            runs[index].elapsed = duration
            runs[index].errorMessage = "Stopped"
        }

        updateCombinedTranscript()
    }

    private func updateCombinedTranscript() {
        transcript = combinedTranscript()
    }

    private func startTranscriptionTimer() {
        transcriptionTimer?.invalidate()
        transcriptionTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.refreshElapsed()
            }
        }
    }

    private func stopTranscriptionTimer() {
        transcriptionTimer?.invalidate()
        transcriptionTimer = nil
    }

    private func refreshElapsed() {
        let now = Date()
        if let overallTranscriptionStartedAt, isTranscribing {
            currentTranscriptionElapsed = now.timeIntervalSince(overallTranscriptionStartedAt)
        }

        for index in runs.indices where runs[index].status.isActive {
            guard let startedAt = runs[index].startedAt else { continue }
            runs[index].elapsed = now.timeIntervalSince(startedAt)
        }
    }

    nonisolated private static func run(request: PreparedTranscriptionRequest, audioURL: URL, processController: TranscriptionProcessController) -> TranscriptionJobOutcome {
        let startedAt = Date()

        do {
            let result: String
            switch request.payload {
            case let .whisperCpp(whisperCLIPath, modelPath):
                result = try runWhisperCpp(audioURL: audioURL, whisperCLIPath: whisperCLIPath, modelPath: modelPath, processController: processController)
            case let .fasterWhisper(pythonPath, model, device, computeType):
                result = try runFasterWhisper(audioURL: audioURL, pythonPath: pythonPath, model: model, device: device, computeType: computeType, processController: processController)
            }
            return TranscriptionJobOutcome(id: request.id, result: .success(text: result, duration: Date().timeIntervalSince(startedAt)))
        } catch TranscriptionCancellation.cancelled {
            return TranscriptionJobOutcome(id: request.id, result: .stopped(duration: Date().timeIntervalSince(startedAt)))
        } catch {
            return TranscriptionJobOutcome(id: request.id, result: .failure(message: error.localizedDescription, duration: Date().timeIntervalSince(startedAt)))
        }
    }

    nonisolated private static func runWhisperCpp(audioURL: URL, whisperCLIPath: String, modelPath: String, processController: TranscriptionProcessController) throws -> String {
        let executableURL = URL(fileURLWithPath: whisperCLIPath)
        let modelURL = URL(fileURLWithPath: modelPath)

        let process = Process()
        process.executableURL = executableURL
        process.arguments = [
            "-m", modelURL.path,
            "-f", audioURL.path,
            "-l", "auto",
            "-nt",
            "-np"
        ]

        var environment = ProcessInfo.processInfo.environment
        environment["GGML_METAL_PATH_RESOURCES"] = "/opt/homebrew/lib"
        process.environment = environment

        let processResult = try processController.run(process)
        let commandLine = "\(executableURL.path) \(process.arguments?.joined(separator: " ") ?? "")"
        writeWhisperLog(backend: .whisperCpp, commandLine: commandLine, processResult: processResult)

        if processResult.wasCancelled {
            throw TranscriptionCancellation.cancelled
        }
        guard processResult.terminationStatus == 0 else {
            throw TranscriptionError.processFailed(commandName: "whisper-cli", status: processResult.terminationStatus, stderr: processResult.stderrText)
        }

        return processResult.stdoutText
    }

    nonisolated private static func runFasterWhisper(audioURL: URL, pythonPath: String, model: String, device: String, computeType: String, processController: TranscriptionProcessController) throws -> String {
        let executableURL = URL(fileURLWithPath: pythonPath)
        let process = Process()
        process.executableURL = executableURL
        process.arguments = [
            "-c", fasterWhisperPythonScript,
            "--audio", audioURL.path,
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
        let commandLine = "\(executableURL.path) -c <faster-whisper transcriber> --audio \(audioURL.path) --model \(model) --device \(device) --compute-type \(computeType)"
        writeWhisperLog(backend: .fasterWhisper, commandLine: commandLine, processResult: processResult)

        if processResult.wasCancelled {
            throw TranscriptionCancellation.cancelled
        }
        guard processResult.terminationStatus == 0 else {
            throw TranscriptionError.processFailed(commandName: "faster-whisper", status: processResult.terminationStatus, stderr: processResult.stderrText)
        }

        return processResult.stdoutText
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

    nonisolated private static func writeWhisperLog(backend: TranscriptionBackend, commandLine: String, processResult: ProcessRunResult) {
        let log = formattedLog(backend: backend, commandLine: commandLine, processResult: processResult)
        let backendLogURL = AppPaths.logsDirectory.appendingPathComponent(backend.logFileName)
        writeLog(log, to: backendLogURL)
        writeLog(log, to: AppPaths.whisperLogURL)
    }

    nonisolated private static func formattedLog(backend: TranscriptionBackend, commandLine: String, processResult: ProcessRunResult) -> String {
        let cancellationText = processResult.wasCancelled ? "yes" : "no"
        return "backend: \(backend.title)\ncancelled: \(cancellationText)\ncommand: \(commandLine)\n\nSTDOUT\n\(processResult.stdoutText)\n\nSTDERR\n\(processResult.stderrText)\n"
    }

    nonisolated private static func writeLog(_ log: String, to url: URL) {
        do {
            try log.write(to: url, atomically: true, encoding: .utf8)
        } catch {
            NSLog("CustomSTT: could not write transcription log to %@: %@", url.path, error.localizedDescription)
        }
    }

    nonisolated private static func isLocalPath(_ model: String) -> Bool {
        model.hasPrefix("/") || model.hasPrefix("./") || model.hasPrefix("../")
    }

    nonisolated private static func modelDescription(forPath path: String, fallback: String) -> String {
        guard !path.isEmpty else { return fallback }
        return URL(fileURLWithPath: path).lastPathComponent
    }

    private static func idleRuns(settings: AppSettings) -> [TranscriptionRun] {
        var idleRuns = [TranscriptionRun(
            id: UUID(),
            backend: .whisperCpp,
            title: TranscriptionBackend.whisperCpp.title,
            modelDescription: modelDescription(forPath: settings.expandedModelPath, fallback: "GGML model"),
            status: .idle,
            elapsed: 0,
            duration: nil,
            transcript: "",
            errorMessage: nil,
            startedAt: nil
        )]

        if settings.useFasterWhisper {
            let fasterWhisperModel = settings.resolvedFasterWhisperModel.isEmpty ? AppPaths.defaultFasterWhisperModelName : settings.resolvedFasterWhisperModel
            idleRuns.append(TranscriptionRun(
                id: UUID(),
                backend: .fasterWhisper,
                title: TranscriptionBackend.fasterWhisper.title,
                modelDescription: fasterWhisperModel,
                status: .idle,
                elapsed: 0,
                duration: nil,
                transcript: "",
                errorMessage: nil,
                startedAt: nil
            ))
        }

        return idleRuns
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
parser.add_argument("--compute-type", default="int8")
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

private struct TranscriptionPlan {
    let requests: [PreparedTranscriptionRequest]
    let runs: [TranscriptionRun]
}

private enum RequestValidation {
    case ready(PreparedTranscriptionRequest)
    case unavailable(backend: TranscriptionBackend, modelDescription: String, message: String)

    func run(startedAt: Date) -> TranscriptionRun {
        switch self {
        case let .ready(request):
            return TranscriptionRun(
                id: request.id,
                backend: request.backend,
                title: request.backend.title,
                modelDescription: request.modelDescription,
                status: .preparing,
                elapsed: 0,
                duration: nil,
                transcript: "",
                errorMessage: nil,
                startedAt: startedAt
            )
        case let .unavailable(backend, modelDescription, message):
            return TranscriptionRun(
                id: UUID(),
                backend: backend,
                title: backend.title,
                modelDescription: modelDescription,
                status: .failed,
                elapsed: 0,
                duration: nil,
                transcript: "",
                errorMessage: message,
                startedAt: nil
            )
        }
    }
}

private struct PreparedTranscriptionRequest: Sendable {
    let id: UUID
    let backend: TranscriptionBackend
    let modelDescription: String
    let payload: TranscriptionRequestPayload
}

private enum TranscriptionRequestPayload: Sendable {
    case whisperCpp(whisperCLIPath: String, modelPath: String)
    case fasterWhisper(pythonPath: String, model: String, device: String, computeType: String)
}

private struct TranscriptionJobOutcome: Sendable {
    let id: UUID
    let result: TranscriptionJobResult
}

private enum TranscriptionJobResult: Sendable {
    case success(text: String, duration: TimeInterval)
    case failure(message: String, duration: TimeInterval)
    case stopped(duration: TimeInterval)
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
