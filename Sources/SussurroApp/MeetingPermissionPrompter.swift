import AppKit
import Foundation

@MainActor
enum MeetingPermissionPrompter {
    static let systemAudioSettingsURL = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AudioCapture")

    static func showSystemAudioRecoveryPrompt(details: String) {
        showOpenSettingsPrompt(
            title: "System audio capture needs permission",
            message: "Sussurro could not start Meeting mode because macOS blocked system audio capture. Open System Settings, enable Sussurro under System Audio Recording, then restart Sussurro. If it is already enabled, remove and re-enable Sussurro to refresh the macOS privacy grant.\n\nDetails: \(details)"
        )
    }

    static func openSystemAudioSettings() {
        guard let url = systemAudioSettingsURL else {
            return
        }
        NSWorkspace.shared.open(url)
    }

    private static func showOpenSettingsPrompt(title: String, message: String) {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = title
        alert.informativeText = message
        alert.addButton(withTitle: "Open System Settings")
        alert.addButton(withTitle: "Not Now")

        if alert.runModal() == .alertFirstButtonReturn {
            openSystemAudioSettings()
        }
    }
}
