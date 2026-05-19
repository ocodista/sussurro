import XCTest
@testable import SussurroApp

final class TranscriptionAutoMinimizePolicyTests: XCTestCase {
    func testMeetingRecordingDoesNotAutoMinimizeAfterTranscription() {
        let recording = RecordedAudio(
            mode: .meeting,
            microphoneURL: URL(fileURLWithPath: "/tmp/meeting-person-a-mic.wav"),
            systemAudioURL: URL(fileURLWithPath: "/tmp/meeting-person-b-system.caf"),
            microphoneStartedAt: Date(),
            systemAudioStartedAt: Date()
        )

        XCTAssertFalse(TranscriptionAutoMinimizePolicy.shouldAutoMinimize(after: recording))
    }

    func testDictationRecordingAutoMinimizesAfterTranscription() {
        let recording = RecordedAudio(
            mode: .dictation,
            microphoneURL: URL(fileURLWithPath: "/tmp/recording.wav"),
            systemAudioURL: nil,
            microphoneStartedAt: Date(),
            systemAudioStartedAt: nil
        )

        XCTAssertTrue(TranscriptionAutoMinimizePolicy.shouldAutoMinimize(after: recording))
    }

    func testMeetingRetryDoesNotAutoMinimize() {
        let recording = RecordingHistoryEntry(
            url: URL(fileURLWithPath: "/tmp/meeting-2026-05-18_10-00-00-person-a-mic.wav"),
            createdAt: Date(),
            byteCount: 42
        )

        XCTAssertFalse(TranscriptionAutoMinimizePolicy.shouldAutoMinimizeAfterRetrying(recording))
    }
}
