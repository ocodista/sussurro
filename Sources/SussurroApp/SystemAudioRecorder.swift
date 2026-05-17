import AVFoundation
import CoreGraphics
import Foundation
import ScreenCaptureKit

final class SystemAudioRecorder: NSObject {
    enum RecorderError: LocalizedError {
        case screenCapturePermissionDenied
        case noDisplayAvailable
        case writerSetupFailed(String)
        case captureFailed(String)
        case writerFailed(String)

        var errorDescription: String? {
            switch self {
            case .screenCapturePermissionDenied:
                return "Meeting mode needs Screen & System Audio Recording permission before it can capture system audio."
            case .noDisplayAvailable:
                return "Could not find a display for system audio capture."
            case let .writerSetupFailed(message):
                return "Could not prepare system audio recording: \(message)"
            case let .captureFailed(message):
                return "Could not capture system audio: \(message). Enable Screen Recording for Sussurro in System Settings → Privacy & Security → Screen & System Audio Recording, then restart Sussurro."
            case let .writerFailed(message):
                return "Could not save system audio: \(message)"
            }
        }
    }

    private let outputURL: URL
    private let sampleRate = 48_000
    private let channelCount = 2
    private let queue = DispatchQueue(label: "app.sussurro.system-audio-recorder")
    private let lock = NSLock()

    private var stream: SCStream?
    private var assetWriter: AVAssetWriter?
    private var audioInput: AVAssetWriterInput?
    private var didStartSession = false
    private var didAppendAudio = false
    private var streamError: Error?

    init(outputURL: URL) {
        self.outputURL = outputURL
        super.init()
    }

    func start() async throws {
        try FileManager.default.createDirectory(
            at: outputURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try? FileManager.default.removeItem(at: outputURL)

        let writer = try AVAssetWriter(outputURL: outputURL, fileType: .caf)
        let input = AVAssetWriterInput(
            mediaType: .audio,
            outputSettings: [
                AVFormatIDKey: Int(kAudioFormatLinearPCM),
                AVSampleRateKey: sampleRate,
                AVNumberOfChannelsKey: channelCount,
                AVLinearPCMBitDepthKey: 32,
                AVLinearPCMIsFloatKey: true,
                AVLinearPCMIsBigEndianKey: false,
                AVLinearPCMIsNonInterleaved: false
            ]
        )
        input.expectsMediaDataInRealTime = true

        guard writer.canAdd(input) else {
            throw RecorderError.writerSetupFailed("AVAssetWriter cannot add a PCM audio input.")
        }
        writer.add(input)
        guard writer.startWriting() else {
            throw RecorderError.writerSetupFailed(writer.error?.localizedDescription ?? "Unknown writer error.")
        }

        assetWriter = writer
        audioInput = input
        didStartSession = false
        didAppendAudio = false
        streamError = nil

        do {
            guard CGPreflightScreenCaptureAccess() else {
                throw RecorderError.screenCapturePermissionDenied
            }

            let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
            guard let display = content.displays.first else {
                throw RecorderError.noDisplayAvailable
            }

            let filter = SCContentFilter(display: display, excludingWindows: [])
            let configuration = SCStreamConfiguration()
            configuration.capturesAudio = true
            configuration.excludesCurrentProcessAudio = true
            configuration.sampleRate = sampleRate
            configuration.channelCount = channelCount
            configuration.width = 2
            configuration.height = 2

            let stream = SCStream(filter: filter, configuration: configuration, delegate: self)
            try stream.addStreamOutput(self, type: .audio, sampleHandlerQueue: queue)
            self.stream = stream
            try await stream.startCapture()
        } catch {
            queue.sync {
                audioInput?.markAsFinished()
                assetWriter?.cancelWriting()
                audioInput = nil
                assetWriter = nil
            }
            self.stream = nil
            try? FileManager.default.removeItem(at: outputURL)

            if let recorderError = error as? RecorderError {
                throw recorderError
            }
            throw RecorderError.captureFailed(error.localizedDescription)
        }
    }

    func stop() async throws -> URL? {
        let activeStream = stream
        stream = nil

        var stopError: Error?
        if let activeStream {
            do {
                try await activeStream.stopCapture()
            } catch {
                stopError = error
            }
            try? activeStream.removeStreamOutput(self, type: .audio)
        }

        let finishedURL = try await finishWriting()
        if let streamError = takeStreamError() {
            throw RecorderError.captureFailed(streamError.localizedDescription)
        }
        if let stopError {
            throw RecorderError.captureFailed(stopError.localizedDescription)
        }
        return finishedURL
    }

    private func finishWriting() async throws -> URL? {
        let state = queue.sync { () -> (writer: AVAssetWriter?, hasAudio: Bool) in
            let writer = assetWriter
            let hasAudio = didStartSession && didAppendAudio

            if hasAudio {
                audioInput?.markAsFinished()
            } else {
                writer?.cancelWriting()
            }

            assetWriter = nil
            audioInput = nil
            didStartSession = false
            didAppendAudio = false
            return (writer, hasAudio)
        }

        guard let writer = state.writer else { return nil }
        guard state.hasAudio else {
            try? FileManager.default.removeItem(at: outputURL)
            return nil
        }

        await withCheckedContinuation { continuation in
            writer.finishWriting {
                continuation.resume()
            }
        }

        if writer.status == .failed || writer.status == .cancelled {
            throw RecorderError.writerFailed(writer.error?.localizedDescription ?? "Unknown writer error.")
        }

        return outputURL
    }

    private func rememberStreamError(_ error: Error) {
        lock.lock()
        streamError = error
        lock.unlock()
    }

    private func takeStreamError() -> Error? {
        lock.lock()
        let error = streamError
        streamError = nil
        lock.unlock()
        return error
    }
}

extension SystemAudioRecorder: SCStreamOutput {
    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of outputType: SCStreamOutputType) {
        guard outputType == .audio else { return }
        guard CMSampleBufferIsValid(sampleBuffer), CMSampleBufferDataIsReady(sampleBuffer) else { return }
        guard CMSampleBufferGetNumSamples(sampleBuffer) > 0 else { return }
        guard let writer = assetWriter, let audioInput else { return }
        guard writer.status == .writing else { return }
        guard audioInput.isReadyForMoreMediaData else { return }

        if !didStartSession {
            let presentationTime = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
            writer.startSession(atSourceTime: presentationTime)
            didStartSession = true
        }

        if audioInput.append(sampleBuffer) {
            didAppendAudio = true
        } else if let error = writer.error {
            rememberStreamError(error)
        }
    }
}

extension SystemAudioRecorder: SCStreamDelegate {
    func stream(_ stream: SCStream, didStopWithError error: Error) {
        rememberStreamError(error)
    }
}
