import XCTest
@testable import SussurroApp

final class AudioReactiveDogAnimationStateTests: XCTestCase {
    func testRecordingOpensMouthAboveAmplitudeThreshold() {
        let date = Date(timeIntervalSinceReferenceDate: 1)

        let quietState = AudioReactiveDogAnimationState.state(
            activity: .recording,
            amplitude: 0.02,
            date: date
        )
        let loudState = AudioReactiveDogAnimationState.state(
            activity: .recording,
            amplitude: 0.35,
            date: date
        )

        XCTAssertEqual(quietState.mouthOpenness, 0, accuracy: 0.001)
        XCTAssertGreaterThan(loudState.mouthOpenness, 0.8)
        XCTAssertGreaterThan(loudState.bodyScale, quietState.bodyScale)
    }

    func testRecordingAnimatesMouthOverTime() {
        let closedFrame = AudioReactiveDogAnimationState.state(
            activity: .recording,
            amplitude: 0.35,
            date: Date(timeIntervalSinceReferenceDate: 0)
        )
        let openFrame = AudioReactiveDogAnimationState.state(
            activity: .recording,
            amplitude: 0.35,
            date: Date(timeIntervalSinceReferenceDate: .pi / 52)
        )

        XCTAssertNotEqual(closedFrame.mouthOpenness, openFrame.mouthOpenness, accuracy: 0.001)
        XCTAssertGreaterThan(openFrame.mouthOpenness, closedFrame.mouthOpenness)
    }

    func testTranscribingShowsThinkingDotsWithoutOpeningMouth() {
        let state = AudioReactiveDogAnimationState.state(
            activity: .transcribing,
            amplitude: 0.8,
            date: Date(timeIntervalSinceReferenceDate: 1)
        )

        XCTAssertTrue(state.showsThinkingDots)
        XCTAssertEqual(state.mouthOpenness, 0, accuracy: 0.001)
        XCTAssertGreaterThan(state.bodyScale, 1)
    }

    func testIdleCanBlinkWithoutThinkingDots() {
        let state = AudioReactiveDogAnimationState.state(
            activity: .idle,
            amplitude: 0,
            date: Date(timeIntervalSinceReferenceDate: 0)
        )

        XCTAssertTrue(state.isBlinking)
        XCTAssertFalse(state.showsThinkingDots)
        XCTAssertEqual(state.mouthOpenness, 0, accuracy: 0.001)
    }
}
