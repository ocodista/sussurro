import XCTest
@testable import SussurroApp

final class TranscriptionLanguageTests: XCTestCase {
    func testWhisperLanguageCodesAreExplicitForPortugueseAndEnglish() {
        XCTAssertEqual(TranscriptionLanguage.automatic.whisperLanguageCode, "auto")
        XCTAssertEqual(TranscriptionLanguage.portugueseBrazil.whisperLanguageCode, "pt")
        XCTAssertEqual(TranscriptionLanguage.englishUS.whisperLanguageCode, "en")
    }

    func testBrazilianPreferredLanguagesDefaultToPortuguese() {
        XCTAssertEqual(
            TranscriptionLanguage.defaultValue(preferredLanguages: ["en-BR", "pt-BR"]),
            .portugueseBrazil
        )
    }

    func testNonBrazilianPreferredLanguagesKeepAutomaticDetection() {
        XCTAssertEqual(
            TranscriptionLanguage.defaultValue(preferredLanguages: ["en-US", "es-ES"]),
            .automatic
        )
    }

    func testWhisperArgumentsUseSelectedLanguageInsteadOfAlwaysUsingAuto() {
        let arguments = WhisperTranscriber.whisperArguments(
            modelPath: "/tmp/model.bin",
            audioPath: "/tmp/audio.wav",
            language: .portugueseBrazil,
            outputBasePath: "/tmp/output"
        )

        let languageFlagIndex = try? XCTUnwrap(arguments.firstIndex(of: "-l"))
        XCTAssertEqual(languageFlagIndex.map { arguments[$0 + 1] }, "pt")
    }

    func testWhisperArgumentsDisablePromptContextToAvoidRepetitionLoops() {
        let arguments = WhisperTranscriber.whisperArguments(
            modelPath: "/tmp/model.bin",
            audioPath: "/tmp/audio.wav",
            language: .automatic,
            outputBasePath: "/tmp/output"
        )

        let maxContextFlagIndex = arguments.firstIndex(of: "-mc")
        XCTAssertEqual(maxContextFlagIndex.map { arguments[$0 + 1] }, "0")
    }
}
