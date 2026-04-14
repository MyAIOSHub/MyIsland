import XCTest
@testable import My_Island

final class MeetingTriggerRuleTests: XCTestCase {
    func testFiredRulesDetectRepeatedDebateAndMissingOwnerSignals() {
        let segments = [
            makeSegment("这个提议成本太高"),
            makeSegment("这个提议成本太高"),
            makeSegment("用户价值还是不清楚"),
            makeSegment("用户价值还是不清楚"),
            makeSegment("下一步安排一下")
        ]

        let context = MeetingAdviceEngine.buildTriggerContext(from: segments)
        let firedIDs = Set(MeetingAdviceEngine.firedRules(context: context).map(\.id))

        XCTAssertTrue(firedIDs.contains("repeated_unresolved_debate"))
        XCTAssertTrue(firedIDs.contains("missing_owner"))
    }

    func testShouldFireHonorsCooldownWindow() {
        let rule = MeetingTriggerRule(
            id: "stall",
            name: "没有收敛",
            description: "讨论停滞",
            logic: #"{"==":[1,1]}"#,
            cooldownSeconds: 90
        )
        let now = Date(timeIntervalSince1970: 1_700_000_000)

        XCTAssertTrue(MeetingAdviceEngine.shouldFire(rule: rule, lastFiredAt: nil, now: now))
        XCTAssertFalse(MeetingAdviceEngine.shouldFire(rule: rule, lastFiredAt: now.addingTimeInterval(-30), now: now))
        XCTAssertTrue(MeetingAdviceEngine.shouldFire(rule: rule, lastFiredAt: now.addingTimeInterval(-120), now: now))
    }

    func testAutomaticAdviceIsBlockedDuringFirstMinuteButManualIsAllowed() {
        let startedAt = Date(timeIntervalSince1970: 1_700_000_000)
        let now = startedAt.addingTimeInterval(45)
        let rule = MeetingTriggerRule.defaultRules.first!

        XCTAssertFalse(
            MeetingCoordinator.shouldAllowAdviceTrigger(
                reason: .meetingStart,
                meetingStartedAt: startedAt,
                now: now
            )
        )
        XCTAssertFalse(
            MeetingCoordinator.shouldAllowAdviceTrigger(
                reason: .silence,
                meetingStartedAt: startedAt,
                now: now
            )
        )
        XCTAssertFalse(
            MeetingCoordinator.shouldAllowAdviceTrigger(
                reason: .rule(rule),
                meetingStartedAt: startedAt,
                now: now
            )
        )
        XCTAssertTrue(
            MeetingCoordinator.shouldAllowAdviceTrigger(
                reason: .manual,
                meetingStartedAt: startedAt,
                now: now
            )
        )
    }

    func testAutomaticAdviceIsAllowedAfterFirstMinute() {
        let startedAt = Date(timeIntervalSince1970: 1_700_000_000)
        let now = startedAt.addingTimeInterval(60)

        XCTAssertTrue(
            MeetingCoordinator.shouldAllowAdviceTrigger(
                reason: .meetingStart,
                meetingStartedAt: startedAt,
                now: now
            )
        )
    }

    func testAudioInputModeFallbackErrorMessageOnlyAppearsWhenSystemAudioFallsBack() {
        XCTAssertEqual(
            MeetingCoordinator.audioInputModeFallbackErrorMessage(
                requestedMode: .microphoneAndSystem,
                effectiveMode: .microphoneOnly
            ),
            MeetingCoordinator.systemAudioPermissionFallbackMessage
        )
        XCTAssertNil(
            MeetingCoordinator.audioInputModeFallbackErrorMessage(
                requestedMode: .microphoneOnly,
                effectiveMode: .microphoneOnly
            )
        )
        XCTAssertNil(
            MeetingCoordinator.audioInputModeFallbackErrorMessage(
                requestedMode: .microphoneAndSystem,
                effectiveMode: .microphoneAndSystem
            )
        )
        XCTAssertEqual(
            MeetingCoordinator.audioInputModeFallbackErrorMessage(
                requestedMode: .systemOnly,
                effectiveMode: .microphoneOnly
            ),
            MeetingCoordinator.systemAudioPermissionFallbackMessage
        )
    }

    func testGenerateAdviceCardsRoutesAcrossSelectedSkillsWithoutConfiguredModel() async {
        let skills = [
            makeSkill(id: "alchaincyf/elon-musk-skill", name: "Elon Musk", description: "first principles"),
            makeSkill(id: "example/business-plan-skill", name: "Business Planner", description: "go to market")
        ]
        let trigger = MeetingTriggerRule.defaultRules.first { $0.id == "missing_owner" }!

        let cards = await MeetingAdviceEngine.generateAdviceCards(
            topic: "first principles growth review",
            triggerRule: trigger,
            recentSegments: [makeSegment("下一步安排一下")],
            installedSkills: skills,
            selectedSkillIDs: skills.map(\.id),
            config: MeetingAgentModelConfig(
                baseURL: "https://api.openai.com/v1",
                apiKey: "",
                model: "gpt-4.1-mini",
                temperature: 0.2,
                systemPrompt: "Be critical."
            )
        )

        XCTAssertEqual(cards.count, 1)
        guard let card = cards.first else {
            XCTFail("expected a fallback live card")
            return
        }
        XCTAssertEqual(card.triggerRuleID, trigger.id)
        XCTAssertTrue(card.skillIDs.contains("meeting-synthesizer"))
        XCTAssertTrue(card.skillIDs.contains("meeting-first-principles"))
        XCTAssertFalse(card.viewpoints.isEmpty)
    }

    private func makeSegment(_ text: String) -> TranscriptSegment {
        TranscriptSegment(text: text, startTimeMs: 0, endTimeMs: 1000)
    }

    private func makeSkill(id: String, name: String, description: String) -> MeetingSkillInstall {
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
            description: description,
            skillMarkdown: "# SKILL\n\(description)"
        )
    }
}
