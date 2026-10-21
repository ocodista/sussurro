import XCTest
@testable import SussurroApp

final class WhisperTranscriberTests: XCTestCase {
    func testLanguageDisplayCodeUsesRegionLabelsForPortugueseAndEnglish() {
        XCTAssertEqual(WhisperTranscriber.languageDisplayCode(for: "pt"), "PT-BR")
        XCTAssertEqual(WhisperTranscriber.languageDisplayCode(for: "pt-BR"), "PT-BR")
        XCTAssertEqual(WhisperTranscriber.languageDisplayCode(for: "en"), "EN-US")
        XCTAssertEqual(WhisperTranscriber.languageDisplayCode(for: "en_US"), "EN-US")
    }

    func testLanguageDisplayCodeKeepsUnknownLanguagesCompact() {
        XCTAssertEqual(WhisperTranscriber.languageDisplayCode(for: "es"), "ES")
    }

    func testMeetingTranscriptLabelsAndSortsTwoLocalSources() {
        let microphone = MeetingTranscriptSource(
            speakerName: "Person A",
            startOffset: 0.2,
            segments: [WhisperTranscriptionSegment(start: 2.0, end: 3.0, text: "I can hear you.")]
        )
        let systemAudio = MeetingTranscriptSource(
            speakerName: "Person B",
            startOffset: 0,
            segments: [WhisperTranscriptionSegment(start: 1.0, end: 1.8, text: "Hello from the call.")]
        )

        let transcript = WhisperTranscriber.meetingTranscript(from: [microphone, systemAudio])

        XCTAssertEqual(transcript, "[00:01] Person B: Hello from the call.\n[00:02] Person A: I can hear you.")
    }

    func testMeetingTranscriptOmitsEmptySegments() {
        let source = MeetingTranscriptSource(
            speakerName: "Person A",
            startOffset: 0,
            segments: [
                WhisperTranscriptionSegment(start: 0, end: 1, text: "   "),
                WhisperTranscriptionSegment(start: 1, end: 2, text: "Kept verbatim.")
            ]
        )

        let transcript = WhisperTranscriber.meetingTranscript(from: [source])

        XCTAssertEqual(transcript, "[00:01] Person A: Kept verbatim.")
    }

    func testRealTimeTranscriptTrimsAndJoinsChunkTextInOrder() {
        let transcript = WhisperTranscriber.realTimeTranscript(from: [
            "  Hello",
            " ",
            "world.  "
        ])

        XCTAssertEqual(transcript, "Hello world.")
    }

    func testRealTimeBoundaryDeduplicationRemovesRepeatedOverlapWords() {
        let nextText = WhisperTranscriber.removingRepeatedBoundaryWords(
            previousText: "we need to keep every word at the boundary",
            nextText: "word at the boundary without dropping anything new"
        )

        XCTAssertEqual(nextText, "without dropping anything new")
    }

    func testRealTimeBoundaryDeduplicationKeepsUnrelatedText() {
        let nextText = WhisperTranscriber.removingRepeatedBoundaryWords(
            previousText: "hello from the first chunk",
            nextText: "this starts a new phrase"
        )

        XCTAssertEqual(nextText, "this starts a new phrase")
    }
}
