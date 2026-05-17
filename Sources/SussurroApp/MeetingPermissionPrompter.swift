import AppKit
import CoreGraphics
import Foundation

@MainActor
enum MeetingPermissionPrompter {
    static func ensureScreenCapturePermission() -> Bool {
        if CGPreflightScreenCaptureAccess() {
            return true
        }

        let primer = NSAlert()
        primer.alertStyle = .informational
        primer.messageText = "Allow system audio for Meeting mode"
        primer.informativeText = "Sussurro needs macOS Screen & System Audio Recording permission to capture the other participant's audio locally. After approving it, restart Sussurro if macOS asks."
        primer.addButton(withTitle: "Continue")
        primer.addButton(withTitle: "Cancel")

        guard primer.runModal() == .alertFirstButtonReturn else {
            return false
        }

        if CGRequestScreenCaptureAccess() || CGPreflightScreenCaptureAccess() {
            return true
        }

        showOpenSettingsPrompt(
            title: "Screen & System Audio permission needed",
            message: "macOS did not grant capture permission. Open System Settings, enable Sussurro under Screen & System Audio Recording, then restart Sussurro if the setting asks you to."
        )
        return false
    }

    static func showSystemAudioRecoveryPrompt(details: String) {
        showOpenSettingsPrompt(
            title: "System audio capture needs permission",
            message: "Sussurro could not start Meeting mode because macOS blocked system audio capture. Open System Settings, enable Sussurro under Screen & System Audio Recording, then try again.\n\nDetails: \(details)"
        )
    }

    static func openScreenCaptureSettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") else {
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
            openScreenCaptureSettings()
        }
    }
}
