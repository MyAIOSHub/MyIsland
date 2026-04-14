import SwiftUI

struct MeetingAdviceCompactViewpoint: Equatable, Identifiable, Sendable {
    let id: String
    let stance: String
    let subagentName: String
    let sentence: String
}

enum MeetingAdviceCardPresentation {
    static func metaBadgeTexts(for card: MeetingAdviceCard, timestampLabel: String?) -> [String] {
        var texts: [String] = []

        if let timestampLabel, !timestampLabel.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            texts.append(timestampLabel)
        }

        if let theme = card.meetingTheme {
            texts.append(theme.displayName)
        }

        if let subtask = card.currentSubtask {
            texts.append(subtask.displayName)
        }

        if let room = card.agoraRoom {
            texts.append(room.displayName)
        }

        return texts
    }

    static func compactViewpoints(
        for card: MeetingAdviceCard,
        maxVisibleViewpoints: Int
    ) -> [MeetingAdviceCompactViewpoint] {
        card.viewpoints
            .prefix(max(1, maxVisibleViewpoints))
            .map { viewpoint in
                MeetingAdviceCompactViewpoint(
                    id: viewpoint.id,
                    stance: viewpoint.stance,
                    subagentName: viewpoint.subagentName.displayName,
                    sentence: compactSentence(for: viewpoint)
                )
            }
    }

    static func compactSentence(for viewpoint: SubagentViewpoint) -> String {
        leadingSentence(from: viewpoint.corePoint)
            ?? leadingSentence(from: viewpoint.followUpLine)
            ?? leadingSentence(from: viewpoint.challenge)
            ?? leadingSentence(from: viewpoint.evidenceNeeded)
            ?? "点击展开查看详情"
    }

    static func collapsedBodyText(for card: MeetingAdviceCard) -> String? {
        leadingSentence(from: card.coreJudgment)
            ?? leadingSentence(from: card.nextStep)
            ?? leadingSentence(from: card.blindSpot)
            ?? leadingSentence(from: card.body)
    }

    static func hasExpandableDetails(
        for card: MeetingAdviceCard,
        maxVisibleViewpoints: Int
    ) -> Bool {
        let _ = maxVisibleViewpoints

        if !card.viewpoints.isEmpty || card.supervisorSummary != nil {
            return true
        }

        if !legacyStructuredAdviceLines(for: card).isEmpty {
            return true
        }

        guard let collapsedText = collapsedBodyText(for: card) else {
            return false
        }

        let fullBody = normalizedText(card.body)
        return !fullBody.isEmpty && fullBody != collapsedText
    }

    static func legacyStructuredAdviceLines(for card: MeetingAdviceCard) -> [String] {
        var lines: [String] = []

        if let coreJudgment = normalizedOptionalText(card.coreJudgment) {
            lines.append("核心判断：\(coreJudgment)")
        }

        if let blindSpot = normalizedOptionalText(card.blindSpot) {
            lines.append("被忽略的问题：\(blindSpot)")
        }

        if let nextStep = normalizedOptionalText(card.nextStep) {
            lines.append("下一步建议：\(nextStep)")
        }

        return lines
    }

    private static func leadingSentence(from text: String?) -> String? {
        guard let text = normalizedOptionalText(text) else {
            return nil
        }

        for index in text.indices {
            let character = text[index]

            if character == "\n" {
                let sentence = String(text[..<index]).trimmingCharacters(in: .whitespacesAndNewlines)
                return sentence.isEmpty ? text : sentence
            }

            if "。！？!?；;".contains(character) {
                let sentence = String(text[...index]).trimmingCharacters(in: .whitespacesAndNewlines)
                return sentence.isEmpty ? text : sentence
            }
        }

        return text
    }

    private static func normalizedText(_ text: String?) -> String {
        text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }

    private static func normalizedOptionalText(_ text: String?) -> String? {
        let value = normalizedText(text)
        return value.isEmpty ? nil : value
    }
}

