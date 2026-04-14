import Foundation

enum MeetingPromptSkillContextBuilder {
    static func buildSkillContext(
        skills: [MeetingSkillInstall],
        emptyText: String,
        maxSkills: Int = 3,
        maxCharactersPerSkill: Int = 1_800
    ) -> String {
        let selected = Array(skills.prefix(maxSkills))
        guard !selected.isEmpty else { return emptyText }

        return selected.map { skill in
            """
            ## \(skill.displayName)
            - 来源: \(skill.sourceKind.displayName)
            - Subagent: \(skill.subagentName)
            - 描述: \(skill.description.isEmpty ? "无" : skill.description)
            - Repo: \(skill.repoFullName)

            正文摘录：
            \(trimMarkdown(skill.skillMarkdown, maxLength: maxCharactersPerSkill))
            """
        }.joined(separator: "\n\n")
    }

    static func buildSingleSkillContext(
        _ skill: MeetingSkillInstall,
        maxCharacters: Int = 1_800
    ) -> String {
        """
        Skill: \(skill.displayName)
        来源: \(skill.sourceKind.displayName)
        Subagent: \(skill.subagentName)
        Repo: \(skill.repoFullName)
        描述: \(skill.description.isEmpty ? "无" : skill.description)

        正文摘录：
        \(trimMarkdown(skill.skillMarkdown, maxLength: maxCharacters))
        """
    }

    private static func trimMarkdown(_ markdown: String, maxLength: Int) -> String {
        let trimmed = markdown.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count > maxLength else { return trimmed }
        let endIndex = trimmed.index(trimmed.startIndex, offsetBy: maxLength)
        return String(trimmed[..<endIndex]) + "\n..."
    }
}

struct MeetingTriggerContextData: Sendable {
    let recentSegmentCount: Int
    let repeatedTailCount: Int
    let ownerMentionCount: Int
    let actionCueCount: Int
    let questionCueCount: Int
    let problemDefinitionCount: Int
    let decisionMentionCount: Int

    var asDictionary: [String: Any] {
        [
            "recentSegmentCount": recentSegmentCount,
            "repeatedTailCount": repeatedTailCount,
            "ownerMentionCount": ownerMentionCount,
            "actionCueCount": actionCueCount,
            "questionCueCount": questionCueCount,
            "problemDefinitionCount": problemDefinitionCount,
            "decisionMentionCount": decisionMentionCount
        ]
    }
}

enum MeetingAdviceEngine {
    static func buildTriggerContext(from segments: [TranscriptSegment]) -> MeetingTriggerContextData {
        let recent = Array(segments.suffix(12))
        let normalizedTail = recent.map { normalize(text: $0.text) }

        let repeatedTailCount = Dictionary(grouping: normalizedTail, by: { $0 })
            .values
            .filter { !$0.first!.isEmpty && $0.count >= 2 }
            .count

        let ownerMentionCount = normalizedTail.filter { line in
            line.contains("负责人") || line.contains("owner") || line.contains("我来") || line.contains("你来")
        }.count

        let actionCueCount = normalizedTail.filter { line in
            line.contains("待办") || line.contains("行动项") || line.contains("follow up") || line.contains("下一步") || line.contains("安排")
        }.count

        let questionCueCount = normalizedTail.filter { line in
            line.contains("为什么") || line.contains("问题") || line.contains("?") || line.contains("？")
        }.count

        let problemDefinitionCount = normalizedTail.filter { line in
            line.contains("目标") || line.contains("问题定义") || line.contains("success") || line.contains("约束") || line.contains("前提")
        }.count

        let decisionMentionCount = normalizedTail.filter { line in
            line.contains("结论") || line.contains("决定") || line.contains("定") || line.contains("拍板") || line.contains("方案")
        }.count

        return MeetingTriggerContextData(
            recentSegmentCount: recent.count,
            repeatedTailCount: repeatedTailCount,
            ownerMentionCount: ownerMentionCount,
            actionCueCount: actionCueCount,
            questionCueCount: questionCueCount,
            problemDefinitionCount: problemDefinitionCount,
            decisionMentionCount: decisionMentionCount
        )
    }

    static func firedRules(
        context: MeetingTriggerContextData,
        rules: [MeetingTriggerRule] = MeetingTriggerRule.defaultRules
    ) -> [MeetingTriggerRule] {
        rules.filter { MeetingJsonLogic.evaluate(rule: $0.logic, data: context.asDictionary) }
    }

    static func recommendSkillIDs(topic: String, installedSkills: [MeetingSkillInstall], limit: Int = 3) -> [String] {
        let tokens = tokenize(topic)
        if tokens.isEmpty {
            return Array(installedSkills.prefix(limit).map(\.id))
        }

        let scored = installedSkills.map { skill in
            let corpus = (skill.displayName + " " + skill.description + " " + skill.skillMarkdown).lowercased()
            let score = tokens.reduce(into: 0) { partialResult, token in
                if corpus.contains(token) {
                    partialResult += 1
                }
            }
            return (skill.id, score)
        }
        .sorted { lhs, rhs in
            if lhs.1 == rhs.1 { return lhs.0 < rhs.0 }
            return lhs.1 > rhs.1
        }

        let positive = scored.filter { $0.1 > 0 }.map(\.0)
        if !positive.isEmpty {
            return Array(positive.prefix(limit))
        }

        return Array(installedSkills.prefix(limit).map(\.id))
    }

    static func shouldFire(rule: MeetingTriggerRule, lastFiredAt: Date?, now: Date = Date()) -> Bool {
        guard let lastFiredAt else { return true }
        return now.timeIntervalSince(lastFiredAt) >= rule.cooldownSeconds
    }

