import Foundation
import XCTest
@testable import SussurroCore

final class LocalReadinessReportTests: XCTestCase {
    private var directory: URL!

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory)
    }

    func testReadyReportSeparatesDictationMeetingAndMCPReadiness() throws {
        let cli = try executable(named: "whisper-cli")
        let mcp = try executable(named: "sussurro-mcp")
        let model = try whisperModel(named: "model.bin", magic: [0x6C, 0x6D, 0x67, 0x67])

        let report = LocalReadinessReport.evaluate(.init(
            microphone: .authorized,
            systemAudio: .denied,
            whisperCLIURL: cli,
            modelURL: model,
            mcpExecutableURL: mcp
        ))

        XCTAssertTrue(report.isDictationReady)
        XCTAssertFalse(report.isMeetingReady)
        XCTAssertTrue(report.isMCPReady)
        XCTAssertEqual(report.item(id: .systemAudio)?.action, .openSystemAudioSettings)
        XCTAssertEqual(report.item(id: .systemAudio)?.detail, "Allow System Audio Recording to capture the other side of meetings.")
    }

    func testMissingLocalFilesProduceSpecificRecoveryActions() {
        let report = LocalReadinessReport.evaluate(.init(
            microphone: .notDetermined,
            systemAudio: .notDetermined,
            whisperCLIURL: directory.appendingPathComponent("missing-cli"),
            modelURL: directory.appendingPathComponent("missing-model.bin"),
            mcpExecutableURL: directory.appendingPathComponent("missing-mcp")
        ))

        XCTAssertFalse(report.isDictationReady)
        XCTAssertEqual(report.item(id: .microphone)?.action, .requestMicrophone)
        XCTAssertEqual(report.item(id: .whisperCLI)?.action, .repairLocalTools)
        XCTAssertEqual(report.item(id: .model)?.action, .chooseOrDownloadModel)
        XCTAssertEqual(report.item(id: .mcp)?.action, .reinstallApplication)
    }

    func testRejectsTinyModelAndExecutableDirectory() throws {
        let emptyModel = directory.appendingPathComponent("invalid-model.bin")
        try Data("not a Whisper model".utf8).write(to: emptyModel)
        let executableDirectory = directory.appendingPathComponent("not-a-tool", isDirectory: true)
        try FileManager.default.createDirectory(at: executableDirectory, withIntermediateDirectories: true)

        let report = LocalReadinessReport.evaluate(.init(
            microphone: .authorized,
            systemAudio: .authorized,
            whisperCLIURL: executableDirectory,
            modelURL: emptyModel,
            mcpExecutableURL: executableDirectory
        ))

        XCTAssertEqual(report.item(id: .whisperCLI)?.status, .needsAction)
        XCTAssertEqual(report.item(id: .model)?.status, .needsAction)
        XCTAssertEqual(report.item(id: .mcp)?.status, .needsAction)
    }

    func testRejectsZeroByteExecutableFile() throws {
        let emptyExecutable = directory.appendingPathComponent("empty-tool")
        try Data().write(to: emptyExecutable)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: emptyExecutable.path)

        let report = LocalReadinessReport.evaluate(.init(
            microphone: .authorized,
            systemAudio: .authorized,
            whisperCLIURL: emptyExecutable,
            modelURL: nil,
            mcpExecutableURL: emptyExecutable
        ))

        XCTAssertEqual(report.item(id: .whisperCLI)?.status, .needsAction)
        XCTAssertEqual(report.item(id: .mcp)?.status, .needsAction)
    }

    func testRejectsExecutablePermissionOnMalformedBytes() throws {
        let malformedExecutable = directory.appendingPathComponent("malformed-tool")
        try Data(repeating: 0xA5, count: 64).write(to: malformedExecutable)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: malformedExecutable.path)

        let report = LocalReadinessReport.evaluate(.init(
            microphone: .authorized,
            systemAudio: .authorized,
            whisperCLIURL: malformedExecutable,
            modelURL: nil,
            mcpExecutableURL: malformedExecutable
        ))

        XCTAssertEqual(report.item(id: .whisperCLI)?.status, .needsAction)
        XCTAssertEqual(report.item(id: .mcp)?.status, .needsAction)
    }

    func testRejectsScriptWithNonAbsoluteShebangInterpreter() throws {
        let malformedScript = directory.appendingPathComponent("malformed-script")
        try Data("#!bin/sh\nexit 0\n".utf8).write(to: malformedScript)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: malformedScript.path)

        let report = LocalReadinessReport.evaluate(.init(
            microphone: .authorized,
            systemAudio: .authorized,
            whisperCLIURL: malformedScript,
            modelURL: nil,
            mcpExecutableURL: nil
        ))

        XCTAssertEqual(report.item(id: .whisperCLI)?.status, .needsAction)
    }

    func testAcceptsValidExecutableShellFixture() throws {
        let shell = try executable(named: "fixture.sh")
        let report = LocalReadinessReport.evaluate(.init(
            microphone: .authorized,
            systemAudio: .authorized,
            whisperCLIURL: shell,
            modelURL: nil,
            mcpExecutableURL: shell
        ))

        XCTAssertEqual(report.item(id: .whisperCLI)?.status, .ready)
        XCTAssertEqual(report.item(id: .mcp)?.status, .ready)
    }

    func testRejectsRandomOneMiBModelWithoutRecognizedHeader() throws {
        let model = directory.appendingPathComponent("random-model.bin")
        try Data(repeating: 0xA5, count: 1_048_576).write(to: model)

        let report = LocalReadinessReport.evaluate(.init(
            microphone: .authorized,
            systemAudio: .authorized,
            whisperCLIURL: nil,
            modelURL: model,
            mcpExecutableURL: nil
        ))

        XCTAssertEqual(report.item(id: .model)?.status, .needsAction)
    }

    func testRecognizesGGMLAndGGUFModelHeaders() throws {
        for (name, magic) in [
            ("ggml-model.bin", [UInt8](arrayLiteral: 0x6C, 0x6D, 0x67, 0x67)),
            ("gguf-model.gguf", [UInt8](arrayLiteral: 0x47, 0x47, 0x55, 0x46)),
        ] {
            let model = try whisperModel(named: name, magic: magic)
            let report = LocalReadinessReport.evaluate(.init(
                microphone: .authorized,
                systemAudio: .authorized,
                whisperCLIURL: nil,
                modelURL: model,
                mcpExecutableURL: nil
            ))

            XCTAssertEqual(report.item(id: .model)?.status, .ready, name)
        }
    }

    func testPrivacySummaryIsContentFreeAndExplicitlyLocal() throws {
        let report = LocalReadinessReport.evaluate(.init(
            microphone: .restricted,
            systemAudio: .unavailable,
            whisperCLIURL: nil,
            modelURL: nil,
            mcpExecutableURL: nil
        ))
        let data = try JSONEncoder().encode(report)
        let json = String(decoding: data, as: UTF8.self)

        XCTAssertEqual(report.privacySummary, "Audio and transcripts stay on this Mac. Readiness checks inspect only permission states and local file availability.")
        XCTAssertFalse(json.contains("speaker"))
        XCTAssertFalse(json.contains("audio_path"))
        XCTAssertEqual(report.item(id: .systemAudio)?.status, .unavailable)
    }

    private func whisperModel(named name: String, magic: [UInt8]) throws -> URL {
        let url = directory.appendingPathComponent(name)
        var data = Data(magic)
        data.append(Data(repeating: 0, count: 1_048_576 - data.count))
        try data.write(to: url)
        return url
    }

    private func executable(named name: String) throws -> URL {
        let url = directory.appendingPathComponent(name)
        try Data("#!/bin/sh\nexit 0\n".utf8).write(to: url)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: url.path)
        return url
    }
}
