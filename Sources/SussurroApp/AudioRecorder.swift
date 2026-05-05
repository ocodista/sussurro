import AudioToolbox
import AVFoundation
import Foundation

@MainActor
final class AudioRecorder: ObservableObject {
    enum RecorderError: LocalizedError {
        case microphoneDenied
        case noInputFormat
        case missingRecordingFile
        case selectedInputUnavailable
        case inputDeviceConfigurationFailed(OSStatus)

        var errorDescription: String? {
            switch self {
            case .microphoneDenied:
                return "Microphone permission is denied. Enable it in System Settings → Privacy & Security → Microphone."
            case .noInputFormat:
                return "Could not read the microphone input format."
            case .missingRecordingFile:
                return "Recording stopped, but no audio file was produced."
            case .selectedInputUnavailable:
                return "Selected audio input is unavailable. Choose another input or use the default system input."
            case let .inputDeviceConfigurationFailed(status):
                return "Could not use the selected audio input (Core Audio status \(status))."
            }
        }
    }

    @Published private(set) var isRecording = false
    @Published private(set) var elapsedSeconds: TimeInterval = 0
    @Published private(set) var levels: [Float] = Array(repeating: 0.02, count: 72)
    @Published var errorMessage: String?

    private let settings: AppSettings
    private let engine = AVAudioEngine()
    private var audioFile: AVAudioFile?
    private var recordingURL: URL?
    private var startedAt: Date?
    private var timer: Timer?

    init(settings: AppSettings) {
        self.settings = settings
    }

    func requestMicrophoneAccess() async -> Bool {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:
            return true
        case .denied, .restricted:
            errorMessage = RecorderError.microphoneDenied.localizedDescription
            return false
        case .notDetermined:
            return await withCheckedContinuation { continuation in
                AVCaptureDevice.requestAccess(for: .audio) { allowed in
                    continuation.resume(returning: allowed)
                }
            }
        @unknown default:
            errorMessage = "Unknown microphone permission state."
            return false
        }
    }

    func startRecording() async {
        guard !isRecording else { return }
        guard await requestMicrophoneAccess() else {
            errorMessage = RecorderError.microphoneDenied.localizedDescription
            return
        }

        do {
            let url = nextRecordingURL()
            let inputNode = engine.inputNode
            try configureSelectedInputDevice(on: inputNode)
            let format = inputNode.outputFormat(forBus: 0)
            guard format.channelCount > 0, format.sampleRate > 0 else {
                throw RecorderError.noInputFormat
            }

            let file = try AVAudioFile(forWriting: url, settings: format.settings)
            audioFile = file
            recordingURL = url
            startedAt = Date()
            elapsedSeconds = 0
            levels = Array(repeating: 0.02, count: 72)

            inputNode.removeTap(onBus: 0)
            inputNode.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self, file] buffer, _ in
                do {
                    try file.write(from: buffer)
                } catch {
                    Task { @MainActor in
                        self?.errorMessage = "Could not write microphone audio: \(error.localizedDescription)"
                    }
                }

                let level = Self.rootMeanSquareLevel(for: buffer)
                Task { @MainActor in
                    self?.pushLevel(level)
                }
            }

            try engine.start()
            isRecording = true
            startTimer()
        } catch {
            cleanupEngine()
            errorMessage = error.localizedDescription
        }
    }

    func stopRecording() throws -> URL {
        guard isRecording else {
            if let recordingURL { return recordingURL }
            throw RecorderError.missingRecordingFile
        }

        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        audioFile = nil
        timer?.invalidate()
        timer = nil
        isRecording = false

        guard let recordingURL else {
            throw RecorderError.missingRecordingFile
        }
        return recordingURL
    }

    private func cleanupEngine() {
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        audioFile = nil
        timer?.invalidate()
        timer = nil
        isRecording = false
    }

    private func configureSelectedInputDevice(on inputNode: AVAudioInputNode) throws {
        let selectedInputDeviceUID = settings.selectedInputDeviceUID.trimmingCharacters(in: .whitespacesAndNewlines)
        let deviceID: AudioDeviceID

        if selectedInputDeviceUID.isEmpty {
            guard let defaultDeviceID = try AudioInputDeviceStore.defaultInputDeviceID() else { return }
            deviceID = defaultDeviceID
        } else {
            guard let selectedDeviceID = try AudioInputDeviceStore.inputDeviceID(forUID: selectedInputDeviceUID) else {
                throw RecorderError.selectedInputUnavailable
            }
            deviceID = selectedDeviceID
        }

        guard let audioUnit = inputNode.audioUnit else {
            throw RecorderError.inputDeviceConfigurationFailed(-1)
        }

        var selectedDeviceID = deviceID
        let status = AudioUnitSetProperty(
            audioUnit,
            kAudioOutputUnitProperty_CurrentDevice,
            kAudioUnitScope_Global,
            0,
            &selectedDeviceID,
            UInt32(MemoryLayout<AudioDeviceID>.size)
        )

        guard status == noErr else {
            throw RecorderError.inputDeviceConfigurationFailed(status)
        }
    }

    private func nextRecordingURL() -> URL {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd_HH-mm-ss"
        let name = "recording-\(formatter.string(from: Date())).wav"
        return AppPaths.recordingsDirectory.appendingPathComponent(name)
    }

    private func startTimer() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 0.2, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self, let startedAt = self.startedAt else { return }
                self.elapsedSeconds = Date().timeIntervalSince(startedAt)
            }
        }
    }

    private func pushLevel(_ level: Float) {
        levels.append(max(0.02, min(1, level)))
        if levels.count > 72 {
            levels.removeFirst(levels.count - 72)
        }
    }

    nonisolated private static func rootMeanSquareLevel(for buffer: AVAudioPCMBuffer) -> Float {
        guard let channelData = buffer.floatChannelData else { return 0.02 }
        let frameLength = Int(buffer.frameLength)
        guard frameLength > 0 else { return 0.02 }

        var squaredSum: Float = 0
        for channel in 0..<Int(buffer.format.channelCount) {
            let samples = channelData[channel]
            for index in 0..<frameLength {
                squaredSum += samples[index] * samples[index]
            }
        }

        let sampleCount = max(1, frameLength * Int(buffer.format.channelCount))
        let rms = sqrt(squaredSum / Float(sampleCount))
        return min(1, rms * 8)
    }
}
