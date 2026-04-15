import Foundation

enum MeetingProcessingState: String, Codable, CaseIterable, Sendable {
    case draft
    case scheduled
    case recording
    case processing
    case completed
    case failed
}

enum MeetingRealtimeASRState: String, Codable, CaseIterable, Sendable {
    case idle
    case connecting
    case ready
    case receiving
    case failed
}

enum MeetingAudioInputMode: String, Codable, CaseIterable, Sendable {
    case microphoneOnly = "microphone_only"
    case systemOnly = "system_only"
    case microphoneAndSystem = "microphone_and_system"

    var displayName: String {
        switch self {
        case .microphoneOnly:
            return "仅麦克风"
        case .systemOnly:
            return "仅系统录音"
        case .microphoneAndSystem:
            return "麦克风+系统录音"
        }
    }

    func effectiveDisplayName(systemAudioAvailable: Bool) -> String {
        switch self {
        case .microphoneOnly:
            return displayName
        case .systemOnly:
            return systemAudioAvailable ? displayName : MeetingAudioInputMode.microphoneOnly.displayName
        case .microphoneAndSystem:
            return systemAudioAvailable ? displayName : MeetingAudioInputMode.microphoneOnly.displayName
        }
    }

    var requiresMicrophone: Bool {
        switch self {
        case .microphoneOnly, .microphoneAndSystem:
            return true
        case .systemOnly:
            return false
        }
    }

    var requiresSystemAudio: Bool {
        switch self {
        case .microphoneOnly:
            return false
        case .systemOnly, .microphoneAndSystem:
            return true
        }
    }
}

enum MeetingImportedMediaKind: String, Codable, CaseIterable, Sendable {
    case audio
    case video

    var displayName: String {
        switch self {
        case .audio:
            return "音频"
        case .video:
            return "视频"
        }
    }
}

enum MeetingCalendarSyncState: String, Codable, CaseIterable, Sendable {
    case disabled
    case pending
    case synced
    case failed

    var displayName: String {
        switch self {
        case .disabled:
            return "未同步"
        case .pending:
            return "待同步"
        case .synced:
            return "已同步"
        case .failed:
            return "同步失败"
        }
    }
}

struct MeetingConfig: Codable, Equatable, Sendable {
    var topic: String
    var selectedSkillIDs: [String]
    var autoRecommendedSkillIDs: [String]
    var createdAt: Date
    var scheduledAt: Date?
    var durationMinutes: Int
    var calendarSyncEnabled: Bool

    init(
        topic: String,
        selectedSkillIDs: [String] = [],
        autoRecommendedSkillIDs: [String] = [],
        createdAt: Date = Date(),
        scheduledAt: Date? = nil,
        durationMinutes: Int = 60,
        calendarSyncEnabled: Bool = false
    ) {
        self.topic = topic
        self.selectedSkillIDs = selectedSkillIDs
        self.autoRecommendedSkillIDs = autoRecommendedSkillIDs
        self.createdAt = createdAt
        self.scheduledAt = scheduledAt
        self.durationMinutes = max(durationMinutes, 1)
        self.calendarSyncEnabled = calendarSyncEnabled
    }
}

enum MeetingAnnotationKind: String, Codable, CaseIterable, Sendable {
    case focus
    case note
}

enum MeetingNoteAttachmentKind: String, Codable, CaseIterable, Sendable {
    case image
    case file
    case screenshot

    var displayName: String {
        switch self {
        case .image:
            return "图片"
        case .file:
            return "文件"
        case .screenshot:
            return "截屏"
        }
    }
}

struct MeetingNoteAttachment: Codable, Equatable, Identifiable, Sendable {
    var id: String
    var kind: MeetingNoteAttachmentKind
    var displayName: String
    var relativePath: String
    var extractedMarkdown: String
    var createdAt: Date

    init(
        id: String = UUID().uuidString,
        kind: MeetingNoteAttachmentKind,
        displayName: String,
        relativePath: String,
        extractedMarkdown: String,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.kind = kind
        self.displayName = displayName
        self.relativePath = relativePath
        self.extractedMarkdown = extractedMarkdown
        self.createdAt = createdAt
    }
}

enum MeetingAnnotationSource: String, Codable, CaseIterable, Sendable {
    case recentContext = "recent_context"
    case transcriptSegment = "transcript_segment"
    case transcriptComment = "transcript_comment"
    case transcriptExcerpt = "transcript_excerpt"
    case manualNote = "manual_note"
    case attachmentImport = "attachment_import"
    case screenshotCapture = "screenshot_capture"

    var displayName: String {
        switch self {
        case .recentContext:
            return "按钮截取"
        case .transcriptSegment:
            return "字幕标记"
        case .transcriptComment:
            return "评论"
        case .transcriptExcerpt:
            return "字幕摘录"
        case .manualNote:
            return "手动笔记"
        case .attachmentImport:
            return "附件导入"
        case .screenshotCapture:
            return "截屏"
        }
    }
}

struct MeetingAnnotationQuoteContext: Equatable, Sendable {
    var timecode: String
    var speakerLabel: String
    var text: String

    var inlineText: String {
        "[\(timecode)][\(speakerLabel)] \(text)"
    }
}

struct MeetingAnnotation: Codable, Equatable, Identifiable, Sendable {
    var id: String
    var kind: MeetingAnnotationKind
    var createdAt: Date
    var timecodeMs: Int
    var text: String
    var sourceSegmentIDs: [String]
    var source: MeetingAnnotationSource
    var attachments: [MeetingNoteAttachment]

    init(
        id: String = UUID().uuidString,
        kind: MeetingAnnotationKind,
        createdAt: Date = Date(),
        timecodeMs: Int,
        text: String,
        sourceSegmentIDs: [String] = [],
        source: MeetingAnnotationSource,
        attachments: [MeetingNoteAttachment] = []
    ) {
        self.id = id
        self.kind = kind
        self.createdAt = createdAt
        self.timecodeMs = max(0, timecodeMs)
        self.text = text
        self.sourceSegmentIDs = sourceSegmentIDs
        self.source = source
        self.attachments = attachments
    }
}

extension MeetingAnnotation {
    private enum CodingKeys: String, CodingKey {
        case id
        case kind
        case createdAt
        case timecodeMs
        case text
        case sourceSegmentIDs
        case source
        case attachments
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(String.self, forKey: .id) ?? UUID().uuidString
        kind = try container.decode(MeetingAnnotationKind.self, forKey: .kind)
        createdAt = try container.decodeIfPresent(Date.self, forKey: .createdAt) ?? Date()
        timecodeMs = max(0, try container.decode(Int.self, forKey: .timecodeMs))
        text = try container.decodeIfPresent(String.self, forKey: .text) ?? ""
        sourceSegmentIDs = try container.decodeIfPresent([String].self, forKey: .sourceSegmentIDs) ?? []
        source = try container.decode(MeetingAnnotationSource.self, forKey: .source)
        attachments = try container.decodeIfPresent([MeetingNoteAttachment].self, forKey: .attachments) ?? []
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(kind, forKey: .kind)
        try container.encode(createdAt, forKey: .createdAt)
        try container.encode(timecodeMs, forKey: .timecodeMs)
        try container.encode(text, forKey: .text)
        try container.encode(sourceSegmentIDs, forKey: .sourceSegmentIDs)
        try container.encode(source, forKey: .source)
        try container.encode(attachments, forKey: .attachments)
    }
}

