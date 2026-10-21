import Foundation

public enum PermissionReadiness: String, Codable, Sendable {
    case authorized
    case denied
    case restricted
    case notDetermined
    case unavailable
}

public enum ReadinessItemID: String, Codable, CaseIterable, Sendable {
    case microphone
    case systemAudio = "system_audio"
    case whisperCLI = "whisper_cli"
    case model
    case mcp
}

public enum ReadinessStatus: String, Codable, Sendable {
    case ready
    case needsAction = "needs_action"
    case unavailable
}

public enum ReadinessAction: String, Codable, Sendable {
    case none
    case requestMicrophone = "request_microphone"
    case openMicrophoneSettings = "open_microphone_settings"
    case openSystemAudioSettings = "open_system_audio_settings"
    case repairLocalTools = "repair_local_tools"
    case chooseOrDownloadModel = "choose_or_download_model"
    case reinstallApplication = "reinstall_application"
}

public struct ReadinessItem: Codable, Equatable, Sendable {
    public let id: ReadinessItemID
    public let title: String
    public let status: ReadinessStatus
    public let detail: String
    public let action: ReadinessAction
}

public struct LocalReadinessInputs: Sendable {
    public let microphone: PermissionReadiness
    public let systemAudio: PermissionReadiness
    public let whisperCLIURL: URL?
    public let modelURL: URL?
    public let mcpExecutableURL: URL?

    public init(
        microphone: PermissionReadiness,
        systemAudio: PermissionReadiness,
        whisperCLIURL: URL?,
        modelURL: URL?,
        mcpExecutableURL: URL?
    ) {
        self.microphone = microphone
        self.systemAudio = systemAudio
        self.whisperCLIURL = whisperCLIURL
        self.modelURL = modelURL
        self.mcpExecutableURL = mcpExecutableURL
    }
}

public struct LocalReadinessReport: Codable, Equatable, Sendable {
    public let isDictationReady: Bool
    public let isMeetingReady: Bool
    public let isMCPReady: Bool
    public let privacySummary: String
    public let items: [ReadinessItem]

    public func item(id: ReadinessItemID) -> ReadinessItem? {
        items.first { $0.id == id }
    }

    public static func evaluate(
        _ inputs: LocalReadinessInputs,
        fileManager: FileManager = .default
    ) -> LocalReadinessReport {
        let microphone = permissionItem(
            id: .microphone,
            title: "Microphone",
            permission: inputs.microphone,
            deniedDetail: "Allow Microphone access to record dictation and your side of meetings.",
            requestAction: .requestMicrophone,
            deniedAction: .openMicrophoneSettings
        )
        let systemAudio = permissionItem(
            id: .systemAudio,
            title: "System audio",
            permission: inputs.systemAudio,
            deniedDetail: "Allow System Audio Recording to capture the other side of meetings.",
            requestAction: .openSystemAudioSettings,
            deniedAction: .openSystemAudioSettings
        )
        let whisper = executableItem(
            id: .whisperCLI,
            title: "Local transcription engine",
            url: inputs.whisperCLIURL,
            missingDetail: "The local whisper-cli executable is missing or cannot run.",
            action: .repairLocalTools,
            fileManager: fileManager
        )
        let model = fileItem(
            id: .model,
            title: "Whisper model",
            url: inputs.modelURL,
            missingDetail: "Choose or download a local Whisper model.",
            action: .chooseOrDownloadModel,
            fileManager: fileManager
        )
        let mcp = executableItem(
            id: .mcp,
            title: "MCP local tool",
            url: inputs.mcpExecutableURL,
            missingDetail: "The bundled sussurro-mcp executable is unavailable. Reinstall Sussurro.",
            action: .reinstallApplication,
            fileManager: fileManager
        )
        let items = [microphone, systemAudio, whisper, model, mcp]
        let localTranscriptionReady = whisper.status == .ready && model.status == .ready

        return LocalReadinessReport(
            isDictationReady: microphone.status == .ready && localTranscriptionReady,
            isMeetingReady: microphone.status == .ready && systemAudio.status == .ready && localTranscriptionReady,
            isMCPReady: mcp.status == .ready && localTranscriptionReady,
            privacySummary: "Audio and transcripts stay on this Mac. Readiness checks inspect only permission states and local file availability.",
            items: items
        )
    }

