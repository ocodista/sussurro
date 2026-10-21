import XCTest
@testable import SussurroApp

final class LiveTypingAnimationPolicyTests: XCTestCase {
    func testRevealAnimationIsShortAndDoesNotThrottleTextUpdates() {
        XCTAssertLessThanOrEqual(LiveTypingAnimationPolicy.revealAnimationDuration, 0.1)
    }

    func testStartingTextKeepsDisplayedPrefix() {
        let startingText = LiveTypingAnimationPolicy.startingText(
            displayedText: "Hello wor",
            targetText: "Hello world"
        )

        XCTAssertEqual(startingText, "Hello wor")
    }

    func testStartingTextFallsBackToCommonPrefixWhenTranscriptChanges() {
        let startingText = LiveTypingAnimationPolicy.startingText(
            displayedText: "Hello brave world",
            targetText: "Hello world"
        )

        XCTAssertEqual(startingText, "Hello ")
    }
}
