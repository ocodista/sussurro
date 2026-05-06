import XCTest
@testable import SussurroApp

final class WhisperModelPresetTests: XCTestCase {
    func testPresetLookupMatchesKnownFileNames() {
        for preset in WhisperModelPreset.allCases {
            XCTAssertEqual(WhisperModelPreset.preset(forFileName: preset.fileName), preset)
        }
    }

    func testDownloadURLsUseHTTPSHuggingFaceHost() {
        for preset in WhisperModelPreset.allCases {
            XCTAssertEqual(preset.downloadURL.scheme, "https")
            XCTAssertEqual(preset.downloadURL.host, "huggingface.co")
            XCTAssertTrue(preset.downloadURL.path.contains(preset.fileName))
        }
    }

    func testSetupCommandDoesNotReferenceDeveloperLocalPaths() {
        let command = WhisperSetupCommands.fullInstallCommand(for: .turbo)

        XCTAssertTrue(command.contains("~/Library/Application Support/Sussurro/Models") || command.contains("$HOME/Library/Application Support/Sussurro/Models"))
        XCTAssertFalse(command.contains("personal/"))
        XCTAssertFalse(command.contains("CustomSTT"))
        XCTAssertFalse(command.contains("superwhisper"))
    }
}
