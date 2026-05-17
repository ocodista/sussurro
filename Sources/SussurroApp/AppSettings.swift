import Foundation

@MainActor
final class AppSettings: ObservableObject {
    static let shared = AppSettings()

    @Published var modelPath: String {
        didSet { save(modelPath, forKey: Self.modelPathKey) }
    }

    @Published var whisperCLIPath: String {
        didSet { save(whisperCLIPath, forKey: Self.whisperCLIPathKey) }
    }

    @Published var selectedInputDeviceUID: String {
        didSet { save(selectedInputDeviceUID, forKey: Self.selectedInputDeviceUIDKey) }
    }

    var expandedModelPath: String {
        AppPaths.expandedPath(modelPath.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    var expandedWhisperCLIPath: String {
        AppPaths.expandedPath(whisperCLIPath.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    private static let modelPathKey = "modelPath"
    private static let whisperCLIPathKey = "whisperCLIPath"
    private static let selectedInputDeviceUIDKey = "selectedInputDeviceUID"
    private static let didMigrateLegacyWhisperCLIPathKey = "didMigrateLegacyWhisperCLIPath"

    private let userDefaults: UserDefaults

    init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults

        let storedModelPath = userDefaults.string(forKey: Self.modelPathKey)
        let resolvedModelPath = Self.resolvedModelPath(storedModelPath)
        let storedWhisperCLIPath = userDefaults.string(forKey: Self.whisperCLIPathKey)
        let resolvedWhisperCLIPath = Self.resolvedWhisperCLIPath(
            storedWhisperCLIPath,
            hasMigratedLegacyDefault: userDefaults.bool(forKey: Self.didMigrateLegacyWhisperCLIPathKey)
        )
        modelPath = resolvedModelPath
        whisperCLIPath = resolvedWhisperCLIPath.path
        selectedInputDeviceUID = userDefaults.string(forKey: Self.selectedInputDeviceUIDKey) ?? ""

        if storedModelPath != resolvedModelPath {
            userDefaults.set(resolvedModelPath, forKey: Self.modelPathKey)
        }
        if storedWhisperCLIPath != resolvedWhisperCLIPath.path {
            userDefaults.set(resolvedWhisperCLIPath.path, forKey: Self.whisperCLIPathKey)
        }
        if resolvedWhisperCLIPath.didMigrateLegacyDefault {
            userDefaults.set(true, forKey: Self.didMigrateLegacyWhisperCLIPathKey)
        }
    }

    func resetPathsToDefaults() {
        modelPath = Self.defaultModelPath()
        whisperCLIPath = Self.defaultWhisperCLIPath()
    }

    private func save(_ value: String, forKey key: String) {
        userDefaults.set(value, forKey: key)
    }

    private static func resolvedModelPath(_ storedModelPath: String?) -> String {
        guard let storedModelPath else { return defaultModelPath() }

        let expandedStoredPath = AppPaths.expandedPath(storedModelPath.trimmingCharacters(in: .whitespacesAndNewlines))
        guard !expandedStoredPath.isEmpty else { return defaultModelPath() }
        guard !FileManager.default.fileExists(atPath: expandedStoredPath) else { return storedModelPath }

        return defaultModelPath()
    }

    private static func defaultModelPath() -> String {
        AppPaths.defaultModelURL()?.path ?? AppPaths.preferredModelURL.path
    }

    private static func resolvedWhisperCLIPath(
        _ storedWhisperCLIPath: String?,
        hasMigratedLegacyDefault: Bool
    ) -> (path: String, didMigrateLegacyDefault: Bool) {
        let defaultPath = defaultWhisperCLIPath()
        guard let storedWhisperCLIPath else { return (defaultPath, false) }

        let expandedStoredPath = AppPaths.expandedPath(storedWhisperCLIPath.trimmingCharacters(in: .whitespacesAndNewlines))
        guard !expandedStoredPath.isEmpty else { return (defaultPath, false) }

        let storedURL = URL(fileURLWithPath: expandedStoredPath)
        if AppPaths.isBundledWhisperCLIURL(storedURL) || isAppBundleWhisperCLIPath(expandedStoredPath) {
            return (defaultPath, false)
        }

        if !hasMigratedLegacyDefault && !defaultPath.isEmpty && isHomebrewDefaultWhisperCLIPath(expandedStoredPath) {
            return (defaultPath, true)
        }

        guard FileManager.default.isExecutableFile(atPath: expandedStoredPath) else { return (defaultPath, false) }
        return (storedWhisperCLIPath, false)
    }

    private static func isHomebrewDefaultWhisperCLIPath(_ path: String) -> Bool {
        path == "/opt/homebrew/bin/whisper-cli" || path == "/usr/local/bin/whisper-cli"
    }

    private static func isAppBundleWhisperCLIPath(_ path: String) -> Bool {
        path.contains(".app/Contents/MacOS/whisper-cli")
    }

    private static func defaultWhisperCLIPath() -> String {
        AppPaths.defaultWhisperCLIURL()?.path ?? ""
    }
}