    static func routeDecision(
        topic: String,
        reason: MeetingThinkingReason,
        recentSegments: [TranscriptSegment],
        installedSkills _: [MeetingSkillInstall]
    ) -> MeetingRouteDecision {
        if case .silence = reason {
            let subagents = subagentBundle(theme: .brainstorming, subtask: .promptNextSentence)
            return MeetingRouteDecision(
                meetingTheme: .brainstorming,
                currentSubtask: .promptNextSentence,
                agoraRoom: .atelier,
                subagents: subagents,
                skillIDs: aggregatedRuntimeSkillIDs(for: subagents),
                why: "会议进入冷场，优先给出可直接接话的提词板。"
            )
        }

        let corpus = normalizedCorpus(topic: topic, recentSegments: recentSegments)

        let theme: MeetingTheme
        let subtask: MeetingSubtask
        let room: MeetingAgoraRoom
        let why: String

        if containsAny(corpus, needles: ["roi", "商业", "收入", "成本", "变现", "增长", "定价", "利润", "闭环"]) {
            theme = .businessEvaluation
            subtask = .assessBusinessCase
            room = .bazaar
            why = "当前讨论集中在 ROI、价值闭环和商业可行性。"
        } else if containsAny(corpus, needles: ["复盘", "教训", "事故", "故障", "风险", "回顾"]) {
            let isRiskDiscussion = containsAny(corpus, needles: ["事故", "故障", "风险", "预案"])
            theme = isRiskDiscussion ? .riskRetro : .retrospective
            subtask = .extractLessons
            room = .clinic
            why = "当前讨论更像复盘与经验抽取，需要明确根因和可复用模式。"
        } else if containsAny(corpus, needles: ["方案", "评审", "取舍", "a 方案", "b 方案", "对比", "比较", "tradeoff"]) {
            theme = .solutionReview
            subtask = .compareOptions
            room = .forge
            why = "当前讨论在比较方案和取舍，适合进入批判、辩论和圆桌视角。"
        } else if containsAny(corpus, needles: ["拍板", "决定", "优先级", "先做", "不做", "资源", "要不要"]) {
            theme = .decisionCommit
            subtask = .forceDecision
            room = .oracle
            why = "当前讨论需要明确做或不做，并承担对应代价。"
        } else if containsAny(corpus, needles: ["卡点", "阻塞", "owner", "负责人", "推进", "排期", "周会", "对齐", "协作"]) {
            theme = .executionAlignment
            subtask = .unblockExecution
            room = containsAny(corpus, needles: ["对齐", "协作", "冲突", "配合"]) ? .hearth : .clinic
            why = "当前讨论更像推进会，需要拆出 owner、依赖和阻塞。"
        } else if containsAny(corpus, needles: ["头脑风暴", "创意", "灵感", "点子", "破冰", "发散"]) {
            theme = .brainstorming
            subtask = .promptNextSentence
            room = .atelier
            why = "当前讨论偏发散，需要多角度拉开视野并给出下一句。"
        } else if containsAny(corpus, needles: ["前提", "假设", "成立", "真的有必要", "为什么现在", "用户是谁", "痛点", "问题定义", "目标"]) {
            theme = .requirementsClarification
            subtask = .defineProblem
            room = .forge
            why = "当前讨论集中在问题定义、目标和前提是否成立。"
        } else {
            theme = .requirementsClarification
            subtask = .defineProblem
            room = .forge
            why = "没有明显的专项信号，先回到问题定义与前提澄清。"
        }

        let subagents = subagentBundle(theme: theme, subtask: subtask)
        return MeetingRouteDecision(
            meetingTheme: theme,
            currentSubtask: subtask,
            agoraRoom: room,
            subagents: subagents,
            skillIDs: aggregatedRuntimeSkillIDs(for: subagents),
            why: why
        )
    }

    static func generateAdviceCards(
        topic: String,
        triggerRule: MeetingTriggerRule,
        recentSegments: [TranscriptSegment],
        installedSkills: [MeetingSkillInstall],
        selectedSkillIDs: [String],
        config: MeetingAgentModelConfig
    ) async -> [MeetingAdviceCard] {
        await generateLiveCards(
            topic: topic,
            reason: .rule(triggerRule),
            meetingMarkdown: nil,
            recentSegments: recentSegments,
            installedSkills: installedSkills,
            selectedSkillIDs: selectedSkillIDs,
            autoRecommendedSkillIDs: selectedSkillIDs,
            config: config
        )
    }

    static func generateThinkingCards(
        topic: String,
        reason: MeetingThinkingReason,
        meetingMarkdown: String,
        recentSegments: [TranscriptSegment],
        installedSkills: [MeetingSkillInstall],
        selectedSkillIDs: [String],
        autoRecommendedSkillIDs: [String],
        config: MeetingAgentModelConfig,
        maxCards _: Int = 3
    ) async -> [MeetingAdviceCard] {
        await generateLiveCards(
            topic: topic,
            reason: reason,
            meetingMarkdown: meetingMarkdown,
            recentSegments: recentSegments,
            installedSkills: installedSkills,
            selectedSkillIDs: selectedSkillIDs,
            autoRecommendedSkillIDs: autoRecommendedSkillIDs,
            config: config
        )
    }