extension MeetingAnnotation {
    var effectiveText: String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty {
            return trimmed
        }
        if attachments.count == 1, let attachment = attachments.first {
            return "附件：\(attachment.displayName)"
        }
        if !attachments.isEmpty {
            return "附件：\(attachments.count) 个文件"
        }
        return ""
    }

    var linkedTranscriptSegmentID: String? {
        sourceSegmentIDs.first
    }

    var isTranscriptComment: Bool {
        kind == .note && source == .transcriptComment && linkedTranscriptSegmentID != nil
    }

    func quoteContext(
        in transcript: [TranscriptSegment],
        maxCharacters: Int = 140
    ) -> MeetingAnnotationQuoteContext? {
        guard let linkedTranscriptSegmentID else {
            return nil
        }
        let matchingSegments = transcript.filter { $0.id == linkedTranscriptSegmentID }
        guard let segment = matchingSegments.max(by: { lhs, rhs in
            if lhs.isFinal != rhs.isFinal {
                return !lhs.isFinal && rhs.isFinal
            }
            if lhs.endTimeMs != rhs.endTimeMs {
                return lhs.endTimeMs < rhs.endTimeMs
            }
            return lhs.text.count < rhs.text.count
        }) else {
            return nil
        }

        let trimmedText = segment.text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedText.isEmpty else { return nil }

        let text: String
        if trimmedText.count > maxCharacters {
            let endIndex = trimmedText.index(trimmedText.startIndex, offsetBy: maxCharacters)
            text = String(trimmedText[..<endIndex]) + "..."
        } else {
            text = trimmedText
        }

        let speakerDisplayMap = MeetingSpeakerLabelResolver.displayMap(transcript: transcript)

        return MeetingAnnotationQuoteContext(
            timecode: MeetingLiveTimeline.timecode(milliseconds: max(0, segment.startTimeMs)),
            speakerLabel: MeetingSpeakerLabelResolver.displayName(
                for: segment.speakerLabel,
                mapping: speakerDisplayMap
            ),
            text: text
        )
    }

    func summaryText(
        in transcript: [TranscriptSegment],
        maxAttachmentCharacters: Int = 2_000,
        maxQuoteCharacters: Int = 220
    ) -> String {
        var parts: [String] = []
        let trimmed = effectiveText
        if !trimmed.isEmpty {
            parts.append(trimmed)
        }

        if let quoteContext = quoteContext(in: transcript, maxCharacters: maxQuoteCharacters) {
            parts.append("引用：\(quoteContext.inlineText)")
        }

        for attachment in attachments {
            let markdown = attachment.extractedMarkdown.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !markdown.isEmpty else { continue }
            if markdown.count > maxAttachmentCharacters {
                let endIndex = markdown.index(markdown.startIndex, offsetBy: maxAttachmentCharacters)
                parts.append("[\(attachment.displayName)] " + String(markdown[..<endIndex]) + "...")
            } else {
                parts.append("[\(attachment.displayName)] " + markdown)
            }
        }

        return parts.joined(separator: "\n")
    }

    func summaryText(maxAttachmentCharacters: Int = 2_000) -> String {
        summaryText(in: [], maxAttachmentCharacters: maxAttachmentCharacters)
    }
}

struct SpeakerSpan: Codable, Equatable, Identifiable, Sendable {
    var id: String
    var speakerLabel: String
    var startTimeMs: Int
    var endTimeMs: Int
    var gender: String?
    var speechRate: Double?
    var volume: Double?
    var emotion: String?

    init(
        id: String = UUID().uuidString,
        speakerLabel: String,
        startTimeMs: Int,
        endTimeMs: Int,
        gender: String? = nil,
        speechRate: Double? = nil,
        volume: Double? = nil,
        emotion: String? = nil
    ) {
        self.id = id
        self.speakerLabel = speakerLabel
        self.startTimeMs = startTimeMs
        self.endTimeMs = endTimeMs
        self.gender = gender
        self.speechRate = speechRate
        self.volume = volume
        self.emotion = emotion
    }
}

enum MeetingSpeakerLabelResolver {
    nonisolated static func displayMap(
        transcript: [TranscriptSegment],
        speakerSpans: [SpeakerSpan] = []
    ) -> [String: String] {
        var orderedGenericLabels: [String] = []

        let orderedTranscript = transcript.sorted { lhs, rhs in
            if lhs.startTimeMs == rhs.startTimeMs {
                return lhs.id < rhs.id
            }
            return lhs.startTimeMs < rhs.startTimeMs
        }
        for segment in orderedTranscript {
            registerGenericLabel(segment.speakerLabel, into: &orderedGenericLabels)
        }

        let orderedSpans = speakerSpans.sorted { lhs, rhs in
            if lhs.startTimeMs == rhs.startTimeMs {
                return lhs.id < rhs.id
            }
            return lhs.startTimeMs < rhs.startTimeMs
        }
        for span in orderedSpans {
            registerGenericLabel(span.speakerLabel, into: &orderedGenericLabels)
        }

        return Dictionary(uniqueKeysWithValues: orderedGenericLabels.enumerated().map { index, rawLabel in
            (rawLabel, "说话人\(index + 1)")
        })
    }

    nonisolated static func displayName(
        for rawLabel: String?,
        transcript: [TranscriptSegment],
        speakerSpans: [SpeakerSpan] = []
    ) -> String {
        displayName(
            for: rawLabel,
            mapping: displayMap(transcript: transcript, speakerSpans: speakerSpans)
        )
    }

    nonisolated static func displayName(
        for rawLabel: String?,
        mapping: [String: String] = [:]
    ) -> String {
        guard let normalized = normalizedLabel(rawLabel) else {
            return "说话人"
        }
        if let mapped = mapping[normalized] {
            return mapped
        }
        if isGenericMachineLabel(normalized) {
            return "说话人"
        }
        return normalized
    }

    private nonisolated static func registerGenericLabel(_ rawLabel: String?, into orderedLabels: inout [String]) {
        guard let normalized = normalizedLabel(rawLabel), isGenericMachineLabel(normalized) else { return }
        if !orderedLabels.contains(normalized) {
            orderedLabels.append(normalized)
        }
    }

    private nonisolated static func normalizedLabel(_ rawLabel: String?) -> String? {
        guard let rawLabel else { return nil }
        let trimmed = rawLabel.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private nonisolated static func isGenericMachineLabel(_ rawLabel: String) -> Bool {
        let lowercased = rawLabel.lowercased()
        if lowercased == "speaker_unknown" {
            return true
        }
        if lowercased.hasPrefix("speaker") || lowercased.hasPrefix("spk") {
            return true
        }
        return Int(lowercased) != nil
    }
}

struct TranscriptSegment: Codable, Equatable, Identifiable, Sendable {
    var id: String
    var text: String
    var startTimeMs: Int
    var endTimeMs: Int
    var speakerLabel: String?
    var gender: String?
    var isFinal: Bool
    var speechRate: Double?
    var volume: Double?
    var emotion: String?
    var source: String

