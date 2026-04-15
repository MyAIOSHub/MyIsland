import SwiftUI

struct MeetingDetailView: View {
    @ObservedObject var viewModel: NotchViewModel
    @ObservedObject private var coordinator = MeetingCoordinator.shared
    @ObservedObject private var settings = MeetingSettingsStore.shared
    let record: MeetingRecord

    private var resolvedRecord: MeetingRecord {
        if let activeMeeting = coordinator.activeMeeting, activeMeeting.id == record.id {
            return activeMeeting
        }
        return coordinator.recentMeetings.first(where: { $0.id == record.id }) ?? record
    }

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: DesignTokens.Spacing.md) {
                header
                summarySection
                decisionsSection
                focusSection
                noteSection
                actionSection
                postMeetingAdviceSection
                qaSection
                speakerViewpointsSection
                speakerSection
                transcriptSection
            }
            .padding(DesignTokens.Spacing.md)
        }
        .background(Color.black)
    }

    private var header: some View {
        HStack(spacing: DesignTokens.Spacing.sm) {
            Button {
                withAnimation(.easeInOut(duration: 0.25)) {
                    viewModel.contentType = .meetingHub
                }
            } label: {
                Image(systemName: "chevron.left")
                    .foregroundColor(.white.opacity(0.72))
            }
            .buttonStyle(.plain)

            VStack(alignment: .leading, spacing: 2) {
                Text(resolvedRecord.topic)
                    .font(DesignTokens.Font.title())
                    .foregroundColor(DesignTokens.Text.primary)
                Text(resolvedRecord.state == .completed ? "会后详情" : "处理中")
                    .font(DesignTokens.Font.caption())
                    .foregroundColor(DesignTokens.Text.tertiary)
            }

            Spacer()

            Button {
                AppDelegate.shared?.showMeetingArchive(meetingID: resolvedRecord.id)
            } label: {
                Text("全局查看")
                    .font(DesignTokens.Font.label())
                    .foregroundColor(.white)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Capsule().fill(DesignTokens.Surface.elevated))
            }
            .buttonStyle(.plain)

            Button {
                Task {
                    await coordinator.retryPostAnalysis(meetingID: record.id)
                }
            } label: {
                Text("重跑总结")
                    .font(DesignTokens.Font.label())
                    .foregroundColor(.white)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Capsule().fill(TerminalColors.blue))
            }
            .buttonStyle(.plain)
        }
    }

    private var summarySection: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.sm) {
            Text("会议总结")
                .font(DesignTokens.Font.heading())
                .foregroundColor(DesignTokens.Text.primary)

            if let summary = resolvedRecord.summaryBundle?.fullSummary, !summary.isEmpty {
                MarkdownText(summary, color: DesignTokens.Text.secondary, fontSize: 12)
            } else {
                Text("暂无总结")
                    .font(DesignTokens.Font.body())
                    .foregroundColor(DesignTokens.Text.tertiary)
            }

            if let chapters = resolvedRecord.summaryBundle?.chapterSummaries, !chapters.isEmpty {
                ForEach(chapters) { chapter in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(chapter.title)
                            .font(DesignTokens.Font.label())
                            .foregroundColor(DesignTokens.Text.primary)
                        Text(chapter.summary)
                            .font(DesignTokens.Font.body())
                            .foregroundColor(DesignTokens.Text.secondary)
                    }
                }
            }

            if let processHighlights = resolvedRecord.summaryBundle?.processHighlights, !processHighlights.isEmpty {
                Divider().background(DesignTokens.Border.subtle)
                Text("流程提取")
                    .font(DesignTokens.Font.label())
                    .foregroundColor(DesignTokens.Text.primary)
                ForEach(Array(processHighlights.enumerated()), id: \.offset) { _, highlight in
                    Text("• \(highlight)")
                        .font(DesignTokens.Font.body())
                        .foregroundColor(DesignTokens.Text.secondary)
                }
            }
        }
        .padding(DesignTokens.Spacing.md)
        .background(
            RoundedRectangle(cornerRadius: DesignTokens.Radius.xl)
                .fill(DesignTokens.Surface.base)
        )
    }

    /// Decisions extracted by the LLM augmentation pass. Hidden entirely
    /// when none — Memo never produces decisions, and an empty card just
    /// adds visual noise when the user hasn't configured a model.
    @ViewBuilder
    private var decisionsSection: some View {
        if let decisions = resolvedRecord.summaryBundle?.decisions, !decisions.isEmpty {
            VStack(alignment: .leading, spacing: DesignTokens.Spacing.sm) {
                Text("决策")
                    .font(DesignTokens.Font.heading())
                    .foregroundColor(DesignTokens.Text.primary)

                ForEach(decisions) { decision in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(decision.statement)
                            .font(DesignTokens.Font.label())
                            .foregroundColor(DesignTokens.Text.primary)
                        if let rationale = decision.rationale, !rationale.isEmpty {
                            Text(rationale)
                                .font(DesignTokens.Font.body())
                                .foregroundColor(DesignTokens.Text.secondary)
                        }
                        let meta = [
                            decision.decidedBy,
                            decision.timecodeMs.map { MeetingLiveTimeline.timecode(milliseconds: $0) }
                        ].compactMap { $0 }.joined(separator: " · ")
                        if !meta.isEmpty {
                            Text(meta)
                                .font(DesignTokens.Font.caption())
                                .foregroundColor(DesignTokens.Text.tertiary)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 4)
                }
            }
            .padding(DesignTokens.Spacing.md)
            .background(
                RoundedRectangle(cornerRadius: DesignTokens.Radius.xl)
                    .fill(DesignTokens.Surface.base)
            )
        }
    }

    /// Per-speaker viewpoint summaries from the LLM augmentation pass.
    /// Hidden when the LLM did not produce any (e.g. agent unconfigured,
    /// or every speaker just exchanged greetings).
    @ViewBuilder
    private var speakerViewpointsSection: some View {
        if let viewpoints = resolvedRecord.summaryBundle?.speakerViewpoints, !viewpoints.isEmpty {
            VStack(alignment: .leading, spacing: DesignTokens.Spacing.sm) {
                Text("各说话人观点")
                    .font(DesignTokens.Font.heading())
                    .foregroundColor(DesignTokens.Text.primary)

                ForEach(viewpoints) { viewpoint in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(viewpoint.speakerLabel)
                            .font(DesignTokens.Font.label())
                            .foregroundColor(DesignTokens.Text.primary)
                        if let stance = viewpoint.stance, !stance.isEmpty {
                            Text(stance)
                                .font(DesignTokens.Font.body())
                                .foregroundColor(DesignTokens.Text.secondary)
                        }
                        ForEach(Array(viewpoint.points.enumerated()), id: \.offset) { _, point in
                            Text("• \(point)")
                                .font(DesignTokens.Font.body())
                                .foregroundColor(DesignTokens.Text.secondary)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 4)
                }
            }
            .padding(DesignTokens.Spacing.md)
            .background(
                RoundedRectangle(cornerRadius: DesignTokens.Radius.xl)
                    .fill(DesignTokens.Surface.base)
            )
        }
    }

    private var actionSection: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.sm) {
            Text("待办与建议")
                .font(DesignTokens.Font.heading())
                .foregroundColor(DesignTokens.Text.primary)

            if let actionItems = resolvedRecord.summaryBundle?.actionItems, !actionItems.isEmpty {
                ForEach(actionItems) { item in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(item.task)
                            .font(DesignTokens.Font.label())
                            .foregroundColor(DesignTokens.Text.primary)
                        let meta = [item.owner, item.dueDate].compactMap { $0 }.joined(separator: " · ")
                        if !meta.isEmpty {
                            Text(meta)
                                .font(DesignTokens.Font.caption())
                                .foregroundColor(DesignTokens.Text.tertiary)
                        }
                    }
                }
            } else {
                Text("暂无结构化待办")
                    .font(DesignTokens.Font.body())
                    .foregroundColor(DesignTokens.Text.tertiary)
            }

            if !resolvedRecord.adviceCards.isEmpty {
                Divider().background(DesignTokens.Border.subtle)
                ForEach(resolvedRecord.adviceCards.prefix(6)) { card in
                    MeetingAdviceCardTile(
                        card: card,
                        maxVisibleViewpoints: settings.maxVisibleViewpoints,
                        backgroundColor: Color(red: 0.14, green: 0.15, blue: 0.19)
                    )
                }
            }
        }
        .padding(DesignTokens.Spacing.md)
        .background(
            RoundedRectangle(cornerRadius: DesignTokens.Radius.xl)
                .fill(DesignTokens.Surface.base)
        )
    }

    @ViewBuilder
    private var focusSection: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.sm) {
            Text("重点关注")
                .font(DesignTokens.Font.heading())
                .foregroundColor(DesignTokens.Text.primary)

            if resolvedRecord.focusAnnotations.isEmpty {
                Text("暂无重点关注")
                    .font(DesignTokens.Font.body())
                    .foregroundColor(DesignTokens.Text.tertiary)
            } else {
                ForEach(resolvedRecord.focusAnnotations.sorted { $0.timecodeMs < $1.timecodeMs }) { annotation in
                    annotationTile(annotation, accent: TerminalColors.amber, label: "重点", transcript: resolvedRecord.transcript)
                }
            }
        }
        .padding(DesignTokens.Spacing.md)
        .background(
            RoundedRectangle(cornerRadius: DesignTokens.Radius.xl)
                .fill(DesignTokens.Surface.base)
        )
    }

    @ViewBuilder
    private var noteSection: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.sm) {
            Text("会议笔记")
                .font(DesignTokens.Font.heading())
                .foregroundColor(DesignTokens.Text.primary)

            if resolvedRecord.noteAnnotations.isEmpty {
                Text("暂无会议笔记")
                    .font(DesignTokens.Font.body())
                    .foregroundColor(DesignTokens.Text.tertiary)
            } else {
                ForEach(resolvedRecord.noteAnnotations.sorted { $0.timecodeMs < $1.timecodeMs }) { annotation in
                    annotationTile(annotation, accent: TerminalColors.green, label: "笔记", transcript: resolvedRecord.transcript)
                }
            }
        }
        .padding(DesignTokens.Spacing.md)
        .background(
            RoundedRectangle(cornerRadius: DesignTokens.Radius.xl)
                .fill(DesignTokens.Surface.base)
        )
    }

    @ViewBuilder
    private var postMeetingAdviceSection: some View {
        if !resolvedRecord.postMeetingAdviceCards.isEmpty {
            VStack(alignment: .leading, spacing: DesignTokens.Spacing.sm) {
                Text("会后讨论建议")
                    .font(DesignTokens.Font.heading())
                    .foregroundColor(DesignTokens.Text.primary)

                ForEach(resolvedRecord.postMeetingAdviceCards.prefix(3)) { card in
                    MeetingAdviceCardTile(
                        card: card,
                        maxVisibleViewpoints: settings.maxVisibleViewpoints,
                        backgroundColor: Color(red: 0.14, green: 0.15, blue: 0.19)
                    )
                }
            }
            .padding(DesignTokens.Spacing.md)
            .background(
                RoundedRectangle(cornerRadius: DesignTokens.Radius.xl)
                    .fill(DesignTokens.Surface.base)
            )
        }
    }

    @ViewBuilder
    private var qaSection: some View {
        if let qaPairs = resolvedRecord.summaryBundle?.qaPairs, !qaPairs.isEmpty {
            VStack(alignment: .leading, spacing: DesignTokens.Spacing.sm) {
                Text("问答提取")
                    .font(DesignTokens.Font.heading())
                    .foregroundColor(DesignTokens.Text.primary)

                ForEach(qaPairs) { pair in
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Q: \(pair.question)")
                            .font(DesignTokens.Font.label())
                            .foregroundColor(DesignTokens.Text.primary)
                        Text("A: \(pair.answer)")
                            .font(DesignTokens.Font.body())
                            .foregroundColor(DesignTokens.Text.secondary)
                    }
                }
            }
            .padding(DesignTokens.Spacing.md)
            .background(
                RoundedRectangle(cornerRadius: DesignTokens.Radius.xl)
                    .fill(DesignTokens.Surface.base)
            )
        }
    }

    @ViewBuilder
    private var speakerSection: some View {
        if !resolvedRecord.speakerSpans.isEmpty {
            VStack(alignment: .leading, spacing: DesignTokens.Spacing.sm) {
                Text("说话人日志")
                    .font(DesignTokens.Font.heading())
                    .foregroundColor(DesignTokens.Text.primary)

                ForEach(resolvedRecord.speakerSpans) { span in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(span.displaySpeakerBadge(in: resolvedRecord.transcript, speakerSpans: resolvedRecord.speakerSpans))
                            .font(DesignTokens.Font.label())
                            .foregroundColor(TerminalColors.blue)
                        Text("\(timestamp(span.startTimeMs)) - \(timestamp(span.endTimeMs))")
                            .font(DesignTokens.Font.caption())
                            .foregroundColor(DesignTokens.Text.tertiary)
                    }
                }
            }
            .padding(DesignTokens.Spacing.md)
            .background(
                RoundedRectangle(cornerRadius: DesignTokens.Radius.xl)
                    .fill(DesignTokens.Surface.base)
            )
        }
    }

    private var transcriptSection: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.sm) {
            Text("完整转写")
                .font(DesignTokens.Font.heading())
                .foregroundColor(DesignTokens.Text.primary)

            ForEach(resolvedRecord.transcript) { segment in
                VStack(alignment: .leading, spacing: 2) {
                    Text(segment.displaySpeakerBadge(in: resolvedRecord.transcript, speakerSpans: resolvedRecord.speakerSpans))
                        .font(DesignTokens.Font.caption())
                        .foregroundColor(TerminalColors.blue)
                    Text(segment.text)
                        .font(DesignTokens.Font.body())
                        .foregroundColor(DesignTokens.Text.secondary)
                }
                .padding(.vertical, 4)
            }
        }
        .padding(DesignTokens.Spacing.md)
        .background(
            RoundedRectangle(cornerRadius: DesignTokens.Radius.xl)
                .fill(DesignTokens.Surface.base)
        )
    }

    private func timestamp(_ milliseconds: Int) -> String {
        let totalSeconds = max(0, milliseconds / 1000)
        let minutes = totalSeconds / 60
        let seconds = totalSeconds % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }

    private func annotationTile(
        _ annotation: MeetingAnnotation,
        accent: Color,
        label: String,
        transcript: [TranscriptSegment]
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: DesignTokens.Spacing.xs) {
                Text(label)
                    .font(DesignTokens.Font.caption())
                    .foregroundColor(accent)
                Text(timestamp(annotation.timecodeMs))
                    .font(DesignTokens.Font.mono(10))
                    .foregroundColor(DesignTokens.Text.tertiary)
            }

            if !annotation.effectiveText.isEmpty {
                Text(annotation.effectiveText)
                    .font(DesignTokens.Font.body())
                    .foregroundColor(DesignTokens.Text.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if let quoteContext = annotation.quoteContext(in: transcript) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("\(quoteContext.timecode) · \(quoteContext.speakerLabel)")
                        .font(DesignTokens.Font.caption())
                        .foregroundColor(DesignTokens.Text.tertiary)
                    Text(quoteContext.text)
                        .font(DesignTokens.Font.caption())
                        .foregroundColor(DesignTokens.Text.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
                .background(
                    RoundedRectangle(cornerRadius: DesignTokens.Radius.md)
                        .fill(DesignTokens.Surface.base)
                )
            }

            if !annotation.attachments.isEmpty {
                VStack(alignment: .leading, spacing: DesignTokens.Spacing.xs) {
                    ForEach(annotation.attachments) { attachment in
                        VStack(alignment: .leading, spacing: 4) {
                            HStack(spacing: 6) {
                                Text(attachment.kind.displayName)
                                    .font(DesignTokens.Font.caption())
                                    .foregroundColor(accent)
                                Text(attachment.displayName)
                                    .font(DesignTokens.Font.caption())
                                    .foregroundColor(DesignTokens.Text.tertiary)
                            }

                            let preview = attachment.extractedMarkdown.trimmingCharacters(in: .whitespacesAndNewlines)
                            if !preview.isEmpty {
                                MarkdownText(
                                    String(preview.prefix(240)),
                                    color: DesignTokens.Text.secondary,
                                    fontSize: 11
                                )
                            }
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 6)
                        .background(
                            RoundedRectangle(cornerRadius: DesignTokens.Radius.md)
                                .fill(DesignTokens.Surface.base)
                        )
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(DesignTokens.Spacing.sm)
        .background(
            RoundedRectangle(cornerRadius: DesignTokens.Radius.lg)
                .fill(DesignTokens.Surface.elevated)
                .overlay(
                    RoundedRectangle(cornerRadius: DesignTokens.Radius.lg)
                        .strokeBorder(accent.opacity(0.35), lineWidth: 1)
                )
        )
    }
}
