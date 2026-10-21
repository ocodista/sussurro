import AVFoundation
import XCTest
import SussurroCore
@testable import SussurroApp

final class AppLocalReadinessTests: XCTestCase {
    func testMapsMicrophoneAuthorizationWithoutRequestingContentAccess() {
        XCTAssertEqual(AppLocalReadiness.microphonePermission(for: .authorized), .authorized)
        XCTAssertEqual(AppLocalReadiness.microphonePermission(for: .denied), .denied)
        XCTAssertEqual(AppLocalReadiness.microphonePermission(for: .restricted), .restricted)
        XCTAssertEqual(AppLocalReadiness.microphonePermission(for: .notDetermined), .notDetermined)
    }

    func testSystemAudioPreflightMapsToActionablePermissionState() {
        XCTAssertEqual(AppLocalReadiness.systemAudioPermission(isPreflightAllowed: true), .authorized)
        XCTAssertEqual(AppLocalReadiness.systemAudioPermission(isPreflightAllowed: false), .denied)
    }
}