    init(
        id: String = UUID().uuidString,
        text: String,
        startTimeMs: Int,
        endTimeMs: Int,
        speakerLabel: String? = nil,
        gender: String? = nil,
        isFinal: Bool = true,
        speechRate: Double? = nil,
        volume: Double? = nil,
        emotion: String? = nil,
        source: String = "live"
    ) {
        self.id = id
        self.text = text
        self.startTimeMs = startTimeMs
        self.endTimeMs = endTimeMs
        self.speakerLabel = speakerLabel
        self.gender = gender
        self.isFinal = isFinal
        self.speechRate = speechRate
        self.volume = volume
        self.emotion = emotion
        self.source = source
    }

    var displaySpeakerLabel: String {
        MeetingSpeakerLabelResolver.displayName(for: speakerLabel)
    }

    var displaySpeakerBadge: String {
        guard let gender, !gender.isEmpty else { return displaySpeakerLabel }
        return "\(displaySpeakerLabel) · \(gender)"
    }

    func displaySpeakerLabel(
        in transcript: [TranscriptSegment],
        speakerSpans: [SpeakerSpan] = []
    ) -> String {
        MeetingSpeakerLabelResolver.displayName(
            for: speakerLabel,
            transcript: transcript,
            speakerSpans: speakerSpans
        )
    }

    func displaySpeakerBadge(
        in transcript: [TranscriptSegment],
        speakerSpans: [SpeakerSpan] = []
    ) -> String {
        let label = displaySpeakerLabel(in: transcript, speakerSpans: speakerSpans)
        guard let gender, !gender.isEmpty else { return label }
        return "\(label) · \(gender)"
    }
}

extension SpeakerSpan {
    func displaySpeakerLabel(
        in transcript: [TranscriptSegment],
        speakerSpans: [SpeakerSpan]
    ) -> String {
        MeetingSpeakerLabelResolver.displayName(
            for: speakerLabel,
            transcript: transcript,
            speakerSpans: speakerSpans
        )
    }

    func displaySpeakerBadge(
        in transcript: [TranscriptSegment],
        speakerSpans: [SpeakerSpan]
    ) -> String {
        let label = displaySpeakerLabel(in: transcript, speakerSpans: speakerSpans)
        guard let gender, !gender.isEmpty else { return label }
        return "\(label) · \(gender)"
    }
}

struct MeetingChapterSummary: Codable, Equatable, Identifiable, Sendable {
    var id: String
    var title: String
    var summary: String

    init(id: String = UUID().uuidString, title: String, summary: String) {
        self.id = id
        self.title = title
        self.summary = summary
    }
}

struct MeetingActionItem: Codable, Equatable, Identifiable, Sendable {
    var id: String
    var task: String
    var owner: String?
    var dueDate: String?

    init(id: String = UUID().uuidString, task: String, owner: String? = nil, dueDate: String? = nil) {
        self.id = id
        self.task = task
        self.owner = owner
        self.dueDate = dueDate
    }
}

struct MeetingQAPair: Codable, Equatable, Identifiable, Sendable {
    var id: String
    var question: String
    var answer: String

    init(id: String = UUID().uuidString, question: String, answer: String) {
        self.id = id
        self.question = question
        self.answer = answer
    }
}

struct MeetingDecision: Codable, Equatable, Identifiable, Sendable {
    var id: UUID
    /// One-sentence statement of what was decided.
    var statement: String
    /// Optional rationale / context that produced the decision.
    var rationale: String?
    /// Speaker label (display name) credited with proposing or confirming
    /// the decision. nil when not attributable to a specific person.
    var decidedBy: String?
    /// Original timecode in milliseconds where the decision crystallised,
    /// used to deep-link back into the transcript.
    var timecodeMs: Int?

    init(
        id: UUID = UUID(),
        statement: String,
        rationale: String? = nil,
        decidedBy: String? = nil,
        timecodeMs: Int? = nil
    ) {
        self.id = id
        self.statement = statement
        self.rationale = rationale
        self.decidedBy = decidedBy
        self.timecodeMs = timecodeMs
    }
}

struct MeetingSpeakerViewpoint: Codable, Equatable, Identifiable, Sendable {
    var id: UUID
    /// Display name (e.g. "说话人1") — keyed against the resolver's mapping.
    var speakerLabel: String
    /// 1-3 short bullet-style points capturing this speaker's stance /
    /// contribution to the meeting.
    var points: [String]
    /// Optional one-line summary of the speaker's overall position.
    var stance: String?

    init(
        id: UUID = UUID(),
        speakerLabel: String,
        points: [String] = [],
        stance: String? = nil
    ) {
        self.id = id
        self.speakerLabel = speakerLabel
        self.points = points
        self.stance = stance
    }
}

struct MeetingSummaryBundle: Codable, Equatable, Sendable {
    var fullSummary: String
    var chapterSummaries: [MeetingChapterSummary]
    var actionItems: [MeetingActionItem]
    var qaPairs: [MeetingQAPair]
    var processHighlights: [String]
    /// Decisions extracted from the meeting. Empty when neither the Memo
    /// pipeline nor the LLM enhancement pass produced anything (or when
    /// the LLM is not configured).
    var decisions: [MeetingDecision]
    /// Per-speaker viewpoint summaries. Empty by the same logic.
    var speakerViewpoints: [MeetingSpeakerViewpoint]
    var source: String

    init(
        fullSummary: String = "",
        chapterSummaries: [MeetingChapterSummary] = [],
        actionItems: [MeetingActionItem] = [],
        qaPairs: [MeetingQAPair] = [],
        processHighlights: [String] = [],
        decisions: [MeetingDecision] = [],
        speakerViewpoints: [MeetingSpeakerViewpoint] = [],
        source: String = "memo"
    ) {
        self.fullSummary = fullSummary
        self.chapterSummaries = chapterSummaries
        self.actionItems = actionItems
        self.qaPairs = qaPairs
        self.processHighlights = processHighlights
        self.decisions = decisions
        self.speakerViewpoints = speakerViewpoints
        self.source = source
    }

    // Backward-compatible decoding: old archived records won't contain
    // `decisions` / `speakerViewpoints` and would otherwise fail to
    // decode.
    enum CodingKeys: String, CodingKey {
        case fullSummary, chapterSummaries, actionItems, qaPairs,
             processHighlights, decisions, speakerViewpoints, source
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.fullSummary       = try c.decodeIfPresent(String.self, forKey: .fullSummary) ?? ""
        self.chapterSummaries  = try c.decodeIfPresent([MeetingChapterSummary].self, forKey: .chapterSummaries) ?? []
        self.actionItems       = try c.decodeIfPresent([MeetingActionItem].self, forKey: .actionItems) ?? []
        self.qaPairs           = try c.decodeIfPresent([MeetingQAPair].self, forKey: .qaPairs) ?? []
        self.processHighlights = try c.decodeIfPresent([String].self, forKey: .processHighlights) ?? []
        self.decisions         = try c.decodeIfPresent([MeetingDecision].self, forKey: .decisions) ?? []
        self.speakerViewpoints = try c.decodeIfPresent([MeetingSpeakerViewpoint].self, forKey: .speakerViewpoints) ?? []
        self.source            = try c.decodeIfPresent(String.self, forKey: .source) ?? "memo"
    }
}

struct MeetingMemoArtifact: Equatable, Sendable {
    var summaryBundle: MeetingSummaryBundle
    var transcriptSegments: [TranscriptSegment]
    var speakerSpans: [SpeakerSpan]
    var diagnosticNotes: [String]

