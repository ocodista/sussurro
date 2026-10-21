import XCTest
@testable import SussurroCore

final class MCPRequestHandlerTests: XCTestCase {
    func testToolsListAdvertisesPhaseOneTools() throws {
        let handler = MCPRequestHandler(toolService: makeService())
        let response = try handler.handle(jsonObject: [
            "jsonrpc": "2.0", "id": 1, "method": "tools/list", "params": [:]
        ])!
        let result = response["result"] as! [String: Any]
        let tools = result["tools"] as! [[String: Any]]

        XCTAssertEqual(Set(tools.compactMap { $0["name"] as? String }), [
            "transcribe_audio", "structure_text", "structure_audio", "get_last_transcription", "get_local_readiness"
        ])
    }

    func testGetLocalReadinessReturnsContentFreeCapabilityStatus() throws {
        let report = LocalReadinessReport.evaluate(.init(
            microphone: .unavailable,
            systemAudio: .unavailable,
            whisperCLIURL: nil,
            modelURL: nil,
            mcpExecutableURL: nil
        ))
        let handler = MCPRequestHandler(toolService: makeService(), readinessReport: report)
        let response = try handler.handle(jsonObject: [
            "jsonrpc": "2.0", "id": 7, "method": "tools/call",
            "params": ["name": "get_local_readiness", "arguments": [:]]
        ])!
        let result = response["result"] as! [String: Any]
        let structured = result["structuredContent"] as! [String: Any]

        XCTAssertEqual(result["isError"] as? Bool, false)
        XCTAssertEqual(structured["is_mcp_ready"] as? Bool, false)
        XCTAssertNotNil(structured["privacy_summary"] as? String)
        XCTAssertNil(structured["text"])
        XCTAssertNil(structured["audio_path"])
    }

    func testToolsCallStructureTextReturnsStructuredContent() throws {
        let handler = MCPRequestHandler(toolService: makeService())
        let response = try handler.handle(jsonObject: [
            "jsonrpc": "2.0",
            "id": 2,
            "method": "tools/call",
            "params": [
                "name": "structure_text",
                "arguments": [
                    "text": "speaker: Ana",
                    "schema": [
                        "type": "object",
                        "properties": ["speaker": ["type": "string"]],
                        "required": ["speaker"],
                        "additionalProperties": false
                    ]
                ]
            ]
        ])!
        XCTAssertNil(response["error"])
        let result = response["result"] as? [String: Any]
        let structured = result?["structuredContent"] as? [String: Any]

        XCTAssertEqual(structured?["speaker"] as? String, "Ana")
        XCTAssertEqual(result?["isError"] as? Bool, false)
    }

    private func makeService() -> SussurroToolService {
        SussurroToolService(
            transcriber: MCPStubTranscriber(),
            lastTranscriptionStore: LastTranscriptionStore(fileURL: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString))
        )
    }
}

private struct MCPStubTranscriber: AudioTranscribing {
    func transcribe(audioURL: URL) throws -> TranscriptionRecord {
        TranscriptionRecord(text: "speaker: Ana", language: "en", audioPath: audioURL.path)
    }
}