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
        availableModelURL(for: .recommended) ?? modelURL(for: .recommended)
    }

    static func modelURL(for preset: WhisperModelPreset) -> URL {
        modelsDirectory.appendingPathComponent(preset.fileName)
    }

    static func availableModelURL(for preset: WhisperModelPreset) -> URL? {
        let downloadedURL = modelURL(for: preset)
        if FileManager.default.fileExists(atPath: downloadedURL.path) {
            return downloadedURL
        }

        return bundledModelURL(for: preset)
    }

    static func bundledModelURL(for preset: WhisperModelPreset) -> URL? {
        bundledModelDirectories()
            .map { $0.appendingPathComponent(preset.fileName) }
            .first { FileManager.default.fileExists(atPath: $0.path) }
    }

    static func isBundledModelURL(_ url: URL) -> Bool {
        bundledModelDirectories().contains { directory in
            url.path.hasPrefix(directory.path + "/")
        }
    }

    static var historyDatabaseURL: URL {
        applicationSupportDirectory.appendingPathComponent("history.sqlite")
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
        let presets = [WhisperModelPreset.recommended] + WhisperModelPreset.allCases.filter { $0 != .recommended }
        return presets.compactMap(availableModelURL(for:)).first
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

    private static func bundledModelDirectories() -> [URL] {
        var directories: [URL] = []

        if let resourceURL = Bundle.main.resourceURL {
            directories.append(resourceURL.appendingPathComponent("Models", isDirectory: true))
        }

        #if SWIFT_PACKAGE
        if let moduleResourceURL = Bundle.module.resourceURL {
            directories.append(moduleResourceURL.appendingPathComponent("Models", isDirectory: true))
        }
        #endif

        directories.append(URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent("Models", isDirectory: true))

        return directories
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
