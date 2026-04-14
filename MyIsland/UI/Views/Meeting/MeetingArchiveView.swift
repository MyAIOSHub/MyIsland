import SwiftUI

struct MeetingArchiveView: View {
    @ObservedObject var viewModel: MeetingArchiveViewModel
    @ObservedObject private var settings = MeetingSettingsStore.shared
    @StateObject private var playbackController = MeetingPlaybackController()
    @State private var inspectorScrollTargetID: String?
    @State private var manuallyHighlightedTranscriptID: String?

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        return formatter
    }()

    var body: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.md) {
            toolbar

            if let meeting = viewModel.selectedMeeting {
                workspace(for: meeting)
            } else {
                emptyState
            }
        }
        .padding(DesignTokens.Spacing.lg)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Color.black)
        .onAppear {
            syncPlayback()
        }
        .onChange(of: viewModel.selectedMeetingID) {
            syncPlayback()
        }
    }

    private var toolbar: some View {
        HStack(spacing: DesignTokens.Spacing.md) {
            Text("会议总览")
                .font(.system(size: 20, weight: .bold))
                .foregroundColor(DesignTokens.Text.primary)

            Spacer(minLength: DesignTokens.Spacing.md)

            TextField("搜索会议/转写/笔记...", text: $viewModel.searchQuery)
                .textFieldStyle(MeetingFieldStyle())
                .frame(width: 280)

            Picker("状态", selection: $viewModel.activeFilter) {
                ForEach(MeetingArchiveFilter.allCases) { filter in
                    Text(filter.displayName).tag(filter)
                }
            }
            .pickerStyle(.segmented)
            .frame(width: 320)

            Button("新开会议") {
                viewModel.openMeetingHub()
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: DesignTokens.Radius.lg)
                    .fill(TerminalColors.blue)
            )
            .foregroundColor(.white)

            Button("关闭") {
                viewModel.closeWindow()
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: DesignTokens.Radius.lg)
                    .fill(DesignTokens.Surface.elevated)
            )
            .foregroundColor(DesignTokens.Text.primary)
        }
    }

    private func workspace(for meeting: MeetingRecord) -> some View {
        HStack(alignment: .top, spacing: DesignTokens.Spacing.md) {
            sidebar
                .frame(width: 300, alignment: .topLeading)
                .frame(maxHeight: .infinity, alignment: .topLeading)

            VStack(alignment: .leading, spacing: DesignTokens.Spacing.md) {
                mainHeader(for: meeting)
                chapterNavigation(for: meeting)
                playbackPanel(for: meeting)
                transcriptPanel(for: meeting)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)

            inspectorPanel(for: meeting)
                .frame(width: 360, alignment: .topLeading)
                .frame(maxHeight: .infinity, alignment: .topLeading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.sm) {
            HStack {
                Text("会议列表")
                    .font(DesignTokens.Font.heading())
                    .foregroundColor(DesignTokens.Text.primary)
                Spacer()
                Text("\(viewModel.listItems.count) 条")
                    .font(DesignTokens.Font.caption())
                    .foregroundColor(DesignTokens.Text.tertiary)
            }

            if viewModel.groupedMeetings.isEmpty {
                VStack(alignment: .leading, spacing: DesignTokens.Spacing.sm) {
                    Text("没有匹配的会议")
                        .font(DesignTokens.Font.label())
                        .foregroundColor(DesignTokens.Text.primary)
                    Text("调整筛选条件或搜索词后再试。")
                        .font(DesignTokens.Font.body())
                        .foregroundColor(DesignTokens.Text.tertiary)
                }
                .padding(DesignTokens.Spacing.md)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: DesignTokens.Radius.xl)
                        .fill(DesignTokens.Surface.base)
                )
            } else {
                ScrollView(.vertical, showsIndicators: false) {
                    LazyVStack(alignment: .leading, spacing: DesignTokens.Spacing.sm, pinnedViews: [.sectionHeaders]) {
                        ForEach(viewModel.groupedMeetings) { group in
                            Section {
                                VStack(alignment: .leading, spacing: DesignTokens.Spacing.sm) {
                                    ForEach(group.items) { item in
                                        MeetingArchiveSidebarRow(
                                            item: item,
                                            isSelected: item.id == viewModel.selectedMeetingID,
                                            onSelect: {
                                                viewModel.focus(meetingID: item.id)
                                            },
                                            onOpenMarkdown: {
                                                viewModel.openMarkdown(for: item.record)
                                            },
                                            onCopySummary: {
                                                viewModel.copySummary(for: item.record)
                                            },
                                            onRevealFiles: {
                                                viewModel.revealMeetingFiles(for: item.record)
                                            }
                                        )
                                    }
                                }
                            } header: {
                                HStack {
                                    Text(group.title)
                                        .font(DesignTokens.Font.caption())
                                        .foregroundColor(DesignTokens.Text.tertiary)
                                    Spacer()
                                }
                                .padding(.horizontal, DesignTokens.Spacing.xs)
                                .padding(.vertical, DesignTokens.Spacing.xs)
                                .background(Color.black.opacity(0.92))
                            }
                        }
                    }
                    .padding(.bottom, DesignTokens.Spacing.lg)
                }
                .mask(
                    LinearGradient(
                        colors: [.clear, .black, .black, .clear],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
            }
        }
        .padding(DesignTokens.Spacing.md)
        .background(
            RoundedRectangle(cornerRadius: DesignTokens.Radius.xl)
                .fill(DesignTokens.Surface.base)
        )
    }

    private func mainHeader(for meeting: MeetingRecord) -> some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.sm) {
            HStack(alignment: .top, spacing: DesignTokens.Spacing.md) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(meeting.topic)
                        .font(.system(size: 18, weight: .bold))
                        .foregroundColor(DesignTokens.Text.primary)
                    Text(headerMetaText(for: meeting))
                        .font(DesignTokens.Font.body())
                        .foregroundColor(DesignTokens.Text.tertiary)
                }

                Spacer(minLength: DesignTokens.Spacing.md)

                HStack(spacing: DesignTokens.Spacing.xs) {
                    headerBadge(title: summaryStatusText(for: meeting), color: meeting.summaryBundle == nil ? TerminalColors.amber : TerminalColors.green)
                    headerBadge(title: "\(meeting.focusAnnotations.count) 个重点", color: TerminalColors.amber)
                    headerBadge(title: "\(meeting.noteAnnotations.count) 条笔记", color: TerminalColors.green)
                    headerBadge(title: "\(meeting.adviceCards.count + meeting.postMeetingAdviceCards.count) 张插个嘴", color: TerminalColors.blue)
                }
            }

            HStack(spacing: DesignTokens.Spacing.xs) {
                archiveActionButton("重跑总结") {
                    viewModel.retrySummary(for: meeting)
                }
                archiveActionButton("打开 md") {
                    viewModel.openMarkdown(for: meeting)
                }
                archiveActionButton("显示文件") {
                    viewModel.revealMeetingFiles(for: meeting)
                }
                archiveActionButton("复制摘要") {
                    viewModel.copySummary(for: meeting)
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
    private func chapterNavigation(for meeting: MeetingRecord) -> some View {
        if let chapters = meeting.summaryBundle?.chapterSummaries, !chapters.isEmpty {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: DesignTokens.Spacing.xs) {
                    ForEach(chapters) { chapter in
                        Button {
                            viewModel.activeInspectorTab = .chapterSummary
                            inspectorScrollTargetID = chapter.id
                        } label: {
                            Text(chapter.title)
                                .font(DesignTokens.Font.caption())
                                .foregroundColor(DesignTokens.Text.primary)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 6)
                                .background(
                                    Capsule()
                                        .fill(DesignTokens.Surface.elevated)
                                )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    private func playbackPanel(for meeting: MeetingRecord) -> some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.sm) {
            Text("回放区")
                .font(DesignTokens.Font.heading())
                .foregroundColor(DesignTokens.Text.primary)

            switch meeting.state {
            case .scheduled:
                archiveStatusCard(
                    title: "预约会议尚未开始",
                    body: "开始会议后，这里会展示音频进度条、转写联动和时间标记。"
                )
            case .processing:
                archiveStatusCard(
                    title: "会议处理中",
                    body: "转写与结构化总结仍可浏览，回放会在录音资产可用时启用。"
                )
            default:
                if playbackController.asset != nil {
                    playbackControls(for: meeting)
                } else {
                    archiveStatusCard(
                        title: playbackController.errorMessage ?? "录音文件不可用",
                        body: "本地录音不存在且没有可回退的远端音频链接。"
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

    private func playbackControls(for meeting: MeetingRecord) -> some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.sm) {
            HStack(spacing: DesignTokens.Spacing.sm) {
                Button {
                    playbackController.togglePlayback()
                } label: {
                    Image(systemName: playbackController.isPlaying ? "pause.fill" : "play.fill")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(.white)
                        .frame(width: 30, height: 30)
                        .background(Circle().fill(TerminalColors.blue))
                }
                .buttonStyle(.plain)

                archiveMiniActionButton("-15s") {
                    playbackController.skip(by: -15)
                }

                archiveMiniActionButton("+15s") {
                    playbackController.skip(by: 15)
                }

                Text("\(formattedPlaybackTime(playbackController.currentTime)) / \(formattedPlaybackTime(playbackController.duration))")
                    .font(DesignTokens.Font.mono(11))
                    .foregroundColor(DesignTokens.Text.secondary)

                Spacer()

                if let asset = playbackController.asset {
                    Text(asset.source == .localFile ? "本地录音" : "远端录音")
                        .font(DesignTokens.Font.caption())
                        .foregroundColor(DesignTokens.Text.tertiary)
                }
            }

            MeetingArchiveProgressBar(
                duration: max(playbackController.duration, 0),
                currentTime: max(playbackController.currentTime, 0),
                markers: playbackMarkers(for: meeting),
                onSeek: { seconds in
                    playbackController.seek(to: seconds)
                    manuallyHighlightedTranscriptID = transcriptSegmentID(at: Int(seconds * 1_000), in: meeting)
                },
                onSelectMarker: { marker in
                    seek(to: marker.timecodeMs, meeting: meeting)
                    switch marker.kind {
                    case .focus, .note:
                        viewModel.activeInspectorTab = .notesAndFocus
                    case .advice:
                        viewModel.activeInspectorTab = .advice
                    }
                }
            )
            .frame(height: 24)

            HStack(spacing: DesignTokens.Spacing.sm) {
                markerLegend(color: TerminalColors.amber, title: "重点关注")
                markerLegend(color: TerminalColors.green, title: "会议笔记")
                markerLegend(color: TerminalColors.blue, title: "插个嘴")
            }

            if let segment = activeTranscriptSegment(in: meeting) {
                Text("[\(MeetingLiveTimeline.timecode(milliseconds: segment.startTimeMs))][\(segment.displaySpeakerLabel(in: meeting.transcript, speakerSpans: meeting.speakerSpans))] \(segment.text)")
                    .font(DesignTokens.Font.body())
                    .foregroundColor(DesignTokens.Text.secondary)
                    .lineLimit(2)
            }
        }
    }

    private func transcriptPanel(for meeting: MeetingRecord) -> some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.sm) {
            HStack {
                Text("实时记录 / 转写时间轴")
                    .font(DesignTokens.Font.heading())
                    .foregroundColor(DesignTokens.Text.primary)
                Spacer()
                Text("\(meeting.transcript.count) 条")
                    .font(DesignTokens.Font.caption())
                    .foregroundColor(DesignTokens.Text.tertiary)
            }

            if meeting.transcript.isEmpty {
                archiveStatusCard(
                    title: "暂无实时转写",
                    body: "当前会议还没有可浏览的字幕。"
                )
            } else {
                ScrollViewReader { proxy in
                    ScrollView(.vertical, showsIndicators: false) {
                        LazyVStack(alignment: .leading, spacing: DesignTokens.Spacing.sm) {
                            ForEach(sortedTranscript(meeting.transcript)) { segment in
                                transcriptRow(segment: segment, meeting: meeting)
                                    .id(segment.id)
                            }
                        }
                        .padding(.bottom, DesignTokens.Spacing.lg)
                    }
                    .onAppear {
                        scrollTranscriptIfNeeded(proxy: proxy, meeting: meeting)
                    }
                    .onChange(of: playbackController.currentTime) {
                        scrollTranscriptIfNeeded(proxy: proxy, meeting: meeting)
                    }
                    .onChange(of: manuallyHighlightedTranscriptID) {
                        scrollTranscriptIfNeeded(proxy: proxy, meeting: meeting)
                    }
                }
            }
        }
        .padding(DesignTokens.Spacing.md)
        .background(
            RoundedRectangle(cornerRadius: DesignTokens.Radius.xl)
                .fill(DesignTokens.Surface.base)
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func transcriptRow(segment: TranscriptSegment, meeting: MeetingRecord) -> some View {
        let annotationCount = meeting.noteAnnotations.filter { $0.linkedTranscriptSegmentID == segment.id }.count
        let focusCount = meeting.focusAnnotations.filter { $0.linkedTranscriptSegmentID == segment.id || $0.sourceSegmentIDs.contains(segment.id) }.count
        let adviceCount = linkedAdviceCount(for: segment, meeting: meeting)
        let isActive = segment.id == effectiveHighlightedTranscriptID(in: meeting)
        let isFocused = focusCount > 0

        return Button {
            seek(to: segment.startTimeMs, meeting: meeting)
            manuallyHighlightedTranscriptID = segment.id
        } label: {
            HStack(alignment: .top, spacing: DesignTokens.Spacing.sm) {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: DesignTokens.Spacing.xs) {
                        Text(MeetingLiveTimeline.timecode(milliseconds: segment.startTimeMs))
                            .font(DesignTokens.Font.mono(10))
                            .foregroundColor(DesignTokens.Text.tertiary)
                        Text(segment.displaySpeakerBadge(in: meeting.transcript, speakerSpans: meeting.speakerSpans))
                            .font(DesignTokens.Font.caption())
                            .foregroundColor(DesignTokens.Text.secondary)
                            .lineLimit(1)
                    }

                    Text(segment.text)
                        .font(DesignTokens.Font.body())
                        .foregroundColor(isActive ? DesignTokens.Text.primary : DesignTokens.Text.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .multilineTextAlignment(.leading)
                }

                Spacer(minLength: DesignTokens.Spacing.sm)

                VStack(alignment: .trailing, spacing: 6) {
                    HStack(spacing: 6) {
                        if focusCount > 0 {
                            inlineTag("重点", color: TerminalColors.amber)
                        }
                        if annotationCount > 0 {
                            inlineTag("笔记 \(annotationCount)", color: TerminalColors.green)
                        }
                        if adviceCount > 0 {
                            inlineTag("插个嘴 \(adviceCount)", color: TerminalColors.blue)
                        }
                    }
                    Text(segment.isFinal ? "final" : "draft")
                        .font(DesignTokens.Font.caption())
                        .foregroundColor(DesignTokens.Text.tertiary)
                }
            }
            .padding(DesignTokens.Spacing.md)
            .background(
                RoundedRectangle(cornerRadius: DesignTokens.Radius.xl)
                    .fill(isActive ? DesignTokens.Surface.pressed : DesignTokens.Surface.elevated)
                    .overlay(
                        RoundedRectangle(cornerRadius: DesignTokens.Radius.xl)
                            .strokeBorder(
                                isFocused ? TerminalColors.amber : (isActive ? DesignTokens.Border.emphasis : DesignTokens.Border.subtle),
                                lineWidth: isFocused || isActive ? 1 : 0.5
                            )
                    )
            )
        }
        .buttonStyle(.plain)
    }

    private func inspectorPanel(for meeting: MeetingRecord) -> some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.sm) {
            Text("右侧检查器")
                .font(DesignTokens.Font.heading())
                .foregroundColor(DesignTokens.Text.primary)

            HStack(spacing: DesignTokens.Spacing.xs) {
                ForEach(MeetingArchiveInspectorTab.allCases) { tab in
                    MeetingArchiveInspectorTabButton(
                        title: tab.displayName,
                        isActive: viewModel.activeInspectorTab == tab
                    ) {
                        viewModel.activeInspectorTab = tab
                    }
                }
            }

            switch viewModel.activeInspectorTab {
            case .chapterSummary:
                chapterInspector(meeting: meeting)
            case .notesAndFocus:
                annotationsInspector(meeting: meeting)
            case .advice:
                adviceInspector(meeting: meeting)
            case .qaAndActions:
                qaInspector(meeting: meeting)
            }
        }
        .padding(DesignTokens.Spacing.md)
        .background(
            RoundedRectangle(cornerRadius: DesignTokens.Radius.xl)
                .fill(DesignTokens.Surface.base)
        )
    }

    @ViewBuilder
    private func chapterInspector(meeting: MeetingRecord) -> some View {
        let fullSummary = meeting.summaryBundle?.fullSummary.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let chapters = meeting.summaryBundle?.chapterSummaries ?? []
        let processHighlights = meeting.summaryBundle?.processHighlights ?? []

        if !fullSummary.isEmpty || !chapters.isEmpty || !processHighlights.isEmpty {
            ScrollViewReader { proxy in
                ScrollView(.vertical, showsIndicators: false) {
                    LazyVStack(alignment: .leading, spacing: DesignTokens.Spacing.sm) {
                        if !fullSummary.isEmpty {
                            VStack(alignment: .leading, spacing: DesignTokens.Spacing.sm) {
                                Text("全文总结")
                                    .font(DesignTokens.Font.label())
                                    .foregroundColor(DesignTokens.Text.primary)
                                MarkdownText(fullSummary, color: DesignTokens.Text.secondary, fontSize: 12)
                            }
                            .padding(DesignTokens.Spacing.md)
                            .background(
                                RoundedRectangle(cornerRadius: DesignTokens.Radius.xl)
                                    .fill(DesignTokens.Surface.elevated)
                            )
                        }

                        ForEach(chapters) { chapter in
                            VStack(alignment: .leading, spacing: DesignTokens.Spacing.xs) {
                                Text(chapter.title)
                                    .font(DesignTokens.Font.label())
                                    .foregroundColor(DesignTokens.Text.primary)
                                Text(chapter.summary)
                                    .font(DesignTokens.Font.body())
                                    .foregroundColor(DesignTokens.Text.secondary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            .padding(DesignTokens.Spacing.md)
                            .background(
                                RoundedRectangle(cornerRadius: DesignTokens.Radius.xl)
                                    .fill(DesignTokens.Surface.elevated)
                            )
                            .id(chapter.id)
                        }

                        if !processHighlights.isEmpty {
                            VStack(alignment: .leading, spacing: DesignTokens.Spacing.sm) {
                                Text("流程提取")
                                    .font(DesignTokens.Font.label())
                                    .foregroundColor(DesignTokens.Text.primary)

                                ForEach(Array(processHighlights.enumerated()), id: \.offset) { _, highlight in
                                    Text("• \(highlight)")
                                        .font(DesignTokens.Font.body())
                                        .foregroundColor(DesignTokens.Text.secondary)
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                            }
                            .padding(DesignTokens.Spacing.md)
                            .background(
                                RoundedRectangle(cornerRadius: DesignTokens.Radius.xl)
                                    .fill(DesignTokens.Surface.elevated)
                            )
                        }
                    }
                    .padding(.bottom, DesignTokens.Spacing.lg)
                }
                .onChange(of: inspectorScrollTargetID) {
                    guard let inspectorScrollTargetID, viewModel.activeInspectorTab == .chapterSummary else { return }
                    withAnimation(.easeInOut(duration: 0.2)) {
                        proxy.scrollTo(inspectorScrollTargetID, anchor: .top)
                    }
                }
            }
        } else {
            archiveStatusCard(
                title: "暂无分段总结",
                body: "这场会议还没有生成章节化总结。"
            )
        }
    }

    @ViewBuilder
    private func annotationsInspector(meeting: MeetingRecord) -> some View {
        let annotations = (meeting.focusAnnotations + meeting.noteAnnotations)
            .sorted {
                if $0.timecodeMs == $1.timecodeMs {
                    return $0.createdAt < $1.createdAt
                }
                return $0.timecodeMs < $1.timecodeMs
            }

        if annotations.isEmpty {
            archiveStatusCard(
                title: "暂无重点或笔记",
                body: "重点关注与会议笔记会统一显示在这里。"
            )
        } else {
            ScrollView(.vertical, showsIndicators: false) {
                LazyVStack(alignment: .leading, spacing: DesignTokens.Spacing.sm) {
                    ForEach(annotations) { annotation in
                        annotationInspectorCard(annotation, meeting: meeting)
                    }
                }
                .padding(.bottom, DesignTokens.Spacing.lg)
            }
        }
    }

    private func annotationInspectorCard(_ annotation: MeetingAnnotation, meeting: MeetingRecord) -> some View {
        let accent = annotation.kind == .focus ? TerminalColors.amber : TerminalColors.green
        let label = annotation.kind == .focus ? "重点关注" : "会议笔记"
        let quote = annotation.quoteContext(in: meeting.transcript)

        return Button {
            let targetMs = quote.flatMap { _ in
                annotation.linkedTranscriptSegmentID.flatMap { linkedID in
                    meeting.transcript.first(where: { $0.id == linkedID })?.startTimeMs
                }
            } ?? annotation.timecodeMs
            seek(to: targetMs, meeting: meeting)
            manuallyHighlightedTranscriptID = annotation.linkedTranscriptSegmentID
        } label: {
            VStack(alignment: .leading, spacing: DesignTokens.Spacing.xs) {
                HStack(spacing: DesignTokens.Spacing.xs) {
                    inlineTag(label, color: accent)
                    Text(annotation.source.displayName)
                        .font(DesignTokens.Font.caption())
                        .foregroundColor(DesignTokens.Text.tertiary)
                    Spacer()
                    Text(MeetingLiveTimeline.timecode(milliseconds: annotation.timecodeMs))
                        .font(DesignTokens.Font.mono(10))
                        .foregroundColor(DesignTokens.Text.tertiary)
                }

                if !annotation.effectiveText.isEmpty {
                    Text(annotation.effectiveText)
                        .font(DesignTokens.Font.body())
                        .foregroundColor(DesignTokens.Text.primary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                if let quote {
                    Text(quote.inlineText)
                        .font(DesignTokens.Font.caption())
                        .foregroundColor(DesignTokens.Text.secondary)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 8)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(
                            RoundedRectangle(cornerRadius: DesignTokens.Radius.lg)
                                .fill(Color.white.opacity(0.04))
                        )
                }

                if !annotation.attachments.isEmpty {
                    Text("附件：\(annotation.attachments.map(\.displayName).joined(separator: " · "))")
                        .font(DesignTokens.Font.caption())
                        .foregroundColor(DesignTokens.Text.tertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(DesignTokens.Spacing.md)
            .background(
                RoundedRectangle(cornerRadius: DesignTokens.Radius.xl)
                    .fill(DesignTokens.Surface.elevated)
                    .overlay(
                        RoundedRectangle(cornerRadius: DesignTokens.Radius.xl)
                            .strokeBorder(accent.opacity(0.6), lineWidth: 1)
                    )
            )
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func adviceInspector(meeting: MeetingRecord) -> some View {
        let cards = (meeting.adviceCards + meeting.postMeetingAdviceCards)
            .sorted { lhs, rhs in
                if lhs.createdAt == rhs.createdAt {
                    return lhs.id < rhs.id
                }
                return lhs.createdAt < rhs.createdAt
            }

        if cards.isEmpty {
            archiveStatusCard(
                title: "暂无插个嘴",
                body: "这场会议还没有生成可回放的建议卡。"
            )
        } else {
            ScrollView(.vertical, showsIndicators: false) {
                LazyVStack(alignment: .leading, spacing: DesignTokens.Spacing.sm) {
                    ForEach(cards) { card in
                        let timecode = anchoredAdviceTimecode(card, meeting: meeting)

                        VStack(alignment: .leading, spacing: DesignTokens.Spacing.xs) {
                            HStack {
                                Text(timecode)
                                    .font(DesignTokens.Font.mono(10))
                                    .foregroundColor(DesignTokens.Text.tertiary)
                                Spacer()
                                Text(card.source)
                                    .font(DesignTokens.Font.caption())
                                    .foregroundColor(DesignTokens.Text.tertiary)
                            }

                            MeetingAdviceCardTile(
                                card: card,
                                maxVisibleViewpoints: settings.maxVisibleViewpoints,
                                timestampLabel: nil,
                                backgroundColor: DesignTokens.Surface.elevated
                            )
                            .simultaneousGesture(
                                TapGesture().onEnded {
                                    let anchor = adviceTimecodeMs(for: card, meeting: meeting)
                                    seek(to: anchor, meeting: meeting)
                                    manuallyHighlightedTranscriptID = card.sourceSegmentIDs.first
                                }
                            )
                        }
                    }
                }
                .padding(.bottom, DesignTokens.Spacing.lg)
            }
        }
    }

    @ViewBuilder
    private func qaInspector(meeting: MeetingRecord) -> some View {
        let actionItems = meeting.summaryBundle?.actionItems ?? []
        let qaPairs = meeting.summaryBundle?.qaPairs ?? []

        if actionItems.isEmpty && qaPairs.isEmpty {
            archiveStatusCard(
                title: "暂无问答与待办",
                body: "会后提取完成后，这里会展示问答与行动项。"
            )
        } else {
            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: DesignTokens.Spacing.md) {
                    if !actionItems.isEmpty {
                        VStack(alignment: .leading, spacing: DesignTokens.Spacing.sm) {
                            Text("待办")
                                .font(DesignTokens.Font.label())
                                .foregroundColor(DesignTokens.Text.primary)

                            ForEach(actionItems) { item in
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(item.task)
                                        .font(DesignTokens.Font.body())
                                        .foregroundColor(DesignTokens.Text.primary)
                                    let meta = [item.owner, item.dueDate]
                                        .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
                                        .filter { !$0.isEmpty }
                                        .joined(separator: " · ")
                                    if !meta.isEmpty {
                                        Text(meta)
                                            .font(DesignTokens.Font.caption())
                                            .foregroundColor(DesignTokens.Text.tertiary)
                                    }
                                }
                                .padding(DesignTokens.Spacing.md)
                                .background(
                                    RoundedRectangle(cornerRadius: DesignTokens.Radius.xl)
                                        .fill(DesignTokens.Surface.elevated)
                                )
                            }
                        }
                    }

                    if !qaPairs.isEmpty {
                        VStack(alignment: .leading, spacing: DesignTokens.Spacing.sm) {
                            Text("问答")
                                .font(DesignTokens.Font.label())
                                .foregroundColor(DesignTokens.Text.primary)

                            ForEach(qaPairs) { pair in
                                VStack(alignment: .leading, spacing: 6) {
                                    Text("Q: \(pair.question)")
                                        .font(DesignTokens.Font.body())
                                        .foregroundColor(DesignTokens.Text.primary)
                                    Text("A: \(pair.answer)")
                                        .font(DesignTokens.Font.body())
                                        .foregroundColor(DesignTokens.Text.secondary)
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                                .padding(DesignTokens.Spacing.md)
                                .background(
                                    RoundedRectangle(cornerRadius: DesignTokens.Radius.xl)
                                        .fill(DesignTokens.Surface.elevated)
                                )
                            }
                        }
                    }
                }
                .padding(.bottom, DesignTokens.Spacing.lg)
            }
        }
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.sm) {
            Text("还没有可浏览的会议")
                .font(DesignTokens.Font.heading())
                .foregroundColor(DesignTokens.Text.primary)
            Text("会议列表会按预约、进行中和历史记录自动聚合到这里。")
                .font(DesignTokens.Font.body())
                .foregroundColor(DesignTokens.Text.secondary)
        }
        .padding(DesignTokens.Spacing.xl)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        .background(
            RoundedRectangle(cornerRadius: DesignTokens.Radius.xl)
                .fill(DesignTokens.Surface.base)
        )
    }

    private func syncPlayback() {
        manuallyHighlightedTranscriptID = nil
        guard let meeting = viewModel.selectedMeeting else { return }
        playbackController.load(record: meeting)
    }

    private func headerMetaText(for meeting: MeetingRecord) -> String {
        let state = meetingStateDisplayName(meeting.state)
        let timestamp = Self.dateFormatter.string(from: MeetingArchiveIndex.primaryDate(for: meeting))
        let duration = MeetingArchiveIndex.durationText(for: meeting)
        return "\(state) · \(timestamp) · \(duration)"
    }

    private func meetingStateDisplayName(_ state: MeetingProcessingState) -> String {
        switch state {
        case .draft:
            return "未开始"
        case .scheduled:
            return "已预约"
        case .recording:
            return "录音中"
        case .processing:
            return "处理中"
        case .completed:
            return "已完成"
        case .failed:
            return "失败"
        }
    }

    private func summaryStatusText(for meeting: MeetingRecord) -> String {
        if meeting.summaryBundle != nil {
            return "总结完成"
        }
        if meeting.state == .processing {
            return "总结处理中"
        }
        return "待总结"
    }

    private func playbackMarkers(for meeting: MeetingRecord) -> [MeetingArchiveProgressMarker] {
        let transcriptByID = Dictionary(uniqueKeysWithValues: meeting.transcript.map { ($0.id, $0) })
        let focusMarkers = meeting.focusAnnotations.map {
            MeetingArchiveProgressMarker(
                id: "focus-\($0.id)",
                timecodeMs: $0.timecodeMs,
                kind: .focus
            )
        }
        let noteMarkers = meeting.noteAnnotations.map {
            MeetingArchiveProgressMarker(
                id: "note-\($0.id)",
                timecodeMs: $0.timecodeMs,
                kind: .note
            )
        }
        let adviceMarkers = (meeting.adviceCards + meeting.postMeetingAdviceCards).map { card in
            MeetingArchiveProgressMarker(
                id: "advice-\(card.id)",
                timecodeMs: MeetingLiveTimeline.anchoredTimeMs(
                    for: card,
                    transcriptByID: transcriptByID,
                    meetingStart: meeting.createdAt
                ),
                kind: .advice
            )
        }

        return (focusMarkers + noteMarkers + adviceMarkers)
            .sorted { lhs, rhs in
                if lhs.timecodeMs == rhs.timecodeMs {
                    return lhs.id < rhs.id
                }
                return lhs.timecodeMs < rhs.timecodeMs
            }
    }

    private func seek(to timecodeMs: Int, meeting: MeetingRecord) {
        playbackController.seek(to: Double(max(0, timecodeMs)) / 1_000)
        manuallyHighlightedTranscriptID = transcriptSegmentID(at: timecodeMs, in: meeting)
    }

    private func transcriptSegmentID(at timecodeMs: Int, in meeting: MeetingRecord) -> String? {
        if let exact = meeting.transcript.first(where: { $0.startTimeMs <= timecodeMs && $0.endTimeMs >= timecodeMs }) {
            return exact.id
        }

        return meeting.transcript
            .filter { $0.startTimeMs <= timecodeMs }
            .sorted { $0.startTimeMs > $1.startTimeMs }
            .first?
            .id
    }

    private func effectiveHighlightedTranscriptID(in meeting: MeetingRecord) -> String? {
        transcriptSegmentID(at: Int(playbackController.currentTime * 1_000), in: meeting)
            ?? manuallyHighlightedTranscriptID
    }

    private func activeTranscriptSegment(in meeting: MeetingRecord) -> TranscriptSegment? {
        guard let segmentID = effectiveHighlightedTranscriptID(in: meeting) else { return nil }
        return meeting.transcript.first(where: { $0.id == segmentID })
    }

    private func linkedAdviceCount(for segment: TranscriptSegment, meeting: MeetingRecord) -> Int {
        (meeting.adviceCards + meeting.postMeetingAdviceCards)
            .filter { $0.sourceSegmentIDs.contains(segment.id) }
            .count
    }

    private func anchoredAdviceTimecode(_ card: MeetingAdviceCard, meeting: MeetingRecord) -> String {
        MeetingLiveTimeline.timecode(milliseconds: adviceTimecodeMs(for: card, meeting: meeting))
    }

    private func adviceTimecodeMs(for card: MeetingAdviceCard, meeting: MeetingRecord) -> Int {
        let transcriptByID = Dictionary(uniqueKeysWithValues: meeting.transcript.map { ($0.id, $0) })
        return MeetingLiveTimeline.anchoredTimeMs(
            for: card,
            transcriptByID: transcriptByID,
            meetingStart: meeting.createdAt
        )
    }

    private func sortedTranscript(_ transcript: [TranscriptSegment]) -> [TranscriptSegment] {
        transcript.sorted {
            if $0.startTimeMs == $1.startTimeMs {
                return $0.endTimeMs < $1.endTimeMs
            }
            return $0.startTimeMs < $1.startTimeMs
        }
    }

    private func formattedPlaybackTime(_ seconds: Double) -> String {
        MeetingLiveTimeline.timecode(milliseconds: Int(max(0, seconds) * 1_000))
    }

    private func scrollTranscriptIfNeeded(proxy: ScrollViewProxy, meeting: MeetingRecord) {
        guard let highlightedID = effectiveHighlightedTranscriptID(in: meeting) else { return }
        withAnimation(.easeInOut(duration: 0.18)) {
            proxy.scrollTo(highlightedID, anchor: .center)
        }
    }

    private func headerBadge(title: String, color: Color) -> some View {
        Text(title)
            .font(DesignTokens.Font.caption())
            .foregroundColor(.white)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Capsule().fill(color))
    }

    private func archiveActionButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button(title, action: action)
            .buttonStyle(.plain)
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(
                RoundedRectangle(cornerRadius: DesignTokens.Radius.lg)
                    .fill(DesignTokens.Surface.elevated)
            )
            .foregroundColor(DesignTokens.Text.primary)
    }

    private func archiveMiniActionButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button(title, action: action)
            .buttonStyle(.plain)
            .font(DesignTokens.Font.caption())
            .foregroundColor(DesignTokens.Text.primary)
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: DesignTokens.Radius.md)
                    .fill(DesignTokens.Surface.elevated)
            )
    }

    private func archiveStatusCard(title: String, body: String) -> some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.xs) {
            Text(title)
                .font(DesignTokens.Font.label())
                .foregroundColor(DesignTokens.Text.primary)
            Text(body)
                .font(DesignTokens.Font.body())
                .foregroundColor(DesignTokens.Text.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(DesignTokens.Spacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: DesignTokens.Radius.xl)
                .fill(DesignTokens.Surface.elevated)
        )
    }

    private func markerLegend(color: Color, title: String) -> some View {
        HStack(spacing: 6) {
            Circle()
                .fill(color)
                .frame(width: 8, height: 8)
            Text(title)
                .font(DesignTokens.Font.caption())
                .foregroundColor(DesignTokens.Text.tertiary)
        }
    }

    private func inlineTag(_ title: String, color: Color) -> some View {
        Text(title)
            .font(DesignTokens.Font.caption())
            .foregroundColor(.white)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(Capsule().fill(color))
    }
}

private struct MeetingArchiveSidebarRow: View {
    let item: MeetingArchiveListItem
    let isSelected: Bool
    let onSelect: () -> Void
    let onOpenMarkdown: () -> Void
    let onCopySummary: () -> Void
    let onRevealFiles: () -> Void

    @State private var isHovered = false

    var body: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.xs) {
            Button(action: onSelect) {
                VStack(alignment: .leading, spacing: DesignTokens.Spacing.xs) {
                    HStack(alignment: .top, spacing: DesignTokens.Spacing.sm) {
                        Text("[\(item.displayTime)]")
                            .font(DesignTokens.Font.mono(10))
                            .foregroundColor(DesignTokens.Text.tertiary)

                        VStack(alignment: .leading, spacing: 4) {
                            Text(item.record.topic)
                                .font(DesignTokens.Font.label())
                                .foregroundColor(DesignTokens.Text.primary)
                                .lineLimit(1)
                            Text(item.previewText)
                                .font(DesignTokens.Font.body())
                                .foregroundColor(DesignTokens.Text.secondary)
                                .lineLimit(2)
                        }

                        Spacer(minLength: 0)
                    }

                    HStack(spacing: DesignTokens.Spacing.xs) {
                        metaBadge(item.durationText)
                        metaBadge(stateLabel(item.record.state))
                        if item.focusCount > 0 {
                            metaBadge("\(item.focusCount) 重点")
                        }
                        if item.noteCount > 0 {
                            metaBadge("\(item.noteCount) 笔记")
                        }
                        if item.adviceCount > 0 {
                            metaBadge("\(item.adviceCount) 插个嘴")
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(DesignTokens.Spacing.md)
                .background(
                    RoundedRectangle(cornerRadius: DesignTokens.Radius.xl)
                        .fill(isSelected ? DesignTokens.Surface.pressed : DesignTokens.Surface.elevated)
                        .overlay(
                            RoundedRectangle(cornerRadius: DesignTokens.Radius.xl)
                                .strokeBorder(isSelected ? DesignTokens.Border.emphasis : DesignTokens.Border.subtle, lineWidth: 1)
                        )
                )
            }
            .buttonStyle(.plain)

            if isHovered || isSelected {
                HStack(spacing: DesignTokens.Spacing.sm) {
                    hoverAction("打开", action: onOpenMarkdown)
                    hoverAction("复制摘要", action: onCopySummary)
                    hoverAction("显示文件", action: onRevealFiles)
                }
                .padding(.horizontal, DesignTokens.Spacing.sm)
            }
        }
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.15)) {
                isHovered = hovering
            }
        }
    }

    private func metaBadge(_ text: String) -> some View {
        Text(text)
            .font(DesignTokens.Font.caption())
            .foregroundColor(DesignTokens.Text.tertiary)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(
                Capsule().fill(Color.white.opacity(0.04))
            )
    }

    private func hoverAction(_ title: String, action: @escaping () -> Void) -> some View {
        Button(title, action: action)
            .buttonStyle(.plain)
            .font(DesignTokens.Font.caption())
            .foregroundColor(DesignTokens.Text.secondary)
    }

    private func stateLabel(_ state: MeetingProcessingState) -> String {
        switch state {
        case .draft:
            return "未开始"
        case .scheduled:
            return "预约"
        case .recording:
            return "进行中"
        case .processing:
            return "处理中"
        case .completed:
            return "已完成"
        case .failed:
            return "失败"
        }
    }
}