struct MeetingAdviceCardTile: View {
    let card: MeetingAdviceCard
    let maxVisibleViewpoints: Int
    let timestampLabel: String?
    var backgroundColor: Color = Color(red: 0.14, green: 0.15, blue: 0.19)

    @State private var isExpanded = false

    init(
        card: MeetingAdviceCard,
        maxVisibleViewpoints: Int,
        timestampLabel: String? = nil,
        backgroundColor: Color = Color(red: 0.14, green: 0.15, blue: 0.19)
    ) {
        self.card = card
        self.maxVisibleViewpoints = maxVisibleViewpoints
        self.timestampLabel = timestampLabel
        self.backgroundColor = backgroundColor
    }

    private var metaBadgeTexts: [String] {
        MeetingAdviceCardPresentation.metaBadgeTexts(
            for: card,
            timestampLabel: timestampLabel
        )
    }

    private var compactViewpoints: [MeetingAdviceCompactViewpoint] {
        MeetingAdviceCardPresentation.compactViewpoints(
            for: card,
            maxVisibleViewpoints: maxVisibleViewpoints
        )
    }

    private var collapsedBodyText: String? {
        MeetingAdviceCardPresentation.collapsedBodyText(for: card)
    }

    private var hasExpandableDetails: Bool {
        MeetingAdviceCardPresentation.hasExpandableDetails(
            for: card,
            maxVisibleViewpoints: maxVisibleViewpoints
        )
    }

