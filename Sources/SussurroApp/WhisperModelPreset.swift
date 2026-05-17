import Foundation

enum WhisperModelPreset: String, CaseIterable, Identifiable {
    case turbo
    case small
    case base

    static let recommended: WhisperModelPreset = .turbo

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .turbo:
            return "Large v3 Turbo Q5_0"
        case .small:
            return "Small"
        case .base:
            return "Base"
        }
    }

    var fileName: String {
        switch self {
        case .turbo:
            return "ggml-large-v3-turbo-q5_0.bin"
        case .small:
            return "ggml-small.bin"
        case .base:
            return "ggml-base.bin"
        }
    }

    var downloadURL: URL {
        URL(string: "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/\(fileName)")!
    }

    var sizeDescription: String {
        switch self {
        case .turbo:
            return "about 550 MB"
        case .small:
            return "about 465 MB"
        case .base:
            return "about 145 MB"
        }
    }

    var setupDescription: String {
        switch self {
        case .turbo:
            return "Recommended. Best quality/speed balance for Apple Silicon; multilingual and still fast because it is Turbo + Q5_0 quantized."
        case .small:
            return "Balanced fallback. Smaller than Turbo and usually faster, but less accurate on noisy audio and mixed languages."
        case .base:
            return "Fastest lightweight option. Good for quick tests, but accuracy drops noticeably on real dictation."
        }
    }

    var isRecommended: Bool { self == Self.recommended }

    static func preset(forFileName fileName: String) -> WhisperModelPreset? {
        allCases.first { $0.fileName == fileName }
    }
}

enum WhisperSetupCommands {
    static func fullInstallCommand(for preset: WhisperModelPreset) -> String {
        """
        mkdir -p "$HOME/Library/Application Support/Sussurro/Models"
        curl -L --fail --progress-bar "\(preset.downloadURL.absoluteString)" -o "$HOME/Library/Application Support/Sussurro/Models/\(preset.fileName)"
        """
    }
}