    static func generatePostMeetingAdviceCards(
        topic: String,
        transcript: [TranscriptSegment],
        summaryBundle: MeetingSummaryBundle?,
        installedSkills: [MeetingSkillInstall],
        selectedSkillIDs: [String],
        config: MeetingAgentModelConfig,
        maxCards: Int = 3
    ) async -> [MeetingAdviceCard] {
        let skills = selectedSkills(
            installedSkills: installedSkills,
            selectedSkillIDs: selectedSkillIDs,
            autoRecommendedSkillIDs: selectedSkillIDs,
            maxCards: maxCards
        )

        guard !skills.isEmpty else {
            return [fallbackPostMeetingCard(skill: nil, sourceSegments: transcript)]
        }

        guard config.isConfigured else {
            return skills.map { fallbackPostMeetingCard(skill: $0, sourceSegments: transcript) }
        }

        var cards: [MeetingAdviceCard] = []
        for skill in skills {
            let prompt = postMeetingPrompt(
                topic: topic,
                transcript: transcript,
                summaryBundle: summaryBundle,
                skill: skill
            )

            do {
                let content = try await MeetingOpenAIModelClient.shared.complete(
                    messages: [
                        ["role": "system", "content": config.systemPrompt],
                        ["role": "user", "content": prompt]
                    ],
                    config: config,
                    responseFormat: ["type": "json_object"]
                )

                if let parsed = parsePostMeetingCard(
                    content: content,
                    skillID: skill.id,
                    sourceSegments: transcript.suffix(12).map(\.id)
                ) {
                    cards.append(parsed)
                    continue
                }
            } catch {
                // Fall through to fallback.
            }

            cards.append(fallbackPostMeetingCard(skill: skill, sourceSegments: transcript))
        }

        return Array(cards.prefix(maxCards))
    }

    private static func generateLiveCards(
        topic: String,
        reason: MeetingThinkingReason,
        meetingMarkdown: String?,
        recentSegments: [TranscriptSegment],
        installedSkills: [MeetingSkillInstall],
        selectedSkillIDs: [String],
        autoRecommendedSkillIDs: [String],
        config: MeetingAgentModelConfig
    ) async -> [MeetingAdviceCard] {
        let selectedInstalls = selectedSkills(
            installedSkills: installedSkills,
            selectedSkillIDs: selectedSkillIDs,
            autoRecommendedSkillIDs: autoRecommendedSkillIDs,
            maxCards: 3
        )
        let route = routeDecision(
            topic: topic,
            reason: reason,
            recentSegments: recentSegments,
            installedSkills: installedSkills
        )
        let preferredRuntimeSkillIDs = inferredRuntimeSkillIDs(from: selectedInstalls)
        let runtimeSkillsBySubagent = Dictionary(
            uniqueKeysWithValues: route.subagents.map {
                ($0, runtimeSkills(for: $0, theme: route.meetingTheme, preferredSkillIDs: preferredRuntimeSkillIDs))
            }
        )
        let routeSkillIDs = Array(
            Set(runtimeSkillsBySubagent.values.flatMap { $0 } + ["meeting-synthesizer"])
        ).sorted()
        let sourceSegmentIDs = recentSegments.suffix(8).map(\.id)

        guard config.isConfigured else {
            return [
                fallbackLiveCard(
                    topic: topic,
                    reason: reason,
                    route: route,
                    runtimeSkillsBySubagent: runtimeSkillsBySubagent,
                    sourceSegments: recentSegments
                )
            ]
        }

        let prompt = livePrompt(
            topic: topic,
            reason: reason,
            route: route,
            meetingMarkdown: meetingMarkdown,
            transcript: recentSegments,
            selectedSkills: selectedInstalls,
            runtimeSkillsBySubagent: runtimeSkillsBySubagent
        )

        do {
            let content = try await MeetingOpenAIModelClient.shared.complete(
                messages: [
                    ["role": "system", "content": config.systemPrompt],
                    ["role": "user", "content": prompt]
                ],
                config: config,
                responseFormat: ["type": "json_object"]
            )

            if let parsed = parseLiveCard(
                content: content,
                reason: reason,
                route: route,
                runtimeSkillsBySubagent: runtimeSkillsBySubagent,
                sourceSegmentIDs: sourceSegmentIDs
            ) {
                var card = parsed
                card.skillIDs = routeSkillIDs
                return [card]
            }
        } catch {
            // Fall through to fallback.
        }

        return [
            fallbackLiveCard(
                topic: topic,
                reason: reason,
                route: route,
                runtimeSkillsBySubagent: runtimeSkillsBySubagent,
                sourceSegments: recentSegments
            )
        ]
    }

    private static func subagentBundle(theme: MeetingTheme, subtask: MeetingSubtask) -> [MeetingSubagentName] {
        switch (theme, subtask) {
        case (.requirementsClarification, .defineProblem),
             (.requirementsClarification, .testPremise):
            return [.socratic, .firstPrinciples, .critic]
        case (.solutionReview, .compareOptions):
            return [.critic, .debate, .roundtable]
        case (.decisionCommit, .forceDecision):
            return [.decision, .risk, .debate]
        case (.executionAlignment, .unblockExecution):
            return [.execution, .socratic, .decision]
        case (.brainstorming, .promptNextSentence):
            return [.roundtable, .firstPrinciples, .business]
        case (.riskRetro, .extractLessons):
            return [.risk, .critic, .retrospective]
        case (.businessEvaluation, .assessBusinessCase):
            return [.business, .decision, .critic]
        case (.retrospective, .extractLessons):
            return [.retrospective, .firstPrinciples, .roundtable]
        default:
            switch subtask {
            case .defineProblem, .testPremise:
                return [.socratic, .firstPrinciples, .critic]
            case .compareOptions:
                return [.critic, .debate, .roundtable]
            case .forceDecision:
                return [.decision, .risk, .debate]
            case .unblockExecution:
                return [.execution, .socratic, .decision]
            case .promptNextSentence:
                return [.roundtable, .firstPrinciples, .business]
            case .assessBusinessCase:
                return [.business, .decision, .critic]
            case .extractLessons:
                return [.retrospective, .critic, .firstPrinciples]
            }
        }
    }

