import XCTest
@testable import SussurroCore

final class SussurroToolServiceTests: XCTestCase {
    func testTranscribeAudioStoresResultForGetLastTranscription() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let store = LastTranscriptionStore(fileURL: directory.appendingPathComponent("last.json"))
        let service = SussurroToolService(
            transcriber: StubTranscriber(text: "speaker: Ana"),
            lastTranscriptionStore: store
        )

        let transcription = try service.transcribeAudio(at: URL(fileURLWithPath: "/fixture.wav"))

        XCTAssertEqual(transcription.text, "speaker: Ana")
        XCTAssertEqual(try service.getLastTranscription()?.text, "speaker: Ana")
    }

    func testStructureAudioUsesTranscriptionThenOfflineSchemaService() throws {
        let schema = """
        {"type":"object","properties":{"speaker":{"type":"string"}},"required":["speaker"],"additionalProperties":false}
        """.data(using: .utf8)!
        let service = SussurroToolService(
            transcriber: StubTranscriber(text: "speaker: Ana"),
            lastTranscriptionStore: LastTranscriptionStore(fileURL: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString))
        )

        let result = try service.structureAudio(at: URL(fileURLWithPath: "/fixture.wav"), schemaData: schema)

        XCTAssertEqual(result["speaker"] as? String, "Ana")
    }
}

private struct StubTranscriber: AudioTranscribing {
    let text: String

    func transcribe(audioURL: URL) throws -> TranscriptionRecord {
        TranscriptionRecord(text: text, language: "en", audioPath: audioURL.path, createdAt: Date(timeIntervalSince1970: 1))
    }
}