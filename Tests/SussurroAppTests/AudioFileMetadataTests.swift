import AVFoundation
import XCTest
@testable import SussurroApp

final class AudioFileMetadataTests: XCTestCase {
    private var temporaryDirectory: URL!

    override func setUpWithError() throws {
        temporaryDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("sussurro-audio-file-metadata-tests-")
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        if let temporaryDirectory {
            try? FileManager.default.removeItem(at: temporaryDirectory)
        }
        temporaryDirectory = nil
    }

    func testByteCountReturnsFileSize() throws {
        let url = temporaryDirectory.appendingPathComponent("recording.wav")
        try Data(repeating: 0, count: 128).write(to: url)

        XCTAssertEqual(AudioFileMetadata.byteCount(for: url), 128)
    }

    func testRecordingByteCountSumsMicrophoneAndSystemAudio() throws {
        let microphoneURL = temporaryDirectory.appendingPathComponent("mic.wav")
        let systemAudioURL = temporaryDirectory.appendingPathComponent("system.caf")
        try Data(repeating: 0, count: 64).write(to: microphoneURL)
        try Data(repeating: 0, count: 96).write(to: systemAudioURL)

        let recording = RecordedAudio(
            mode: .meeting,
            microphoneURL: microphoneURL,
            systemAudioURL: systemAudioURL,
            microphoneStartedAt: Date(),
            systemAudioStartedAt: Date()
        )

        XCTAssertEqual(AudioFileMetadata.byteCount(for: recording), 160)
    }

    func testDurationReadsAudioLength() throws {
        let url = temporaryDirectory.appendingPathComponent("recording.caf")
        try writeSilentAudio(to: url, duration: 1.25)

        let duration = try XCTUnwrap(AudioFileMetadata.duration(for: url))

        XCTAssertEqual(duration, 1.25, accuracy: 0.01)
    }

    func testRecordingDurationUsesLongestOffsetAudio() throws {
        let microphoneURL = temporaryDirectory.appendingPathComponent("mic.caf")
        let systemAudioURL = temporaryDirectory.appendingPathComponent("system.caf")
        try writeSilentAudio(to: microphoneURL, duration: 1.0)
        try writeSilentAudio(to: systemAudioURL, duration: 1.0)

        let startedAt = Date()
        let recording = RecordedAudio(
            mode: .meeting,
            microphoneURL: microphoneURL,
            systemAudioURL: systemAudioURL,
            microphoneStartedAt: startedAt,
            systemAudioStartedAt: startedAt.addingTimeInterval(0.5)
        )

        let duration = try XCTUnwrap(AudioFileMetadata.duration(for: recording))

        XCTAssertEqual(duration, 1.5, accuracy: 0.01)
    }

    private func writeSilentAudio(to url: URL, duration: TimeInterval) throws {
        let sampleRate = 16_000.0
        let frameCount = AVAudioFrameCount((duration * sampleRate).rounded())
        let format = try XCTUnwrap(AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1))
        let buffer = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount))
        buffer.frameLength = frameCount

        let file = try AVAudioFile(forWriting: url, settings: format.settings)
        try file.write(from: buffer)
    }
}
