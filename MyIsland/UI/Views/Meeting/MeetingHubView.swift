import SwiftUI
#if canImport(AppKit)
import AppKit
#endif
import UniformTypeIdentifiers

struct MeetingHubView: View {
    enum HubSection: CaseIterable {
        case newMeeting
        case scheduled
        case currentMeeting
        case history
    }

    @ObservedObject var viewModel: NotchViewModel
    @ObservedObject private var coordinator = MeetingCoordinator.shared

    @State private var topic: String = ""
    @State private var showsScheduleComposer = false
    @State private var editingScheduledMeetingID: String?
    @State private var scheduledAt = Date().addingTimeInterval(3600)
    @State private var durationMinutes = 60
    @State private var calendarSyncEnabled = true

    private static let scheduleDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "MM-dd HH:mm"
        formatter.locale = Locale(identifier: "zh_CN")
        return formatter
    }()

    private var liveMeeting: MeetingRecord? {
        guard let activeMeeting = coordinator.activeMeeting, activeMeeting.state == .recording else {
            return nil
        }
        return activeMeeting
    }

    private var scheduledMeetings: [MeetingRecord] {
        coordinator.recentMeetings
            .filter { $0.state == .scheduled }
            .sorted {
                ($0.scheduledAt ?? .distantFuture) < ($1.scheduledAt ?? .distantFuture)
            }
    }

    private var historyMeetings: [MeetingRecord] {
        coordinator.recentMeetings.filter { $0.state != .scheduled }
    }

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: DesignTokens.Spacing.md) {
                header
                ForEach(HubSection.allCases, id: \.self) { section in
                    sectionView(for: section)
                }
            }
            .padding(DesignTokens.Spacing.md)
        }
        .background(Color.black)
    }

    private var header: some View {
        HStack(spacing: DesignTokens.Spacing.sm) {
            Button {
                withAnimation(.easeInOut(duration: 0.25)) {
                    viewModel.contentType = .menu
                }
            } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.white.opacity(0.72))
            }
            .buttonStyle(.plain)

            Text("会议助手")
                .font(DesignTokens.Font.title())
                .foregroundColor(DesignTokens.Text.primary)

            Spacer()

            Button {
                withAnimation(.easeInOut(duration: 0.25)) {
                    viewModel.contentType = .meetingSettings
                }
            } label: {
                Image(systemName: "slider.horizontal.3")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.white.opacity(0.72))
            }
            .buttonStyle(.plain)
        }
    }

    private var composerCard: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.sm) {
            Text(editingScheduledMeetingID == nil ? "开始会议" : "编辑预约")
                .font(DesignTokens.Font.heading())
                .foregroundColor(DesignTokens.Text.primary)

            TextField(
                showsScheduleComposer
                    ? "输入会议主题，例如：需求评审 / 商业判断 / 方案讨论"
                    : "输入会议主题，例如：增长复盘 / 产品评审 / 商业计划",
                text: $topic
            )
            .textFieldStyle(MeetingFieldStyle())

            if showsScheduleComposer {
                DatePicker(
                    "开始时间",
                    selection: $scheduledAt,
                    in: Date()...,
                    displayedComponents: [.date, .hourAndMinute]
                )
                .datePickerStyle(.compact)
                .font(DesignTokens.Font.body())
                .foregroundColor(DesignTokens.Text.secondary)

                Stepper(value: $durationMinutes, in: 15...240, step: 15) {
                    Text("会议时长 \(durationMinutes) 分钟")
                        .font(DesignTokens.Font.body())
                        .foregroundColor(DesignTokens.Text.secondary)
                }

                Toggle(isOn: $calendarSyncEnabled) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("同步到系统日历")
                            .font(DesignTokens.Font.body())
                            .foregroundColor(DesignTokens.Text.primary)
                        Text("创建、编辑、删除预约时同步更新 Apple Calendar")
                            .font(DesignTokens.Font.caption())
                            .foregroundColor(DesignTokens.Text.tertiary)
                    }
                }
                .toggleStyle(.switch)
            }

            HStack(spacing: DesignTokens.Spacing.sm) {
                if showsScheduleComposer {
                    Button {
                        Task { await saveScheduledMeeting() }
                    } label: {
                        HStack {
                            Image(systemName: "calendar.badge.plus")
                            Text(editingScheduledMeetingID == nil ? "创建预约" : "保存预约")
                        }
                        .font(DesignTokens.Font.label())
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(
                            RoundedRectangle(cornerRadius: DesignTokens.Radius.lg)
                                .fill(TerminalColors.blue)
                        )
                    }
                    .buttonStyle(.plain)

                    Button {
                        resetComposer()
                    } label: {
                        Text("取消")
                            .font(DesignTokens.Font.label())
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                            .background(
                                RoundedRectangle(cornerRadius: DesignTokens.Radius.lg)
                                    .fill(DesignTokens.Surface.base)
                            )
                    }
                    .buttonStyle(.plain)
                } else {
                    Button {
                        Task { await startImmediateMeeting() }
                    } label: {
                        HStack {
                            Image(systemName: liveMeeting == nil ? "record.circle.fill" : "waveform")
                            Text(liveMeeting == nil ? "开始会议" : "查看进行中的会议")
                        }
                        .font(DesignTokens.Font.label())
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(
                            RoundedRectangle(cornerRadius: DesignTokens.Radius.lg)
                                .fill(Color(red: 0.80, green: 0.25, blue: 0.26))
                        )
                    }
                    .buttonStyle(.plain)
                    .disabled(liveMeeting != nil)

                    Button {
                        showsScheduleComposer = true
                        editingScheduledMeetingID = nil
                    } label: {
                        HStack {
                            Image(systemName: "calendar.badge.plus")
                            Text("预约会议")
                        }
                        .font(DesignTokens.Font.label())
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(
                            RoundedRectangle(cornerRadius: DesignTokens.Radius.lg)
                                .fill(TerminalColors.blue)
                        )
                    }
                    .buttonStyle(.plain)

                    Button {
                        uploadTranscriptMedia()
                    } label: {
                        HStack {
                            Image(systemName: coordinator.isImportingTranscriptMedia ? "arrow.triangle.2.circlepath" : "square.and.arrow.up")
                            Text(coordinator.isImportingTranscriptMedia ? "导入中..." : "上传转录")
                        }
                        .font(DesignTokens.Font.label())
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(
                            RoundedRectangle(cornerRadius: DesignTokens.Radius.lg)
                                .fill(DesignTokens.Surface.base)
                        )
                    }
                    .buttonStyle(.plain)
                    .disabled(coordinator.isImportingTranscriptMedia)
                }
            }
        }
        .padding(DesignTokens.Spacing.md)
        .background(
            RoundedRectangle(cornerRadius: DesignTokens.Radius.xl)
                .fill(DesignTokens.Surface.elevated)
        )
    }

    @ViewBuilder
    private var scheduledMeetingsSection: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.xs) {
            Text("预约会议")
                .font(DesignTokens.Font.heading())
                .foregroundColor(DesignTokens.Text.primary)

            if scheduledMeetings.isEmpty {
                Text("暂无预约会议")
                    .font(DesignTokens.Font.body())
                    .foregroundColor(DesignTokens.Text.tertiary)
            } else {
                ForEach(scheduledMeetings) { record in
                    scheduledMeetingRow(record)
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
    private var activeMeetingCard: some View {
        if let activeMeeting = liveMeeting {
            VStack(alignment: .leading, spacing: DesignTokens.Spacing.sm) {
                HStack {
                    Text(activeMeeting.topic)
                        .font(DesignTokens.Font.heading())
                        .foregroundColor(DesignTokens.Text.primary)
                        .lineLimit(1)

                    Spacer()

                    Text("进行中")
                        .font(DesignTokens.Font.caption())
                        .foregroundColor(.red)
                }

                Text("\(activeMeeting.transcript.count) 条字幕 · \(activeMeeting.adviceCards.count) 条插个嘴")
                    .font(DesignTokens.Font.body())
                    .foregroundColor(DesignTokens.Text.secondary)

                Button {
                    withAnimation(.easeInOut(duration: 0.25)) {
                        viewModel.contentType = .meetingLive
                    }
                } label: {
                    Text("打开实时面板")
                        .font(DesignTokens.Font.label())
                        .foregroundColor(.white)
                }
                .buttonStyle(.plain)
            }
            .padding(DesignTokens.Spacing.md)
            .background(
                RoundedRectangle(cornerRadius: DesignTokens.Radius.xl)
                    .fill(DesignTokens.Surface.base)
                    .overlay(
                        RoundedRectangle(cornerRadius: DesignTokens.Radius.xl)
                            .strokeBorder(DesignTokens.Border.standard, lineWidth: 1)
                    )
            )
        }
    }

    @ViewBuilder
    private func sectionView(for section: HubSection) -> some View {
        switch section {
        case .newMeeting:
            composerCard
        case .scheduled:
            scheduledMeetingsSection
        case .currentMeeting:
            activeMeetingCard
        case .history:
            recentMeetingsSection
        }
    }

    private var recentMeetingsSection: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.xs) {
            HStack {
                Text("会议历史")
                    .font(DesignTokens.Font.heading())
                    .foregroundColor(DesignTokens.Text.primary)

                Spacer()

                Button("全局查看") {
                    AppDelegate.shared?.showMeetingArchive(meetingID: historyMeetings.first?.id)
                }
                .buttonStyle(.plain)
                .font(DesignTokens.Font.caption())
                .foregroundColor(TerminalColors.blue)
            }

            if historyMeetings.isEmpty {
                Text("暂无会议记录")
                    .font(DesignTokens.Font.body())
                    .foregroundColor(DesignTokens.Text.tertiary)
            } else {
                ForEach(historyMeetings.prefix(8)) { record in
                    Button {
                        withAnimation(.easeInOut(duration: 0.25)) {
                            viewModel.contentType = .meetingDetail(record)
                        }
                    } label: {
                        HStack(alignment: .top, spacing: DesignTokens.Spacing.sm) {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(record.topic)
                                    .font(DesignTokens.Font.label())
                                    .foregroundColor(DesignTokens.Text.primary)
                                    .lineLimit(1)
                                Text(record.summaryBundle?.fullSummary.isEmpty == false
                                    ? record.summaryBundle?.fullSummary ?? ""
                                    : record.transcript.last?.text ?? "暂无摘要")
                                    .font(DesignTokens.Font.body())
                                    .foregroundColor(DesignTokens.Text.secondary)
                                    .lineLimit(2)
                            }

                            Spacer()

                            Text(record.state.rawValue)
                                .font(DesignTokens.Font.caption())
                                .foregroundColor(DesignTokens.Text.tertiary)
                        }
                        .padding(.vertical, 6)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(DesignTokens.Spacing.md)
        .background(
            RoundedRectangle(cornerRadius: DesignTokens.Radius.xl)
                .fill(DesignTokens.Surface.base)
        )
    }

    private func scheduledMeetingRow(_ record: MeetingRecord) -> some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.sm) {
            HStack(alignment: .top, spacing: DesignTokens.Spacing.sm) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(record.topic)
                        .font(DesignTokens.Font.label())
                        .foregroundColor(DesignTokens.Text.primary)
                        .lineLimit(1)

                    Text(scheduledSummary(for: record))
                        .font(DesignTokens.Font.body())
                        .foregroundColor(DesignTokens.Text.secondary)

                    HStack(spacing: DesignTokens.Spacing.xs) {
                        scheduleBadge(record.calendarSyncState.displayName, color: color(for: record.calendarSyncState))
                        if record.calendarSyncEnabled {
                            let syncLabel = record.calendarSyncState == .synced ? "已同步系统日历" : "启用系统日历"
                            scheduleBadge(syncLabel, color: TerminalColors.blue)
                        } else {
                            scheduleBadge("仅应用内", color: DesignTokens.Text.tertiary)
                        }
                    }
                }

                Spacer()
            }

            HStack(spacing: DesignTokens.Spacing.sm) {
                Button {
                    Task {
                        await coordinator.startScheduledMeeting(id: record.id)
                        if coordinator.activeMeeting?.state == .recording {
                            withAnimation(.easeInOut(duration: 0.25)) {
                                viewModel.contentType = .meetingLive
                            }
                        }
                    }
                } label: {
                    Text("开始")
                        .font(DesignTokens.Font.caption())
                        .foregroundColor(.white)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 5)
                        .background(Capsule().fill(Color(red: 0.80, green: 0.25, blue: 0.26)))
                }
                .buttonStyle(.plain)
                .disabled(liveMeeting != nil)

                Button {
                    beginEditing(record)
                } label: {
                    Text("编辑")
                        .font(DesignTokens.Font.caption())
                        .foregroundColor(.white)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 5)
                        .background(Capsule().fill(TerminalColors.blue))
                }
                .buttonStyle(.plain)

                if record.calendarSyncEnabled, record.calendarSyncState == .failed, let scheduledAt = record.scheduledAt {
                    Button {
                        Task {
                            await coordinator.updateScheduledMeeting(
                                meetingID: record.id,
                                topic: record.topic,
                                scheduledAt: scheduledAt,
                                durationMinutes: record.durationMinutes,
                                calendarSyncEnabled: true
                            )
                        }
                    } label: {
                        Text("重试日历")
                            .font(DesignTokens.Font.caption())
                            .foregroundColor(.white)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 5)
                            .background(Capsule().fill(TerminalColors.green))
                    }
                    .buttonStyle(.plain)
                }

                Button {
                    Task { await coordinator.deleteScheduledMeeting(id: record.id) }
                } label: {
                    Text("删除")
                        .font(DesignTokens.Font.caption())
                        .foregroundColor(.white)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 5)
                        .background(Capsule().fill(Color(red: 0.76, green: 0.28, blue: 0.31)))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.vertical, 6)
    }

    private func startImmediateMeeting() async {
        let config = MeetingConfig(topic: topic)
        await coordinator.startMeeting(config: config)
        if coordinator.activeMeeting?.state == .recording {
            withAnimation(.easeInOut(duration: 0.25)) {
                viewModel.contentType = .meetingLive
            }
            resetComposer()
        }
    }

    private func uploadTranscriptMedia() {
        guard let sourceURL = openImportPanel(
            allowedContentTypes: [.audio, .movie, .mpeg4Movie, .quickTimeMovie]
        ) else {
            return
        }

        Task {
            if await coordinator.importTranscriptMedia(fileURL: sourceURL, topic: topic) {
                topic = ""
            }
        }
    }

    private func saveScheduledMeeting() async {
        if let editingScheduledMeetingID {
            await coordinator.updateScheduledMeeting(
                meetingID: editingScheduledMeetingID,
                topic: topic,
                scheduledAt: scheduledAt,
                durationMinutes: durationMinutes,
                calendarSyncEnabled: calendarSyncEnabled
            )
        } else {
            await coordinator.scheduleMeeting(
                config: MeetingConfig(
                    topic: topic,
                    createdAt: Date(),
                    scheduledAt: scheduledAt,
                    durationMinutes: durationMinutes,
                    calendarSyncEnabled: calendarSyncEnabled
                )
            )
        }
        resetComposer()
    }

    private func beginEditing(_ record: MeetingRecord) {
        editingScheduledMeetingID = record.id
        topic = record.isTopicUserProvided ? record.topic : ""
        scheduledAt = record.scheduledAt ?? Date().addingTimeInterval(3600)
        durationMinutes = max(record.durationMinutes, 15)
        calendarSyncEnabled = record.calendarSyncEnabled
        showsScheduleComposer = true
    }

    private func resetComposer() {
        topic = ""
        showsScheduleComposer = false
        editingScheduledMeetingID = nil
        scheduledAt = Date().addingTimeInterval(3600)
        durationMinutes = 60
        calendarSyncEnabled = true
    }

    private func scheduledSummary(for record: MeetingRecord) -> String {
        let dateText = record.scheduledAt.map(Self.scheduleDateFormatter.string(from:)) ?? "未设置时间"
        return "\(dateText) · \(max(record.durationMinutes, 1)) 分钟"
    }

    private func scheduleBadge(_ text: String, color: Color) -> some View {
        Text(text)
            .font(DesignTokens.Font.caption())
            .foregroundColor(.white)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(
                Capsule().fill(color)
            )
    }

    private func color(for state: MeetingCalendarSyncState) -> Color {
        switch state {
        case .disabled:
            return DesignTokens.Text.tertiary
        case .pending:
            return TerminalColors.amber
        case .synced:
            return TerminalColors.green
        case .failed:
            return Color(red: 0.76, green: 0.28, blue: 0.31)
        }
    }

    private func openImportPanel(allowedContentTypes: [UTType]) -> URL? {
#if canImport(AppKit)
        MeetingFilePanelPresenter.pickSingleURL(
            allowedContentTypes: allowedContentTypes,
            prompt: "导入",
            message: "选择一个本地音频或视频文件并执行转录"
        )
#else
        return nil
#endif
    }
}

