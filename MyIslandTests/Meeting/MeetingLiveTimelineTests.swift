import XCTest
@testable import My_Island

final class MeetingLiveTimelineTests: XCTestCase {
    func testBuildTranscriptItemsKeepsOwnTimestampsWithoutSharedTimeline() {
        let meeting = MeetingRecord(
            topic: "产品评审",
            state: .recording,
            transcript: [
                TranscriptSegment(id: "seg-2", text: "再比较方案", startTimeMs: 3_000, endTimeMs: 4_000),
                TranscriptSegment(id: "seg-1", text: "先定义问题", startTimeMs: 1_000, endTimeMs: 2_000)
            ]
        )

        let items = MeetingLiveTimeline.buildTranscriptItems(meeting: meeting)

        XCTAssertEqual(items.map(\.id), ["seg-1", "seg-2"])
        XCTAssertEqual(items.map(\.timecode), ["00:01", "00:03"])
        XCTAssertTrue(items.allSatisfy {
            if case .transcript = $0.kind {
                return true
            }
            return false
        })
    }

    func testBuildAdviceItemsKeepsAdviceTimestampsWithoutSharedTimeline() {
        let meetingStart = Date(timeIntervalSince1970: 1_700_000_000)
        let meeting = MeetingRecord(
            topic: "产品评审",
            state: .recording,
            createdAt: meetingStart,
            transcript: [
                TranscriptSegment(id: "seg-1", text: "先定义问题", startTimeMs: 1_000, endTimeMs: 2_000),
                TranscriptSegment(id: "seg-2", text: "再比较方案", startTimeMs: 3_000, endTimeMs: 4_000)
            ]
        )
        let cards = [
            MeetingAdviceCard(
                id: "card-2",
                createdAt: meetingStart.addingTimeInterval(8),
                title: "插个嘴 2",
                body: "先定义边界",
                triggerRuleID: "manual_think",
                sourceSegmentIDs: ["seg-2"]
            ),
            MeetingAdviceCard(
                id: "card-1",
                createdAt: meetingStart.addingTimeInterval(5),
                title: "插个嘴 1",
                body: "先澄清用户",
                triggerRuleID: "manual_think",
                sourceSegmentIDs: ["seg-1"]
            )
        ]

        let items = MeetingLiveTimeline.buildAdviceItems(meeting: meeting, adviceCards: cards)

        XCTAssertEqual(items.map(\.id), ["card-1", "card-2"])
        XCTAssertEqual(items.map(\.timecode), ["00:02", "00:04"])
        XCTAssertTrue(items.allSatisfy {
            if case .advice = $0.kind {
                return true
            }
            return false
        })
    }

    func testBuildItemsOrdersTranscriptAndAdviceChronologically() {
        let meetingStart = Date(timeIntervalSince1970: 1_700_000_000)
        let meeting = MeetingRecord(
            topic: "产品评审",
            state: .recording,
            createdAt: meetingStart,
            transcript: [
                TranscriptSegment(id: "seg-1", text: "先定义问题", startTimeMs: 1_000, endTimeMs: 2_000),
                TranscriptSegment(id: "seg-2", text: "再比较方案", startTimeMs: 3_000, endTimeMs: 4_000)
            ]
        )
        let card = MeetingAdviceCard(
            id: "card-1",
            createdAt: meetingStart.addingTimeInterval(5),
            title: "插个嘴",
            body: "先别拍板",
            triggerRuleID: "manual_think",
            sourceSegmentIDs: ["seg-2"]
        )

        let items = MeetingLiveTimeline.buildItems(meeting: meeting, adviceCards: [card])

        XCTAssertEqual(items.map(\.id), ["seg-1", "seg-2", "card-1"])
        XCTAssertEqual(items.map(\.timecode), ["00:01", "00:03", "00:04"])
    }

    func testAdviceFallsBackToCreatedAtOffsetWhenSourceSegmentsMissing() {
        let meetingStart = Date(timeIntervalSince1970: 1_700_000_000)
        let meeting = MeetingRecord(
            topic: "需求澄清",
            state: .recording,
            createdAt: meetingStart
        )
        let card = MeetingAdviceCard(
            id: "card-fallback",
            createdAt: meetingStart.addingTimeInterval(65),
            title: "插个嘴",
            body: "先澄清目标用户",
            triggerRuleID: "manual_think"
        )

        let items = MeetingLiveTimeline.buildItems(meeting: meeting, adviceCards: [card])

        XCTAssertEqual(items.map(\.id), ["card-fallback"])
        XCTAssertEqual(items.first?.timecode, "01:05")
    }