    private static func permissionItem(
        id: ReadinessItemID,
        title: String,
        permission: PermissionReadiness,
        deniedDetail: String,
        requestAction: ReadinessAction,
        deniedAction: ReadinessAction
    ) -> ReadinessItem {
        switch permission {
        case .authorized:
            return ReadinessItem(id: id, title: title, status: .ready, detail: "Allowed on this Mac.", action: .none)
        case .notDetermined:
            return ReadinessItem(id: id, title: title, status: .needsAction, detail: deniedDetail, action: requestAction)
        case .denied, .restricted:
            return ReadinessItem(id: id, title: title, status: .needsAction, detail: deniedDetail, action: deniedAction)
        case .unavailable:
            return ReadinessItem(id: id, title: title, status: .unavailable, detail: "This capability is unavailable on this Mac.", action: .none)
        }
    }

    private static func executableItem(
        id: ReadinessItemID,
        title: String,
        url: URL?,
        missingDetail: String,
        action: ReadinessAction,
        fileManager: FileManager
    ) -> ReadinessItem {
        let ready = url.map {
            guard fileManager.isExecutableFile(atPath: $0.path),
                  let values = try? $0.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey]),
                  values.isRegularFile == true,
                  (values.fileSize ?? 0) > 0,
                  let handle = try? FileHandle(forReadingFrom: $0)
            else { return false }
            defer { try? handle.close() }
            guard let prefix = try? handle.read(upToCount: 4_096), !prefix.isEmpty else {
                return false
            }
            return isPlausibleExecutable(prefix)
        } ?? false
        return ReadinessItem(
            id: id,
            title: title,
            status: ready ? .ready : .needsAction,
            detail: ready ? "Available locally." : missingDetail,
            action: ready ? .none : action
        )
    }

    private static func isPlausibleExecutable(_ prefix: Data) -> Bool {
        let bytes = [UInt8](prefix.prefix(4))
        let nativeMagics: [[UInt8]] = [
            [0xCE, 0xFA, 0xED, 0xFE], [0xFE, 0xED, 0xFA, 0xCE],
            [0xCF, 0xFA, 0xED, 0xFE], [0xFE, 0xED, 0xFA, 0xCF],
            [0xCA, 0xFE, 0xBA, 0xBE], [0xBE, 0xBA, 0xFE, 0xCA],
            [0xCA, 0xFE, 0xBA, 0xBF], [0xBF, 0xBA, 0xFE, 0xCA],
            [0x7F, 0x45, 0x4C, 0x46],
        ]
        if nativeMagics.contains(bytes) {
            return true
        }

        guard prefix.starts(with: Data([0x23, 0x21])),
              let newline = prefix.firstIndex(of: 0x0A)
        else {
            return false
        }
        let interpreterLine = prefix[prefix.index(prefix.startIndex, offsetBy: 2)..<newline]
        let interpreter = interpreterLine.drop { byte in
            byte == 0x20 || byte == 0x09 || byte == 0x0D
        }
        return interpreter.count > 1
            && interpreter.first == 0x2F
            && !interpreter.contains(0)
    }

    private static func fileItem(
        id: ReadinessItemID,
        title: String,
        url: URL?,
        missingDetail: String,
        action: ReadinessAction,
        fileManager: FileManager
    ) -> ReadinessItem {
        let ready = url.map {
            guard let values = try? $0.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey]),
                  values.isRegularFile == true,
                  (values.fileSize ?? 0) >= 1_048_576,
                  let handle = try? FileHandle(forReadingFrom: $0)
            else {
                return false
            }
            defer { try? handle.close() }
            guard let header = try? handle.read(upToCount: 4), header.count == 4 else {
                return false
            }
            return header == Data([0x6C, 0x6D, 0x67, 0x67]) // GGML magic 0x67676D6C, little-endian
                || header == Data([0x47, 0x47, 0x55, 0x46]) // GGUF
        } ?? false
        return ReadinessItem(
            id: id,
            title: title,
            status: ready ? .ready : .needsAction,
            detail: ready ? "Available locally." : missingDetail,
            action: ready ? .none : action
        )
    }
}
