import XCTest
@testable import My_Island

final class MeetingThinkingEngineTests: XCTestCase {
    func testManualThinkingBuildsMultiViewpointCard() async {
        let skills = [
            makeSkill(id: "alchaincyf/elon-musk-skill", name: "Elon Musk"),
            makeSkill(id: "example/business-plan-skill", name: "Business Planner"),
            makeSkill(id: "example/roundtable-skill", name: "Roundtable")
        ]

        let cards = await MeetingAdviceEngine.generateThinkingCards(
            topic: "产品评审",
            reason: .manual,
            meetingMarkdown: "# 产品评审",
            recentSegments: [TranscriptSegment(text: "这个场景是否真的成立？", startTimeMs: 0, endTimeMs: 1000)],
            installedSkills: skills,
            selectedSkillIDs: ["example/business-plan-skill"],
            autoRecommendedSkillIDs: ["alchaincyf/elon-musk-skill", "example/roundtable-skill"],
            config: unconfiguredModel()
        )

        XCTAssertEqual(cards.count, 1)
        XCTAssertEqual(cards.first?.triggerRuleID, "manual_think")
        XCTAssertEqual(cards.first?.meetingTheme, .solutionReview)
        XCTAssertEqual(cards.first?.currentSubtask, .compareOptions)
        XCTAssertEqual(cards.first?.agoraRoom, .forge)
        XCTAssertEqual(cards.first?.viewpoints.count, 3)
        XCTAssertEqual(
            cards.first?.viewpoints.map(\.subagentName),
            [.critic, .debate, .roundtable]
        )
        XCTAssertEqual(cards.first?.supervisorSummary?.bestFollowUpLine.isEmpty, false)
    }

    func testSilenceThinkingReturnsSingleCardWithThreeViewpoints() async {
        let skills = [
            makeSkill(id: "skill-1", name: "Skill 1"),
            makeSkill(id: "skill-2", name: "Skill 2"),
            makeSkill(id: "skill-3", name: "Skill 3"),
            makeSkill(id: "skill-4", name: "Skill 4")
        ]

        let cards = await MeetingAdviceEngine.generateThinkingCards(
            topic: "商业计划",
            reason: .silence,
            meetingMarkdown: "# 商业计划",
            recentSegments: [],
            installedSkills: skills,
            selectedSkillIDs: [],
            autoRecommendedSkillIDs: skills.map(\.id),
            config: unconfiguredModel()
        )

        XCTAssertEqual(cards.count, 1)
        XCTAssertEqual(cards.first?.triggerRuleID, "silence_prompt")
        XCTAssertEqual(cards.first?.meetingTheme, .brainstorming)
        XCTAssertEqual(cards.first?.currentSubtask, .promptNextSentence)
        XCTAssertEqual(cards.first?.agoraRoom, .atelier)
        XCTAssertEqual(cards.first?.viewpoints.count, 3)
        XCTAssertEqual(
            cards.first?.viewpoints.map(\.subagentName),
            [.roundtable, .firstPrinciples, .business]
        )
        XCTAssertEqual(cards.first?.supervisorSummary?.nextAction.isEmpty, false)
    }

    private func unconfiguredModel() -> MeetingAgentModelConfig {
        MeetingAgentModelConfig(
            baseURL: "https://dashscope.aliyuncs.com/compatible-mode/v1",
            apiKey: "",
            model: "qwen-plus",
            temperature: 0.2,
            systemPrompt: "你是会议助手"
        )
    }

    private func makeSkill(id: String, name: String) -> MeetingSkillInstall {
        MeetingSkillInstall(
            id: id,
            catalogEntryID: id,
            displayName: name,
            repoURL: "https://github.com/\(id)",
            repoFullName: id,
            installedAt: .distantPast,
            skillRelativePath: "Skills/\(id)/SKILL.md",
            readmeRelativePath: nil,
            localSnapshotDirectory: "Skills/\(id)",
            defaultBranch: "main",
            sourceIndexURL: "https://example.com/index",
            description: name,
            skillMarkdown: "# SKILL\n\(name)"
        )
    }
}
