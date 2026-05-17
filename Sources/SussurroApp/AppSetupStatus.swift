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

        let whisperCLIURL = URL(fileURLWithPath: whisperCLIPath)
        if isWhisperCLIReady {
            if AppPaths.isBundledWhisperCLIURL(whisperCLIURL) {
                return "Included with Sussurro · whisper-cli"
            }
            return AppPaths.abbreviatedPath(whisperCLIURL)
        }

        return "Not executable at \(AppPaths.abbreviatedPath(whisperCLIURL))"
    }

    var modelDetail: String {
        if modelPath.isEmpty {
            return "Missing path"
        }

        let modelURL = URL(fileURLWithPath: modelPath)
        if isModelReady {
            if AppPaths.isBundledModelURL(modelURL) {
                return "Included with Sussurro · \(modelURL.lastPathComponent)"
            }
            return AppPaths.abbreviatedPath(modelURL)
        }

        return "Not found at \(AppPaths.abbreviatedPath(modelURL))"
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
