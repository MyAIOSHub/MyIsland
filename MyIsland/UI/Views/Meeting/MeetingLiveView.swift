import SwiftUI
#if canImport(AppKit)
import AppKit
import UniformTypeIdentifiers
#endif

struct MeetingLiveView: View {
    @ObservedObject var viewModel: NotchViewModel
    @ObservedObject private var coordinator = MeetingCoordinator.shared
    @ObservedObject private var settings = MeetingSettingsStore.shared
    @State private var isStoppingMeeting = false
    @State private var noteDraft = ""
    @State private var pendingLinkedSegmentID: String?

    private let transcriptBottomID = "meeting-live-transcript-bottom"
    private let timelineBottomID = "meeting-live-timeline-bottom"

    var body: some View {
        if let meeting = coordinator.activeMeeting {
            VStack(alignment: .leading, spacing: DesignTokens.Spacing.md) {
                header(meeting: meeting)
                if let audioInputModeError = coordinator.audioInputModeError, !audioInputModeError.isEmpty {
                    audioInputModeErrorBanner(audioInputModeError)
                }
                liveColumnsSection(meeting: meeting)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            }
            .padding(DesignTokens.Spacing.md)
            .background(Color.black)
            .onChange(of: meeting.id) {
                pendingLinkedSegmentID = nil
                noteDraft = ""
            }
        } else {
            VStack(spacing: DesignTokens.Spacing.sm) {
                Text("没有进行中的会议")
                    .font(DesignTokens.Font.heading())
                    .foregroundColor(DesignTokens.Text.tertiary)
                Button("返回会议助手") {
                    withAnimation(.easeInOut(duration: 0.25)) {
                        viewModel.contentType = .meetingHub
                    }
                }
                .buttonStyle(.plain)
                .foregroundColor(.white)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.black)
        }
    }

    private func liveColumnsSection(meeting: MeetingRecord) -> some View {
        let transcriptItems = MeetingLiveTimeline.buildTranscriptItems(meeting: meeting)
        let timelineItems = MeetingLiveTimeline.buildSidebarItemsForLiveColumn(
            meeting: meeting,
            activeAdviceCards: coordinator.activeAdviceCards,
            persistedAdviceCards: meeting.adviceCards,
            isGeneratingThinking: coordinator.isGeneratingThinking
        )
        let transcriptScrollToken = "\(meeting.transcript.count)-\(meeting.transcript.last?.id ?? "")-\(meeting.transcript.last?.text ?? "")-\(meeting.focusAnnotations.count)"
        let timelineScrollToken = "\(timelineItems.count)-\(timelineItems.last?.id ?? "")-\(timelineItems.last?.timecode ?? "")-\(meeting.noteAnnotations.count)-\(meeting.adviceCards.count)"

        return GeometryReader { proxy in
            let columnWidth = MeetingLiveLayout.dualColumnWidth(
                containerWidth: proxy.size.width,
                spacing: DesignTokens.Spacing.md
            )

            HStack(alignment: .top, spacing: DesignTokens.Spacing.md) {
                transcriptColumn(meeting: meeting, items: transcriptItems, scrollToken: transcriptScrollToken)
                    .frame(width: columnWidth, alignment: .top)
                    .frame(maxHeight: .infinity, alignment: .top)

                timelineColumn(meeting: meeting, items: timelineItems, scrollToken: timelineScrollToken)
                    .frame(width: columnWidth, alignment: .top)
                    .frame(maxHeight: .infinity, alignment: .top)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    private func header(meeting: MeetingRecord) -> some View {
        let inlineRecordingStatusSummary = MeetingLiveLayout.inlineRecordingStatusSummary(
            realtimeStatusMessage: coordinator.realtimeASRMessage,
            audioInputMode: settings.audioInputMode,
            systemAudioAvailable: coordinator.audioCapture.systemAudioAvailable
        )

        return HStack(spacing: DesignTokens.Spacing.sm) {
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
                Text(meeting.topic)
                    .font(DesignTokens.Font.heading())
                    .foregroundColor(DesignTokens.Text.primary)
                    .lineLimit(1)
                Text(meeting.state == .recording ? "实时字幕与时间轴" : "会议处理中")
                    .font(DesignTokens.Font.caption())
                    .foregroundColor(DesignTokens.Text.tertiary)
            }
            .layoutPriority(1)

            Spacer()

            if let inlineRecordingStatusSummary {
                inlineRecordingStatus(summary: inlineRecordingStatusSummary)
            }

            Button {
                AppDelegate.shared?.showMeetingArchive(meetingID: meeting.id)
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
                Task { await coordinator.captureRecentFocus() }
            } label: {
                Text("重点关注")
                    .font(DesignTokens.Font.label())
                    .foregroundColor(.white)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Capsule().fill(TerminalColors.amber))
            }
            .buttonStyle(.plain)
            .disabled(meeting.transcript.isEmpty)

            Button {
                Task {
                    await coordinator.triggerManualThinking()
                }
            } label: {
                Text(coordinator.isGeneratingThinking ? "思考中" : "思考")
                    .font(DesignTokens.Font.label())
                    .foregroundColor(.white)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Capsule().fill(TerminalColors.blue))
            }
            .buttonStyle(.plain)
            .disabled(coordinator.isGeneratingThinking)

            Button {
                endRecording()
            } label: {
                Text(meeting.state == .recording ? "结束录制" : "刷新")
                    .font(DesignTokens.Font.label())
                    .foregroundColor(.white)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(
                        Capsule()
                            .fill(meeting.state == .recording ? Color.red.opacity(0.85) : TerminalColors.blue)
                    )
            }
            .buttonStyle(.plain)
            .disabled(isStoppingMeeting)
        }
    }

