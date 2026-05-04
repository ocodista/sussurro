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

    var expandedModelPath: String {
        AppPaths.expandedPath(modelPath.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    var expandedWhisperCLIPath: String {
        AppPaths.expandedPath(whisperCLIPath.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    private static let modelPathKey = "modelPath"
    private static let whisperCLIPathKey = "whisperCLIPath"

    private let userDefaults: UserDefaults

    init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
        modelPath = userDefaults.string(forKey: Self.modelPathKey) ?? Self.defaultModelPath()
        whisperCLIPath = userDefaults.string(forKey: Self.whisperCLIPathKey) ?? Self.defaultWhisperCLIPath()
    }

    func resetPathsToDefaults() {
        modelPath = Self.defaultModelPath()
        whisperCLIPath = Self.defaultWhisperCLIPath()
    }

    private func save(_ value: String, forKey key: String) {
        userDefaults.set(value, forKey: key)
    }

    private static func defaultModelPath() -> String {
        AppPaths.defaultModelURL()?.path ?? AppPaths.preferredModelURL.path
    }

    private static func defaultWhisperCLIPath() -> String {
        AppPaths.defaultWhisperCLIURL()?.path ?? "/opt/homebrew/bin/whisper-cli"
    }
}
