import XCTest
@testable import SussurroApp

final class MeetingPermissionPrompterTests: XCTestCase {
    @MainActor
    func testSystemAudioSettingsURLTargetsSystemAudioPrivacyPane() {
        XCTAssertEqual(
            MeetingPermissionPrompter.systemAudioSettingsURL?.absoluteString,
            "x-apple.systempreferences:com.apple.preference.security?Privacy_AudioCapture"
        )
    }
}