    init(
        summaryBundle: MeetingSummaryBundle = MeetingSummaryBundle(),
        transcriptSegments: [TranscriptSegment] = [],
        speakerSpans: [SpeakerSpan] = [],
        diagnosticNotes: [String] = []
    ) {
        self.summaryBundle = summaryBundle
        self.transcriptSegments = transcriptSegments
        self.speakerSpans = speakerSpans
        self.diagnosticNotes = diagnosticNotes
    }
}

enum MeetingTheme: String, Codable, CaseIterable, Sendable {
    case requirementsClarification = "requirements_clarification"
    case solutionReview = "solution_review"
    case decisionCommit = "decision_commit"
    case executionAlignment = "execution_alignment"
    case brainstorming = "brainstorming"
    case riskRetro = "risk_retro"
    case businessEvaluation = "business_evaluation"
    case retrospective = "retrospective"

    var displayName: String {
        switch self {
        case .requirementsClarification:
            return "需求澄清"
        case .solutionReview:
            return "方案评审"
        case .decisionCommit:
            return "决策拍板"
        case .executionAlignment:
            return "项目推进"
        case .brainstorming:
            return "头脑风暴"
        case .riskRetro:
            return "风险复盘"
        case .businessEvaluation:
            return "商业判断"
        case .retrospective:
            return "复盘总结"
        }
    }
}

enum MeetingSubtask: String, Codable, CaseIterable, Sendable {
    case defineProblem = "define_problem"
    case testPremise = "test_premise"
    case compareOptions = "compare_options"
    case forceDecision = "force_decision"
    case unblockExecution = "unblock_execution"
    case promptNextSentence = "prompt_next_sentence"
    case assessBusinessCase = "assess_business_case"
    case extractLessons = "extract_lessons"

    var displayName: String {
        switch self {
        case .defineProblem:
            return "定义问题"
        case .testPremise:
            return "检验前提"
        case .compareOptions:
            return "比较方案"
        case .forceDecision:
            return "推动决策"
        case .unblockExecution:
            return "解除阻塞"
        case .promptNextSentence:
            return "生成下一句"
        case .assessBusinessCase:
            return "评估商业性"
        case .extractLessons:
            return "提炼经验"
        }
    }
}

enum MeetingSubagentName: String, Codable, CaseIterable, Sendable {
    case socratic = "socratic"
    case firstPrinciples = "first_principles"
    case critic = "critic"
    case debate = "debate"
    case roundtable = "roundtable"
    case decision = "decision"
    case execution = "execution"
    case risk = "risk"
    case business = "business"
    case retrospective = "retrospective"

    var displayName: String {
        switch self {
        case .socratic:
            return "SocraticAgent"
        case .firstPrinciples:
            return "FirstPrinciplesAgent"
        case .critic:
            return "CriticAgent"
        case .debate:
            return "DebateAgent"
        case .roundtable:
            return "RoundtableAgent"
        case .decision:
            return "DecisionAgent"
        case .execution:
            return "ExecutionAgent"
        case .risk:
            return "RiskAgent"
        case .business:
            return "BusinessAgent"
        case .retrospective:
            return "RetrospectiveAgent"
        }
    }
}

enum MeetingAgoraRoom: String, Codable, CaseIterable, Sendable {
    case forge
    case bazaar
    case atelier
    case clinic
    case hearth
    case oracle

    var displayName: String {
        switch self {
        case .forge:
            return "Forge"
        case .bazaar:
            return "Bazaar"
        case .atelier:
            return "Atelier"
        case .clinic:
            return "Clinic"
        case .hearth:
            return "Hearth"
        case .oracle:
            return "Oracle"
        }
    }
}

struct SubagentViewpoint: Codable, Equatable, Identifiable, Sendable {
    var id: String
    var subagentName: MeetingSubagentName
    var stance: String
    var corePoint: String
    var challenge: String
    var evidenceNeeded: String
    var followUpLine: String
    var skillIDs: [String]

    init(
        id: String = UUID().uuidString,
        subagentName: MeetingSubagentName,
        stance: String,
        corePoint: String,
        challenge: String,
        evidenceNeeded: String,
        followUpLine: String,
        skillIDs: [String] = []
    ) {
        self.id = id
        self.subagentName = subagentName
        self.stance = stance
        self.corePoint = corePoint
        self.challenge = challenge
        self.evidenceNeeded = evidenceNeeded
        self.followUpLine = followUpLine
        self.skillIDs = skillIDs
    }
}

struct MeetingSupervisorSummary: Codable, Equatable, Sendable {
    var keyGap: String
    var ignoredQuestion: String
    var bestFollowUpLine: String
    var nextAction: String

    init(
        keyGap: String,
        ignoredQuestion: String,
        bestFollowUpLine: String,
        nextAction: String
    ) {
        self.keyGap = keyGap
        self.ignoredQuestion = ignoredQuestion
        self.bestFollowUpLine = bestFollowUpLine
        self.nextAction = nextAction
    }
}

struct MeetingRouteDecision: Equatable, Sendable {
    var meetingTheme: MeetingTheme
    var currentSubtask: MeetingSubtask
    var agoraRoom: MeetingAgoraRoom
    var subagents: [MeetingSubagentName]
    var skillIDs: [String]
    var why: String
}

struct MeetingAdviceCard: Codable, Equatable, Identifiable, Sendable {
    var id: String
    var createdAt: Date
    var title: String
    var body: String
    var triggerRuleID: String
    var skillIDs: [String]
    var sourceSegmentIDs: [String]
    var source: String
    var coreJudgment: String?
    var blindSpot: String?
    var nextStep: String?
    var meetingTheme: MeetingTheme?
    var currentSubtask: MeetingSubtask?
    var agoraRoom: MeetingAgoraRoom?
    var subagents: [MeetingSubagentName]
    var viewpoints: [SubagentViewpoint]
    var supervisorSummary: MeetingSupervisorSummary?
    var routingWhy: String?

