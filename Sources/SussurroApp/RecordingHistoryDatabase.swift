import Foundation
import SQLite3

final class RecordingHistoryDatabase {
    private let url: URL

    init(url: URL = AppPaths.historyDatabaseURL) {
        self.url = url
    }

    func upsertRecordings(_ recordings: [RecordingHistoryEntry]) throws {
        let connection = try SQLiteConnection(url: url)
        defer { connection.close() }
        try connection.migrate()

        guard !recordings.isEmpty else { return }
        try connection.performImmediateTransaction {
            for recording in recordings {
                try connection.upsertRecording(recording)
            }
        }
    }

    func updateTranscription(
        audioURL: URL,
        transcript: String?,
        status: RecordingTranscriptionStatus,
        modelPath: String?,
        languageCode: String?,
        errorMessage: String?,
        transcribedAt: Date
    ) throws {
        let connection = try SQLiteConnection(url: url)
        defer { connection.close() }
        try connection.migrate()
        try connection.updateTranscription(
            audioURL: audioURL,
            transcript: transcript,
            status: status,
            modelPath: modelPath,
            languageCode: languageCode,
            errorMessage: errorMessage,
            transcribedAt: transcribedAt
        )
    }

    func fetchRecordings() throws -> [RecordingHistoryEntry] {
        let connection = try SQLiteConnection(url: url)
        defer { connection.close() }
        try connection.migrate()
        return try connection.fetchRecordings()
    }
}

private final class SQLiteConnection {
    private let database: OpaquePointer?

    init(url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)

        var database: OpaquePointer?
        let status = sqlite3_open_v2(url.path, &database, SQLITE_OPEN_CREATE | SQLITE_OPEN_READWRITE | SQLITE_OPEN_FULLMUTEX, nil)
        guard status == SQLITE_OK, let openedDatabase = database else {
            let message = database.map(Self.errorMessage(for:)) ?? "Could not open SQLite database."
            if let database {
                sqlite3_close(database)
            }
            throw RecordingHistoryDatabaseError.openFailed(message)
        }