    func testResolveLiveAdviceCardsPrefersRealtimeBufferAndDeduplicates() {
        let persisted = MeetingAdviceCard(
            id: "card-1",
            title: "持久化卡片",
            body: "persisted",
            triggerRuleID: "manual_think"
        )
        let live = MeetingAdviceCard(
            id: "card-2",
            title: "实时卡片",
            body: "live",
            triggerRuleID: "manual_think"
        )

        let resolved = MeetingLiveTimeline.resolveLiveAdviceCards(
            activeAdviceCards: [live, persisted],
            persistedAdviceCards: [persisted]
        )

        XCTAssertEqual(resolved.map(\.id), ["card-2", "card-1"])
    }

    func testResolveLiveAdviceCardsFallsBackToPersistedWhenRealtimeEmpty() {
        let persisted = MeetingAdviceCard(
            id: "card-1",
            title: "持久化卡片",
            body: "persisted",
            triggerRuleID: "manual_think"
        )

        let resolved = MeetingLiveTimeline.resolveLiveAdviceCards(
            activeAdviceCards: [],
            persistedAdviceCards: [persisted]
        )

        XCTAssertEqual(resolved.map(\.id), ["card-1"])
    }

    func testBuildAdviceItemsForLiveColumnShowsPendingCardWhileThinking() {
        let meetingStart = Date(timeIntervalSince1970: 1_700_000_000)
        let meeting = MeetingRecord(
            topic: "需求澄清",
            state: .recording,
            createdAt: meetingStart
        )

        let items = MeetingLiveTimeline.buildAdviceItemsForLiveColumn(
            meeting: meeting,
            activeAdviceCards: [],
            persistedAdviceCards: [],
            isGeneratingThinking: true,
            now: meetingStart.addingTimeInterval(12)
        )

        XCTAssertEqual(items.map(\.id), ["thinking-placeholder"])
        XCTAssertEqual(items.first?.timecode, "00:12")
        guard case .advice(let card) = items.first?.kind else {
            return XCTFail("expected advice placeholder")
        }
        XCTAssertEqual(card.title, "思考中")
    }

    func testBuildSidebarItemsForLiveColumnMixesAdviceAndNotesChronologically() {
        let meetingStart = Date(timeIntervalSince1970: 1_700_000_000)
        let meeting = MeetingRecord(
            topic: "需求澄清",
            state: .recording,
            createdAt: meetingStart,
            transcript: [
                TranscriptSegment(id: "seg-1", text: "先确认问题边界", startTimeMs: 1_000, endTimeMs: 2_000)
            ],
            annotations: [
                MeetingAnnotation(
                    id: "note-1",
                    kind: .note,
                    createdAt: meetingStart.addingTimeInterval(6),
                    timecodeMs: 3_000,
                    text: "这句要记下来",
                    sourceSegmentIDs: ["seg-1"],
                    source: .transcriptExcerpt
                )
            ]
        )
        let card = MeetingAdviceCard(
            id: "card-1",
            createdAt: meetingStart.addingTimeInterval(8),
            title: "插个嘴",
            body: "先别急着拍板",
            triggerRuleID: "manual_think",
            sourceSegmentIDs: ["seg-1"]
        )

        let items = MeetingLiveTimeline.buildSidebarItemsForLiveColumn(
            meeting: meeting,
            activeAdviceCards: [card],
            persistedAdviceCards: [],
            isGeneratingThinking: false
        )

        XCTAssertEqual(items.map { $0.id }, ["card-1", "note-1"])
        XCTAssertEqual(items.map { $0.timecode }, ["00:02", "00:03"])

        guard case .advice = items[0].kind else {
            return XCTFail("expected first sidebar item to be advice")
        }
        guard case .note(let annotation) = items[1].kind else {
            return XCTFail("expected second sidebar item to be note")
        }
        XCTAssertEqual(annotation.source, MeetingAnnotationSource.transcriptExcerpt)
    }

    func testBuildSidebarItemsForLiveColumnPlacesPendingThinkingAmongNotes() {
        let meetingStart = Date(timeIntervalSince1970: 1_700_000_000)
        let meeting = MeetingRecord(
            topic: "需求澄清",
            state: .recording,
            createdAt: meetingStart,
            annotations: [
                MeetingAnnotation(
                    id: "note-1",
                    kind: .note,
                    createdAt: meetingStart.addingTimeInterval(6),
                    timecodeMs: 5_000,
                    text: "先保留这个结论",
                    source: .manualNote
                )
            ]
        )

        let items = MeetingLiveTimeline.buildSidebarItemsForLiveColumn(
            meeting: meeting,
            activeAdviceCards: [],
            persistedAdviceCards: [],
            isGeneratingThinking: true,
            now: meetingStart.addingTimeInterval(12)
        )

        XCTAssertEqual(items.map { $0.id }, ["note-1", "thinking-placeholder"])
    }
}
