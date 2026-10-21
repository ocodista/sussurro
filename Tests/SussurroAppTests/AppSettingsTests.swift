import XCTest
@testable import SussurroApp

final class AppSettingsTests: XCTestCase {
    func testRealTimeChunkIntervalDefaultsToFiveSeconds() {
        XCTAssertEqual(
            AppSettings.sanitizedRealTimeChunkIntervalSeconds(nil),
            AppSettings.defaultRealTimeChunkIntervalSeconds
        )
    }

    func testRealTimeChunkIntervalIsClampedToSupportedRange() {
        XCTAssertEqual(AppSettings.sanitizedRealTimeChunkIntervalSeconds(1), 2)
        XCTAssertEqual(AppSettings.sanitizedRealTimeChunkIntervalSeconds(5), 5)
        XCTAssertEqual(AppSettings.sanitizedRealTimeChunkIntervalSeconds(60), 30)
    }

    func testRealTimeChunkIntervalRejectsNonFiniteValues() {
        XCTAssertEqual(
            AppSettings.sanitizedRealTimeChunkIntervalSeconds(.infinity),
            AppSettings.defaultRealTimeChunkIntervalSeconds
        )
    }
}
