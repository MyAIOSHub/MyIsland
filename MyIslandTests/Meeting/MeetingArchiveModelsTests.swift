import Foundation
import XCTest
@testable import My_Island

final class MeetingArchiveModelsTests: XCTestCase {
    func testBuildListItemsUsesMatchedSnippetBeforeSummaryPreview() {
        let record = MeetingRecord(
            id: "meeting-1",
            topic: "商业判断",
            state: .completed,
            createdAt: makeDate(day: 12, hour: 15, minute: 32),
            transcript: [
                TranscriptSegment(
                    id: "seg-1",
                    text: "我们现在重点讨论商业判断是否成立，以及后续的验证路径。",
                    startTimeMs: 1_000,
                    endTimeMs: 5_000
                )
            ],
            summaryBundle: MeetingSummaryBundle(
                fullSummary: "这是摘要，不该在命中片段优先时排到前面。",
                source: "memo"
            )
        )

        let items = MeetingArchiveIndex.buildListItems(
            meetings: [record],
            filter: .all,
            searchQuery: "商业判断"
        )

        XCTAssertEqual(items.count, 1)
        XCTAssertTrue(items[0].previewText.contains("商业判断"))
        XCTAssertFalse(items[0].previewText.contains("这是摘要"))
    }

    func testBuildListItemsFiltersOutUnmatchedMeetingsWhenSearching() {
        let matching = MeetingRecord(
            id: "meeting-1",
            topic: "增长复盘",
            state: .completed,
            createdAt: makeDate(day: 12, hour: 15, minute: 32),
            transcript: [
                TranscriptSegment(
                    id: "seg-1",
                    text: "这里提到了增长漏斗和转化问题。",
                    startTimeMs: 1_000,
                    endTimeMs: 5_000
                )
            ]
        )
        let unmatched = MeetingRecord(
            id: "meeting-2",
            topic: "财务对账",
            state: .completed,
            createdAt: makeDate(day: 12, hour: 11, minute: 0),
            transcript: [
                TranscriptSegment(
                    id: "seg-2",
                    text: "只讨论报销流程。",
                    startTimeMs: 1_000,
                    endTimeMs: 5_000
                )
            ]
        )

        let items = MeetingArchiveIndex.buildListItems(
            meetings: [matching, unmatched],
            filter: .all,
            searchQuery: "增长"
        )

        XCTAssertEqual(items.map(\.id), ["meeting-1"])
    }

    func testBuildListItemsFallsBackFromSummaryToChapterThenTranscript() {
        let chapterOnly = MeetingRecord(
            id: "meeting-1",
            topic: "方案比较",
            state: .completed,
            createdAt: makeDate(day: 12, hour: 9, minute: 0),
            transcript: [
                TranscriptSegment(id: "seg-1", text: "这里是最后一条转写", startTimeMs: 8_000, endTimeMs: 9_000)
            ],
            summaryBundle: MeetingSummaryBundle(
                fullSummary: "",
                chapterSummaries: [
                    MeetingChapterSummary(title: "问题定义", summary: "先收敛边界，再讨论解法。")
                ],
                source: "memo"
            )
        )
        let transcriptOnly = MeetingRecord(
            id: "meeting-2",
            topic: "无摘要会议",
            state: .completed,
            createdAt: makeDate(day: 11, hour: 9, minute: 0),
            transcript: [
                TranscriptSegment(id: "seg-2", text: "这是最终保底预览", startTimeMs: 3_000, endTimeMs: 4_000, isFinal: true)
            ]
        )

        let items = MeetingArchiveIndex.buildListItems(
            meetings: [chapterOnly, transcriptOnly],
            filter: .all,
            searchQuery: ""
        )

        XCTAssertEqual(items.first(where: { $0.id == "meeting-1" })?.previewText, "先收敛边界，再讨论解法。")
        XCTAssertEqual(items.first(where: { $0.id == "meeting-2" })?.previewText, "这是最终保底预览")
    }

    func testGroupItemsUsesScheduledDateForScheduledMeetings() {
        let scheduled = MeetingRecord(
            id: "scheduled-1",
            topic: "预约会议",
            state: .scheduled,
            createdAt: makeDate(day: 10, hour: 12, minute: 0),
            scheduledAt: makeDate(day: 13, hour: 8, minute: 30),
            durationMinutes: 60
        )

        let grouped = MeetingArchiveIndex.group(
            items: MeetingArchiveIndex.buildListItems(meetings: [scheduled], filter: .all, searchQuery: ""),
            now: makeDate(day: 12, hour: 18, minute: 0)
        )

        XCTAssertEqual(grouped.count, 1)
        XCTAssertEqual(grouped[0].items.first?.displayTime, "08:30")
        XCTAssertEqual(grouped[0].items.first?.primaryDate, makeDate(day: 13, hour: 8, minute: 30))
    }

    func testFilterIncludesOnlyRequestedStates() {
        let meetings = [
            MeetingRecord(id: "scheduled", topic: "预约", state: .scheduled, createdAt: makeDate(day: 12, hour: 9, minute: 0)),
            MeetingRecord(id: "recording", topic: "进行中", state: .recording, createdAt: makeDate(day: 12, hour: 10, minute: 0)),
            MeetingRecord(id: "completed", topic: "已完成", state: .completed, createdAt: makeDate(day: 12, hour: 11, minute: 0)),
            MeetingRecord(id: "failed", topic: "失败", state: .failed, createdAt: makeDate(day: 12, hour: 12, minute: 0))
        ]

        XCTAssertEqual(
            MeetingArchiveIndex.buildListItems(meetings: meetings, filter: .scheduled, searchQuery: "").map(\.id),
            ["scheduled"]
        )
        XCTAssertEqual(
            MeetingArchiveIndex.buildListItems(meetings: meetings, filter: .recording, searchQuery: "").map(\.id),
            ["recording"]
        )
        XCTAssertEqual(
            MeetingArchiveIndex.buildListItems(meetings: meetings, filter: .completed, searchQuery: "").map(\.id),
            ["completed"]
        )
        XCTAssertEqual(
            MeetingArchiveIndex.buildListItems(meetings: meetings, filter: .failed, searchQuery: "").map(\.id),
            ["failed"]
        )
    }

    private func makeDate(day: Int, hour: Int, minute: Int) -> Date {
        var components = DateComponents()
        components.calendar = Calendar(identifier: .gregorian)
        components.timeZone = TimeZone.current
        components.year = 2026
        components.month = 4
        components.day = day
        components.hour = hour
        components.minute = minute
        return components.date ?? Date(timeIntervalSince1970: 0)
    }
}
