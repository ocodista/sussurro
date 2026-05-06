import Foundation

struct AppPaths {
    static let applicationName = "Sussurro"
    static let defaultModelFileName = "ggml-large-v3-turbo-q5_0.bin"

    static var applicationSupportDirectory: URL {
        createDirectory(at: userDirectory(.applicationSupportDirectory).appendingPathComponent(applicationName, isDirectory: true))
    }

    static var modelsDirectory: URL {
        createDirectory(at: applicationSupportDirectory.appendingPathComponent("Models", isDirectory: true))
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
        WhisperModelPreset.allCases
            .map(modelURL(for:))
            .first { FileManager.default.fileExists(atPath: $0.path) }
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
