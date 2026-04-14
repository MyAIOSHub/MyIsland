import XCTest
@testable import My_Island

final class MeetingLiveLayoutTests: XCTestCase {
    func testDualColumnWidthSplitsAvailableWidthEvenly() {
        XCTAssertEqual(
            MeetingLiveLayout.dualColumnWidth(containerWidth: 996, spacing: 12),
            492
        )
    }

    func testDualColumnWidthClampsToZero() {
        XCTAssertEqual(
            MeetingLiveLayout.dualColumnWidth(containerWidth: 8, spacing: 12),
            0
        )
    }

    func testInlineRecordingStatusSummaryUsesSystemAudioLabel() {
        XCTAssertEqual(
            MeetingLiveLayout.inlineRecordingStatusSummary(
                realtimeStatusMessage: "实时字幕识别中",
                audioInputMode: .microphoneAndSystem,
                systemAudioAvailable: true
            ),
            MeetingLiveInlineRecordingStatusSummary(
                statusText: "实时字幕识别中",
                sourceText: "麦克风+系统录音"
            )
        )
    }

    func testInlineRecordingStatusSummaryUsesMicOnlyLabel() {
        XCTAssertEqual(
            MeetingLiveLayout.inlineRecordingStatusSummary(
                realtimeStatusMessage: "连接中",
                audioInputMode: .microphoneOnly,
                systemAudioAvailable: false
            ),
            MeetingLiveInlineRecordingStatusSummary(
                statusText: "连接中",
                sourceText: "仅麦克风"
            )
        )
    }

    func testInlineRecordingStatusSummaryFallsBackToMicOnlyWhenSystemAudioUnavailable() {
        XCTAssertEqual(
            MeetingLiveLayout.inlineRecordingStatusSummary(
                realtimeStatusMessage: "连接中",
                audioInputMode: .microphoneAndSystem,
                systemAudioAvailable: false
            ),
            MeetingLiveInlineRecordingStatusSummary(
                statusText: "连接中",
                sourceText: "仅麦克风"
            )
        )
    }

    func testInlineRecordingStatusSummaryIgnoresEmptyStatusText() {
        XCTAssertNil(
            MeetingLiveLayout.inlineRecordingStatusSummary(
                realtimeStatusMessage: "   ",
                audioInputMode: .microphoneOnly,
                systemAudioAvailable: true
            )
        )
    }
}