    private static func runtimeSkills(
        for subagent: MeetingSubagentName,
        theme: MeetingTheme,
        preferredSkillIDs: Set<String>
    ) -> [String] {
        let candidates: [String]
        switch subagent {
        case .socratic:
            candidates = ["meeting-socratic", "meeting-jtbd"]
        case .firstPrinciples:
            candidates = ["meeting-first-principles", "meeting-five-whys"]
        case .critic:
            candidates = ["meeting-critic", "meeting-tradeoff"]
        case .debate:
            candidates = ["meeting-tradeoff", "meeting-roundtable"]
        case .roundtable:
            candidates = ["meeting-roundtable", "meeting-divergence"]
        case .decision:
            candidates = ["meeting-decision", "meeting-tradeoff"]
        case .execution:
            candidates = ["meeting-execution", "meeting-pattern"]
        case .risk:
            candidates = ["meeting-risk", "meeting-antipattern"]
        case .business:
            candidates = theme == .businessEvaluation
                ? ["meeting-business", "meeting-unit-economics", "meeting-moat"]
                : ["meeting-business", "meeting-moat", "meeting-unit-economics"]
        case .retrospective:
            candidates = ["meeting-retrospective", "meeting-pattern", "meeting-antipattern"]
        }

        let prioritized = candidates.sorted { lhs, rhs in
            let lhsPreferred = preferredSkillIDs.contains(lhs)
            let rhsPreferred = preferredSkillIDs.contains(rhs)
            if lhsPreferred != rhsPreferred {
                return lhsPreferred && !rhsPreferred
            }
            return lhs < rhs
        }

        return Array(prioritized.prefix(2))
    }

    private static func aggregatedRuntimeSkillIDs(for subagents: [MeetingSubagentName]) -> [String] {
        Array(
            Set(subagents.flatMap { runtimeSkills(for: $0, theme: .requirementsClarification, preferredSkillIDs: []) })
        ).sorted()
    }

    private static func selectedSkills(
        installedSkills: [MeetingSkillInstall],
        selectedSkillIDs: [String],
        autoRecommendedSkillIDs: [String],
        maxCards: Int
    ) -> [MeetingSkillInstall] {
        let requestedIDs = (selectedSkillIDs.isEmpty ? autoRecommendedSkillIDs : selectedSkillIDs)
        var seen = Set<String>()
        let installsByID = Dictionary(uniqueKeysWithValues: installedSkills.map { ($0.id, $0) })
        let ordered = requestedIDs.compactMap { id -> MeetingSkillInstall? in
            guard let install = installsByID[id], seen.insert(id).inserted else { return nil }
            return install
        }
        if !ordered.isEmpty {
            return Array(ordered.prefix(maxCards))
        }
        return Array(installedSkills.prefix(maxCards))
    }

    private static func inferredRuntimeSkillIDs(from skills: [MeetingSkillInstall]) -> Set<String> {
        var runtimeSkillIDs: Set<String> = []
        for skill in skills {
            let corpus = normalizedSkillCorpus(skill)
            if containsAny(corpus, needles: ["musk", "第一性原理", "first principles", "rank", "本质"]) {
                runtimeSkillIDs.insert("meeting-first-principles")
            }
            if containsAny(corpus, needles: ["business", "商业", "roi", "invest", "市场"]) {
                runtimeSkillIDs.insert("meeting-business")
                runtimeSkillIDs.insert("meeting-unit-economics")
            }
            if containsAny(corpus, needles: ["roundtable", "辩论", "debate", "圆桌"]) {
                runtimeSkillIDs.insert("meeting-roundtable")
            }
            if containsAny(corpus, needles: ["learn", "概念", "clarify", "用户"]) {
                runtimeSkillIDs.insert("meeting-socratic")
            }
            if containsAny(corpus, needles: ["writes", "写作", "收敛"]) {
                runtimeSkillIDs.insert("meeting-synthesizer")
            }
        }
        return runtimeSkillIDs
    }

