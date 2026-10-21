import Foundation

enum TranscriptionLanguage: String, CaseIterable, Identifiable, Sendable {
    case automatic
    case portugueseBrazil
    case englishUS

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .automatic:
            return "Automatic"
        case .portugueseBrazil:
            return "Português (Brasil)"
        case .englishUS:
            return "English (US)"
        }
    }

    var whisperLanguageCode: String {
        switch self {
        case .automatic:
            return "auto"
        case .portugueseBrazil:
            return "pt"
        case .englishUS:
            return "en"
        }
    }

    static func defaultValue(preferredLanguages: [String] = Locale.preferredLanguages) -> TranscriptionLanguage {
        preferredLanguages.contains { language in
            language.lowercased().split { $0 == "-" || $0 == "_" }.first == "pt"
        } ? .portugueseBrazil : .automatic
    }
}
