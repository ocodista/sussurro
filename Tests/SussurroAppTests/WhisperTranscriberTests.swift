import XCTest
@testable import SussurroApp

final class WhisperTranscriberTests: XCTestCase {
    func testLanguageDisplayCodeUsesRegionLabelsForPortugueseAndEnglish() {
        XCTAssertEqual(WhisperTranscriber.languageDisplayCode(for: "pt"), "PT-BR")
        XCTAssertEqual(WhisperTranscriber.languageDisplayCode(for: "pt-BR"), "PT-BR")
        XCTAssertEqual(WhisperTranscriber.languageDisplayCode(for: "en"), "EN-US")
        XCTAssertEqual(WhisperTranscriber.languageDisplayCode(for: "en_US"), "EN-US")
    }

    func testLanguageDisplayCodeKeepsUnknownLanguagesCompact() {
        XCTAssertEqual(WhisperTranscriber.languageDisplayCode(for: "es"), "ES")
    }
}
