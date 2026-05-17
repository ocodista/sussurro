import XCTest
@testable import SussurroApp

final class AppPathsTests: XCTestCase {
    func testDefaultWhisperCLIURLDoesNotRequireHomebrewInstall() {
        let defaultURL = AppPaths.defaultWhisperCLIURL()

        XCTAssertNotEqual(defaultURL?.path, "/opt/homebrew/bin/whisper-cli")
        XCTAssertNotEqual(defaultURL?.path, "/usr/local/bin/whisper-cli")
    }

    func testAbbreviatedPathReplacesHomeDirectoryWithTilde() {
        let homeURL = FileManager.default.homeDirectoryForCurrentUser
        let modelURL = homeURL
            .appendingPathComponent("Library/Application Support/Sussurro/Models", isDirectory: true)
            .appendingPathComponent("ggml-base.bin")

        XCTAssertEqual(
            AppPaths.abbreviatedPath(modelURL),
            "~/Library/Application Support/Sussurro/Models/ggml-base.bin"
        )
    }
}
