import AVFoundation
import Darwin
import Foundation

struct RealTimeAudioChunk: Sendable, Equatable {
    let index: Int
    let url: URL
    let duration: TimeInterval
    let overlapDuration: TimeInterval
    let sessionDirectoryURL: URL
}

struct RealTimeBreathDetection: Sendable, Equatable {
    let chunkIndex: Int
    let chunkDuration: TimeInterval
}

enum RealTimeBreathDetectionPolicy {
    static let silenceLevelThreshold: Float = 0.015
    static let minimumSpeechDurationBeforeBreath: TimeInterval = 0.65
    static let minimumChunkDurationBeforeBreath: TimeInterval = 1.25
    static let breathPauseDuration: TimeInterval = 0.30
}

private enum RealTimeChunkCloseReason: Equatable {
    case breath
    case maximumDuration
}

final class RealTimeAudioChunkWriter: @unchecked Sendable {
    private let format: AVAudioFormat
    private let minimumBreathChunkFrameLimit: AVAudioFramePosition
    private let maximumChunkFrameLimit: AVAudioFramePosition
    private let breathPauseFrameLimit: AVAudioFramePosition
    private let minimumSpeechFrameLimit: AVAudioFramePosition
    private let overlapFrameLimit: AVAudioFramePosition
    private let silenceLevelThreshold: Float = RealTimeBreathDetectionPolicy.silenceLevelThreshold
    private let sessionDirectoryURL: URL
    private let onChunkReady: @Sendable (RealTimeAudioChunk) -> Void
    private let onBreathDetected: @Sendable (RealTimeBreathDetection) -> Void
    private let onError: @Sendable (String) -> Void
    private let lock = NSLock()

    private var currentFile: AVAudioFile?
    private var currentChunkURL: URL?
    private var currentChunkLiveFrameCount: AVAudioFramePosition = 0
    private var currentChunkTotalFrameCount: AVAudioFramePosition = 0
    private var currentChunkOverlapFrameCount: AVAudioFramePosition = 0
    private var overlapBuffers: [AVAudioPCMBuffer] = []
    private var overlapBufferFrameCount: AVAudioFramePosition = 0
    private var consecutiveSilentFrameCount: AVAudioFramePosition = 0
    private var speechFrameCount: AVAudioFramePosition = 0
    private var nextChunkIndex = 0
    private var isFinished = false

    init(
        format: AVAudioFormat,
        chunkInterval: TimeInterval,
        sessionDirectoryURL: URL,
        onChunkReady: @escaping @Sendable (RealTimeAudioChunk) -> Void,
        onBreathDetected: @escaping @Sendable (RealTimeBreathDetection) -> Void = { _ in },
        onError: @escaping @Sendable (String) -> Void
    ) throws {
        self.format = format
        self.minimumBreathChunkFrameLimit = Self.frameLimit(
            seconds: min(RealTimeBreathDetectionPolicy.minimumChunkDurationBeforeBreath, chunkInterval),
            sampleRate: format.sampleRate
        )
        self.maximumChunkFrameLimit = Self.frameLimit(seconds: chunkInterval, sampleRate: format.sampleRate)
        self.breathPauseFrameLimit = Self.frameLimit(
            seconds: RealTimeBreathDetectionPolicy.breathPauseDuration,
            sampleRate: format.sampleRate
        )
        self.minimumSpeechFrameLimit = Self.frameLimit(
            seconds: RealTimeBreathDetectionPolicy.minimumSpeechDurationBeforeBreath,
            sampleRate: format.sampleRate
        )
        let overlapInterval = min(2.0, max(0.75, chunkInterval * 0.3))
        self.overlapFrameLimit = Self.frameLimit(seconds: overlapInterval, sampleRate: format.sampleRate)
        self.sessionDirectoryURL = sessionDirectoryURL
        self.onChunkReady = onChunkReady
        self.onBreathDetected = onBreathDetected
        self.onError = onError

        try FileManager.default.createDirectory(at: sessionDirectoryURL, withIntermediateDirectories: true)
    }