        self.database = openedDatabase
        try configureForAppWorkload()
    }

    func close() {
        if let database {
            sqlite3_exec(database, "PRAGMA optimize;", nil, nil, nil)
            sqlite3_close(database)
        }
    }

    func migrate() throws {
        try execute("""
        CREATE TABLE IF NOT EXISTS recordings (
            audio_path TEXT PRIMARY KEY NOT NULL,
            created_at REAL NOT NULL,
            byte_count INTEGER NOT NULL,
            transcript TEXT NOT NULL DEFAULT '',
            status TEXT NOT NULL DEFAULT 'not_transcribed',
            model_path TEXT,
            language_code TEXT,
            error_message TEXT,
            transcribed_at REAL
        );
        """)

        try execute("CREATE INDEX IF NOT EXISTS recordings_created_at_index ON recordings(created_at DESC);")
        try execute("PRAGMA optimize;")
    }

    func performImmediateTransaction(_ operation: () throws -> Void) throws {
        try execute("BEGIN IMMEDIATE;")
        do {
            try operation()
            try execute("COMMIT;")
        } catch {
            try? execute("ROLLBACK;")
            throw error
        }
    }

    func upsertRecording(_ recording: RecordingHistoryEntry) throws {
        let statement = try prepare("""
        INSERT INTO recordings (audio_path, created_at, byte_count)
        VALUES (?, ?, ?)
        ON CONFLICT(audio_path) DO UPDATE SET
            created_at = excluded.created_at,
            byte_count = excluded.byte_count;
        """)
        defer { sqlite3_finalize(statement) }

        try bindText(recording.url.path, at: 1, in: statement)
        sqlite3_bind_double(statement, 2, recording.createdAt.timeIntervalSince1970)
        sqlite3_bind_int64(statement, 3, recording.byteCount)
        try step(statement)
    }

    func updateTranscription(
        audioURL: URL,
        transcript: String?,
        status: RecordingTranscriptionStatus,
        modelPath: String?,
        languageCode: String?,
        errorMessage: String?,
        transcribedAt: Date
    ) throws {
        let statement = try prepare("""
        UPDATE recordings
        SET transcript = COALESCE(?, transcript),
            status = ?,
            model_path = ?,
            language_code = ?,
            error_message = ?,
            transcribed_at = ?
        WHERE audio_path = ?;
        """)
        defer { sqlite3_finalize(statement) }

        try bindOptionalText(transcript, at: 1, in: statement)
        try bindText(status.rawValue, at: 2, in: statement)
        try bindOptionalText(modelPath, at: 3, in: statement)
        try bindOptionalText(languageCode, at: 4, in: statement)
        try bindOptionalText(errorMessage, at: 5, in: statement)
        sqlite3_bind_double(statement, 6, transcribedAt.timeIntervalSince1970)
        try bindText(audioURL.path, at: 7, in: statement)
        try step(statement)
    }

    func fetchRecordings() throws -> [RecordingHistoryEntry] {
        let statement = try prepare("""
        SELECT audio_path,
               created_at,
               byte_count,
               transcript,
               status,
               model_path,
               language_code,
               error_message,
               transcribed_at
        FROM recordings
        ORDER BY created_at DESC, audio_path DESC;
        """)
        defer { sqlite3_finalize(statement) }

        var recordings: [RecordingHistoryEntry] = []
        while true {
            let status = sqlite3_step(statement)
            if status == SQLITE_DONE {
                return recordings
            }
            guard status == SQLITE_ROW else {
                throw RecordingHistoryDatabaseError.queryFailed(Self.errorMessage(for: database))
            }

            recordings.append(RecordingHistoryEntry(
                url: URL(fileURLWithPath: columnText(statement, index: 0) ?? ""),
                createdAt: Date(timeIntervalSince1970: sqlite3_column_double(statement, 1)),
                byteCount: sqlite3_column_int64(statement, 2),
                transcript: columnText(statement, index: 3) ?? "",
                status: RecordingTranscriptionStatus(rawValue: columnText(statement, index: 4) ?? "") ?? .notTranscribed,
                modelPath: columnText(statement, index: 5),
                languageCode: columnText(statement, index: 6),
                errorMessage: columnText(statement, index: 7),
                transcribedAt: columnDate(statement, index: 8)
            ))
        }
    }

    private func configureForAppWorkload() throws {
        try execute("PRAGMA journal_mode = WAL;")
        try execute("PRAGMA synchronous = NORMAL;")
        try execute("PRAGMA foreign_keys = ON;")
        try execute("PRAGMA busy_timeout = 5000;")
        try execute("PRAGMA temp_store = MEMORY;")
        try execute("PRAGMA cache_size = -64000;")
        try execute("PRAGMA mmap_size = 268435456;")
        try execute("PRAGMA wal_autocheckpoint = 1000;")
    }

    private func execute(_ sql: String) throws {
        var errorMessagePointer: UnsafeMutablePointer<CChar>?
        let status = sqlite3_exec(database, sql, nil, nil, &errorMessagePointer)
        guard status == SQLITE_OK else {
            let message = errorMessagePointer.map { String(cString: $0) } ?? Self.errorMessage(for: database)
            sqlite3_free(errorMessagePointer)
            throw RecordingHistoryDatabaseError.queryFailed(message)
        }
    }

    private func prepare(_ sql: String) throws -> OpaquePointer? {
        var statement: OpaquePointer?
        let status = sqlite3_prepare_v2(database, sql, -1, &statement, nil)
        guard status == SQLITE_OK else {
            throw RecordingHistoryDatabaseError.queryFailed(Self.errorMessage(for: database))
        }
        return statement
    }

    private func step(_ statement: OpaquePointer?) throws {
        let status = sqlite3_step(statement)
        guard status == SQLITE_DONE else {
            throw RecordingHistoryDatabaseError.queryFailed(Self.errorMessage(for: database))
        }
    }

    private func bindText(_ text: String, at index: Int32, in statement: OpaquePointer?) throws {
        let status = text.withCString { textPointer in
            sqlite3_bind_text(statement, index, textPointer, -1, sqliteTransient)
        }
        guard status == SQLITE_OK else {
            throw RecordingHistoryDatabaseError.queryFailed(Self.errorMessage(for: database))
        }
    }

    private func bindOptionalText(_ text: String?, at index: Int32, in statement: OpaquePointer?) throws {
        guard let text, !text.isEmpty else {
            sqlite3_bind_null(statement, index)
            return
        }

        try bindText(text, at: index, in: statement)
    }

    private func columnText(_ statement: OpaquePointer?, index: Int32) -> String? {
        guard sqlite3_column_type(statement, index) != SQLITE_NULL else { return nil }
        guard let text = sqlite3_column_text(statement, index) else { return nil }
        return String(cString: text)
    }

    private func columnDate(_ statement: OpaquePointer?, index: Int32) -> Date? {
        guard sqlite3_column_type(statement, index) != SQLITE_NULL else { return nil }
        return Date(timeIntervalSince1970: sqlite3_column_double(statement, index))
    }

    private static func errorMessage(for database: OpaquePointer?) -> String {
        guard let message = sqlite3_errmsg(database) else { return "Unknown SQLite error." }
        return String(cString: message)
    }
}

private let sqliteTransient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

enum RecordingHistoryDatabaseError: LocalizedError {
    case openFailed(String)
    case queryFailed(String)

    var errorDescription: String? {
        switch self {
        case let .openFailed(message):
            return "Could not open history database: \(message)"
        case let .queryFailed(message):
            return "Could not update history database: \(message)"
        }
    }
}