    private static func livePrompt(
        topic: String,
        reason: MeetingThinkingReason,
        route: MeetingRouteDecision,
        meetingMarkdown: String?,
        transcript: [TranscriptSegment],
        selectedSkills: [MeetingSkillInstall],
        runtimeSkillsBySubagent: [MeetingSubagentName: [String]]
    ) -> String {
        let speakerDisplayMap = MeetingSpeakerLabelResolver.displayMap(transcript: transcript)
        let transcriptBody = transcript.suffix(10).map { segment in
            let speaker = MeetingSpeakerLabelResolver.displayName(
                for: segment.speakerLabel,
                mapping: speakerDisplayMap
            )
            return "[\(speaker)] \(segment.text)"
        }.joined(separator: "\n")
        let markdownBody = String((meetingMarkdown ?? "").suffix(3_000))
        let selectedSkillContext = MeetingPromptSkillContextBuilder.buildSkillContext(
            skills: selectedSkills,
            emptyText: "无显式选择的 imported/custom skill，按会议主题自动套用 normalized skills。"
        )

        let subagentBlocks = route.subagents.map { subagent in
            let skillIDs = runtimeSkillsBySubagent[subagent] ?? []
            let skillDocs = skillIDs.map { skillID in
                """
                ### \(skillID)
                \(MeetingAgentPackStore.shared.runtimeSkillDocument(for: skillID))
                """
            }.joined(separator: "\n\n")

            return """
            ## \(subagent.displayName)
            边界：\(taskBoundary(for: subagent, subtask: route.currentSubtask))
            skills: \(skillIDs.joined(separator: ", "))

            \(skillDocs)
            """
        }.joined(separator: "\n\n")

        return """
        你是会议讨论 supervisor。请根据 route decision 调度多个 subagents，并保留每个 subagent 的独立观点。
        只返回一个 JSON 对象，不要输出 Markdown 代码块：
        {
          "title": "string",
          "body": "string",
          "routingWhy": "string",
          "viewpoints": [
            {
              "subagentName": "socratic|first_principles|critic|debate|roundtable|decision|execution|risk|business|retrospective",
              "stance": "string",
              "corePoint": "string",
              "challenge": "string",
              "evidenceNeeded": "string",
              "followUpLine": "string",
              "skillIDs": ["string"]
            }
          ],
          "supervisorSummary": {
            "keyGap": "string",
            "ignoredQuestion": "string",
            "bestFollowUpLine": "string",
            "nextAction": "string"
          }
        }

        约束：
        - viewpoints 只返回 route 里的 2 到 3 个 subagents，且不能重复。
        - 每个 subagent 的 stance 必须不同。
        - 每个字段都短、锐利、适合会议中实时阅读。
        - supervisor 不要覆盖子观点，只负责指出真正冲突点和下一步动作。
        - body 只写 1 到 2 句摘要。
        - 必须显式吸收 imported/custom skill 正文的方法，而不是只重复 skill 名称。

        Route decision:
        - meetingTheme: \(route.meetingTheme.rawValue)
        - currentSubtask: \(route.currentSubtask.rawValue)
        - agoraRoom: \(route.agoraRoom.rawValue)
        - why: \(route.why)

        Agora room guidance:
        \(MeetingAgentPackStore.shared.agoraRoomDocument(for: route.agoraRoom))

        imported skill signal:
        \(selectedSkillContext)

        当前 meeting.md 摘要：
        \(markdownBody)

        最近会议片段：
        \(transcriptBody)

        Subagents:
        \(subagentBlocks)

        会议主题：\(topic)
        触发原因：\(reason.displayName) - \(reason.description)
        """
    }

    private static func postMeetingPrompt(
        topic: String,
        transcript: [TranscriptSegment],
        summaryBundle: MeetingSummaryBundle?,
        skill: MeetingSkillInstall
    ) -> String {
        let speakerDisplayMap = MeetingSpeakerLabelResolver.displayMap(transcript: transcript)
        let transcriptBody = transcript.suffix(12).map { segment in
            let speaker = MeetingSpeakerLabelResolver.displayName(
                for: segment.speakerLabel,
                mapping: speakerDisplayMap
            )
            return "[\(speaker)] \(segment.text)"
        }.joined(separator: "\n")

        let summaryText = summaryBundle.map { bundle in
            """
            全文总结：\(bundle.fullSummary)
            待办：\(bundle.actionItems.map(\.task).joined(separator: "；"))
            问答：\(bundle.qaPairs.map { "\($0.question) -> \($0.answer)" }.joined(separator: "；"))
            """
        } ?? "暂无妙记结构化结果"

        return """
        你正在扮演会后复盘 agent。请只返回一个 JSON 对象：
        {
          "title": "string",
          "coreJudgment": "string",
          "blindSpot": "string",
          "nextStep": "string"
        }

        输出约束：
        - title 12 字以内。
        - 三个字段都必须简洁、明确、可执行。
        - 结合 skill 的方法论，但不要引用太长原文。

        会议主题：\(topic)

        结构化摘要：
        \(summaryText)

        采用 skill：
        \(MeetingPromptSkillContextBuilder.buildSingleSkillContext(skill))

        会议片段：
        \(transcriptBody)
        """
    }

