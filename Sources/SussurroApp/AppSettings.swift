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

    private let userDefaults: UserDefaults

    init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults

        let storedModelPath = userDefaults.string(forKey: Self.modelPathKey)
        let resolvedModelPath = Self.resolvedModelPath(storedModelPath)
        modelPath = resolvedModelPath
        whisperCLIPath = userDefaults.string(forKey: Self.whisperCLIPathKey) ?? Self.defaultWhisperCLIPath()
        selectedInputDeviceUID = userDefaults.string(forKey: Self.selectedInputDeviceUIDKey) ?? ""

        if storedModelPath != resolvedModelPath {
            userDefaults.set(resolvedModelPath, forKey: Self.modelPathKey)
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

    private static func defaultWhisperCLIPath() -> String {
        AppPaths.defaultWhisperCLIURL()?.path ?? "/opt/homebrew/bin/whisper-cli"
    }
}
