import XCTest
@testable import My_Island

final class MeetingLiveSizingTests: XCTestCase {
    func testMeetingLiveUsesDoubleWidthBaseline() {
        let liveWidth = NotchSizing.meetingLiveWidth(
            screenWidth: 1_600,
            panelWidth: 480
        )

        XCTAssertEqual(liveWidth, 1_240)
        XCTAssertGreaterThan(liveWidth, 620)
    }
}