    init(
        id: String = UUID().uuidString,
        createdAt: Date = Date(),
        title: String,
        body: String,
        triggerRuleID: String,
        skillIDs: [String] = [],
        sourceSegmentIDs: [String] = [],
        source: String = "agent",
        coreJudgment: String? = nil,
        blindSpot: String? = nil,
        nextStep: String? = nil,
        meetingTheme: MeetingTheme? = nil,
        currentSubtask: MeetingSubtask? = nil,
        agoraRoom: MeetingAgoraRoom? = nil,
        subagents: [MeetingSubagentName] = [],
        viewpoints: [SubagentViewpoint] = [],
        supervisorSummary: MeetingSupervisorSummary? = nil,
        routingWhy: String? = nil
    ) {
        self.id = id
        self.createdAt = createdAt
        self.title = title
        self.body = body
        self.triggerRuleID = triggerRuleID
        self.skillIDs = skillIDs
        self.sourceSegmentIDs = sourceSegmentIDs
        self.source = source
        self.coreJudgment = coreJudgment
        self.blindSpot = blindSpot
        self.nextStep = nextStep
        self.meetingTheme = meetingTheme
        self.currentSubtask = currentSubtask
        self.agoraRoom = agoraRoom
        self.subagents = subagents
        self.viewpoints = viewpoints
        self.supervisorSummary = supervisorSummary
        self.routingWhy = routingWhy
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case createdAt
        case title
        case body
        case triggerRuleID
        case skillIDs
        case sourceSegmentIDs
        case source
        case coreJudgment
        case blindSpot
        case nextStep
        case meetingTheme
        case currentSubtask
        case agoraRoom
        case subagents
        case viewpoints
        case supervisorSummary
        case routingWhy
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(String.self, forKey: .id) ?? UUID().uuidString
        createdAt = try container.decodeIfPresent(Date.self, forKey: .createdAt) ?? Date()
        title = try container.decodeIfPresent(String.self, forKey: .title) ?? "会议建议"
        body = try container.decodeIfPresent(String.self, forKey: .body) ?? ""
        triggerRuleID = try container.decodeIfPresent(String.self, forKey: .triggerRuleID) ?? "manual_think"
        skillIDs = try container.decodeIfPresent([String].self, forKey: .skillIDs) ?? []
        sourceSegmentIDs = try container.decodeIfPresent([String].self, forKey: .sourceSegmentIDs) ?? []
        source = try container.decodeIfPresent(String.self, forKey: .source) ?? "agent"
        coreJudgment = try container.decodeIfPresent(String.self, forKey: .coreJudgment)
        blindSpot = try container.decodeIfPresent(String.self, forKey: .blindSpot)
        nextStep = try container.decodeIfPresent(String.self, forKey: .nextStep)
        meetingTheme = try container.decodeIfPresent(MeetingTheme.self, forKey: .meetingTheme)
        currentSubtask = try container.decodeIfPresent(MeetingSubtask.self, forKey: .currentSubtask)
        agoraRoom = try container.decodeIfPresent(MeetingAgoraRoom.self, forKey: .agoraRoom)
        subagents = try container.decodeIfPresent([MeetingSubagentName].self, forKey: .subagents) ?? []
        viewpoints = try container.decodeIfPresent([SubagentViewpoint].self, forKey: .viewpoints) ?? []
        supervisorSummary = try container.decodeIfPresent(MeetingSupervisorSummary.self, forKey: .supervisorSummary)
        routingWhy = try container.decodeIfPresent(String.self, forKey: .routingWhy)
    }
}

nonisolated struct MeetingSkillCatalogEntry: Codable, Equatable, Identifiable, Sendable {
    var id: String
    var category: String
    var title: String
    var repoURL: String
    var repoFullName: String
    var description: String
    var sourceIndexURL: String
    var isInstallable: Bool
    var subagentID: String
    var subagentName: String

    init(
        id: String? = nil,
        category: String,
        title: String,
        repoURL: String,
        repoFullName: String,
        description: String,
        sourceIndexURL: String,
        isInstallable: Bool = true,
        subagentID: String? = nil,
        subagentName: String? = nil
    ) {
        let resolvedSubagentName = MeetingSkillCatalogEntry.resolvedCatalogSubagentName(
            explicitName: subagentName,
            category: category
        )
        self.id = id ?? repoFullName
        self.category = category
        self.title = title
        self.repoURL = repoURL
        self.repoFullName = repoFullName
        self.description = description
        self.sourceIndexURL = sourceIndexURL
        self.isInstallable = isInstallable
        self.subagentName = resolvedSubagentName
        self.subagentID = subagentID ?? MeetingSkillCatalogEntry.catalogSubagentID(for: resolvedSubagentName)
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case category
        case title
        case repoURL
        case repoFullName
        case description
        case sourceIndexURL
        case isInstallable
        case subagentID
        case subagentName
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let category = try container.decode(String.self, forKey: .category)
        let resolvedSubagentName = Self.resolvedCatalogSubagentName(
            explicitName: try container.decodeIfPresent(String.self, forKey: .subagentName),
            category: category
        )

        id = try container.decodeIfPresent(String.self, forKey: .id)
            ?? container.decode(String.self, forKey: .repoFullName)
        self.category = category
        title = try container.decode(String.self, forKey: .title)
        repoURL = try container.decode(String.self, forKey: .repoURL)
        repoFullName = try container.decode(String.self, forKey: .repoFullName)
        description = try container.decode(String.self, forKey: .description)
        sourceIndexURL = try container.decode(String.self, forKey: .sourceIndexURL)
        isInstallable = try container.decodeIfPresent(Bool.self, forKey: .isInstallable) ?? true
        subagentName = resolvedSubagentName
        subagentID = try container.decodeIfPresent(String.self, forKey: .subagentID)
            ?? Self.catalogSubagentID(for: resolvedSubagentName)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(category, forKey: .category)
        try container.encode(title, forKey: .title)
        try container.encode(repoURL, forKey: .repoURL)
        try container.encode(repoFullName, forKey: .repoFullName)
        try container.encode(description, forKey: .description)
        try container.encode(sourceIndexURL, forKey: .sourceIndexURL)
        try container.encode(isInstallable, forKey: .isInstallable)
        try container.encode(subagentID, forKey: .subagentID)
        try container.encode(subagentName, forKey: .subagentName)
    }

    static let defaultCatalogSubagentName = "未分组"
    static let defaultCatalogSubagentID = "catalog:uncategorized"

    static func catalogSubagentID(for name: String) -> String {
        let slug = MeetingSkillIdentity.slug(from: name)
        return slug.isEmpty ? defaultCatalogSubagentID : "catalog:\(slug)"
    }

    static func resolvedCatalogSubagentName(explicitName: String?, category: String) -> String {
        let trimmedExplicit = explicitName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !trimmedExplicit.isEmpty {
            return trimmedExplicit
        }
        let trimmedCategory = category.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmedCategory.isEmpty ? defaultCatalogSubagentName : trimmedCategory
    }
}

nonisolated enum MeetingSkillSourceKind: String, Codable, CaseIterable, Sendable {
    case catalog
    case imported
    case user

    var displayName: String {
        switch self {
        case .catalog:
            return "索引"
        case .imported:
            return "导入"
        case .user:
            return "自建"
        }
    }
}

nonisolated struct MeetingSkillSubagent: Codable, Equatable, Identifiable, Sendable {
    var id: String
    var name: String
    var description: String
    var sourceKind: MeetingSkillSourceKind
    var sortOrder: Int

    init(
        id: String,
        name: String,
        description: String,
        sourceKind: MeetingSkillSourceKind,
        sortOrder: Int = 0
    ) {
        self.id = id
        self.name = name
        self.description = description
        self.sourceKind = sourceKind
        self.sortOrder = sortOrder
    }
}

nonisolated struct MeetingCatalogSubagentGroup: Equatable, Identifiable, Sendable {
    var subagent: MeetingSkillSubagent
    var entries: [MeetingSkillCatalogEntry]
    var installedCount: Int

    var id: String { subagent.id }
}

nonisolated struct MeetingInstalledSkillSubagentGroup: Equatable, Identifiable, Sendable {
    var subagent: MeetingSkillSubagent
    var skills: [MeetingSkillInstall]

    var id: String { subagent.id }
}

nonisolated struct MeetingSkillInstall: Codable, Equatable, Identifiable, Sendable {
    var id: String
    var catalogEntryID: String
    var displayName: String
    var repoURL: String
    var repoFullName: String
    var installedAt: Date
    var skillRelativePath: String
    var readmeRelativePath: String?
    var localSnapshotDirectory: String
    var defaultBranch: String
    var sourceIndexURL: String
    var description: String
    var skillMarkdown: String
    var subagentID: String
    var subagentName: String
    var sourceKind: MeetingSkillSourceKind
    var isEditable: Bool

    init(
        id: String,
        catalogEntryID: String,
        displayName: String,
        repoURL: String,
        repoFullName: String,
        installedAt: Date = Date(),
        skillRelativePath: String,
        readmeRelativePath: String? = nil,
        localSnapshotDirectory: String,
        defaultBranch: String,
        sourceIndexURL: String,
        description: String,
        skillMarkdown: String,
        subagentID: String = MeetingSkillCatalogEntry.defaultCatalogSubagentID,
        subagentName: String = MeetingSkillCatalogEntry.defaultCatalogSubagentName,
        sourceKind: MeetingSkillSourceKind = .catalog,
        isEditable: Bool = false
    ) {
        self.id = id
        self.catalogEntryID = catalogEntryID
        self.displayName = displayName
        self.repoURL = repoURL
        self.repoFullName = repoFullName
        self.installedAt = installedAt
        self.skillRelativePath = skillRelativePath
        self.readmeRelativePath = readmeRelativePath
        self.localSnapshotDirectory = localSnapshotDirectory
        self.defaultBranch = defaultBranch
        self.sourceIndexURL = sourceIndexURL
        self.description = description
        self.skillMarkdown = skillMarkdown
        self.subagentID = subagentID
        self.subagentName = subagentName
        self.sourceKind = sourceKind
        self.isEditable = isEditable
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case catalogEntryID
        case displayName
        case repoURL
        case repoFullName
        case installedAt
        case skillRelativePath
        case readmeRelativePath
        case localSnapshotDirectory
        case defaultBranch
        case sourceIndexURL
        case description
        case skillMarkdown
        case subagentID
        case subagentName
        case sourceKind
        case isEditable
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let decodedSourceKind = try container.decodeIfPresent(MeetingSkillSourceKind.self, forKey: .sourceKind) ?? .catalog

        id = try container.decode(String.self, forKey: .id)
        catalogEntryID = try container.decode(String.self, forKey: .catalogEntryID)
        displayName = try container.decode(String.self, forKey: .displayName)
        repoURL = try container.decode(String.self, forKey: .repoURL)
        repoFullName = try container.decode(String.self, forKey: .repoFullName)
        installedAt = try container.decode(Date.self, forKey: .installedAt)
        skillRelativePath = try container.decode(String.self, forKey: .skillRelativePath)
        readmeRelativePath = try container.decodeIfPresent(String.self, forKey: .readmeRelativePath)
        localSnapshotDirectory = try container.decode(String.self, forKey: .localSnapshotDirectory)
        defaultBranch = try container.decode(String.self, forKey: .defaultBranch)
        sourceIndexURL = try container.decode(String.self, forKey: .sourceIndexURL)
        description = try container.decode(String.self, forKey: .description)
        skillMarkdown = try container.decode(String.self, forKey: .skillMarkdown)
        sourceKind = decodedSourceKind
        subagentName = try container.decodeIfPresent(String.self, forKey: .subagentName)
            ?? (decodedSourceKind == .user ? MeetingSkillIdentity.defaultUserSubagentName : MeetingSkillCatalogEntry.defaultCatalogSubagentName)
        subagentID = try container.decodeIfPresent(String.self, forKey: .subagentID)
            ?? (decodedSourceKind == .user ? MeetingSkillIdentity.defaultUserSubagentID : MeetingSkillCatalogEntry.defaultCatalogSubagentID)
        isEditable = try container.decodeIfPresent(Bool.self, forKey: .isEditable) ?? (decodedSourceKind == .user)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(catalogEntryID, forKey: .catalogEntryID)
        try container.encode(displayName, forKey: .displayName)
        try container.encode(repoURL, forKey: .repoURL)
        try container.encode(repoFullName, forKey: .repoFullName)
        try container.encode(installedAt, forKey: .installedAt)
        try container.encode(skillRelativePath, forKey: .skillRelativePath)
        try container.encodeIfPresent(readmeRelativePath, forKey: .readmeRelativePath)
        try container.encode(localSnapshotDirectory, forKey: .localSnapshotDirectory)
        try container.encode(defaultBranch, forKey: .defaultBranch)
        try container.encode(sourceIndexURL, forKey: .sourceIndexURL)
        try container.encode(description, forKey: .description)
        try container.encode(skillMarkdown, forKey: .skillMarkdown)
        try container.encode(subagentID, forKey: .subagentID)
        try container.encode(subagentName, forKey: .subagentName)
        try container.encode(sourceKind, forKey: .sourceKind)
        try container.encode(isEditable, forKey: .isEditable)
    }
}

nonisolated enum MeetingSkillIdentity {
    static let defaultUserSubagentID = "user:unassigned"
    static let defaultUserSubagentName = "我的 Subagent"

    static func slug(from rawValue: String) -> String {
        let lowercase = rawValue.lowercased()
        let pieces = lowercase.components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
        return pieces.joined(separator: "-")
    }

    static func normalizedLookupName(_ rawValue: String) -> String {
        slug(from: rawValue)
    }
}

nonisolated struct MeetingSkillCatalogSyncResult: Equatable, Sendable {
    var catalogEntries: [MeetingSkillCatalogEntry]
    var installedSkills: [MeetingSkillInstall]
    var newlyInstalledRepoFullNames: [String]
    var unsupportedRepoFullNames: [String]
    var failedRepoErrors: [String: String]

    var installableCatalogCount: Int {
        catalogEntries.filter(\.isInstallable).count
    }
}

struct MeetingTriggerRule: Codable, Equatable, Identifiable, Sendable {
    var id: String
    var name: String
    var description: String
    var logic: String
    var cooldownSeconds: TimeInterval

