import XCTest
@testable import My_Island

final class MeetingHubLayoutTests: XCTestCase {
    func testHubShowsComposerScheduledCurrentMeetingAndHistorySections() {
        XCTAssertEqual(
            MeetingHubView.HubSection.allCases,
            [.newMeeting, .scheduled, .currentMeeting, .history]
        )
    }
}
