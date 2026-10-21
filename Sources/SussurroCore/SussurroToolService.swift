import Foundation

public struct TranscriptionRecord: Codable, Equatable, Sendable {
    public let text: String
    public let language: String?
    public let audioPath: String
    public let createdAt: Date

    public init(text: String, language: String?, audioPath: String, createdAt: Date = Date()) {
        self.text = text
        self.language = language
        self.audioPath = audioPath
        self.createdAt = createdAt
    }
}

public protocol AudioTranscribing: Sendable {
    func transcribe(audioURL: URL) throws -> TranscriptionRecord
}

public struct LastTranscriptionStore: Sendable {
    public let fileURL: URL

    public init(fileURL: URL = Self.defaultFileURL) {
        self.fileURL = fileURL
    }

    public static var defaultFileURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/Sussurro/last-transcription.json")
    }

    public func save(_ record: TranscriptionRecord) throws {
        try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        let data = try JSONEncoder.sussurro.encode(record)
        try data.write(to: fileURL, options: [.atomic])
    }

    public func load() throws -> TranscriptionRecord? {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return nil }
        return try JSONDecoder.sussurro.decode(TranscriptionRecord.self, from: Data(contentsOf: fileURL))
    }
}

public struct SussurroToolService: Sendable {
    private let transcriber: any AudioTranscribing
    private let lastTranscriptionStore: LastTranscriptionStore
    private let structuredTextService = StructuredTextService()
    private let eventLogger: PrivacySafeEventLogger

    public init(
        transcriber: any AudioTranscribing,
        lastTranscriptionStore: LastTranscriptionStore = LastTranscriptionStore(),
        eventLogger: PrivacySafeEventLogger = PrivacySafeEventLogger()
    ) {
        self.transcriber = transcriber
        self.lastTranscriptionStore = lastTranscriptionStore
        self.eventLogger = eventLogger
    }

    public func transcribeAudio(at audioURL: URL) throws -> TranscriptionRecord {
        let startedAt = Date()
        do {
            let record = try transcriber.transcribe(audioURL: audioURL)
            try lastTranscriptionStore.save(record)
            eventLogger.write(name: "transcribe_audio.completed", startedAt: startedAt, succeeded: true)
            return record
        } catch {
            eventLogger.write(name: "transcribe_audio.completed", startedAt: startedAt, succeeded: false)
            throw error
        }
    }

    public func structureText(_ text: String, schemaData: Data) throws -> [String: Any] {
        let startedAt = Date()
        do {
            let result = try structuredTextService.structure(text: text, schemaData: schemaData)
            eventLogger.write(name: "structure_text.completed", startedAt: startedAt, succeeded: true)
            return result
        } catch {
            eventLogger.write(name: "structure_text.completed", startedAt: startedAt, succeeded: false)
            throw error
        }
    }

    public func structureAudio(at audioURL: URL, schemaData: Data) throws -> [String: Any] {
        let record = try transcribeAudio(at: audioURL)
        return try structureText(record.text, schemaData: schemaData)
    }

    public func getLastTranscription() throws -> TranscriptionRecord? {
        try lastTranscriptionStore.load()
    }
}

public struct PrivacySafeEventLogger: Sendable {
    public let isEnabled: Bool
    public let fileURL: URL

    public init(isEnabled: Bool = false, fileURL: URL = FileManager.default.temporaryDirectory.appendingPathComponent("sussurro-events.jsonl")) {
        self.isEnabled = isEnabled
        self.fileURL = fileURL
    }

    public func write(name: String, startedAt: Date, succeeded: Bool) {
        guard isEnabled else { return }
        let event: [String: Any] = [
            "event": name,
            "success": succeeded,
            "duration_ms": max(0, Int(Date().timeIntervalSince(startedAt) * 1_000)),
            "timestamp": ISO8601DateFormatter().string(from: Date())
        ]
        guard let data = try? JSONSerialization.data(withJSONObject: event, options: [.sortedKeys]),
              var line = String(data: data, encoding: .utf8)?.data(using: .utf8)
        else { return }
        line.append(0x0A)
        do {
            try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            if FileManager.default.fileExists(atPath: fileURL.path), let handle = try? FileHandle(forWritingTo: fileURL) {
                defer { try? handle.close() }
                try handle.seekToEnd()
                try handle.write(contentsOf: line)
            } else {
                try line.write(to: fileURL, options: [.atomic])
            }
        } catch {
            // Events are best-effort and never affect local transcription behavior.
        }
    }
}

private extension JSONEncoder {
    static var sussurro: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }
}

private extension JSONDecoder {
    static var sussurro: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}