    private func inlineRecordingStatus(summary: MeetingLiveInlineRecordingStatusSummary) -> some View {
        HStack(spacing: DesignTokens.Spacing.xs) {
            Circle()
                .fill(realtimeStatusColor)
                .frame(width: 8, height: 8)

            VStack(alignment: .leading, spacing: 1) {
                Text(summary.statusText)
                    .font(DesignTokens.Font.caption())
                    .foregroundColor(DesignTokens.Text.secondary)
                    .lineLimit(1)

                Menu {
                    ForEach(MeetingAudioInputMode.allCases, id: \.rawValue) { mode in
                        Button {
                            Task {
                                await coordinator.updateAudioInputMode(mode)
                            }
                        } label: {
                            HStack {
                                Text(mode.displayName)
                                Spacer()
                                if settings.audioInputMode == mode {
                                    Image(systemName: "checkmark")
                                }
                            }
                        }
                    }
                } label: {
                    HStack(spacing: 4) {
                        Text(summary.sourceText)
                            .font(DesignTokens.Font.mono(10))
                            .foregroundColor(DesignTokens.Text.tertiary)
                            .lineLimit(1)
                        Image(systemName: "chevron.down")
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundColor(DesignTokens.Text.tertiary)
                    }
                }
                .menuStyle(.borderlessButton)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: DesignTokens.Radius.lg)
                .fill(DesignTokens.Surface.elevated)
        )
    }

