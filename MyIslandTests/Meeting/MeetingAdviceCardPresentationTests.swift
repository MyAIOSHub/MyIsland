import XCTest
@testable import My_Island

final class MeetingAdviceCardPresentationTests: XCTestCase {
    func testMetaBadgeTextsPlaceTimestampBeforeRouteMetadata() {
        let card = MeetingAdviceCard(
            title: "插个嘴",
            body: "先别拍板",
            triggerRuleID: "manual_think",
            meetingTheme: .solutionReview,
            currentSubtask: .compareOptions,
            agoraRoom: .forge
        )

        let texts = MeetingAdviceCardPresentation.metaBadgeTexts(
            for: card,
            timestampLabel: "00:42"
        )

        XCTAssertEqual(texts, ["00:42", "方案评审", "比较方案", "Forge"])
    }

    func testMetaBadgeTextsOmitTimestampWhenMissing() {
        let card = MeetingAdviceCard(
            title: "插个嘴",
            body: "先定义问题",
            triggerRuleID: "manual_think",
            meetingTheme: .requirementsClarification
        )

        let texts = MeetingAdviceCardPresentation.metaBadgeTexts(
            for: card,
            timestampLabel: nil
        )

        XCTAssertEqual(texts, ["需求澄清"])
    }

    func testCompactViewpointsKeepSingleSentencePerAgent() {
        let card = MeetingAdviceCard(
            title: "插个嘴",
            body: "",
            triggerRuleID: "manual_think",
            viewpoints: [
                SubagentViewpoint(
                    id: "critic-1",
                    subagentName: .critic,
                    stance: "批判视角",
                    corePoint: "先证伪核心假设。后面这句不该出现在折叠态。",
                    challenge: "这个问题定义可能不成立。",
                    evidenceNeeded: "需要真实用户证据。",
                    followUpLine: "如果假设错了怎么办？"
                )
            ]
        )

        let viewpoints = MeetingAdviceCardPresentation.compactViewpoints(
            for: card,
            maxVisibleViewpoints: 3
        )

        XCTAssertEqual(
            viewpoints,
            [
                MeetingAdviceCompactViewpoint(
                    id: "critic-1",
                    stance: "批判视角",
                    subagentName: "CriticAgent",
                    sentence: "先证伪核心假设。"
                )
            ]
        )
    }

    func testCollapsedBodyTextUsesLeadingSentenceFromLegacyCard() {
        let card = MeetingAdviceCard(
            title: "插个嘴",
            body: "我们先把目标写清楚。\n下一行不该在折叠态展示。",
            triggerRuleID: "manual_think"
        )

        let text = MeetingAdviceCardPresentation.collapsedBodyText(for: card)

        XCTAssertEqual(text, "我们先把目标写清楚。")
    }

    func testHasExpandableDetailsForStructuredLegacyAdvice() {
        let card = MeetingAdviceCard(
            title: "插个嘴",
            body: "",
            triggerRuleID: "manual_think",
            coreJudgment: "问题定义还不够清楚",
            nextStep: "先写一句目标用户和成功标准"
        )

        XCTAssertTrue(
            MeetingAdviceCardPresentation.hasExpandableDetails(
                for: card,
                maxVisibleViewpoints: 3
            )
        )
    }
}