    func write(_ buffer: AVAudioPCMBuffer) {
        guard buffer.frameLength > 0 else { return }
        let overlapBuffer = Self.copiedBuffer(from: buffer)
        let level = Self.rootMeanSquareLevel(for: buffer)

        let completedChunk: (chunk: RealTimeAudioChunk, closeReason: RealTimeChunkCloseReason)?
        do {
            lock.lock()
            defer { lock.unlock() }

            guard !isFinished else { return }
            try ensureCurrentFileLocked()
            try currentFile?.write(from: buffer)

            let frameCount = AVAudioFramePosition(buffer.frameLength)
            currentChunkLiveFrameCount += frameCount
            currentChunkTotalFrameCount += frameCount

            if let overlapBuffer {
                appendOverlapBufferLocked(overlapBuffer)
            }

            if let closeReason = closeReasonForCurrentChunkLocked(latestLevel: level, frameCount: frameCount),
               let chunk = closeCurrentChunkLocked() {
                completedChunk = (chunk, closeReason)
            } else {
                completedChunk = nil
            }
        } catch {
            onError("Could not write real-time audio chunk: \(error.localizedDescription)")
            return
        }

        if let completedChunk {
            if completedChunk.closeReason == .breath {
                onBreathDetected(RealTimeBreathDetection(
                    chunkIndex: completedChunk.chunk.index,
                    chunkDuration: completedChunk.chunk.duration
                ))
            }
            onChunkReady(completedChunk.chunk)
        }
    }

    func finish() {
        let completedChunk: RealTimeAudioChunk?

        lock.lock()
        if isFinished {
            completedChunk = nil
        } else {
            isFinished = true
            completedChunk = closeCurrentChunkLocked()
        }
        lock.unlock()

        if let completedChunk {
            onChunkReady(completedChunk)
        }
    }

    private func ensureCurrentFileLocked() throws {
        guard currentFile == nil else { return }

        let chunkURL = sessionDirectoryURL.appendingPathComponent(String(format: "chunk-%05d.caf", nextChunkIndex))
        currentFile = try AVAudioFile(forWriting: chunkURL, settings: format.settings)
        currentChunkURL = chunkURL
        currentChunkLiveFrameCount = 0
        currentChunkTotalFrameCount = 0
        currentChunkOverlapFrameCount = 0

        guard nextChunkIndex > 0 else { return }
        for buffer in overlapBuffers {
            try currentFile?.write(from: buffer)
            let frameCount = AVAudioFramePosition(buffer.frameLength)
            currentChunkOverlapFrameCount += frameCount
            currentChunkTotalFrameCount += frameCount
        }
    }

    private func appendOverlapBufferLocked(_ buffer: AVAudioPCMBuffer) {
        let frameCount = AVAudioFramePosition(buffer.frameLength)
        overlapBuffers.append(buffer)
        overlapBufferFrameCount += frameCount

        while overlapBufferFrameCount > overlapFrameLimit, overlapBuffers.count > 1 {
            let firstFrameCount = AVAudioFramePosition(overlapBuffers[0].frameLength)
            guard overlapBufferFrameCount - firstFrameCount >= overlapFrameLimit else { break }
            overlapBuffers.removeFirst()
            overlapBufferFrameCount -= firstFrameCount
        }
    }

    private func closeReasonForCurrentChunkLocked(
        latestLevel: Float,
        frameCount: AVAudioFramePosition
    ) -> RealTimeChunkCloseReason? {
        updateBreathDetectionStateLocked(latestLevel: latestLevel, frameCount: frameCount)

        if shouldCloseAtBreathLocked {
            return .breath
        }

        if currentChunkLiveFrameCount >= maximumChunkFrameLimit {
            return .maximumDuration
        }

        return nil
    }

    private func updateBreathDetectionStateLocked(latestLevel: Float, frameCount: AVAudioFramePosition) {
        if latestLevel < silenceLevelThreshold {
            consecutiveSilentFrameCount += frameCount
        } else {
            consecutiveSilentFrameCount = 0
            speechFrameCount += frameCount
        }
    }

    private var shouldCloseAtBreathLocked: Bool {
        currentChunkLiveFrameCount >= minimumBreathChunkFrameLimit
            && speechFrameCount >= minimumSpeechFrameLimit
            && consecutiveSilentFrameCount >= breathPauseFrameLimit
    }

    private func closeCurrentChunkLocked() -> RealTimeAudioChunk? {
        guard let currentChunkURL, currentChunkLiveFrameCount > 0 else {
            currentFile = nil
            self.currentChunkURL = nil
            resetCurrentChunkCountersLocked()
            return nil
        }

        currentFile = nil
        self.currentChunkURL = nil

        let chunk = RealTimeAudioChunk(
            index: nextChunkIndex,
            url: currentChunkURL,
            duration: TimeInterval(currentChunkTotalFrameCount) / format.sampleRate,
            overlapDuration: TimeInterval(currentChunkOverlapFrameCount) / format.sampleRate,
            sessionDirectoryURL: sessionDirectoryURL
        )
        nextChunkIndex += 1
        resetCurrentChunkCountersLocked()
        return chunk
    }

