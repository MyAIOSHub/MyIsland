import Foundation

actor MeetingSummaryEngine {
    static let shared = MeetingSummaryEngine()

    struct SummaryResponse: Decodable {
        let fullSummary: String?
        let chapterSummaries: [ChapterResponse]?
        let actionItems: [ActionResponse]?
        let qaPairs: [QAResponse]?
        let processHighlights: [String]?
        let decisions: [DecisionResponse]?
        let speakerViewpoints: [SpeakerViewpointResponse]?
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

    struct DecisionResponse: Decodable {
        let statement: String
        let rationale: String?
        let decidedBy: String?
        let timecodeMs: Int?
    }

    struct SpeakerViewpointResponse: Decodable {
        let speakerLabel: String
        let stance: String?
        let points: [String]?
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

    /// Run an LLM enhancement pass on top of an existing (likely Memo-derived)
    /// summary, filling in fields that Memo did not produce — most
    /// importantly **decisions** and **per-speaker viewpoints**, which
    /// Miaoji's pipeline does not extract at all. Also opportunistically
    /// fills in chapter / action / Q&A / process-highlight slots when the
    /// Memo pass left them empty.
    ///
    /// The pass is *additive* by design: existing Memo fields are passed
    /// in as authoritative context, and the LLM is instructed not to
    /// overwrite them. We then merge the LLM output back into a single
    /// bundle, preferring the original Memo content for any field that
    /// Memo provided.
    func augmentSummary(
        existing: MeetingSummaryBundle,
        transcript: [TranscriptSegment],
        topic: String,
        config: MeetingAgentModelConfig
    ) async throws -> MeetingSummaryBundle {
        let speakerDisplayMap = MeetingSpeakerLabelResolver.displayMap(transcript: transcript)
        let knownSpeakers = Array(Set(speakerDisplayMap.values)).sorted()
        let speakersHint = knownSpeakers.isEmpty
            ? "（暂无可识别的说话人标签）"
            : knownSpeakers.joined(separator: "、")

        let transcriptBody = transcript.prefix(800).map { segment in
            let speaker = MeetingSpeakerLabelResolver.displayName(
                for: segment.speakerLabel,
                mapping: speakerDisplayMap
            )
            let timecode = MeetingLiveTimeline.timecode(milliseconds: segment.startTimeMs)
            return "[\(timecode)][\(speaker)] \(segment.text)"
        }.joined(separator: "\n")

        let chapterText = existing.chapterSummaries
            .map { "\($0.title)：\($0.summary)" }
            .joined(separator: "；")
        let actionText = existing.actionItems
            .map { item in
                [item.task, item.owner, item.dueDate]
                    .compactMap { $0 }
                    .joined(separator: " / ")
            }
            .joined(separator: "；")
        let qaText = existing.qaPairs
            .map { "\($0.question) -> \($0.answer)" }
            .joined(separator: "；")
        let processText = existing.processHighlights.joined(separator: "；")

        let userPrompt = """
        你是一名资深会议记录员。基于下面的会议转写，输出一份补全后的结构化纪要。
        妙记 ASR 已经给出了一部分内容（见“现有总结”），你的工作是：

        1. 抽取**决策(decisions)**：会议中明确达成的结论、共识、定论、行动方向。
           - 每条决策一句话陈述（`statement`），越具体越好。
           - 如果该决策的提出/拍板者明确，写入 `decidedBy`（用现有说话人标签，如“说话人1”）。
           - 如果该决策的背景/原因清晰，写入 `rationale`。
           - 如果决策出现在转写的某个时间点附近，写入 `timecodeMs`（毫秒）。
           - **没有真正决策时返回空数组**。不要把单纯的讨论或观点当成决策。

        2. 抽取**按发言人维度的观点总结(speakerViewpoints)**：
           - 对每个 `speakersHint` 中出现过的说话人各产出一组观点：
             - `speakerLabel` 必须严格用 `speakersHint` 里的中文标签（如“说话人1”），不要自创名字。
             - `points` 1-3 条，每条 ≤ 30 字，捕捉这位说话人核心立场/贡献。
             - `stance` 一句话概括这位说话人的整体取向（可为 null）。
           - 如果某说话人只是寒暄/附和、没有可识别立场，跳过他。

        3. 当现有总结里 `chapterSummaries` / `actionItems` / `qaPairs` / `processHighlights`
           **为空**时，再尝试基于转写补足；如果现有总结已有内容，**保留为空数组让调用方用现有值合并**，避免覆盖。
           - chapterSummaries 最多 4 项，actionItems 最多 8 项，qaPairs 最多 5 项。

        4. fullSummary 字段：如现有总结已有非空内容，**返回空字符串**，调用方会保留原版；
           只有原始为空时才生成（≤ 200 字，markdown 列表结构）。

        会议主题：\(topic)
        已知说话人：\(speakersHint)

        现有总结（作为权威背景，不要覆写非空字段）：
        - fullSummary：\(existing.fullSummary.isEmpty ? "无" : existing.fullSummary)
        - chapterSummaries：\(chapterText.isEmpty ? "无" : chapterText)
        - actionItems：\(actionText.isEmpty ? "无" : actionText)
        - qaPairs：\(qaText.isEmpty ? "无" : qaText)
        - processHighlights：\(processText.isEmpty ? "无" : processText)

        会议转写（最多 800 段，每段格式 `[时:分:秒][说话人] 内容`）：
        \(transcriptBody)

        只返回合法 JSON，不要 markdown code fence：
        {
          "fullSummary": "string",
          "chapterSummaries": [{"title":"string","summary":"string"}],
          "actionItems": [{"task":"string","owner":"string|null","dueDate":"string|null"}],
          "qaPairs": [{"question":"string","answer":"string"}],
          "processHighlights": ["string"],
          "decisions": [{"statement":"string","rationale":"string|null","decidedBy":"string|null","timecodeMs":number|null}],
          "speakerViewpoints": [{"speakerLabel":"string","stance":"string|null","points":["string"]}]
        }
        """

        let response = try await MeetingOpenAIModelClient.shared.complete(
            messages: [
                ["role": "system", "content": config.systemPrompt],
                ["role": "user", "content": userPrompt]
            ],
            config: config,
            responseFormat: ["type": "json_object"]
        )

        let llm = decodeSummaryBundle(from: response, source: "agent-augment")

        // Merge: keep existing Memo fields when they have content, otherwise
        // accept the LLM's. New fields (decisions / speakerViewpoints)
        // always come from the LLM since Memo doesn't produce them.
        return MeetingSummaryBundle(
            fullSummary:       existing.fullSummary.isEmpty ? llm.fullSummary : existing.fullSummary,
            chapterSummaries:  existing.chapterSummaries.isEmpty ? llm.chapterSummaries : existing.chapterSummaries,
            actionItems:       existing.actionItems.isEmpty ? llm.actionItems : existing.actionItems,
            qaPairs:           existing.qaPairs.isEmpty ? llm.qaPairs : existing.qaPairs,
            processHighlights: existing.processHighlights.isEmpty ? llm.processHighlights : existing.processHighlights,
            decisions:         llm.decisions,
            speakerViewpoints: llm.speakerViewpoints,
            source:            existing.source.isEmpty ? "agent-augment" : "\(existing.source)+agent-augment"
        )
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
        只返回合法 JSON，**字段值内部允许使用 Markdown**（用于加粗），不要在 JSON 外层套 ```code fence```。
        结构：
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

        【加粗规则 — 必须遵守】
        - 在 fullSummary 与 chapterSummaries.summary 中：凡是与“重点关注”或“会议笔记”
          所述内容**语义相关**的句子或短语，**必须用 Markdown 双星号包裹加粗**
          （例如：发布日期改到下周三 → **发布日期改到下周三**）。
        - 加粗范围限制为关键名词短语 / 决定 / 数字 / 截止日期，不要把整段长句全部加粗。
        - 没被用户标重点的内容不要加粗。
        - actionItems / qaPairs / processHighlights 的字符串值同样允许加粗，
          但同样仅限于命中用户标注的部分。

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
        // The refine prompt does not touch decisions / speakerViewpoints,
        // so always carry the augment-pass output forward instead of
        // accidentally clearing it.
        if refined.decisions.isEmpty {
            refined.decisions = summaryBundle.decisions
        }
        if refined.speakerViewpoints.isEmpty {
            refined.speakerViewpoints = summaryBundle.speakerViewpoints
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
                decisions: (decoded.decisions ?? []).map {
                    MeetingDecision(
                        statement: $0.statement,
                        rationale: $0.rationale,
                        decidedBy: $0.decidedBy,
                        timecodeMs: $0.timecodeMs
                    )
                },
                speakerViewpoints: (decoded.speakerViewpoints ?? []).map {
                    MeetingSpeakerViewpoint(
                        speakerLabel: $0.speakerLabel,
                        points: $0.points ?? [],
                        stance: $0.stance
                    )
                },
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