#if canImport(AppKit)
enum MeetingFilePanelPresenter {
    static func pickSingleURL(
        allowedContentTypes: [UTType],
        prompt: String,
        message: String
    ) -> URL? {
        presentPanel { panel in
            panel.allowedContentTypes = allowedContentTypes
            panel.allowsMultipleSelection = false
            panel.canChooseDirectories = false
            panel.canChooseFiles = true
            panel.prompt = prompt
            panel.message = message
            return panel.runModal() == .OK ? panel.url : nil
        }
    }

    static func pickMultipleURLs(
        allowedContentTypes: [UTType],
        allowsOtherFileTypes: Bool,
        message: String? = nil
    ) -> [URL] {
        presentPanel { panel in
            panel.canChooseFiles = true
            panel.canChooseDirectories = false
            panel.allowsMultipleSelection = true
            panel.allowedContentTypes = allowedContentTypes
            panel.allowsOtherFileTypes = allowsOtherFileTypes
            if let message {
                panel.message = message
            }
            return panel.runModal() == .OK ? panel.urls : []
        }
    }

    private static func presentPanel<T>(_ operation: (NSOpenPanel) -> T) -> T {
        let notchWindow = AppDelegate.shared?.windowController?.window
        let shouldRestoreNotch = notchWindow?.isVisible == true
        let notchWasKey = notchWindow?.isKeyWindow == true
        let notchIgnoredMouseEvents = notchWindow?.ignoresMouseEvents ?? true

        if shouldRestoreNotch {
            notchWindow?.orderOut(nil)
        }

        NSApplication.shared.activate(ignoringOtherApps: true)

        let panel = NSOpenPanel()
        defer {
            if shouldRestoreNotch {
                notchWindow?.ignoresMouseEvents = notchIgnoredMouseEvents
                notchWindow?.orderFrontRegardless()
                if notchWasKey {
                    notchWindow?.makeKey()
                }
            }
        }

        return operation(panel)
    }
}
#endif

struct MeetingFieldStyle: TextFieldStyle {
    func _body(configuration: TextField<Self._Label>) -> some View {
        configuration
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: DesignTokens.Radius.lg)
                    .fill(DesignTokens.Surface.base)
                    .overlay(
                        RoundedRectangle(cornerRadius: DesignTokens.Radius.lg)
                            .strokeBorder(DesignTokens.Border.standard, lineWidth: 1)
                    )
            )
            .font(DesignTokens.Font.body())
            .foregroundColor(DesignTokens.Text.primary)
    }
}
