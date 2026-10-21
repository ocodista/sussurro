import AVFoundation
import CoreGraphics
import Foundation
import SussurroCore

@MainActor
enum AppLocalReadiness {
    static func current(settings: AppSettings) -> LocalReadinessReport {
        let executableDirectory = Bundle.main.executableURL?.deletingLastPathComponent()
        return LocalReadinessReport.evaluate(.init(
            microphone: microphonePermission(for: AVCaptureDevice.authorizationStatus(for: .audio)),
            systemAudio: systemAudioPermission(isPreflightAllowed: CGPreflightScreenCaptureAccess()),
            whisperCLIURL: nonEmptyFileURL(settings.expandedWhisperCLIPath),
            modelURL: nonEmptyFileURL(settings.expandedModelPath),
            mcpExecutableURL: executableDirectory?.appendingPathComponent("sussurro-mcp")
        ))
    }

    nonisolated static func microphonePermission(for status: AVAuthorizationStatus) -> PermissionReadiness {
        switch status {
        case .authorized: return .authorized
        case .denied: return .denied
        case .restricted: return .restricted
        case .notDetermined: return .notDetermined
        @unknown default: return .unavailable
        }
    }

    nonisolated static func systemAudioPermission(isPreflightAllowed: Bool) -> PermissionReadiness {
        isPreflightAllowed ? .authorized : .denied
    }

    private static func nonEmptyFileURL(_ path: String) -> URL? {
        path.isEmpty ? nil : URL(fileURLWithPath: path)
    }
}