private struct MeetingArchiveInspectorTabButton: View {
    let title: String
    let isActive: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(DesignTokens.Font.caption())
                .foregroundColor(isActive ? .white : DesignTokens.Text.secondary)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(
                    Capsule()
                        .fill(isActive ? TerminalColors.blue : DesignTokens.Surface.elevated)
                )
        }
        .buttonStyle(.plain)
    }
}

private struct MeetingArchiveProgressMarker: Identifiable, Equatable {
    enum Kind: Equatable {
        case focus
        case note
        case advice

        var color: Color {
            switch self {
            case .focus:
                return TerminalColors.amber
            case .note:
                return TerminalColors.green
            case .advice:
                return TerminalColors.blue
            }
        }
    }

    let id: String
    let timecodeMs: Int
    let kind: Kind
}

private struct MeetingArchiveProgressBar: View {
    let duration: Double
    let currentTime: Double
    let markers: [MeetingArchiveProgressMarker]
    let onSeek: (Double) -> Void
    let onSelectMarker: (MeetingArchiveProgressMarker) -> Void

    var body: some View {
        GeometryReader { proxy in
            let width = max(proxy.size.width, 1)
            let progress = duration > 0 ? min(max(currentTime / duration, 0), 1) : 0

            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.white.opacity(0.08))
                    .frame(height: 10)

                Capsule()
                    .fill(TerminalColors.blue.opacity(0.95))
                    .frame(width: width * progress, height: 10)

                ForEach(markers) { marker in
                    Button {
                        onSelectMarker(marker)
                    } label: {
                        Circle()
                            .fill(marker.kind.color)
                            .frame(width: 10, height: 10)
                            .overlay(
                                Circle()
                                    .strokeBorder(Color.black.opacity(0.6), lineWidth: 1)
                            )
                    }
                    .buttonStyle(.plain)
                    .position(
                        x: markerX(marker, width: width),
                        y: proxy.size.height / 2
                    )
                }
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        guard duration > 0 else { return }
                        let clamped = min(max(value.location.x, 0), width)
                        onSeek((clamped / width) * duration)
                    }
            )
        }
    }

    private func markerX(_ marker: MeetingArchiveProgressMarker, width: CGFloat) -> CGFloat {
        guard duration > 0 else { return 0 }
        let ratio = min(max(Double(marker.timecodeMs) / (duration * 1_000), 0), 1)
        return max(6, min(width - 6, width * ratio))
    }
}