    private static func parseLiveCard(
        content: String,
        reason: MeetingThinkingReason,
        route: MeetingRouteDecision,
        runtimeSkillsBySubagent: [MeetingSubagentName: [String]],
        sourceSegmentIDs: [String]
    ) -> MeetingAdviceCard? {
        guard let data = cleanedJSONData(content),
              let payload = try? JSONDecoder().decode(LiveCardPayload.self, from: data) else {
            return nil
        }

        let fallback = fallbackLiveCard(
            topic: route.meetingTheme.displayName,
            reason: reason,
            route: route,
            runtimeSkillsBySubagent: runtimeSkillsBySubagent,
            sourceSegments: []
        )

        let parsedViewpoints = payload.viewpoints.compactMap { raw -> SubagentViewpoint? in
            guard let subagent = MeetingSubagentName(rawValue: raw.subagentName) else {
                return nil
            }
            let stance = raw.stance.nonEmpty ?? fallback.viewpoints.first(where: { $0.subagentName == subagent })?.stance ?? subagent.displayName
            let corePoint = raw.corePoint.nonEmpty ?? fallback.viewpoints.first(where: { $0.subagentName == subagent })?.corePoint ?? ""
            let challenge = raw.challenge.nonEmpty ?? fallback.viewpoints.first(where: { $0.subagentName == subagent })?.challenge ?? ""
            let evidenceNeeded = raw.evidenceNeeded.nonEmpty ?? fallback.viewpoints.first(where: { $0.subagentName == subagent })?.evidenceNeeded ?? ""
            let followUpLine = raw.followUpLine.nonEmpty ?? fallback.viewpoints.first(where: { $0.subagentName == subagent })?.followUpLine ?? ""

            guard !corePoint.isEmpty, !challenge.isEmpty, !evidenceNeeded.isEmpty, !followUpLine.isEmpty else {
                return nil
            }

            return SubagentViewpoint(
                subagentName: subagent,
                stance: stance,
                corePoint: corePoint,
                challenge: challenge,
                evidenceNeeded: evidenceNeeded,
                followUpLine: followUpLine,
                skillIDs: raw.skillIDs ?? runtimeSkillsBySubagent[subagent] ?? []
            )
        }

        let viewpoints = parsedViewpoints.isEmpty ? fallback.viewpoints : parsedViewpoints
        let summary = payload.supervisorSummary.map {
            MeetingSupervisorSummary(
                keyGap: $0.keyGap.nonEmpty ?? fallback.supervisorSummary?.keyGap ?? "",
                ignoredQuestion: $0.ignoredQuestion.nonEmpty ?? fallback.supervisorSummary?.ignoredQuestion ?? "",
                bestFollowUpLine: $0.bestFollowUpLine.nonEmpty ?? viewpoints.first?.followUpLine ?? "",
                nextAction: $0.nextAction.nonEmpty ?? fallback.supervisorSummary?.nextAction ?? ""
            )
        } ?? fallback.supervisorSummary

        guard let summary else { return nil }

        return MeetingAdviceCard(
            title: payload.title.nonEmpty ?? fallback.title,
            body: payload.body.nonEmpty ?? fallback.body,
            triggerRuleID: reason.triggerRuleID,
            skillIDs: fallback.skillIDs,
            sourceSegmentIDs: sourceSegmentIDs,
            source: "agent",
            meetingTheme: route.meetingTheme,
            currentSubtask: route.currentSubtask,
            agoraRoom: route.agoraRoom,
            subagents: viewpoints.map(\.subagentName),
            viewpoints: viewpoints,
            supervisorSummary: summary,
            routingWhy: payload.routingWhy.nonEmpty ?? route.why
        )
    }

    private static func parsePostMeetingCard(
        content: String,
        skillID: String,
        sourceSegments: [String]
    ) -> MeetingAdviceCard? {
        guard let json = parseJSONObject(content),
              let title = json["title"] as? String,
              let coreJudgment = json["coreJudgment"] as? String,
              let blindSpot = json["blindSpot"] as? String,
              let nextStep = json["nextStep"] as? String,
              !title.isEmpty,
              !coreJudgment.isEmpty,
              !blindSpot.isEmpty,
              !nextStep.isEmpty else {
            return nil
        }

        let body = """
        核心判断：\(coreJudgment)
        被忽略的问题：\(blindSpot)
        下一步建议：\(nextStep)
        """

        return MeetingAdviceCard(
            title: title,
            body: body,
            triggerRuleID: "post_meeting_review",
            skillIDs: [skillID],
            sourceSegmentIDs: sourceSegments,
            source: "post-agent",
            coreJudgment: coreJudgment,
            blindSpot: blindSpot,
            nextStep: nextStep
        )
    }

    private static func fallbackLiveCard(
        topic: String,
        reason: MeetingThinkingReason,
        route: MeetingRouteDecision,
        runtimeSkillsBySubagent: [MeetingSubagentName: [String]],
        sourceSegments: [TranscriptSegment]
    ) -> MeetingAdviceCard {
        let focus = mostRecentMeaningfulLine(from: sourceSegments) ?? topic
        let viewpoints = route.subagents.map { subagent in
            fallbackViewpoint(
                subagent: subagent,
                route: route,
                focus: focus,
                skillIDs: runtimeSkillsBySubagent[subagent] ?? []
            )
        }
        let summary = MeetingSupervisorSummary(
            keyGap: keyGap(for: route, focus: focus),
            ignoredQuestion: ignoredQuestion(for: route),
            bestFollowUpLine: viewpoints.first?.followUpLine ?? "这次会议真正要拍板的到底是什么？",
            nextAction: nextAction(for: route)
        )

        return MeetingAdviceCard(
            title: route.currentSubtask.displayName,
            body: "\(summary.keyGap) \(summary.nextAction)",
            triggerRuleID: reason.triggerRuleID,
            skillIDs: Array(Set(viewpoints.flatMap(\.skillIDs) + ["meeting-synthesizer"])).sorted(),
            sourceSegmentIDs: sourceSegments.suffix(8).map(\.id),
            source: "agent",
            meetingTheme: route.meetingTheme,
            currentSubtask: route.currentSubtask,
            agoraRoom: route.agoraRoom,
            subagents: viewpoints.map(\.subagentName),
            viewpoints: viewpoints,
            supervisorSummary: summary,
            routingWhy: route.why
        )
    }

    private static func fallbackPostMeetingCard(
        skill: MeetingSkillInstall?,
        sourceSegments: [TranscriptSegment]
    ) -> MeetingAdviceCard {
        let coreJudgment = "当前讨论仍需要进一步收敛成一个明确判断。"
        let blindSpot = "尚未充分验证核心场景、前提假设和 owner 承接。"
        let nextStep = "把核心问题、成功标准和负责人拆成三项明确行动。"
        let body = """
        核心判断：\(coreJudgment)
        被忽略的问题：\(blindSpot)
        下一步建议：\(nextStep)
        """
        return MeetingAdviceCard(
            title: "会后建议",
            body: body,
            triggerRuleID: "post_meeting_review",
            skillIDs: skill.map { [$0.id] } ?? [],
            sourceSegmentIDs: sourceSegments.suffix(12).map(\.id),
            source: "post-agent",
            coreJudgment: coreJudgment,
            blindSpot: blindSpot,
            nextStep: nextStep
        )
    }

