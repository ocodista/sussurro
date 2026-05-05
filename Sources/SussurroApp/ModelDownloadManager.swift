import Foundation

enum ModelDownloadState: Equatable {
    case idle
    case downloading(String)
    case completed(String)
    case failed(String)

    var isDownloading: Bool {
        if case .downloading = self { return true }
        return false
    }
}

@MainActor
final class ModelDownloadManager: ObservableObject {
    @Published private(set) var state: ModelDownloadState = .idle

    private var downloadTask: Task<Void, Never>?

    func download(_ preset: WhisperModelPreset, settings: AppSettings) {
        guard !state.isDownloading else { return }

        downloadTask?.cancel()
        downloadTask = Task { [weak self, settings] in
            await self?.downloadModel(preset, settings: settings)
        }
    }

    func cancel() {
        downloadTask?.cancel()
        downloadTask = nil
        state = .idle
    }

    private func downloadModel(_ preset: WhisperModelPreset, settings: AppSettings) async {
        let destinationURL = AppPaths.modelURL(for: preset)

        if FileManager.default.fileExists(atPath: destinationURL.path) {
            settings.modelPath = destinationURL.path
            state = .completed("Using existing \(preset.fileName)")
            return
        }

        state = .downloading("Downloading \(preset.displayName) (\(preset.sizeDescription))…")

        do {
            let (temporaryURL, response) = try await URLSession.shared.download(from: preset.downloadURL)
            try Task.checkCancellation()

            guard let httpResponse = response as? HTTPURLResponse else {
                throw ModelDownloadError.missingHTTPResponse
            }

            guard (200..<300).contains(httpResponse.statusCode) else {
                throw ModelDownloadError.badServerResponse(httpResponse.statusCode)
            }

            try FileManager.default.createDirectory(at: destinationURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try? FileManager.default.removeItem(at: destinationURL)
            try FileManager.default.moveItem(at: temporaryURL, to: destinationURL)

            settings.modelPath = destinationURL.path
            state = .completed("Installed \(preset.fileName)")
        } catch is CancellationError {
            state = .idle
        } catch {
            state = .failed(error.localizedDescription)
        }
    }
}

enum ModelDownloadError: LocalizedError {
    case missingHTTPResponse
    case badServerResponse(Int)

    var errorDescription: String? {
        switch self {
        case .missingHTTPResponse:
            return "The model download did not return an HTTP response."
        case let .badServerResponse(statusCode):
            return "The model download failed with HTTP \(statusCode)."
        }
    }
}