    init(id: String, name: String, description: String, logic: String, cooldownSeconds: TimeInterval = 90) {
        self.id = id
        self.name = name
        self.description = description
        self.logic = logic
        self.cooldownSeconds = cooldownSeconds
    }
}

struct MeetingAgentModelConfig: Codable, Equatable, Sendable {
    var baseURL: String
    var apiKey: String
    var model: String
    var temperature: Double
    var systemPrompt: String

    var isConfigured: Bool {
        !baseURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !model.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}

struct MeetingObjectStorageConfig: Codable, Equatable, Sendable {
    var stsURL: String
    var stsBearerToken: String
    var accessKeyID: String
    var secretAccessKey: String
    var sessionToken: String
    var bucket: String
    var region: String
    var endpoint: String
    var keyPrefix: String

    init(
        stsURL: String = "",
        stsBearerToken: String = "",
        accessKeyID: String = "",
        secretAccessKey: String = "",
        sessionToken: String = "",
        bucket: String = "",
        region: String = "",
        endpoint: String = "",
        keyPrefix: String = ""
    ) {
        self.stsURL = stsURL
        self.stsBearerToken = stsBearerToken
        self.accessKeyID = accessKeyID
        self.secretAccessKey = secretAccessKey
        self.sessionToken = sessionToken
        self.bucket = bucket
        self.region = region
        self.endpoint = endpoint
        self.keyPrefix = keyPrefix
    }

