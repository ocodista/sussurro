import AudioToolbox
import AVFoundation
import Foundation
import ScreenCaptureKit

final class SystemAudioRecorder: NSObject {
    enum RecorderError: LocalizedError {
        case systemAudioPermissionDenied
        case noDisplayAvailable
        case writerSetupFailed(String)
        case captureFailed(String)
        case writerFailed(String)

        var errorDescription: String? {
            switch self {
            case .systemAudioPermissionDenied:
                return "Meeting mode needs System Audio Recording permission before it can capture system audio."
            case .noDisplayAvailable:
                return "Could not find a display for system audio capture."
            case let .writerSetupFailed(message):
                return "Could not prepare system audio recording: \(message)"
            case let .captureFailed(message):
                return "Could not capture system audio: \(message). Enable System Audio Recording for Sussurro in System Settings → Privacy & Security, then try again."
            case let .writerFailed(message):
                return "Could not save system audio: \(message)"
            }
        }
    }

    private let outputURL: URL
    private let levelHandler: (@Sendable (Float) -> Void)?
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

    init(outputURL: URL, levelHandler: (@Sendable (Float) -> Void)? = nil) {
        self.outputURL = outputURL
        self.levelHandler = levelHandler
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
            // System audio has its own TCC service. Screen capture preflight stays false when only
            // System Audio Recording is granted, so let ScreenCaptureKit request/validate audio access.
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
            if Self.isSystemAudioPermissionError(error) {
                throw RecorderError.systemAudioPermissionDenied
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

    static func isSystemAudioPermissionError(_ error: Error) -> Bool {
        let nsError = error as NSError
        return nsError.domain == SCStreamErrorDomain && nsError.code == SCStreamError.userDeclined.rawValue
    }

    static func rootMeanSquareLevel(for sampleBuffer: CMSampleBuffer) -> Float {
        guard let formatDescription = CMSampleBufferGetFormatDescription(sampleBuffer),
              let streamDescriptionPointer = CMAudioFormatDescriptionGetStreamBasicDescription(formatDescription) else {
            return 0.02
        }

        let streamDescription = streamDescriptionPointer.pointee
        guard streamDescription.mFormatID == kAudioFormatLinearPCM else { return 0.02 }

        var bufferListSizeNeeded = 0
        CMSampleBufferGetAudioBufferListWithRetainedBlockBuffer(
            sampleBuffer,
            bufferListSizeNeededOut: &bufferListSizeNeeded,
            bufferListOut: nil,
            bufferListSize: 0,
            blockBufferAllocator: nil,
            blockBufferMemoryAllocator: nil,
            flags: 0,
            blockBufferOut: nil
        )
        guard bufferListSizeNeeded > 0 else { return 0.02 }

        let rawBufferList = UnsafeMutableRawPointer.allocate(
            byteCount: bufferListSizeNeeded,
            alignment: MemoryLayout<AudioBufferList>.alignment
        )
        defer { rawBufferList.deallocate() }

        let audioBufferList = rawBufferList.bindMemory(to: AudioBufferList.self, capacity: 1)
        var blockBuffer: CMBlockBuffer?
        let status = CMSampleBufferGetAudioBufferListWithRetainedBlockBuffer(
            sampleBuffer,
            bufferListSizeNeededOut: nil,
            bufferListOut: audioBufferList,
            bufferListSize: bufferListSizeNeeded,
            blockBufferAllocator: nil,
            blockBufferMemoryAllocator: nil,
            flags: 0,
            blockBufferOut: &blockBuffer
        )
        guard status == noErr else { return 0.02 }

        let buffers = UnsafeMutableAudioBufferListPointer(audioBufferList)
        let level = rootMeanSquareLevel(for: buffers, streamDescription: streamDescription)
        return min(1, max(0.02, level * 8))
    }

    private static func rootMeanSquareLevel(
        for buffers: UnsafeMutableAudioBufferListPointer,
        streamDescription: AudioStreamBasicDescription
    ) -> Float {
        guard streamDescription.mFormatFlags & kAudioFormatFlagIsFloat != 0,
              streamDescription.mBitsPerChannel == 32 else {
            return 0.02
        }

        var squaredSum: Float = 0
        var sampleCount = 0
        for buffer in buffers {
            guard let data = buffer.mData else { continue }
            let samples = data.assumingMemoryBound(to: Float.self)
            let bufferSampleCount = Int(buffer.mDataByteSize) / MemoryLayout<Float>.size
            guard bufferSampleCount > 0 else { continue }

            for index in 0..<bufferSampleCount {
                squaredSum += samples[index] * samples[index]
            }
            sampleCount += bufferSampleCount
        }

        guard sampleCount > 0 else { return 0.02 }
        return sqrt(squaredSum / Float(sampleCount))
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
            levelHandler?(Self.rootMeanSquareLevel(for: sampleBuffer))
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
