import XCTest
@testable import SussurroCore

final class LocalWhisperTranscriberTests: XCTestCase {
    func testTranscribesWAVWithConfiguredLocalWhisperExecutable() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let audio = directory.appendingPathComponent("fixture.wav")
        let model = directory.appendingPathComponent("model.bin")
        let cli = directory.appendingPathComponent("whisper-cli")
        try Data("RIFFfixture".utf8).write(to: audio)
        try Data("model".utf8).write(to: model)
        try """
        #!/bin/sh
        while [ "$#" -gt 0 ]; do
          if [ "$1" = "-of" ]; then shift; output="$1"; fi
          shift
        done
        printf '{"result":{"language":"en"},"transcription":[]}' > "${output}.json"
        printf 'speaker: Ana\nminutes: 12\napproved: true\n'
        """.write(to: cli, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: cli.path)

        let transcriber = LocalWhisperTranscriber(
            whisperCLIURL: cli,
            modelURL: model,
            language: "en"
        )

        let result = try transcriber.transcribe(audioURL: audio)

        XCTAssertEqual(result.text, "speaker: Ana\nminutes: 12\napproved: true")
        XCTAssertEqual(result.language, "en")
    }
}