    private func audioInputModeErrorBanner(_ message: String) -> some View {
        HStack(alignment: .top, spacing: DesignTokens.Spacing.sm) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundColor(TerminalColors.amber)
                .padding(.top, 1)

            Text(message)
                .font(DesignTokens.Font.caption())
                .foregroundColor(DesignTokens.Text.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: 12)

            Button("打开权限设置") {
                coordinator.openAudioCapturePermissionSettings()
            }
            .buttonStyle(.plain)
            .font(DesignTokens.Font.caption())
            .foregroundColor(TerminalColors.blue)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: DesignTokens.Radius.lg)
                .fill(DesignTokens.Surface.elevated)
                .overlay(
                    RoundedRectangle(cornerRadius: DesignTokens.Radius.lg)
                        .strokeBorder(TerminalColors.amber.opacity(0.35), lineWidth: 1)
                )
        )
    }

    private var realtimeStatusColor: Color {
        switch coordinator.realtimeASRState {
        case .idle:
            return DesignTokens.Text.tertiary
        case .connecting:
            return TerminalColors.amber
        case .ready:
            return TerminalColors.blue
        case .receiving:
            return TerminalColors.green
        case .failed:
            return Color.red.opacity(0.9)
        }
    }

    private func endRecording() {
        guard !isStoppingMeeting else { return }
        isStoppingMeeting = true

        Task {
            await coordinator.stopMeeting()
            let processingMeeting = coordinator.activeMeeting
            await MainActor.run {
                isStoppingMeeting = false
                if let processingMeeting {
                    withAnimation(.easeInOut(duration: 0.25)) {
                        viewModel.contentType = .meetingDetail(processingMeeting)
                    }
                }
            }
        }
    }

    private func transcriptColumn(
        meeting: MeetingRecord,
        items: [MeetingLiveFeedItem],
        scrollToken: String
    ) -> some View {
        meetingColumn(title: "实时转录", bottomID: transcriptBottomID, scrollToken: scrollToken) {
            if items.isEmpty {
                Text("等待实时字幕...")
                    .font(DesignTokens.Font.body())
                    .foregroundColor(DesignTokens.Text.tertiary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                ForEach(items) { item in
                    if case .transcript(let segment) = item.kind {
                        transcriptTile(
                            segment,
                            timecode: item.timecode,
                            isFocused: coordinator.isTranscriptFocused(segment.id, in: meeting),
                            isNoted: coordinator.isTranscriptNoted(segment.id, in: meeting)
                        )
                    }
                }
            }
        }
    }

    private func timelineColumn(
        meeting: MeetingRecord,
        items: [MeetingLiveFeedItem],
        scrollToken: String
    ) -> some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.md) {
            meetingColumn(title: "时间轴", bottomID: timelineBottomID, scrollToken: scrollToken) {
                if items.isEmpty {
                    Text("等待插个嘴或笔记...")
                        .font(DesignTokens.Font.body())
                        .foregroundColor(DesignTokens.Text.tertiary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    ForEach(items) { item in
                        switch item.kind {
                        case .advice(let card):
                            MeetingAdviceCardTile(
                                card: card,
                                maxVisibleViewpoints: settings.maxVisibleViewpoints,
                                timestampLabel: item.timecode
                            )
                        case .note(let annotation):
                            noteTile(annotation, timecode: item.timecode, meeting: meeting)
                        case .transcript:
                            EmptyView()
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)

            noteComposerBar(meeting: meeting)
        }
    }

    private func noteComposerBar(meeting: MeetingRecord) -> some View {
        let linkedSegment = pendingLinkedSegment(in: meeting)

        return VStack(alignment: .leading, spacing: DesignTokens.Spacing.xs) {
            Text("会议笔记")
                .font(DesignTokens.Font.caption())
                .foregroundColor(DesignTokens.Text.secondary)

            if let linkedSegment {
                linkedTranscriptPreview(segment: linkedSegment, meeting: meeting)
            }

            HStack(spacing: DesignTokens.Spacing.sm) {
                Button {
                    importImageAttachments()
                } label: {
                    attachmentActionIcon("photo")
                }
                .buttonStyle(.plain)
                .help("上传图片作为会议笔记")
                .disabled(coordinator.isImportingNoteAttachment)

                Button {
                    importGenericAttachments()
                } label: {
                    attachmentActionIcon("paperclip")
                }
                .buttonStyle(.plain)
                .help("上传文件作为会议笔记")
                .disabled(coordinator.isImportingNoteAttachment)

                Button {
                    captureScreenshotAttachment()
                } label: {
                    attachmentActionIcon("camera.viewfinder")
                }
                .buttonStyle(.plain)
                .help("截屏并加入会议笔记")
                .disabled(coordinator.isImportingNoteAttachment)

                TextField(
                    linkedSegment == nil ? "随时记录一条笔记..." : "写下你对这句字幕的评论...",
                    text: $noteDraft
                )
                    .textFieldStyle(MeetingFieldStyle())

                Button {
                    let composerState = consumeNoteComposerState()
                    Task {
                        await coordinator.addNote(
                            composerState.text,
                            linkedSegmentID: composerState.linkedSegmentID
                        )
                    }
                } label: {
                    Text("记录")
                        .font(DesignTokens.Font.caption())
                        .foregroundColor(.white)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 8)
                        .background(Capsule().fill(TerminalColors.green))
                }
                .buttonStyle(.plain)
                .disabled(
                    coordinator.isImportingNoteAttachment ||
                    noteDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                )
            }

            if coordinator.isImportingNoteAttachment {
                Text("正在解析附件并写入 meeting.md ...")
                    .font(DesignTokens.Font.caption())
                    .foregroundColor(DesignTokens.Text.tertiary)
            }
        }
        .padding(DesignTokens.Spacing.md)
        .background(
            RoundedRectangle(cornerRadius: DesignTokens.Radius.xl)
                .fill(DesignTokens.Surface.base)
        )
    }

    private func meetingColumn<Content: View>(
        title: String,
        bottomID: String,
        scrollToken: String,
        @ViewBuilder content: @escaping () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.sm) {
            Text(title)
                .font(DesignTokens.Font.heading())
                .foregroundColor(DesignTokens.Text.primary)

            ScrollViewReader { proxy in
                ScrollView(.vertical, showsIndicators: false) {
                    LazyVStack(alignment: .leading, spacing: DesignTokens.Spacing.sm) {
                        content()

                        Color.clear
                            .frame(height: 1)
                            .id(bottomID)
                    }
                }
                .onAppear {
                    scrollColumnToLatest(proxy: proxy, bottomID: bottomID)
                }
                .onChange(of: scrollToken) {
                    scrollColumnToLatest(proxy: proxy, bottomID: bottomID)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .padding(DesignTokens.Spacing.md)
        .background(
            RoundedRectangle(cornerRadius: DesignTokens.Radius.xl)
                .fill(DesignTokens.Surface.base)
        )
    }

    private func transcriptTile(
        _ segment: TranscriptSegment,
        timecode: String,
        isFocused: Bool,
        isNoted: Bool
    ) -> some View {
        let transcript = coordinator.activeMeeting?.transcript ?? []
        let speakerSpans = coordinator.activeMeeting?.speakerSpans ?? []
        return VStack(alignment: .leading, spacing: 2) {
            HStack(alignment: .center, spacing: DesignTokens.Spacing.xs) {
                HStack(spacing: DesignTokens.Spacing.xs) {
                    Text(segment.displaySpeakerBadge(in: transcript, speakerSpans: speakerSpans))
                        .font(DesignTokens.Font.caption())
                        .foregroundColor(TerminalColors.blue)
                    if let emotion = segment.emotion, !emotion.isEmpty {
                        Text(emotion)
                            .font(DesignTokens.Font.caption())
                            .foregroundColor(DesignTokens.Text.tertiary)
                    }
                }
                Spacer()
                if isFocused {
                    Text("重点")
                        .font(DesignTokens.Font.caption())
                        .foregroundColor(.black)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(Capsule().fill(TerminalColors.amber))
                }
                Button {
                    pendingLinkedSegmentID = segment.id
                } label: {
                    Image(systemName: isNoted ? "checkmark.circle.fill" : "plus.circle")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(isNoted ? TerminalColors.green : DesignTokens.Text.secondary)
                }
                .buttonStyle(.plain)
                .help(isNoted ? "这条字幕已写过评论" : "针对这条字幕写一条评论")
                .disabled(isNoted)
                timeBadge(timecode)
            }
            Text(segment.text)
                .font(DesignTokens.Font.body())
                .foregroundColor(DesignTokens.Text.primary)
        }
        .padding(DesignTokens.Spacing.sm)
        .background(
            RoundedRectangle(cornerRadius: DesignTokens.Radius.lg)
                .fill(DesignTokens.Surface.elevated)
                .overlay(
                    RoundedRectangle(cornerRadius: DesignTokens.Radius.lg)
                        .strokeBorder(isFocused ? TerminalColors.amber : Color.clear, lineWidth: 1.5)
                )
        )
        .contentShape(RoundedRectangle(cornerRadius: DesignTokens.Radius.lg))
        .onTapGesture {
            Task { await coordinator.toggleFocus(segmentID: segment.id) }
        }
    }

    private func noteTile(
        _ annotation: MeetingAnnotation,
        timecode: String,
        meeting: MeetingRecord
    ) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                HStack(spacing: 6) {
                    Text("笔记")
                        .font(DesignTokens.Font.caption())
                        .foregroundColor(TerminalColors.green)
                    Text(annotation.source.displayName)
                        .font(DesignTokens.Font.caption())
                        .foregroundColor(DesignTokens.Text.tertiary)
                }
                Spacer()
                timeBadge(timecode)
            }

            if !annotation.effectiveText.isEmpty {
                Text(annotation.effectiveText)
                    .font(DesignTokens.Font.body())
                    .foregroundColor(DesignTokens.Text.primary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if let quoteContext = annotation.quoteContext(in: meeting.transcript) {
                quotePreview(quoteContext)
            }

            if !annotation.attachments.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(annotation.attachments) { attachment in
                        attachmentPreview(attachment)
                    }
                }
            }
        }
        .padding(DesignTokens.Spacing.sm)
        .background(
            RoundedRectangle(cornerRadius: DesignTokens.Radius.lg)
                .fill(DesignTokens.Surface.elevated)
        )
    }

    private func timeBadge(_ text: String) -> some View {
        Text(text)
            .font(DesignTokens.Font.mono(10))
            .foregroundColor(DesignTokens.Text.secondary)
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(
                Capsule()
                    .fill(DesignTokens.Surface.base)
            )
    }

    private func scrollColumnToLatest(proxy: ScrollViewProxy, bottomID: String) {
        DispatchQueue.main.async {
            withAnimation(.easeOut(duration: 0.2)) {
                proxy.scrollTo(bottomID, anchor: .bottom)
            }
        }
    }

    private func attachmentActionIcon(_ systemName: String) -> some View {
        Image(systemName: systemName)
            .font(.system(size: 13, weight: .semibold))
            .foregroundColor(DesignTokens.Text.secondary)
            .frame(width: 28, height: 28)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(DesignTokens.Surface.elevated)
            )
    }

    private func attachmentPreview(_ attachment: MeetingNoteAttachment) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Text(attachment.kind.displayName)
                    .font(DesignTokens.Font.caption())
                    .foregroundColor(TerminalColors.amber)
                Text(attachment.displayName)
                    .font(DesignTokens.Font.caption())
                    .foregroundColor(DesignTokens.Text.secondary)
                    .lineLimit(1)
            }

            let preview = attachment.extractedMarkdown.trimmingCharacters(in: .whitespacesAndNewlines)
            if !preview.isEmpty {
                Text(String(preview.prefix(180)))
                    .font(DesignTokens.Font.caption())
                    .foregroundColor(DesignTokens.Text.tertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: DesignTokens.Radius.md)
                .fill(DesignTokens.Surface.base)
        )
    }

    private func importImageAttachments() {
#if canImport(AppKit)
        let selectedURLs = openAttachmentPanel(
            allowedContentTypes: [.image],
            allowsOtherFileTypes: false
        )
        guard !selectedURLs.isEmpty else { return }
        let composerState = consumeNoteComposerState()
        Task {
            await coordinator.addNoteAttachments(
                from: selectedURLs,
                preferredKind: .image,
                text: composerState.text,
                linkedSegmentID: composerState.linkedSegmentID
            )
        }
#endif
    }

    private func importGenericAttachments() {
#if canImport(AppKit)
        let selectedURLs = openAttachmentPanel(
            allowedContentTypes: [],
            allowsOtherFileTypes: true
        )
        guard !selectedURLs.isEmpty else { return }
        let composerState = consumeNoteComposerState()
        Task {
            await coordinator.addNoteAttachments(
                from: selectedURLs,
                preferredKind: .file,
                text: composerState.text,
                linkedSegmentID: composerState.linkedSegmentID
            )
        }
#endif
    }

    private func captureScreenshotAttachment() {
        let composerState = consumeNoteComposerState()
        Task {
            await coordinator.captureScreenshotNote(
                text: composerState.text,
                linkedSegmentID: composerState.linkedSegmentID
            )
        }
    }

    private func consumeNoteComposerState() -> (text: String, linkedSegmentID: String?) {
        let draft = noteDraft
        let linkedSegmentID = pendingLinkedSegmentID
        noteDraft = ""
        pendingLinkedSegmentID = nil
        return (draft, linkedSegmentID)
    }

    private func pendingLinkedSegment(in meeting: MeetingRecord) -> TranscriptSegment? {
        guard let pendingLinkedSegmentID else { return nil }
        return meeting.transcript.first(where: { $0.id == pendingLinkedSegmentID })
    }

    private func linkedTranscriptPreview(segment: TranscriptSegment, meeting: MeetingRecord) -> some View {
        let quoteContext = MeetingAnnotationQuoteContext(
            timecode: MeetingLiveTimeline.timecode(milliseconds: max(0, segment.startTimeMs)),
            speakerLabel: segment.displaySpeakerBadge(in: meeting.transcript, speakerSpans: meeting.speakerSpans),
            text: segment.text.trimmingCharacters(in: .whitespacesAndNewlines)
        )

        return VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Text("评论这句字幕")
                    .font(DesignTokens.Font.caption())
                    .foregroundColor(TerminalColors.blue)
                Spacer()
                Button("取消") {
                    pendingLinkedSegmentID = nil
                }
                .buttonStyle(.plain)
                .font(DesignTokens.Font.caption())
                .foregroundColor(DesignTokens.Text.tertiary)
            }

            quotePreview(quoteContext, maxCharacters: 180)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: DesignTokens.Radius.lg)
                .fill(DesignTokens.Surface.elevated)
        )
    }

    private func quotePreview(
        _ quoteContext: MeetingAnnotationQuoteContext,
        maxCharacters: Int = 140
    ) -> some View {
        let previewText: String
        if quoteContext.text.count > maxCharacters {
            let endIndex = quoteContext.text.index(quoteContext.text.startIndex, offsetBy: maxCharacters)
            previewText = String(quoteContext.text[..<endIndex]) + "..."
        } else {
            previewText = quoteContext.text
        }

        return VStack(alignment: .leading, spacing: 4) {
            Text("\(quoteContext.timecode) · \(quoteContext.speakerLabel)")
                .font(DesignTokens.Font.caption())
                .foregroundColor(DesignTokens.Text.tertiary)
            Text(previewText)
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

#if canImport(AppKit)
    private func openAttachmentPanel(
        allowedContentTypes: [UTType],
        allowsOtherFileTypes: Bool
    ) -> [URL] {
        MeetingFilePanelPresenter.pickMultipleURLs(
            allowedContentTypes: allowedContentTypes,
            allowsOtherFileTypes: allowsOtherFileTypes
        )
    }
#endif
}
