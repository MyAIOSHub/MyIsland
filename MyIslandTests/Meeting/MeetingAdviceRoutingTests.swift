import XCTest
@testable import My_Island

final class MeetingAdviceRoutingTests: XCTestCase {
    func testRouteDecisionMapsRequirementClarification() {
        let decision = MeetingAdviceEngine.routeDecision(
            topic: "需求澄清会",
            reason: .manual,
            recentSegments: [
                TranscriptSegment(text: "我们先确认用户是谁。", startTimeMs: 0, endTimeMs: 1_000),
                TranscriptSegment(text: "这个痛点为什么现在值得做？", startTimeMs: 1_000, endTimeMs: 2_000)
            ],
            installedSkills: []
        )

        XCTAssertEqual(decision.meetingTheme, .requirementsClarification)
        XCTAssertEqual(decision.currentSubtask, .defineProblem)
        XCTAssertEqual(decision.agoraRoom, .forge)
        XCTAssertEqual(decision.subagents, [.socratic, .firstPrinciples, .critic])
    }

    func testRouteDecisionMapsSolutionReviewToDistinctSubagentBundle() {
        let decision = MeetingAdviceEngine.routeDecision(
            topic: "方案评审",
            reason: .manual,
            recentSegments: [
                TranscriptSegment(text: "我们现在对比 A 和 B 两个方案。", startTimeMs: 0, endTimeMs: 1_000),
                TranscriptSegment(text: "这个取舍到底怎么定？", startTimeMs: 1_000, endTimeMs: 2_000)
            ],
            installedSkills: []
        )

        XCTAssertEqual(decision.meetingTheme, .solutionReview)
        XCTAssertEqual(decision.currentSubtask, .compareOptions)
        XCTAssertEqual(decision.agoraRoom, .forge)
        XCTAssertEqual(decision.subagents, [.critic, .debate, .roundtable])
        XCTAssertEqual(Set(decision.subagents).count, 3)
    }

    func testRouteDecisionMapsBusinessEvaluationToBazaar() {
        let decision = MeetingAdviceEngine.routeDecision(
            topic: "商业化讨论",
            reason: .manual,
            recentSegments: [
                TranscriptSegment(text: "这件事的 ROI 现在算得过来吗？", startTimeMs: 0, endTimeMs: 1_000),
                TranscriptSegment(text: "收入成本和商业闭环都还没清楚。", startTimeMs: 1_000, endTimeMs: 2_000)
            ],
            installedSkills: []
        )

        XCTAssertEqual(decision.meetingTheme, .businessEvaluation)
        XCTAssertEqual(decision.currentSubtask, .assessBusinessCase)
        XCTAssertEqual(decision.agoraRoom, .bazaar)
        XCTAssertEqual(decision.subagents, [.business, .decision, .critic])
    }
}
