import Foundation

struct AppPaths {
    static let applicationName = "Sussurro"
    static let legacyApplicationName = "CustomSTT"
    static let defaultModelFileName = "ggml-large-v3-turbo-q5_0.bin"

    static var applicationSupportDirectory: URL {
        createDirectory(at: userDirectory(.applicationSupportDirectory).appendingPathComponent(applicationName, isDirectory: true))
    }

    static var modelsDirectory: URL {
        createDirectory(at: applicationSupportDirectory.appendingPathComponent("Models", isDirectory: true))
    }

    static var legacyModelsDirectory: URL {
        userDirectory(.applicationSupportDirectory)
            .appendingPathComponent(legacyApplicationName, isDirectory: true)
            .appendingPathComponent("Models", isDirectory: true)
    }

    static var recordingsDirectory: URL {
        createDirectory(at: applicationSupportDirectory.appendingPathComponent("Recordings", isDirectory: true))
    }

    static var logsDirectory: URL {
        createDirectory(at: userDirectory(.libraryDirectory)
            .appendingPathComponent("Logs", isDirectory: true)
            .appendingPathComponent(applicationName, isDirectory: true))
    }

    static var preferredModelURL: URL {
        modelURL(for: .recommended)
    }

    static func modelURL(for preset: WhisperModelPreset) -> URL {
        modelsDirectory.appendingPathComponent(preset.fileName)
    }

    static var whisperLogURL: URL {
        logsDirectory.appendingPathComponent("whisper-last.log")
    }

    static func defaultWhisperCLIURL() -> URL? {
        let candidates = [
            "/opt/homebrew/bin/whisper-cli",
            "/usr/local/bin/whisper-cli"
        ]
        return candidates.map(URL.init(fileURLWithPath:)).first { FileManager.default.isExecutableFile(atPath: $0.path) }
    }

    static func defaultModelURL() -> URL? {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let projectModelsDirectory = home.appendingPathComponent("personal/sussurro/Models", isDirectory: true)
        let legacyProjectModelsDirectory = home.appendingPathComponent("personal/custom-stt-swift_ui/Models", isDirectory: true)
        let candidates = [
            modelsDirectory.appendingPathComponent(defaultModelFileName),
            modelsDirectory.appendingPathComponent("ggml-base.bin"),
            modelsDirectory.appendingPathComponent("ggml-small.bin"),
            legacyModelsDirectory.appendingPathComponent(defaultModelFileName),
            legacyModelsDirectory.appendingPathComponent("ggml-base.bin"),
            legacyModelsDirectory.appendingPathComponent("ggml-small.bin"),
            home.appendingPathComponent(".whisper-models/ggml-large-v3-turbo-q5_0.bin"),
            home.appendingPathComponent("Library/Application Support/superwhisper/ggml-large-v3-turbo.bin"),
            home.appendingPathComponent("Library/Application Support/superwhisper/ggml-small.en.bin"),
            home.appendingPathComponent("personal/whisper_bun/models/ggml-base.en.bin"),
            projectModelsDirectory.appendingPathComponent(defaultModelFileName),
            projectModelsDirectory.appendingPathComponent("ggml-base.bin"),
            projectModelsDirectory.appendingPathComponent("ggml-small.bin"),
            legacyProjectModelsDirectory.appendingPathComponent(defaultModelFileName),
            legacyProjectModelsDirectory.appendingPathComponent("ggml-base.bin"),
            legacyProjectModelsDirectory.appendingPathComponent("ggml-small.bin")
        ]
        return candidates.first { FileManager.default.fileExists(atPath: $0.path) }
    }

    static func expandedPath(_ path: String) -> String {
        NSString(string: path).expandingTildeInPath
    }

    static func abbreviatedPath(_ url: URL) -> String {
        let path = url.path
        let homePath = FileManager.default.homeDirectoryForCurrentUser.path

        if path == homePath {
            return "~"
        }

        if path.hasPrefix(homePath + "/") {
            return "~" + String(path.dropFirst(homePath.count))
        }

        return path
    }

    private static func userDirectory(_ directory: FileManager.SearchPathDirectory) -> URL {
        if let url = FileManager.default.urls(for: directory, in: .userDomainMask).first {
            return url
        }

        return FileManager.default.homeDirectoryForCurrentUser
    }

    @discardableResult
    private static func createDirectory(at url: URL) -> URL {
        do {
            try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        } catch {
            NSLog("Sussurro: could not create directory at %@: %@", url.path, error.localizedDescription)
        }
        return url
    }
}