    private static func fallbackViewpoint(
        subagent: MeetingSubagentName,
        route: MeetingRouteDecision,
        focus: String,
        skillIDs: [String]
    ) -> SubagentViewpoint {
        switch subagent {
        case .socratic:
            return SubagentViewpoint(
                subagentName: .socratic,
                stance: "定义追问",
                corePoint: "先把“\(focus)”对应的问题定义清楚，再继续讨论方案。",
                challenge: "现在最大风险是大家在回答不同的问题。",
                evidenceNeeded: "需要一句可验证的问题定义和成功标准。",
                followUpLine: "我们现在到底在解决哪个具体问题？",
                skillIDs: skillIDs
            )
        case .firstPrinciples:
            return SubagentViewpoint(
                subagentName: .firstPrinciples,
                stance: "本质追问",
                corePoint: "把“\(focus)”拆到最小约束，先看哪一条是不可绕开的。",
                challenge: "如果关键约束没找对，后面的争论都在表层打转。",
                evidenceNeeded: "需要列出 1 到 2 个不可退让的核心约束。",
                followUpLine: "如果只保留一个核心约束，它到底是什么？",
                skillIDs: skillIDs
            )
        case .critic:
            return SubagentViewpoint(
                subagentName: .critic,
                stance: "批判视角",
                corePoint: "当前论证里最脆弱的一点，是把“\(focus)”背后的假设默认当真。",
                challenge: "一旦这个前提不成立，今天的结论会整体失效。",
                evidenceNeeded: "需要一条会击穿现有结论的反例或用户证据。",
                followUpLine: "如果这个前提被证伪，我们还会继续做吗？",
                skillIDs: skillIDs
            )
        case .debate:
            return SubagentViewpoint(
                subagentName: .debate,
                stance: "A/B 对打",
                corePoint: "让支持推进和反对推进两个立场只说最强论点，避免温和折中。",
                challenge: "现在的讨论还没有形成真正的张力。",
                evidenceNeeded: "需要一条能决定 A/B 取舍的证据标准。",
                followUpLine: "支持和反对各自最强的一条论据分别是什么？",
                skillIDs: skillIDs
            )
        case .roundtable:
            return SubagentViewpoint(
                subagentName: .roundtable,
                stance: "圆桌视角",
                corePoint: "当前议题适合拉出支持者、谨慎反对者和意外视角者三方对打。",
                challenge: "如果没有第三方意外视角，讨论会很快收敛成原有框架。",
                evidenceNeeded: "需要一个来自相邻领域的类比或反例。",
                followUpLine: "如果让一个完全不同背景的人来反驳我们，他会先质疑什么？",
                skillIDs: skillIDs
            )
        case .decision:
            return SubagentViewpoint(
                subagentName: .decision,
                stance: "拍板视角",
                corePoint: "讨论应该尽快落到“做 / 不做 / 先试”三选一，而不是继续拉长。",
                challenge: "不愿承担代价，通常意味着其实还没有准备好拍板。",
                evidenceNeeded: "需要明确这次决定承担的代价和放弃项。",
                followUpLine: "如果现在必须拍板，我们愿意承担的代价是什么？",
                skillIDs: skillIDs
            )
        case .execution:
            return SubagentViewpoint(
                subagentName: .execution,
                stance: "推进视角",
                corePoint: "把“\(focus)”拆成 owner、依赖、时间点，阻塞就会具体化。",
                challenge: "现在最大问题不是没想法，而是没有人对下一步负责。",
                evidenceNeeded: "需要一条明确的 owner + due date。",
                followUpLine: "这件事下一步到底由谁在什么时间推进？",
                skillIDs: skillIDs
            )
        case .risk:
            return SubagentViewpoint(
                subagentName: .risk,
                stance: "风险视角",
                corePoint: "先看“\(focus)”失败时最贵的代价，再决定是否继续押注。",
                challenge: "如果只看收益，不看失败路径，讨论会系统性偏乐观。",
                evidenceNeeded: "需要列出最坏情况和触发条件。",
                followUpLine: "这件事最容易在哪个环节出问题，代价有多大？",
                skillIDs: skillIDs
            )
        case .business:
            return SubagentViewpoint(
                subagentName: .business,
                stance: "商业视角",
                corePoint: "先回答“\(focus)”是否真的改变用户行为，再谈扩张和规模化。",
                challenge: "技术上能做，不等于商业上值得做。",
                evidenceNeeded: "需要最小可验证的用户价值与成本测算。",
                followUpLine: "如果用户真的需要，它会改变什么行为，值多少钱？",
                skillIDs: skillIDs
            )
        case .retrospective:
            return SubagentViewpoint(
                subagentName: .retrospective,
                stance: "复盘视角",
                corePoint: "先抽出这次关于“\(focus)”的模式，再决定哪些经验可复制。",
                challenge: "只记结论不记模式，下一次还会在同样位置犯错。",
                evidenceNeeded: "需要一条成功模式和一条反模式。",
                followUpLine: "这次最值得保留的一条做法，以及最该避免的一条坏模式分别是什么？",
                skillIDs: skillIDs
            )
        }
    }

