import XCTest
@testable import My_Island

final class NotchLauncherLayoutTests: XCTestCase {
    func testOpenedLayoutPlacesPetOnFirstRowAndClipboardMeetingOnSecondRow() {
        XCTAssertEqual(
            NotchLauncherLayout.openedRows,
            [
                [.pet],
                [.clipboard, .meetingAssistant]
            ]
        )
    }
}
