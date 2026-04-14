import Foundation

actor MeetingSummaryEngine {
    static let shared = MeetingSummaryEngine()

    struct SummaryResponse: Decodable {
        let fullSummary: String?
        let chapterSummaries: [ChapterResponse]?
        let actionItems: [ActionResponse]?
        let qaPairs: [QAResponse]?
        let processHighlights: [String]?
    }

    struct ChapterResponse: Decodable {
        let title: String
        let summary: String
    }

    struct ActionResponse: Decodable {
        let task: String
        let owner: String?
        let dueDate: String?
    }

    struct QAResponse: Decodable {
        let question: String
        let answer: String
    }

    func buildSummary(
        transcript: [TranscriptSegment],
        topic: String,
        config: MeetingAgentModelConfig
    ) async throws -> MeetingSummaryBundle {
        let speakerDisplayMap = MeetingSpeakerLabelResolver.displayMap(transcript: transcript)
        let transcriptBody = transcript.map { segment in
            let speaker = MeetingSpeakerLabelResolver.displayName(
                for: segment.speakerLabel,
                mapping: speakerDisplayMap
            )
            return "[\(speaker)] \(segment.text)"
        }.joined(separator: "\n")

        let systemPrompt = config.systemPrompt
        let userPrompt = """
        请把以下会议内容整理成 JSON，结构如下：
        {
          "fullSummary": "string",
          "chapterSummaries": [{"title":"string","summary":"string"}],
          "actionItems": [{"task":"string","owner":"string|null","dueDate":"string|null"}],
          "qaPairs": [{"question":"string","answer":"string"}],
          "processHighlights": ["string"]
        }

        约束：
        - 输出必须是合法 JSON，不要 markdown code fence。
        - chapterSummaries 最多 4 项，actionItems 最多 8 项，qaPairs 最多 5 项。
        - 如果没有对应内容，返回空数组。

        会议主题：\(topic)
        会议转写：
        \(transcriptBody)
        """

        let response = try await MeetingOpenAIModelClient.shared.complete(
            messages: [
                ["role": "system", "content": systemPrompt],
                ["role": "user", "content": userPrompt]
            ],
            config: config,
            responseFormat: ["type": "json_object"]
        )

        return decodeSummaryBundle(from: response, source: "agent-fallback")
    }

    func refineSummary(
        record: MeetingRecord,
        summaryBundle: MeetingSummaryBundle,
        installedSkills: [MeetingSkillInstall],
        selectedSkillIDs: [String],
        config: MeetingAgentModelConfig
    ) async throws -> MeetingSummaryBundle {
        let installedByID = Dictionary(uniqueKeysWithValues: installedSkills.map { ($0.id, $0) })
        let selectedSkills = selectedSkillIDs.compactMap { installedByID[$0] }
        let skillContext = MeetingPromptSkillContextBuilder.buildSkillContext(
            skills: selectedSkills,
            emptyText: "无显式 skill 正文。"
        )
        let focusText = record.focusAnnotations
            .sorted { $0.timecodeMs < $1.timecodeMs }
            .map { "[\(MeetingLiveTimeline.timecode(milliseconds: $0.timecodeMs))] \($0.text)" }
            .joined(separator: "\n")
        let noteText = record.noteAnnotations
            .sorted { $0.timecodeMs < $1.timecodeMs }
            .map { "[\(MeetingLiveTimeline.timecode(milliseconds: $0.timecodeMs))] \($0.summaryText(in: record.transcript))" }
            .joined(separator: "\n")
        let chapterText = summaryBundle.chapterSummaries
            .map { "\($0.title)：\($0.summary)" }
            .joined(separator: "；")
        let actionText = summaryBundle.actionItems
            .map { item in
                [item.task, item.owner, item.dueDate]
                    .compactMap { $0 }
                    .joined(separator: " / ")
            }
            .joined(separator: "；")
        let qaText = summaryBundle.qaPairs
            .map { "\($0.question) -> \($0.answer)" }
            .joined(separator: "；")
        let processText = summaryBundle.processHighlights.joined(separator: "；")
        let meetingMarkdown = String(
            MeetingMarkdownRenderer.render(record: record, installedSkills: installedSkills)
                .suffix(5_000)
        )

        let userPrompt = """
        你要在不伪造事实的前提下，对现有会议总结做一次“重点加权 refinement”。
        只返回合法 JSON，不要输出 Markdown 代码块，结构如下：
        {
          "fullSummary": "string",
          "chapterSummaries": [{"title":"string","summary":"string"}],
          "actionItems": [{"task":"string","owner":"string|null","dueDate":"string|null"}],
          "qaPairs": [{"question":"string","answer":"string"}],
          "processHighlights": ["string"]
        }

        约束：
        - 只能强化用户明确标出的重点关注和会议笔记，不能杜撰未发生的事实。
        - 如果重点和现有总结冲突，以会议原文与重点原文为准。
        - fullSummary 保持简洁，但必须优先覆盖重点关注与笔记提到的内容。
        - chapterSummaries 最多 4 项，actionItems 最多 8 项，qaPairs 最多 5 项。

        当前总结：
        全文总结：\(summaryBundle.fullSummary)
        章节总结：\(chapterText.isEmpty ? "无" : chapterText)
        待办：\(actionText.isEmpty ? "无" : actionText)
        问答：\(qaText.isEmpty ? "无" : qaText)
        流程提取：\(processText.isEmpty ? "无" : processText)

        重点关注：
        \(focusText.isEmpty ? "无" : focusText)

        会议笔记：
        \(noteText.isEmpty ? "无" : noteText)

        skill 正文：
        \(skillContext)

        当前 meeting.md：
        \(meetingMarkdown)
        """

        let response = try await MeetingOpenAIModelClient.shared.complete(
            messages: [
                ["role": "system", "content": config.systemPrompt],
                ["role": "user", "content": userPrompt]
            ],
            config: config,
            responseFormat: ["type": "json_object"]
        )

        var refined = decodeSummaryBundle(from: response, source: "\(summaryBundle.source)+refined")
        if refined.fullSummary.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            refined.fullSummary = summaryBundle.fullSummary
        }
        if refined.chapterSummaries.isEmpty {
            refined.chapterSummaries = summaryBundle.chapterSummaries
        }
        if refined.actionItems.isEmpty {
            refined.actionItems = summaryBundle.actionItems
        }
        if refined.qaPairs.isEmpty {
            refined.qaPairs = summaryBundle.qaPairs
        }
        if refined.processHighlights.isEmpty {
            refined.processHighlights = summaryBundle.processHighlights
        }
        return refined
    }

    private func decodeSummaryBundle(from rawResponse: String, source: String) -> MeetingSummaryBundle {
        let cleaned = rawResponse
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "```json", with: "")
            .replacingOccurrences(of: "```", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard let data = cleaned.data(using: .utf8) else {
            return MeetingSummaryBundle(
                fullSummary: cleaned,
                source: source
            )
        }

        do {
            let decoded = try JSONDecoder().decode(SummaryResponse.self, from: data)
            return MeetingSummaryBundle(
                fullSummary: decoded.fullSummary ?? "",
                chapterSummaries: (decoded.chapterSummaries ?? []).map {
                    MeetingChapterSummary(title: $0.title, summary: $0.summary)
                },
                actionItems: (decoded.actionItems ?? []).map {
                    MeetingActionItem(task: $0.task, owner: $0.owner, dueDate: $0.dueDate)
                },
                qaPairs: (decoded.qaPairs ?? []).map {
                    MeetingQAPair(question: $0.question, answer: $0.answer)
                },
                processHighlights: decoded.processHighlights ?? [],
                source: source
            )
        } catch {
            return MeetingSummaryBundle(
                fullSummary: cleaned,
                source: source
            )
        }
    }
}