    private func resetCurrentChunkCountersLocked() {
        currentChunkLiveFrameCount = 0
        currentChunkTotalFrameCount = 0
        currentChunkOverlapFrameCount = 0
        consecutiveSilentFrameCount = 0
        speechFrameCount = 0
    }

    private static func frameLimit(seconds: TimeInterval, sampleRate: Double) -> AVAudioFramePosition {
        max(1, AVAudioFramePosition((seconds * sampleRate).rounded(.toNearestOrAwayFromZero)))
    }

    private static func copiedBuffer(from buffer: AVAudioPCMBuffer) -> AVAudioPCMBuffer? {
        guard let copy = AVAudioPCMBuffer(pcmFormat: buffer.format, frameCapacity: buffer.frameLength) else {
            return nil
        }

        copy.frameLength = buffer.frameLength
        let frameLength = Int(buffer.frameLength)
        let channelCount = Int(buffer.format.channelCount)

        if copyFloatSamples(from: buffer, to: copy, frameLength: frameLength, channelCount: channelCount) {
            return copy
        }
        if copyInt16Samples(from: buffer, to: copy, frameLength: frameLength, channelCount: channelCount) {
            return copy
        }
        if copyInt32Samples(from: buffer, to: copy, frameLength: frameLength, channelCount: channelCount) {
            return copy
        }

        return nil
    }

    private static func copyFloatSamples(from source: AVAudioPCMBuffer, to destination: AVAudioPCMBuffer, frameLength: Int, channelCount: Int) -> Bool {
        guard let sourceChannels = source.floatChannelData,
              let destinationChannels = destination.floatChannelData
        else { return false }

        for channel in 0..<channelCount {
            memcpy(destinationChannels[channel], sourceChannels[channel], frameLength * MemoryLayout<Float>.size)
        }
        return true
    }

    private static func copyInt16Samples(from source: AVAudioPCMBuffer, to destination: AVAudioPCMBuffer, frameLength: Int, channelCount: Int) -> Bool {
        guard let sourceChannels = source.int16ChannelData,
              let destinationChannels = destination.int16ChannelData
        else { return false }

        for channel in 0..<channelCount {
            memcpy(destinationChannels[channel], sourceChannels[channel], frameLength * MemoryLayout<Int16>.size)
        }
        return true
    }

    private static func copyInt32Samples(from source: AVAudioPCMBuffer, to destination: AVAudioPCMBuffer, frameLength: Int, channelCount: Int) -> Bool {
        guard let sourceChannels = source.int32ChannelData,
              let destinationChannels = destination.int32ChannelData
        else { return false }

        for channel in 0..<channelCount {
            memcpy(destinationChannels[channel], sourceChannels[channel], frameLength * MemoryLayout<Int32>.size)
        }
        return true
    }

    private static func rootMeanSquareLevel(for buffer: AVAudioPCMBuffer) -> Float {
        if let channels = buffer.floatChannelData {
            return floatRootMeanSquareLevel(channels: channels, frameLength: Int(buffer.frameLength), channelCount: Int(buffer.format.channelCount))
        }

        if let channels = buffer.int16ChannelData {
            return int16RootMeanSquareLevel(channels: channels, frameLength: Int(buffer.frameLength), channelCount: Int(buffer.format.channelCount))
        }

        return 1
    }

    private static func floatRootMeanSquareLevel(channels: UnsafePointer<UnsafeMutablePointer<Float>>, frameLength: Int, channelCount: Int) -> Float {
        guard frameLength > 0, channelCount > 0 else { return 0 }

        var sum: Float = 0
        for channel in 0..<channelCount {
            let samples = channels[channel]
            for frame in 0..<frameLength {
                let sample = samples[frame]
                sum += sample * sample
            }
        }

        return sqrt(sum / Float(frameLength * channelCount))
    }

    private static func int16RootMeanSquareLevel(channels: UnsafePointer<UnsafeMutablePointer<Int16>>, frameLength: Int, channelCount: Int) -> Float {
        guard frameLength > 0, channelCount > 0 else { return 0 }

        var sum: Float = 0
        for channel in 0..<channelCount {
            let samples = channels[channel]
            for frame in 0..<frameLength {
                let sample = Float(samples[frame]) / Float(Int16.max)
                sum += sample * sample
            }
        }

        return sqrt(sum / Float(frameLength * channelCount))
    }
}
