import XCTest
@testable import SussurroCore

final class MCPServerConfigurationTests: XCTestCase {
    func testParsesRequiredLocalPathsAndOptInEvents() throws {
        let configuration = try MCPServerConfiguration.parse(arguments: [
            "sussurro-mcp", "--whisper-cli", "/tmp/whisper-cli", "--model", "/tmp/model.bin",
            "--language", "en", "--events-file", "/tmp/events.jsonl"
        ], environment: [:])

        XCTAssertEqual(configuration.whisperCLIURL.path, "/tmp/whisper-cli")
        XCTAssertEqual(configuration.modelURL.path, "/tmp/model.bin")
        XCTAssertEqual(configuration.language, "en")
        XCTAssertTrue(configuration.eventsEnabled)
    }
}