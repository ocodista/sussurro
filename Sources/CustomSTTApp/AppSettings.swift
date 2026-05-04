import Foundation

@MainActor
final class AppSettings: ObservableObject {
    static let shared = AppSettings()

    @Published var useFasterWhisper: Bool {
        didSet { userDefaults.set(useFasterWhisper, forKey: Self.useFasterWhisperKey) }
    }

    @Published var modelPath: String {
        didSet { save(modelPath, forKey: Self.modelPathKey) }
    }

    @Published var whisperCLIPath: String {
        didSet { save(whisperCLIPath, forKey: Self.whisperCLIPathKey) }
    }

    @Published var fasterWhisperModel: String {
        didSet { save(fasterWhisperModel, forKey: Self.fasterWhisperModelKey) }
    }

    @Published var fasterWhisperPythonPath: String {
        didSet { save(fasterWhisperPythonPath, forKey: Self.fasterWhisperPythonPathKey) }
    }

    @Published var fasterWhisperDevice: String {
        didSet { save(fasterWhisperDevice, forKey: Self.fasterWhisperDeviceKey) }
    }

    var expandedModelPath: String {
        AppPaths.expandedPath(modelPath.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    var expandedWhisperCLIPath: String {
        AppPaths.expandedPath(whisperCLIPath.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    var expandedFasterWhisperPythonPath: String {
        AppPaths.expandedPath(fasterWhisperPythonPath.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    var resolvedFasterWhisperModel: String {
        let trimmedModel = fasterWhisperModel.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmedModel.hasPrefix("~") {
            return AppPaths.expandedPath(trimmedModel)
        }
        return trimmedModel
    }

    private static let useFasterWhisperKey = "useFasterWhisper"
    private static let modelPathKey = "modelPath"
    private static let whisperCLIPathKey = "whisperCLIPath"
    private static let fasterWhisperModelKey = "fasterWhisperModel"
    private static let fasterWhisperPythonPathKey = "fasterWhisperPythonPath"
    private static let fasterWhisperDeviceKey = "fasterWhisperDevice"

    private let userDefaults: UserDefaults

    init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
        useFasterWhisper = userDefaults.bool(forKey: Self.useFasterWhisperKey)
        modelPath = userDefaults.string(forKey: Self.modelPathKey) ?? Self.defaultModelPath()
        whisperCLIPath = userDefaults.string(forKey: Self.whisperCLIPathKey) ?? Self.defaultWhisperCLIPath()
        fasterWhisperModel = userDefaults.string(forKey: Self.fasterWhisperModelKey) ?? AppPaths.defaultFasterWhisperModelName
        fasterWhisperPythonPath = userDefaults.string(forKey: Self.fasterWhisperPythonPathKey) ?? Self.defaultPythonPath()
        fasterWhisperDevice = userDefaults.string(forKey: Self.fasterWhisperDeviceKey) ?? "auto"
    }

    func resetPathsToDefaults() {
        modelPath = Self.defaultModelPath()
        whisperCLIPath = Self.defaultWhisperCLIPath()
        fasterWhisperModel = AppPaths.defaultFasterWhisperModelName
        fasterWhisperPythonPath = Self.defaultPythonPath()
        fasterWhisperDevice = "auto"
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

    private static func defaultPythonPath() -> String {
        AppPaths.defaultPythonURL()?.path ?? "/usr/bin/python3"
    }
}
