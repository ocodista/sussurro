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
        whisperCLICandidateURLs().first { FileManager.default.isExecutableFile(atPath: $0.path) }
    }

    static func bundledWhisperCLIURL() -> URL? {
        bundledWhisperCLIURLCandidates().first { FileManager.default.isExecutableFile(atPath: $0.path) }
    }

    static func isBundledWhisperCLIURL(_ url: URL) -> Bool {
        let path = normalizedPath(url)
        return bundledWhisperCLIURLCandidates().contains { normalizedPath($0) == path }
    }

    static func whisperResourcesURL(forExecutableURL executableURL: URL) -> URL? {
        guard isBundledWhisperCLIURL(executableURL) else { return nil }

        return bundledWhisperResourceDirectoryCandidates(forExecutableURL: executableURL)
            .first { FileManager.default.fileExists(atPath: $0.path) }
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

        return uniqueURLs(directories)
    }

    private static func whisperCLICandidateURLs() -> [URL] {
        bundledWhisperCLIURLCandidates()
    }

    private static func bundledWhisperCLIURLCandidates() -> [URL] {
        var candidates: [URL] = []

        if let executableDirectory = Bundle.main.executableURL?.deletingLastPathComponent() {
            candidates.append(executableDirectory.appendingPathComponent("whisper-cli"))
        }

        if let resourceURL = Bundle.main.resourceURL {
            candidates.append(resourceURL.appendingPathComponent("whisper-cli"))
        }

        #if SWIFT_PACKAGE
        if let moduleResourceURL = Bundle.module.resourceURL {
            candidates.append(moduleResourceURL.appendingPathComponent("whisper-cli"))
        }
        #endif

        candidates.append(URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent(".build/sussurro-whisper/artifacts/whisper-cli"))

        return uniqueURLs(candidates)
    }

    private static func bundledWhisperResourceDirectoryCandidates(forExecutableURL executableURL: URL) -> [URL] {
        var candidates: [URL] = []

        if let resourceURL = Bundle.main.resourceURL {
            candidates.append(resourceURL.appendingPathComponent("Whisper", isDirectory: true))
        }

        candidates.append(executableURL.deletingLastPathComponent().appendingPathComponent("resources", isDirectory: true))

        #if SWIFT_PACKAGE
        if let moduleResourceURL = Bundle.module.resourceURL {
            candidates.append(moduleResourceURL.appendingPathComponent("Whisper", isDirectory: true))
        }
        #endif

        return uniqueURLs(candidates)
    }

    private static func uniqueURLs(_ urls: [URL]) -> [URL] {
        var seenPaths = Set<String>()
        var uniqueURLs: [URL] = []

        for url in urls {
            let path = normalizedPath(url)
            guard !seenPaths.contains(path) else { continue }
            seenPaths.insert(path)
            uniqueURLs.append(url)
        }

        return uniqueURLs
    }

    private static func normalizedPath(_ url: URL) -> String {
        url.standardizedFileURL.path
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
