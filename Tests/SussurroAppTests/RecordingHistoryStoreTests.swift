import Foundation
import XCTest
@testable import SussurroApp

final class RecordingHistoryStoreTests: XCTestCase {
    func testScanRecordingsReturnsRetryableAudioNewestFirst() throws {
        let directory = try makeTemporaryDirectory()
        let oldDate = Date(timeIntervalSince1970: 1_700_000_000)
        let newDate = Date(timeIntervalSince1970: 1_700_000_600)

        try writeFile(named: "recording-old.wav", data: Data([1, 2]), date: oldDate, in: directory)
        try writeFile(named: "recording-new.m4a", data: Data([1, 2, 3]), date: newDate, in: directory)
        try writeFile(named: "recording-new-whisper.wav", data: Data([9]), date: newDate, in: directory)
        try writeFile(named: "notes.txt", data: Data([4]), date: newDate, in: directory)

        let recordings = try RecordingHistoryStore.scanRecordings(in: directory)

        XCTAssertEqual(recordings.map(\.fileName), ["recording-new.m4a", "recording-old.wav"])
        XCTAssertEqual(recordings.map(\.byteCount), [3, 2])
    }

    func testScanRecordingsReturnsEmptyArrayForMissingDirectory() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("SussurroMissingRecordings-\(UUID().uuidString)", isDirectory: true)

        let recordings = try RecordingHistoryStore.scanRecordings(in: directory)

        XCTAssertTrue(recordings.isEmpty)
    }

    func testHistoryDatabasePersistsTranscriptForRecording() throws {
        let directory = try makeTemporaryDirectory()
        let databaseURL = directory.appendingPathComponent("history.sqlite")
        let database = RecordingHistoryDatabase(url: databaseURL)
        let audioURL = directory.appendingPathComponent("recording.wav")
        let createdAt = Date(timeIntervalSince1970: 1_700_000_000)
        let transcribedAt = Date(timeIntervalSince1970: 1_700_000_300)
        let recording = RecordingHistoryEntry(url: audioURL, createdAt: createdAt, byteCount: 42)

        try database.upsertRecordings([recording])
        try database.updateTranscription(
            audioURL: audioURL,
            transcript: "hello from sqlite",
            status: .completed,
            modelPath: "/models/ggml-large.bin",
            languageCode: "en",
            errorMessage: nil,
            transcribedAt: transcribedAt
        )

        let recordings = try database.fetchRecordings()

        XCTAssertEqual(recordings.count, 1)
        XCTAssertEqual(recordings[0].url.path, audioURL.path)
        XCTAssertEqual(recordings[0].transcript, "hello from sqlite")
        XCTAssertEqual(recordings[0].status, .completed)
        XCTAssertEqual(recordings[0].modelPath, "/models/ggml-large.bin")
        XCTAssertEqual(recordings[0].languageCode, "en")
        XCTAssertEqual(recordings[0].transcribedAt, transcribedAt)
    }

    func testHistoryDatabaseKeepsExistingTranscriptWhenRetryFails() throws {
        let directory = try makeTemporaryDirectory()
        let databaseURL = directory.appendingPathComponent("history.sqlite")
        let database = RecordingHistoryDatabase(url: databaseURL)
        let audioURL = directory.appendingPathComponent("recording.wav")
        let recording = RecordingHistoryEntry(url: audioURL, createdAt: Date(), byteCount: 42)

        try database.upsertRecordings([recording])
        try database.updateTranscription(
            audioURL: audioURL,
            transcript: "previous transcript",
            status: .completed,
            modelPath: nil,
            languageCode: nil,
            errorMessage: nil,
            transcribedAt: Date()
        )
        try database.updateTranscription(
            audioURL: audioURL,
            transcript: nil,
            status: .failed,
            modelPath: nil,
            languageCode: nil,
            errorMessage: "model failed",
            transcribedAt: Date()
        )

        let recordings = try database.fetchRecordings()

        XCTAssertEqual(recordings[0].transcript, "previous transcript")
        XCTAssertEqual(recordings[0].status, .failed)
        XCTAssertEqual(recordings[0].errorMessage, "model failed")
    }

    private func makeTemporaryDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("SussurroRecordingHistoryTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        addTeardownBlock {
            try? FileManager.default.removeItem(at: directory)
        }
        return directory
    }

    private func writeFile(named fileName: String, data: Data, date: Date, in directory: URL) throws {
        let url = directory.appendingPathComponent(fileName)
        try data.write(to: url)
        try FileManager.default.setAttributes(
            [.creationDate: date, .modificationDate: date],
            ofItemAtPath: url.path
        )
    }
}