    private var legacyStructuredAdviceLines: [String] {
        MeetingAdviceCardPresentation.legacyStructuredAdviceLines(for: card)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.sm) {
            header

            if isExpanded {
                expandedContent
            } else {
                collapsedContent
            }
        }
        .padding(DesignTokens.Spacing.sm)
        .background(
            RoundedRectangle(cornerRadius: DesignTokens.Radius.xl)
                .fill(backgroundColor)
        )
        .contentShape(RoundedRectangle(cornerRadius: DesignTokens.Radius.xl))
        .onTapGesture {
            guard hasExpandableDetails else { return }

            withAnimation(.easeInOut(duration: 0.2)) {
                isExpanded.toggle()
            }
        }
    }

    @ViewBuilder
    private var header: some View {
        HStack(alignment: .top, spacing: DesignTokens.Spacing.sm) {
            VStack(alignment: .leading, spacing: 4) {
                Text(card.title)
                    .font(DesignTokens.Font.label())
                    .foregroundColor(DesignTokens.Text.primary)

                if !metaBadgeTexts.isEmpty {
                    routeMeta
                }
            }

            Spacer(minLength: DesignTokens.Spacing.sm)

            if hasExpandableDetails {
                HStack(spacing: 4) {
                    Text(isExpanded ? "收起" : "展开")
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                }
                .font(DesignTokens.Font.caption())
                .foregroundColor(DesignTokens.Text.tertiary)
            }
        }
    }

    @ViewBuilder
    private var collapsedContent: some View {
        if !compactViewpoints.isEmpty {
            VStack(alignment: .leading, spacing: DesignTokens.Spacing.xs) {
                ForEach(compactViewpoints) { viewpoint in
                    compactViewpointTile(viewpoint)
                }
            }
        } else if let collapsedBodyText {
            Text(collapsedBodyText)
                .font(DesignTokens.Font.body())
                .foregroundColor(DesignTokens.Text.secondary)
                .lineLimit(3)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    @ViewBuilder
    private var expandedContent: some View {
        if !card.viewpoints.isEmpty {
            VStack(alignment: .leading, spacing: DesignTokens.Spacing.sm) {
                ForEach(card.viewpoints) { viewpoint in
                    viewpointTile(viewpoint)
                }
            }
        }

        if let summary = card.supervisorSummary {
            Divider().background(DesignTokens.Border.subtle)
            VStack(alignment: .leading, spacing: 4) {
                Text("Supervisor")
                    .font(DesignTokens.Font.caption())
                    .foregroundColor(TerminalColors.amber)
                Text("关键缺口：\(summary.keyGap)")
                    .font(DesignTokens.Font.body())
                    .foregroundColor(DesignTokens.Text.secondary)
                Text("被忽略的问题：\(summary.ignoredQuestion)")
                    .font(DesignTokens.Font.body())
                    .foregroundColor(DesignTokens.Text.secondary)
                Text("最值得追问：\(summary.bestFollowUpLine)")
                    .font(DesignTokens.Font.body())
                    .foregroundColor(DesignTokens.Text.primary)
                Text("下一步动作：\(summary.nextAction)")
                    .font(DesignTokens.Font.body())
                    .foregroundColor(DesignTokens.Text.secondary)
            }
        } else if !card.body.isEmpty {
            Text(card.body)
                .font(DesignTokens.Font.body())
                .foregroundColor(DesignTokens.Text.secondary)
        }

        if card.supervisorSummary == nil {
            legacyStructuredAdvice
        }
    }

    @ViewBuilder
    private var routeMeta: some View {
        HStack(spacing: DesignTokens.Spacing.xs) {
            ForEach(metaBadgeTexts, id: \.self) { text in
                metaChip(text)
            }
        }
    }

    @ViewBuilder
    private var legacyStructuredAdvice: some View {
        if !legacyStructuredAdviceLines.isEmpty {
            VStack(alignment: .leading, spacing: 2) {
                ForEach(legacyStructuredAdviceLines, id: \.self) { line in
                    Text(line)
                        .font(DesignTokens.Font.body())
                        .foregroundColor(DesignTokens.Text.secondary)
                }
            }
        }
    }

    private func compactViewpointTile(_ viewpoint: MeetingAdviceCompactViewpoint) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: DesignTokens.Spacing.xs) {
                Text(viewpoint.stance)
                    .font(DesignTokens.Font.label())
                    .foregroundColor(DesignTokens.Text.primary)
                Text(viewpoint.subagentName)
                    .font(DesignTokens.Font.caption())
                    .foregroundColor(TerminalColors.blue)
            }

            Text(viewpoint.sentence)
                .font(DesignTokens.Font.caption())
                .foregroundColor(DesignTokens.Text.secondary)
                .lineLimit(2)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, DesignTokens.Spacing.sm)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: DesignTokens.Radius.lg)
                .fill(DesignTokens.Surface.base)
        )
    }

    private func viewpointTile(_ viewpoint: SubagentViewpoint) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: DesignTokens.Spacing.xs) {
                Text(viewpoint.stance)
                    .font(DesignTokens.Font.label())
                    .foregroundColor(DesignTokens.Text.primary)
                Text(viewpoint.subagentName.displayName)
                    .font(DesignTokens.Font.caption())
                    .foregroundColor(TerminalColors.blue)
            }
            Text(viewpoint.corePoint)
                .font(DesignTokens.Font.body())
                .foregroundColor(DesignTokens.Text.secondary)
            Text("质疑：\(viewpoint.challenge)")
                .font(DesignTokens.Font.caption())
                .foregroundColor(DesignTokens.Text.secondary)
            Text("证据：\(viewpoint.evidenceNeeded)")
                .font(DesignTokens.Font.caption())
                .foregroundColor(DesignTokens.Text.tertiary)
            Text("追问：\(viewpoint.followUpLine)")
                .font(DesignTokens.Font.caption())
                .foregroundColor(DesignTokens.Text.primary)
            if !viewpoint.skillIDs.isEmpty {
                Text("skills: \(viewpoint.skillIDs.joined(separator: ", "))")
                    .font(DesignTokens.Font.caption())
                    .foregroundColor(DesignTokens.Text.tertiary)
                    .lineLimit(2)
            }
        }
        .padding(DesignTokens.Spacing.sm)
        .background(
            RoundedRectangle(cornerRadius: DesignTokens.Radius.lg)
                .fill(DesignTokens.Surface.base)
        )
    }

    private func metaChip(_ text: String) -> some View {
        Text(text)
            .font(DesignTokens.Font.caption())
            .foregroundColor(DesignTokens.Text.secondary)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(
                Capsule()
                    .fill(DesignTokens.Surface.base)
            )
    }
}