    var usesDirectCredentials: Bool {
        !accessKeyID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !secretAccessKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !bucket.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !region.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !endpoint.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var isConfigured: Bool {
        usesDirectCredentials || !stsURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}

struct DoubaoStreamingConfig: Codable, Equatable, Sendable {
    var endpoint: String
    var appID: String
    var accessToken: String
    var resourceID: String
    var userID: String
    var language: String?

    var isConfigured: Bool {
        !endpoint.isEmpty && !appID.isEmpty && !accessToken.isEmpty && !resourceID.isEmpty
    }
}

struct DoubaoMemoConfig: Codable, Equatable, Sendable {
    var submitURL: String
    var queryURL: String
    var appID: String
    var accessToken: String
    var resourceID: String

    var isConfigured: Bool {
        !submitURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !queryURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !appID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !accessToken.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}

enum MeetingThinkingReason: Sendable {
    case manual
    case silence
    case meetingStart
    case rule(MeetingTriggerRule)

    var triggerRuleID: String {
        switch self {
        case .manual:
            return "manual_think"
        case .silence:
            return "silence_prompt"
        case .meetingStart:
            return "meeting_start"
        case .rule(let rule):
            return rule.id
        }
    }

    var displayName: String {
        switch self {
        case .manual:
            return "手动思考"
        case .silence:
            return "冷场提示"
        case .meetingStart:
            return "会议开始"
        case .rule(let rule):
            return rule.name
        }
    }

    var description: String {
        switch self {
        case .manual:
            return "用户主动请求会议助手从多个视角补充批判性建议。"
        case .silence:
            return "会议进入冷场，会议助手应给出提示板式建议。"
        case .meetingStart:
            return "会议刚开始，会议助手基于主题和技能包给出初始引导建议。"
        case .rule(let rule):
            return rule.description
        }
    }
}

struct MeetingRecord: Codable, Equatable, Identifiable, Sendable {
    static let untitledTopicPlaceholder = "未命名会议"

    var id: String
    var topic: String
    var isTopicUserProvided: Bool
    var state: MeetingProcessingState
    var createdAt: Date
    var endedAt: Date?
    var audioRelativePath: String?
    var sourceMediaRelativePath: String?
    var sourceMediaKind: MeetingImportedMediaKind?
    var sourceMediaDisplayName: String?
    var markdownRelativePath: String?
    var uploadedAudioObjectKey: String?
    var uploadedAudioRemoteURL: String?
    var scheduledAt: Date?
    var durationMinutes: Int
    var calendarEventIdentifier: String?
    var calendarSyncState: MeetingCalendarSyncState
    var calendarSyncEnabled: Bool
    var transcript: [TranscriptSegment]
    var speakerSpans: [SpeakerSpan]
    var annotations: [MeetingAnnotation]
    var summaryBundle: MeetingSummaryBundle?
    var adviceCards: [MeetingAdviceCard]
    var postMeetingAdviceCards: [MeetingAdviceCard]
    var selectedSkillIDs: [String]
    var autoRecommendedSkillIDs: [String]
    var lastError: String?
    var notes: [String]

    init(
        id: String = UUID().uuidString,
        topic: String,
        isTopicUserProvided: Bool? = nil,
        state: MeetingProcessingState = .draft,
        createdAt: Date = Date(),
        endedAt: Date? = nil,
        audioRelativePath: String? = nil,
        sourceMediaRelativePath: String? = nil,
        sourceMediaKind: MeetingImportedMediaKind? = nil,
        sourceMediaDisplayName: String? = nil,
        markdownRelativePath: String? = nil,
        uploadedAudioObjectKey: String? = nil,
        uploadedAudioRemoteURL: String? = nil,
        scheduledAt: Date? = nil,
        durationMinutes: Int = 60,
        calendarEventIdentifier: String? = nil,
        calendarSyncState: MeetingCalendarSyncState = .disabled,
        calendarSyncEnabled: Bool = false,
        transcript: [TranscriptSegment] = [],
        speakerSpans: [SpeakerSpan] = [],
        annotations: [MeetingAnnotation] = [],
        summaryBundle: MeetingSummaryBundle? = nil,
        adviceCards: [MeetingAdviceCard] = [],
        postMeetingAdviceCards: [MeetingAdviceCard] = [],
        selectedSkillIDs: [String] = [],
        autoRecommendedSkillIDs: [String] = [],
        lastError: String? = nil,
        notes: [String] = []
    ) {
        self.id = id
        self.topic = topic
        self.isTopicUserProvided = isTopicUserProvided ?? !Self.isUntitledPlaceholder(topic)
        self.state = state
        self.createdAt = createdAt
        self.endedAt = endedAt
        self.audioRelativePath = audioRelativePath
        self.sourceMediaRelativePath = sourceMediaRelativePath
        self.sourceMediaKind = sourceMediaKind
        self.sourceMediaDisplayName = sourceMediaDisplayName
        self.markdownRelativePath = markdownRelativePath
        self.uploadedAudioObjectKey = uploadedAudioObjectKey
        self.uploadedAudioRemoteURL = uploadedAudioRemoteURL
        self.scheduledAt = scheduledAt
        self.durationMinutes = max(durationMinutes, 1)
        self.calendarEventIdentifier = calendarEventIdentifier
        self.calendarSyncState = calendarSyncState
        self.calendarSyncEnabled = calendarSyncEnabled
        self.transcript = transcript
        self.speakerSpans = speakerSpans
        self.annotations = annotations
        self.summaryBundle = summaryBundle
        self.adviceCards = adviceCards
        self.postMeetingAdviceCards = postMeetingAdviceCards
        self.selectedSkillIDs = selectedSkillIDs
        self.autoRecommendedSkillIDs = autoRecommendedSkillIDs
        self.lastError = lastError
        self.notes = notes
    }

    var isActive: Bool {
        state == .recording
    }

    var effectiveSkillIDs: [String] {
        selectedSkillIDs.isEmpty ? autoRecommendedSkillIDs : selectedSkillIDs
    }

    var focusAnnotations: [MeetingAnnotation] {
        annotations.filter { $0.kind == .focus }
    }

    var noteAnnotations: [MeetingAnnotation] {
        annotations.filter { $0.kind == .note }
    }

    static func isUntitledPlaceholder(_ topic: String) -> Bool {
        topic.trimmingCharacters(in: .whitespacesAndNewlines) == untitledTopicPlaceholder
    }
}

extension MeetingRecord {
    private enum CodingKeys: String, CodingKey {
        case id
        case topic
        case isTopicUserProvided
        case state
        case createdAt
        case endedAt
        case audioRelativePath
        case sourceMediaRelativePath
        case sourceMediaKind
        case sourceMediaDisplayName
        case markdownRelativePath
        case uploadedAudioObjectKey
        case uploadedAudioRemoteURL
        case scheduledAt
        case durationMinutes
        case calendarEventIdentifier
        case calendarSyncState
        case calendarSyncEnabled
        case transcript
        case speakerSpans
        case annotations
        case summaryBundle
        case adviceCards
        case postMeetingAdviceCards
        case selectedSkillIDs
        case autoRecommendedSkillIDs
        case lastError
        case notes
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(String.self, forKey: .id) ?? UUID().uuidString
        topic = try container.decodeIfPresent(String.self, forKey: .topic) ?? Self.untitledTopicPlaceholder
        isTopicUserProvided = try container.decodeIfPresent(Bool.self, forKey: .isTopicUserProvided)
            ?? !Self.isUntitledPlaceholder(topic)
        state = try container.decodeIfPresent(MeetingProcessingState.self, forKey: .state) ?? .draft
        createdAt = try container.decodeIfPresent(Date.self, forKey: .createdAt) ?? Date()
        endedAt = try container.decodeIfPresent(Date.self, forKey: .endedAt)
        audioRelativePath = try container.decodeIfPresent(String.self, forKey: .audioRelativePath)
        sourceMediaRelativePath = try container.decodeIfPresent(String.self, forKey: .sourceMediaRelativePath)
        sourceMediaKind = try container.decodeIfPresent(MeetingImportedMediaKind.self, forKey: .sourceMediaKind)
        sourceMediaDisplayName = try container.decodeIfPresent(String.self, forKey: .sourceMediaDisplayName)
        markdownRelativePath = try container.decodeIfPresent(String.self, forKey: .markdownRelativePath)
        uploadedAudioObjectKey = try container.decodeIfPresent(String.self, forKey: .uploadedAudioObjectKey)
        uploadedAudioRemoteURL = try container.decodeIfPresent(String.self, forKey: .uploadedAudioRemoteURL)
        scheduledAt = try container.decodeIfPresent(Date.self, forKey: .scheduledAt)
        durationMinutes = max(try container.decodeIfPresent(Int.self, forKey: .durationMinutes) ?? 60, 1)
        calendarEventIdentifier = try container.decodeIfPresent(String.self, forKey: .calendarEventIdentifier)
        calendarSyncState = try container.decodeIfPresent(MeetingCalendarSyncState.self, forKey: .calendarSyncState) ?? .disabled
        calendarSyncEnabled = try container.decodeIfPresent(Bool.self, forKey: .calendarSyncEnabled) ?? false
        transcript = try container.decodeIfPresent([TranscriptSegment].self, forKey: .transcript) ?? []
        speakerSpans = try container.decodeIfPresent([SpeakerSpan].self, forKey: .speakerSpans) ?? []
        annotations = try container.decodeIfPresent([MeetingAnnotation].self, forKey: .annotations) ?? []
        summaryBundle = try container.decodeIfPresent(MeetingSummaryBundle.self, forKey: .summaryBundle)
        adviceCards = try container.decodeIfPresent([MeetingAdviceCard].self, forKey: .adviceCards) ?? []
        postMeetingAdviceCards = try container.decodeIfPresent([MeetingAdviceCard].self, forKey: .postMeetingAdviceCards) ?? []
        selectedSkillIDs = try container.decodeIfPresent([String].self, forKey: .selectedSkillIDs) ?? []
        autoRecommendedSkillIDs = try container.decodeIfPresent([String].self, forKey: .autoRecommendedSkillIDs) ?? []
        lastError = try container.decodeIfPresent(String.self, forKey: .lastError)
        notes = try container.decodeIfPresent([String].self, forKey: .notes) ?? []
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(topic, forKey: .topic)
        try container.encode(isTopicUserProvided, forKey: .isTopicUserProvided)
        try container.encode(state, forKey: .state)
        try container.encode(createdAt, forKey: .createdAt)
        try container.encodeIfPresent(endedAt, forKey: .endedAt)
        try container.encodeIfPresent(audioRelativePath, forKey: .audioRelativePath)
        try container.encodeIfPresent(sourceMediaRelativePath, forKey: .sourceMediaRelativePath)
        try container.encodeIfPresent(sourceMediaKind, forKey: .sourceMediaKind)
        try container.encodeIfPresent(sourceMediaDisplayName, forKey: .sourceMediaDisplayName)
        try container.encodeIfPresent(markdownRelativePath, forKey: .markdownRelativePath)
        try container.encodeIfPresent(uploadedAudioObjectKey, forKey: .uploadedAudioObjectKey)
        try container.encodeIfPresent(uploadedAudioRemoteURL, forKey: .uploadedAudioRemoteURL)
        try container.encodeIfPresent(scheduledAt, forKey: .scheduledAt)
        try container.encode(durationMinutes, forKey: .durationMinutes)
        try container.encodeIfPresent(calendarEventIdentifier, forKey: .calendarEventIdentifier)
        try container.encode(calendarSyncState, forKey: .calendarSyncState)
        try container.encode(calendarSyncEnabled, forKey: .calendarSyncEnabled)
        try container.encode(transcript, forKey: .transcript)
        try container.encode(speakerSpans, forKey: .speakerSpans)
        try container.encode(annotations, forKey: .annotations)
        try container.encodeIfPresent(summaryBundle, forKey: .summaryBundle)
        try container.encode(adviceCards, forKey: .adviceCards)
        try container.encode(postMeetingAdviceCards, forKey: .postMeetingAdviceCards)
        try container.encode(selectedSkillIDs, forKey: .selectedSkillIDs)
        try container.encode(autoRecommendedSkillIDs, forKey: .autoRecommendedSkillIDs)
        try container.encodeIfPresent(lastError, forKey: .lastError)
        try container.encode(notes, forKey: .notes)
    }
}

extension MeetingTriggerRule {
    static let defaultRules: [MeetingTriggerRule] = [
        MeetingTriggerRule(
            id: "repeated_unresolved_debate",
            name: "重复争论",
            description: "话题反复拉扯但没有结论。",
            logic: #"{"and":[{">=":[{"var":"repeatedTailCount"},2]},{"==":[{"var":"decisionMentionCount"},0]}]}"#
        ),
        MeetingTriggerRule(
            id: "missing_owner",
            name: "缺少Owner",
            description: "已经讨论到行动项，但没有明确负责人。",
            logic: #"{"and":[{">=":[{"var":"actionCueCount"},1]},{"==":[{"var":"ownerMentionCount"},0]}]}"#
        ),
        MeetingTriggerRule(
            id: "unclear_problem_statement",
            name: "问题没定义清楚",
            description: "提问很多，但目标和问题定义仍模糊。",
            logic: #"{"and":[{">=":[{"var":"questionCueCount"},2]},{"<":[{"var":"problemDefinitionCount"},1]}]}"#
        ),
        MeetingTriggerRule(
            id: "lack_of_convergence",
            name: "没有收敛",
            description: "说了很多，但缺少收敛和定论信号。",
            logic: #"{"and":[{">=":[{"var":"recentSegmentCount"},8]},{"==":[{"var":"decisionMentionCount"},0]},{"<":[{"var":"ownerMentionCount"},1]}]}"#
        )
    ]
}
