import XCTest
@testable import SussurroApp

final class AppPathsTests: XCTestCase {
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
