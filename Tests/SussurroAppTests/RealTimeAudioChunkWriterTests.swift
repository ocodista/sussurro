import AVFoundation
import XCTest
@testable import SussurroApp

private final class LockedValues<Value>: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [Value] = []

    var values: [Value] {
        lock.lock()
        defer { lock.unlock() }
        return storage
    }

    func append(_ value: Value) {
        lock.lock()
        storage.append(value)
        lock.unlock()
    }
}

final class RealTimeAudioChunkWriterTests: XCTestCase {
    func testMaximumIntervalClosesContinuousSpeechChunk() throws {
        let format = try XCTUnwrap(AVAudioFormat(standardFormatWithSampleRate: 16_000, channels: 1))
        let sessionDirectoryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("sussurro-realtime-max-test-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: sessionDirectoryURL) }

        let chunks = LockedValues<RealTimeAudioChunk>()
        let errors = LockedValues<String>()
        let writer = try RealTimeAudioChunkWriter(
            format: format,
            chunkInterval: 2,
            sessionDirectoryURL: sessionDirectoryURL,
            onChunkReady: { chunks.append($0) },
            onBreathDetected: { _ in },
            onError: { errors.append($0) }
        )

        for _ in 0..<21 {
            writer.write(Self.buffer(format: format, sample: 0.08))
        }

        XCTAssertTrue(errors.values.isEmpty)
        XCTAssertEqual(chunks.values.count, 1)
        XCTAssertEqual(chunks.values.first?.index, 0)
        XCTAssertGreaterThanOrEqual(chunks.values.first?.duration ?? 0, 2)
    }

    func testFinishFlushesTrailingAudioExactlyOnce() throws {
        let format = try XCTUnwrap(AVAudioFormat(standardFormatWithSampleRate: 16_000, channels: 1))
        let sessionDirectoryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("sussurro-realtime-finish-test-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: sessionDirectoryURL) }

        let chunks = LockedValues<RealTimeAudioChunk>()
        let errors = LockedValues<String>()
        let writer = try RealTimeAudioChunkWriter(
            format: format,
            chunkInterval: 5,
            sessionDirectoryURL: sessionDirectoryURL,
            onChunkReady: { chunks.append($0) },
            onBreathDetected: { _ in },
            onError: { errors.append($0) }
        )

        for _ in 0..<8 {
            writer.write(Self.buffer(format: format, sample: 0.08))
        }
        writer.finish()
        writer.finish()

        XCTAssertTrue(errors.values.isEmpty)
        XCTAssertEqual(chunks.values.count, 1)
        XCTAssertEqual(chunks.values.first?.index, 0)
        XCTAssertEqual(chunks.values.first?.duration ?? 0, 0.8, accuracy: 0.02)
        XCTAssertTrue(FileManager.default.fileExists(atPath: chunks.values[0].url.path))
    }

    func testBreathPauseClosesChunkBeforeMaximumInterval() throws {
        let format = try XCTUnwrap(AVAudioFormat(standardFormatWithSampleRate: 16_000, channels: 1))
        let sessionDirectoryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("sussurro-realtime-test-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: sessionDirectoryURL) }

        let chunks = LockedValues<RealTimeAudioChunk>()
        let breaths = LockedValues<RealTimeBreathDetection>()
        let errors = LockedValues<String>()

        let writer = try RealTimeAudioChunkWriter(
            format: format,
            chunkInterval: 5,
            sessionDirectoryURL: sessionDirectoryURL,
            onChunkReady: { chunk in
                chunks.append(chunk)
            },
            onBreathDetected: { breath in
                breaths.append(breath)
            },
            onError: { message in
                errors.append(message)
            }
        )

        for _ in 0..<12 {
            writer.write(Self.buffer(format: format, sample: 0.08))
        }
        for _ in 0..<4 {
            writer.write(Self.buffer(format: format, sample: 0))
        }

        let capturedChunks = chunks.values
        let capturedBreaths = breaths.values
        let capturedErrors = errors.values

        XCTAssertTrue(capturedErrors.isEmpty)
        XCTAssertEqual(capturedChunks.count, 1)
        XCTAssertEqual(capturedBreaths.count, 1)
        XCTAssertEqual(capturedBreaths.first?.chunkIndex, capturedChunks.first?.index)
        XCTAssertLessThan(capturedChunks[0].duration, 5)
        XCTAssertGreaterThanOrEqual(capturedChunks[0].duration, RealTimeBreathDetectionPolicy.minimumChunkDurationBeforeBreath)
    }

    private static func buffer(
        format: AVAudioFormat,
        sample: Float,
        frameCount: AVAudioFrameCount = 1_600
    ) -> AVAudioPCMBuffer {
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount)!
        buffer.frameLength = frameCount

        let channelCount = Int(format.channelCount)
        let frameLength = Int(frameCount)
        for channel in 0..<channelCount {
            let samples = buffer.floatChannelData![channel]
            for frame in 0..<frameLength {
                samples[frame] = sample
            }
        }

        return buffer
    }
}
