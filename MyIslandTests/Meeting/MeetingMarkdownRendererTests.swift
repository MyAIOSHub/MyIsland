import XCTest
@testable import My_Island

final class MeetingMarkdownRendererTests: XCTestCase {
    func testRendererBuildsCanonicalMarkdownWithTranscriptThinkingAndSummary() {
        let partial = TranscriptSegment(
            id: "seg-1",
            text: "现在这个",
            startTimeMs: 5_000,
            endTimeMs: 6_000,
            speakerLabel: "speaker_1",
            isFinal: false
        )
        let final = TranscriptSegment(
            id: "seg-1",
            text: "现在这个。",
            startTimeMs: 5_000,
            endTimeMs: 7_000,
            speakerLabel: "speaker_1",
            isFinal: true
        )
        let summary = MeetingSummaryBundle(
            fullSummary: "会议明确先做问题定义，再确认 owner。",
            chapterSummaries: [MeetingChapterSummary(title: "背景", summary: "先收敛问题边界。")],
            actionItems: [MeetingActionItem(task: "补齐路线图", owner: "Alice", dueDate: "2026-04-12")],
            qaPairs: [MeetingQAPair(question: "为什么现在改？", answer: "因为窗口变化。")],
            processHighlights: ["先定义问题", "再指定 owner"],
            source: "memo-lark"
        )
        let record = MeetingRecord(
            id: "meeting-1",
            topic: "产品评审",
            state: .completed,
            createdAt: Date(timeIntervalSince1970: 1_700_000_000),
            endedAt: Date(timeIntervalSince1970: 1_700_000_600),
            scheduledAt: Date(timeIntervalSince1970: 1_699_999_800),
            durationMinutes: 45,
            calendarSyncState: .synced,
            transcript: [partial, final],
            annotations: [
                MeetingAnnotation(
                    id: "focus-1",
                    kind: .focus,
                    createdAt: Date(timeIntervalSince1970: 1_700_000_100),
                    timecodeMs: 7_000,
                    text: "先定义问题边界",
                    sourceSegmentIDs: ["seg-1"],
                    source: .transcriptSegment
                ),
                MeetingAnnotation(
                    id: "note-comment-1",
                    kind: .note,
                    createdAt: Date(timeIntervalSince1970: 1_700_000_110),
                    timecodeMs: 5_000,
                    text: "这里缺少用户证据，不能直接推进方案。",
                    sourceSegmentIDs: ["seg-1"],
                    source: .transcriptComment
                ),
                MeetingAnnotation(
                    id: "note-1",
                    kind: .note,
                    createdAt: Date(timeIntervalSince1970: 1_700_000_120),
                    timecodeMs: 12_000,
                    text: "用户证据要补齐",
                    sourceSegmentIDs: [],
                    source: .manualNote,
                    attachments: [
                        MeetingNoteAttachment(
                            id: "attachment-1",
                            kind: .screenshot,
                            displayName: "meeting-shot.png",
                            relativePath: "meeting-1/Attachments/meeting-shot.png",
                            extractedMarkdown: "## 截图摘要\n\n当前页展示了问题定义、下一步动作和负责人空缺。"
                        )
                    ]
                )
            ],
            summaryBundle: summary,
            adviceCards: [
                MeetingAdviceCard(
                    title: "问题边界",
                    body: "先确认讨论的是需求必要性，而不是实现细节。",
                    triggerRuleID: "manual_think",
                    skillIDs: ["meeting-critic", "meeting-roundtable"],
                    meetingTheme: .solutionReview,
                    currentSubtask: .compareOptions,
                    agoraRoom: .forge,
                    viewpoints: [
                        SubagentViewpoint(
                            subagentName: .critic,
                            stance: "批判视角",
                            corePoint: "当前把需求必要性和实现方案混在一起了。",
                            challenge: "如果场景不成立，再优雅的实现也没有意义。",
                            evidenceNeeded: "需要先验证用户是否真的有该行为。",
                            followUpLine: "有没有证据表明这个高频场景真实存在？",
                            skillIDs: ["meeting-critic"]
                        ),
                        SubagentViewpoint(
                            subagentName: .roundtable,
                            stance: "圆桌视角",
                            corePoint: "支持方和反对方讨论的不是同一个问题。",
                            challenge: "现在缺少统一的议题定义。",
                            evidenceNeeded: "需要明确本次拍板的是必要性还是方案。",
                            followUpLine: "这次会我们到底要拍板问题定义，还是拍板实现方案？",
                            skillIDs: ["meeting-roundtable"]
                        )
                    ],
                    supervisorSummary: MeetingSupervisorSummary(
                        keyGap: "议题定义还没统一。",
                        ignoredQuestion: "用户为什么现在需要这个能力？",
                        bestFollowUpLine: "先把问题定义锁住，再谈方案取舍。",
                        nextAction: "补一页问题定义，再继续评审。"
                    )
                )
            ],
            selectedSkillIDs: ["alchaincyf/elon-musk-skill"],
            autoRecommendedSkillIDs: ["example/business-plan-skill"]
        )

        let markdown = MeetingMarkdownRenderer.render(record: record, installedSkills: [
            makeSkill(id: "alchaincyf/elon-musk-skill", name: "Elon Musk"),
            makeSkill(id: "example/business-plan-skill", name: "Business Planner")
        ])

        XCTAssertTrue(markdown.contains("# 产品评审"))
        XCTAssertTrue(markdown.contains("Meeting ID: meeting-1"))
        XCTAssertTrue(markdown.contains("预约时长: 45 分钟"))
        XCTAssertTrue(markdown.contains("日历同步: 已同步"))
        XCTAssertTrue(markdown.contains("已选 Skills: Elon Musk"))
        XCTAssertTrue(markdown.contains("自动推荐 Skills: Business Planner"))
        XCTAssertTrue(markdown.contains("## 重点关注"))
        XCTAssertTrue(markdown.contains("[00:07][字幕标记] 先定义问题边界"))
        XCTAssertTrue(markdown.contains("## 会议笔记"))
        XCTAssertTrue(markdown.contains("[00:05][评论] 这里缺少用户证据，不能直接推进方案。"))
        XCTAssertTrue(markdown.contains("> [00:05][说话人1] 现在这个。"))
        XCTAssertTrue(markdown.contains("[00:12][手动笔记] 用户证据要补齐"))
        XCTAssertTrue(markdown.contains("### 附件 · 00:12 · meeting-shot.png"))
        XCTAssertTrue(markdown.contains("类型：截屏"))
        XCTAssertTrue(markdown.contains("原文件：meeting-1/Attachments/meeting-shot.png"))
        XCTAssertTrue(markdown.contains("## 截图摘要"))
        XCTAssertTrue(markdown.contains("## 实时转写"))
        XCTAssertTrue(markdown.contains("[00:05][说话人1] 现在这个。"))
        XCTAssertFalse(markdown.contains("[00:05][说话人1] 现在这个\n"))
        XCTAssertTrue(markdown.contains("## 思考记录"))
        XCTAssertTrue(markdown.contains("问题边界"))
        XCTAssertTrue(markdown.contains("- topic_taxonomy: solution_review"))
        XCTAssertTrue(markdown.contains("- current_subtask: compare_options"))
        XCTAssertTrue(markdown.contains("- agora_room: forge"))
        XCTAssertTrue(markdown.contains("#### 批判视角 · critic"))
        XCTAssertTrue(markdown.contains("#### 圆桌视角 · roundtable"))
        XCTAssertTrue(markdown.contains("- 关键缺口：议题定义还没统一。"))
        XCTAssertTrue(markdown.contains("- 最值得追问：先把问题定义锁住，再谈方案取舍。"))
        XCTAssertTrue(markdown.contains("## 会后总结"))
        XCTAssertTrue(markdown.contains("会议明确先做问题定义，再确认 owner。"))
        XCTAssertTrue(markdown.contains("### 流程提取"))
        XCTAssertTrue(markdown.contains("先定义问题"))
        XCTAssertTrue(markdown.contains("补齐路线图"))
    }

    func testTranscriptCommentSummaryTextPrioritizesCommentBeforeQuote() {
        let annotation = MeetingAnnotation(
            id: "note-comment-1",
            kind: .note,
            createdAt: Date(timeIntervalSince1970: 1_700_000_110),
            timecodeMs: 5_000,
            text: "这里先补用户证据。",
            sourceSegmentIDs: ["seg-1"],
            source: .transcriptComment
        )
        let transcript = [
            TranscriptSegment(
                id: "seg-1",
                text: "现在这个。",
                startTimeMs: 5_000,
                endTimeMs: 7_000,
                speakerLabel: "speaker_1",
                isFinal: true
            )
        ]

        let summary = annotation.summaryText(in: transcript)

        XCTAssertTrue(summary.hasPrefix("这里先补用户证据。"))
        XCTAssertTrue(summary.contains("引用：[00:05][说话人1] 现在这个。"))
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
