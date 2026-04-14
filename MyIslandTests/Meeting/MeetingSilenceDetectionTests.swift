import Foundation
import XCTest
@testable import My_Island

final class MeetingSilenceDetectionTests: XCTestCase {
    func testSilenceDetectorByDefaultTriggersAfterTenSecondsOfSilence() {
        var detector = MeetingSilenceDetector()
        let start = Date(timeIntervalSince1970: 1_700_000_000)

        detector.begin(at: start)
        XCTAssertFalse(detector.processEnergyLevel(0.0, at: start))
        XCTAssertFalse(detector.processEnergyLevel(0.0, at: start.addingTimeInterval(9.9)))
        XCTAssertTrue(detector.processEnergyLevel(0.0, at: start.addingTimeInterval(10.0)))
    }

    func testSpeechResetsSilenceWindow() {
        var detector = MeetingSilenceDetector(
            silenceDuration: 10,
            cooldownDuration: 120,
            energyThreshold: 0.02
        )
        let start = Date(timeIntervalSince1970: 1_700_000_000)

        detector.begin(at: start)
        XCTAssertFalse(detector.processEnergyLevel(0.0, at: start))
        XCTAssertFalse(detector.processEnergyLevel(0.03, at: start.addingTimeInterval(4)))
        XCTAssertFalse(detector.processEnergyLevel(0.0, at: start.addingTimeInterval(13)))
        XCTAssertTrue(detector.processEnergyLevel(0.0, at: start.addingTimeInterval(14)))
    }

    func testCooldownPreventsRepeatedSilenceTriggers() {
        var detector = MeetingSilenceDetector(
            silenceDuration: 10,
            cooldownDuration: 120,
            energyThreshold: 0.02
        )
        let start = Date(timeIntervalSince1970: 1_700_000_000)

        detector.begin(at: start)
        XCTAssertTrue(detector.processEnergyLevel(0.0, at: start.addingTimeInterval(10)))
        XCTAssertFalse(detector.processEnergyLevel(0.0, at: start.addingTimeInterval(20)))
        XCTAssertTrue(detector.processEnergyLevel(0.0, at: start.addingTimeInterval(131)))
    }
}
