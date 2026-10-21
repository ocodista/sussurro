import Foundation

public struct MCPServerConfiguration: Sendable, Equatable {
    public let whisperCLIURL: URL
    public let modelURL: URL
    public let language: String
    public let eventsFileURL: URL?
    public let lastTranscriptionFileURL: URL

    public var eventsEnabled: Bool { eventsFileURL != nil }

    public static func parse(arguments: [String], environment: [String: String]) throws -> Self {
        var values: [String: String] = [:]
        var index = 1
        while index < arguments.count {
            let key = arguments[index]
            guard key.hasPrefix("--"), index + 1 < arguments.count else {
                throw MCPConfigurationError.invalidArgument(key)
            }
            values[key] = arguments[index + 1]
            index += 2
        }

        guard let cli = values["--whisper-cli"] ?? environment["SUSSURRO_WHISPER_CLI"], !cli.isEmpty else {
            throw MCPConfigurationError.missing("--whisper-cli or SUSSURRO_WHISPER_CLI")
        }
        guard let model = values["--model"] ?? environment["SUSSURRO_MODEL"], !model.isEmpty else {
            throw MCPConfigurationError.missing("--model or SUSSURRO_MODEL")
        }
        let events = values["--events-file"] ?? environment["SUSSURRO_EVENTS_FILE"]
        let last = values["--last-transcription-file"] ?? environment["SUSSURRO_LAST_TRANSCRIPTION_FILE"]
        return Self(
            whisperCLIURL: URL(fileURLWithPath: cli),
            modelURL: URL(fileURLWithPath: model),
            language: values["--language"] ?? environment["SUSSURRO_LANGUAGE"] ?? "auto",
            eventsFileURL: events.map { URL(fileURLWithPath: $0) },
            lastTranscriptionFileURL: last.map { URL(fileURLWithPath: $0) } ?? LastTranscriptionStore.defaultFileURL
        )
    }
}

public enum MCPConfigurationError: LocalizedError {
    case missing(String)
    case invalidArgument(String)

    public var errorDescription: String? {
        switch self {
        case let .missing(value): return "Missing MCP configuration: \(value)."
        case let .invalidArgument(value): return "Invalid MCP argument: \(value)."
        }
    }
}
