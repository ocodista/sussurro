import Foundation

struct AppSetupStatus {
    let whisperCLIPath: String
    let isWhisperCLIReady: Bool
    let modelPath: String
    let isModelReady: Bool

    var isReady: Bool {
        isWhisperCLIReady && isModelReady
    }

    var whisperCLIDetail: String {
        if whisperCLIPath.isEmpty {
            return "Missing path"
        }

        if isWhisperCLIReady {
            return AppPaths.abbreviatedPath(URL(fileURLWithPath: whisperCLIPath))
        }

        return "Not executable at \(AppPaths.abbreviatedPath(URL(fileURLWithPath: whisperCLIPath)))"
    }

    var modelDetail: String {
        if modelPath.isEmpty {
            return "Missing path"
        }

        if isModelReady {
            return AppPaths.abbreviatedPath(URL(fileURLWithPath: modelPath))
        }

        return "Not found at \(AppPaths.abbreviatedPath(URL(fileURLWithPath: modelPath)))"
    }

    @MainActor
    static func current(settings: AppSettings) -> AppSetupStatus {
        let whisperCLIPath = settings.expandedWhisperCLIPath
        let modelPath = settings.expandedModelPath

        return AppSetupStatus(
            whisperCLIPath: whisperCLIPath,
            isWhisperCLIReady: !whisperCLIPath.isEmpty && FileManager.default.isExecutableFile(atPath: whisperCLIPath),
            modelPath: modelPath,
            isModelReady: !modelPath.isEmpty && FileManager.default.fileExists(atPath: modelPath)
        )
    }

    @MainActor
    static func requiresAttention(settings: AppSettings) -> Bool {
        !current(settings: settings).isReady
    }
}
