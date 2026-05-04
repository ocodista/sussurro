import Foundation

struct AppPaths {
    static let applicationName = "CustomSTT"
    static let defaultModelFileName = "ggml-large-v3-turbo-q5_0.bin"
    static let defaultFasterWhisperModelName = "large-v3-turbo"

    static var applicationSupportDirectory: URL {
        createDirectory(at: userDirectory(.applicationSupportDirectory).appendingPathComponent(applicationName, isDirectory: true))
    }

    static var modelsDirectory: URL {
        createDirectory(at: applicationSupportDirectory.appendingPathComponent("Models", isDirectory: true))
    }

    static var fasterWhisperModelsDirectory: URL {
        createDirectory(at: modelsDirectory.appendingPathComponent("FasterWhisper", isDirectory: true))
    }

    static var recordingsDirectory: URL {
        createDirectory(at: applicationSupportDirectory.appendingPathComponent("Recordings", isDirectory: true))
    }

    static var cacheDirectory: URL {
        createDirectory(at: userDirectory(.cachesDirectory).appendingPathComponent(applicationName, isDirectory: true))
    }

    static var huggingFaceCacheDirectory: URL {
        createDirectory(at: cacheDirectory.appendingPathComponent("HuggingFace", isDirectory: true))
    }

    static var logsDirectory: URL {
        createDirectory(at: userDirectory(.libraryDirectory)
            .appendingPathComponent("Logs", isDirectory: true)
            .appendingPathComponent(applicationName, isDirectory: true))
    }

    static var preferredModelURL: URL {
        modelsDirectory.appendingPathComponent(defaultModelFileName)
    }

    static var whisperLogURL: URL {
        logsDirectory.appendingPathComponent("whisper-last.log")
    }

    static var fasterWhisperVirtualEnvironmentDirectory: URL {
        applicationSupportDirectory.appendingPathComponent("faster-whisper-venv", isDirectory: true)
    }

    static var fasterWhisperVirtualEnvironmentPythonURL: URL {
        fasterWhisperVirtualEnvironmentDirectory.appendingPathComponent("bin/python")
    }

    static func defaultWhisperCLIURL() -> URL? {
        let candidates = [
            "/opt/homebrew/bin/whisper-cli",
            "/usr/local/bin/whisper-cli"
        ]
        return candidates.map(URL.init(fileURLWithPath:)).first { FileManager.default.isExecutableFile(atPath: $0.path) }
    }

    static func defaultPythonURL() -> URL? {
        let candidates = [
            fasterWhisperVirtualEnvironmentPythonURL.path,
            "/opt/homebrew/bin/python3",
            "/usr/local/bin/python3",
            "/usr/bin/python3"
        ]
        return candidates.map(URL.init(fileURLWithPath:)).first { FileManager.default.isExecutableFile(atPath: $0.path) }
    }

    static func defaultModelURL() -> URL? {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let legacyProjectModelsDirectory = home.appendingPathComponent("personal/custom-stt-swift_ui/Models", isDirectory: true)
        let candidates = [
            modelsDirectory.appendingPathComponent(defaultModelFileName),
            modelsDirectory.appendingPathComponent("ggml-base.bin"),
            modelsDirectory.appendingPathComponent("ggml-small.bin"),
            home.appendingPathComponent(".whisper-models/ggml-large-v3-turbo-q5_0.bin"),
            home.appendingPathComponent("Library/Application Support/superwhisper/ggml-large-v3-turbo.bin"),
            home.appendingPathComponent("Library/Application Support/superwhisper/ggml-small.en.bin"),
            home.appendingPathComponent("personal/whisper_bun/models/ggml-base.en.bin"),
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
            NSLog("CustomSTT: could not create directory at %@: %@", url.path, error.localizedDescription)
        }
        return url
    }
}
