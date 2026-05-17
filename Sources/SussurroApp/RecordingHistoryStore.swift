import Foundation

struct RecordingHistoryEntry: Identifiable, Equatable {
    let url: URL
    let createdAt: Date
    let byteCount: Int64
    let transcript: String
    let status: RecordingTranscriptionStatus
    let modelPath: String?
    let languageCode: String?
    let errorMessage: String?
    let transcribedAt: Date?

    var id: String { url.path }
    var fileName: String { url.lastPathComponent }

    var hasTranscript: Bool {
        !transcript.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    init(
        url: URL,
        createdAt: Date,
        byteCount: Int64,
        transcript: String = "",
        status: RecordingTranscriptionStatus = .notTranscribed,
        modelPath: String? = nil,
        languageCode: String? = nil,
        errorMessage: String? = nil,
        transcribedAt: Date? = nil
    ) {
        self.url = url
        self.createdAt = createdAt
        self.byteCount = byteCount
        self.transcript = transcript
        self.status = status
        self.modelPath = modelPath
        self.languageCode = languageCode
        self.errorMessage = errorMessage
        self.transcribedAt = transcribedAt
    }
}

enum RecordingTranscriptionStatus: String, Equatable {
    case notTranscribed = "not_transcribed"
    case completed
    case failed
    case stopped

    var displayTitle: String {
        switch self {
        case .notTranscribed:
            return "Not transcribed"
        case .completed:
            return "Transcribed"
        case .failed:
            return "Failed"
        case .stopped:
            return "Stopped"
        }
    }
}

@MainActor
final class RecordingHistoryStore: ObservableObject {
    @Published private(set) var recordings: [RecordingHistoryEntry] = []
    @Published private(set) var errorMessage: String?

    private let database: RecordingHistoryDatabase

    init(database: RecordingHistoryDatabase = RecordingHistoryDatabase()) {
        self.database = database
    }

    func reload() {
        do {
            let fileRecordings = try Self.scanRecordings(in: AppPaths.recordingsDirectory)
            try database.upsertRecordings(fileRecordings)
            recordings = try database.fetchRecordings()
                .filter { FileManager.default.fileExists(atPath: $0.url.path) }
            errorMessage = nil
        } catch {
            recordings = (try? Self.scanRecordings(in: AppPaths.recordingsDirectory)) ?? []
            errorMessage = "Could not load previous recordings: \(error.localizedDescription)"
        }
    }

    func updateTranscription(
        audioURL: URL,
        transcript: String?,
        status: RecordingTranscriptionStatus,
        modelPath: String?,
        languageCode: String?,
        errorMessage: String?
    ) {
        do {
            try database.updateTranscription(
                audioURL: audioURL,
                transcript: transcript,
                status: status,
                modelPath: modelPath,
                languageCode: languageCode,
                errorMessage: errorMessage,
                transcribedAt: Date()
            )
            reload()
        } catch {
            self.errorMessage = "Could not save transcription history: \(error.localizedDescription)"
        }
    }

    nonisolated static func scanRecordings(in directory: URL, fileManager: FileManager = .default) throws -> [RecordingHistoryEntry] {
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: directory.path, isDirectory: &isDirectory), isDirectory.boolValue else {
            return []
        }

        let resourceKeys: Set<URLResourceKey> = [
            .creationDateKey,
            .contentModificationDateKey,
            .fileSizeKey,
            .isRegularFileKey
        ]

        let urls = try fileManager.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: Array(resourceKeys),
            options: [.skipsHiddenFiles]
        )

        return urls.compactMap { url -> RecordingHistoryEntry? in
            guard Self.isRetryableAudioFile(url) else { return nil }

            let resourceValues = try? url.resourceValues(forKeys: resourceKeys)
            guard resourceValues?.isRegularFile != false else { return nil }

            let createdAt = resourceValues?.creationDate
                ?? resourceValues?.contentModificationDate
                ?? Date.distantPast
            let byteCount = Int64(resourceValues?.fileSize ?? 0)

            return RecordingHistoryEntry(url: url, createdAt: createdAt, byteCount: byteCount)
        }
        .sorted { lhs, rhs in
            if lhs.createdAt == rhs.createdAt {
                return lhs.fileName > rhs.fileName
            }
            return lhs.createdAt > rhs.createdAt
        }
    }

    nonisolated private static func isRetryableAudioFile(_ url: URL) -> Bool {
        guard !url.deletingPathExtension().lastPathComponent.hasSuffix("-whisper") else {
            return false
        }

        switch url.pathExtension.lowercased() {
        case "aif", "aiff", "caf", "m4a", "mp3", "wav":
            return true
        default:
            return false
        }
    }
}