    private static func keyGap(for route: MeetingRouteDecision, focus: String) -> String {
        switch route.currentSubtask {
        case .defineProblem:
            return "关键缺口是“\(focus)”对应的问题定义还不够清楚。"
        case .testPremise:
            return "关键缺口是核心前提还没有被验证。"
        case .compareOptions:
            return "关键缺口是方案取舍标准还没统一。"
        case .forceDecision:
            return "关键缺口是团队还没有承诺一个明确选择。"
        case .unblockExecution:
            return "关键缺口是 owner、依赖和时间点没有锁住。"
        case .promptNextSentence:
            return "关键缺口是现场缺少一条可以直接接住讨论的下一句。"
        case .assessBusinessCase:
            return "关键缺口是商业闭环和 ROI 仍然模糊。"
        case .extractLessons:
            return "关键缺口是经验还没被抽成可复用模式。"
        }
    }

    private static func ignoredQuestion(for route: MeetingRouteDecision) -> String {
        switch route.currentSubtask {
        case .defineProblem:
            return "如果问题定义错了，后面的方案讨论还有没有意义？"
        case .testPremise:
            return "哪个关键假设一旦不成立，会让结论整体失效？"
        case .compareOptions:
            return "到底哪一条证据会决定 A/B 方案的取舍？"
        case .forceDecision:
            return "我们到底愿意接受什么代价来换这次决定？"
        case .unblockExecution:
            return "没有 owner 的那一步为什么到现在还没被认领？"
        case .promptNextSentence:
            return "现场最值得继续追问的那一句到底是什么？"
        case .assessBusinessCase:
            return "用户真的会因为这个价值而改变行为吗？"
        case .extractLessons:
            return "这次得到的教训里，哪一条是下次绝不能再犯的？"
        }
    }

    private static func nextAction(for route: MeetingRouteDecision) -> String {
        switch route.currentSubtask {
        case .defineProblem:
            return "下一步先把问题定义、目标用户和成功标准写成一句话。"
        case .testPremise:
            return "下一步先补一条验证前提的证据，再继续推进讨论。"
        case .compareOptions:
            return "下一步明确取舍标准，再让 A/B 方案按同一标准比较。"
        case .forceDecision:
            return "下一步把备选项收敛到 1 到 2 个，并当场拍板。"
        case .unblockExecution:
            return "下一步把 owner、依赖和截止时间当场锁定。"
        case .promptNextSentence:
            return "下一步直接抛出最值得追问的一句，把讨论重新拉起来。"
        case .assessBusinessCase:
            return "下一步补一页 ROI 和用户价值测算，再决定是否继续。"
        case .extractLessons:
            return "下一步把可复用模式和反模式各写一条，沉淀到会后记录。"
        }
    }

    private static func taskBoundary(for subagent: MeetingSubagentName, subtask: MeetingSubtask) -> String {
        switch subagent {
        case .socratic:
            return "只负责追问定义和假设，不替团队下结论。"
        case .firstPrinciples:
            return "只负责拆本质变量和不可退让约束。"
        case .critic:
            return "只负责打最脆弱的一点和反例。"
        case .debate:
            return "只负责让冲突立场显形，不能温和折中。"
        case .roundtable:
            return subtask == .promptNextSentence
                ? "把讨论拉开成多个有张力的角度，并给可直接接话的下一句。"
                : "把支持者、反对者和意外视角者同时摆上桌。"
        case .decision:
            return "只负责迫使团队做选择并承担代价。"
        case .execution:
            return "只负责拆 owner、依赖、时间点和阻塞。"
        case .risk:
            return "只负责推演失败路径和隐藏代价。"
        case .business:
            return "只负责判断做出来有没有商业意义。"
        case .retrospective:
            return "只负责抽经验模式和反模式。"
        }
    }

    private static func parseJSONObject(_ content: String) -> [String: Any]? {
        guard let data = cleanedJSONData(content),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        return json
    }

    private static func cleanedJSONData(_ content: String) -> Data? {
        let cleaned = content
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "```json", with: "")
            .replacingOccurrences(of: "```", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return cleaned.data(using: .utf8)
    }

    private static func normalizedCorpus(topic: String, recentSegments: [TranscriptSegment]) -> String {
        ([topic] + recentSegments.suffix(10).map(\.text))
            .map(normalize(text:))
            .joined(separator: " ")
    }

    private static func normalizedSkillCorpus(_ skill: MeetingSkillInstall) -> String {
        normalize(text: [skill.displayName, skill.description, trimSkill(skill.skillMarkdown, maxLength: 800)].joined(separator: " "))
    }

    private static func containsAny(_ corpus: String, needles: [String]) -> Bool {
        needles.contains { corpus.contains($0.lowercased()) }
    }

    private static func normalize(text: String) -> String {
        text
            .lowercased()
            .replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func tokenize(_ topic: String) -> [String] {
        topic.lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { $0.count >= 2 }
    }

    private static func mostRecentMeaningfulLine(from segments: [TranscriptSegment]) -> String? {
        segments.reversed().first { !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }?.text
    }

    private static func trimSkill(_ markdown: String, maxLength: Int = 2_500) -> String {
        String(markdown.prefix(maxLength))
    }

    private struct LiveCardPayload: Decodable {
        let title: String?
        let body: String?
        let routingWhy: String?
        let viewpoints: [LiveViewpointPayload]
        let supervisorSummary: LiveSupervisorSummaryPayload?
    }

    private struct LiveViewpointPayload: Decodable {
        let subagentName: String
        let stance: String?
        let corePoint: String?
        let challenge: String?
        let evidenceNeeded: String?
        let followUpLine: String?
        let skillIDs: [String]?
    }

    private struct LiveSupervisorSummaryPayload: Decodable {
        let keyGap: String?
        let ignoredQuestion: String?
        let bestFollowUpLine: String?
        let nextAction: String?
    }
}

private extension Optional where Wrapped == String {
    var nonEmpty: String? {
        guard let value = self?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else {
            return nil
        }
        return value
    }
}
