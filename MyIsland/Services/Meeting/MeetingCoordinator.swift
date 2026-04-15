import Combine
import Foundation
import os.log
#if canImport(AppKit)
import AppKit
#endif

@MainActor
final class MeetingCoordinator: ObservableObject {
    static let shared = MeetingCoordinator()
    static let automaticAdviceStartupDelay: TimeInterval = 60
    private static let automaticAdviceStartupDelayNanoseconds: UInt64 = 60_000_000_000
    nonisolated static let systemAudioPermissionFallbackMessage = "系统录音未启用，已回退到仅麦克风。请在系统设置 > 隐私与安全性 > 屏幕与系统音频录制中允许 My Island。"

    private let logger = Logger(subsystem: "com.myisland", category: "Meeting")

    @Published private(set) var activeMeeting: MeetingRecord?
    @Published private(set) var recentMeetings: [MeetingRecord] = []
    @Published private(set) var catalogEntries: [MeetingSkillCatalogEntry] = []
    @Published private(set) var installedSkills: [MeetingSkillInstall] = []
    @Published private(set) var userSubagents: [MeetingSkillSubagent] = []
    @Published private(set) var activeAdviceCards: [MeetingAdviceCard] = []
    @Published private(set) var isRefreshingCatalog = false
    @Published private(set) var isSyncingCatalogSkills = false
    @Published private(set) var skillCatalogStatusText: String?
    @Published private(set) var lastOperationError: String?
    @Published private(set) var audioInputModeError: String?
    @Published private(set) var realtimeASRState: MeetingRealtimeASRState = .idle
    @Published private(set) var realtimeASRMessage: String?
    @Published private(set) var isGeneratingThinking = false
    @Published private(set) var isImportingTranscriptMedia = false
    @Published private(set) var isImportingNoteAttachment = false

    let audioCapture = MeetingAudioCaptureCoordinator()
    let settings = MeetingSettingsStore.shared

    private var ruleCooldowns: [String: Date] = [:]
    private var postProcessingTasks: [String: Task<Void, Never>] = [:]
    private var meetingStartThinkingTask: Task<Void, Never>?
    private var activeASRDiagnosticsURL: URL?
    private var silenceDetector = MeetingSilenceDetector()

    // MARK: - Live transcript aggregation state
    //
    // Doubao streaming ASR emits segments at *word* granularity — each short
    // fragment ("哈", "喽", "一", "二", …) arrives as its own `definite=true`
    // utterance with its own start_time. Rendering each of those as a new
    // transcript row produces the "token-by-token" UX the user complained
    // about. We need to aggregate consecutive fragments from the same speaker
    // into a single sentence row, closing the sentence only when:
    //   • the speaker changes (implicit — each speaker has its own bucket),
    //   • the silence gap since the last fragment exceeds `sentenceGapMs`, or
    //   • the accumulated text ends with a sentence terminator (。！？.!?…).
    private struct PendingSentence {
        var rowID: String
        var text: String
        var startTimeMs: Int
        var endTimeMs: Int
        var speakerLabel: String
        /// Last activity timestamp for gap detection. Tracks the latest
        /// `endTimeMs` we've seen for this speaker's ongoing sentence.
        var latestEndMs: Int
    }
    private var pendingSentenceBySpeaker: [String: PendingSentence] = [:]
    private static let sentenceGapMs = 1_200
    private static let sentenceTerminators: Set<Character> = [
        "。", "！", "？", ".", "!", "?", "…"
    ]
    private let transcriptLogEncoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }()

    private init() {
        Task { [weak self] in
            await self?.bootstrap()
        }
    }

    func bootstrap() async {
        await MeetingStorage.shared.start()
        await MeetingSkillCatalogService.shared.start()
        await reloadMeetings()
        await reloadInstalledSkills()
        await reloadUserSubagents()

        // Re-register reminders for every meeting that's still in the
        // .scheduled state. This handles the cold-start case where the user
        // opened My Island after rebooting — pending Timer objects would
        // otherwise be lost.
        MeetingScheduleReminder.shared.requestNotificationAuthorizationIfNeeded()
        MeetingScheduleReminder.shared.reconcile(with: recentMeetings)

        let cached = await MeetingSkillCatalogService.shared.cachedCatalog()
        catalogEntries = cached
        if cached.isEmpty {
            await refreshCatalog()
        } else {
            await syncCatalogInstalls(entries: cached, force: false)
        }
    }

    func reloadMeetings() async {
        recentMeetings = await MeetingStorage.shared.allMeetings()
    }

    func reloadInstalledSkills() async {
        installedSkills = await MeetingSkillCatalogService.shared.currentInstalledSkills()
    }

    func reloadUserSubagents() async {
        userSubagents = await MeetingSkillCatalogService.shared.currentUserSubagents()
    }

    func clearLastOperationError() {
        lastOperationError = nil
    }

    func clearAudioInputModeError() {
        audioInputModeError = nil
    }

    static func shouldAllowAdviceTrigger(
        reason: MeetingThinkingReason,
        meetingStartedAt: Date,
        now: Date = Date()
    ) -> Bool {
        switch reason {
        case .manual:
            return true
        case .silence, .meetingStart, .rule(_):
            return now.timeIntervalSince(meetingStartedAt) >= automaticAdviceStartupDelay
        }
    }

    nonisolated static func audioInputModeFallbackErrorMessage(
        requestedMode: MeetingAudioInputMode,
        effectiveMode: MeetingAudioInputMode
    ) -> String? {
        switch (requestedMode, effectiveMode) {
        case (.systemOnly, .microphoneOnly),
             (.microphoneAndSystem, .microphoneOnly):
            return systemAudioPermissionFallbackMessage
        default:
            return nil
        }
    }

    func refreshCatalog() async {
        isRefreshingCatalog = true
        isSyncingCatalogSkills = true
        defer {
            isRefreshingCatalog = false
            isSyncingCatalogSkills = false
        }

        do {
            let result = try await MeetingSkillCatalogService.shared.refreshCatalogAndSyncInstalls(force: false)
            applyCatalogSyncResult(result)
        } catch {
            lastOperationError = error.localizedDescription
        }
    }

    @discardableResult
    func installSkill(_ entry: MeetingSkillCatalogEntry) async -> Bool {
        do {
            _ = try await MeetingSkillCatalogService.shared.install(entry: entry)
            await reloadInstalledSkills()
            lastOperationError = nil
            return true
        } catch {
            lastOperationError = error.localizedDescription
            return false
        }
    }

    @discardableResult
    func uninstallSkill(id: String) async -> Bool {
        do {
            try await MeetingSkillCatalogService.shared.removeInstall(id: id)
            await reloadInstalledSkills()
            lastOperationError = nil
            return true
        } catch {
            lastOperationError = error.localizedDescription
            return false
        }
    }

    @discardableResult
    func importGitHubSkills(repoURL: String) async -> Bool {
        do {
            let installs = try await MeetingSkillCatalogService.shared.importGitHubRepository(repoURL: repoURL)
            await reloadInstalledSkills()
            await reloadUserSubagents()
            lastOperationError = nil
            skillCatalogStatusText = "已导入 \(installs.count) 个 Skill"
            return true
        } catch {
            lastOperationError = error.localizedDescription
            return false
        }
    }

    @discardableResult
    func createUserSubagent(name: String, description: String) async -> Bool {
        do {
            _ = try await MeetingSkillCatalogService.shared.createUserSubagent(name: name, description: description)
            await reloadUserSubagents()
            lastOperationError = nil
            return true
        } catch {
            lastOperationError = error.localizedDescription
            return false
        }
    }

    @discardableResult
    func deleteUserSubagent(id: String) async -> Bool {
        do {
            try await MeetingSkillCatalogService.shared.deleteUserSubagent(id: id)
            await reloadUserSubagents()
            lastOperationError = nil
            return true
        } catch {
            lastOperationError = error.localizedDescription
            return false
        }
    }

    @discardableResult
    func createCustomSkill(
        subagentID: String,
        name: String,
        description: String,
        skillMarkdown: String
    ) async -> Bool {
        do {
            _ = try await MeetingSkillCatalogService.shared.createCustomSkill(
                subagentID: subagentID,
                name: name,
                description: description,
                skillMarkdown: skillMarkdown
            )
            await reloadInstalledSkills()
            await reloadUserSubagents()
            lastOperationError = nil
            return true
        } catch {
            lastOperationError = error.localizedDescription
            return false
        }
    }

    @discardableResult
    func updateCustomSkill(
        id: String,
        subagentID: String,
        name: String,
        description: String,
        skillMarkdown: String
    ) async -> Bool {
        do {
            _ = try await MeetingSkillCatalogService.shared.updateCustomSkill(
                id: id,
                subagentID: subagentID,
                name: name,
                description: description,
                skillMarkdown: skillMarkdown
            )
            await reloadInstalledSkills()
            await reloadUserSubagents()
            lastOperationError = nil
            return true
        } catch {
            lastOperationError = error.localizedDescription
            return false
        }
    }

    func recommendedSkillIDs(for topic: String) -> [String] {
        MeetingAdviceEngine.recommendSkillIDs(topic: topic, installedSkills: installedSkills)
    }

    func scheduleMeeting(config: MeetingConfig) async {
        do {
            var effectiveConfig = config
            if effectiveConfig.autoRecommendedSkillIDs.isEmpty {
                effectiveConfig.autoRecommendedSkillIDs = recommendedSkillIDs(for: effectiveConfig.topic)
            }

            var record = try await MeetingStorage.shared.createMeeting(config: effectiveConfig)
            record = await syncCalendar(record: record)
            try await persist(record: record, keepActiveMeeting: false, refreshRecentMeetings: true)
            MeetingScheduleReminder.shared.register(meeting: record)
            if record.calendarSyncState == .synced || !record.calendarSyncEnabled {
                lastOperationError = nil
            }
        } catch {
            lastOperationError = error.localizedDescription
        }
    }

    func updateScheduledMeeting(
        meetingID: String,
        topic: String,
        scheduledAt: Date,
        durationMinutes: Int,
        calendarSyncEnabled: Bool
    ) async {
        guard var record = await MeetingStorage.shared.meeting(id: meetingID) else { return }
        guard record.state == .scheduled else { return }

        let trimmedTopic = topic.trimmingCharacters(in: .whitespacesAndNewlines)
        record.topic = trimmedTopic.isEmpty ? MeetingRecord.untitledTopicPlaceholder : trimmedTopic
        record.isTopicUserProvided = !trimmedTopic.isEmpty
        record.scheduledAt = scheduledAt
        record.durationMinutes = max(durationMinutes, 1)
        record.calendarSyncEnabled = calendarSyncEnabled

        record = await syncCalendar(record: record)

        do {
            try await persist(record: record, keepActiveMeeting: false, refreshRecentMeetings: true)
            // Re-register reminders to pick up the new scheduledAt — the
            // helper internally cancels the previous timers first.
            MeetingScheduleReminder.shared.register(meeting: record)
            if record.calendarSyncState == .synced || !record.calendarSyncEnabled {
                lastOperationError = nil
            }
        } catch {
            lastOperationError = error.localizedDescription
        }
    }

    func deleteScheduledMeeting(id: String) async {
        guard let record = await MeetingStorage.shared.meeting(id: id) else { return }
        await MeetingCalendarService.shared.remove(eventIdentifier: record.calendarEventIdentifier)
        MeetingScheduleReminder.shared.cancel(meetingID: id)
        do {
            try await MeetingStorage.shared.deleteMeeting(id: id)
            await reloadMeetings()
            lastOperationError = nil
        } catch {
            lastOperationError = error.localizedDescription
        }
    }

    func startScheduledMeeting(id: String) async {
        guard var record = await MeetingStorage.shared.meeting(id: id) else { return }
        guard record.state == .scheduled else { return }

        // Once the user actually starts recording, suppress any pending
        // reminders for this meeting — they'd be noise after the fact.
        MeetingScheduleReminder.shared.cancel(meetingID: id)

        resetLiveSessionState()

        do {
            if record.autoRecommendedSkillIDs.isEmpty {
                record.autoRecommendedSkillIDs = recommendedSkillIDs(for: record.topic)
            }
            record.state = .recording
            record.createdAt = Date()
            record.endedAt = nil
            record.lastError = nil
            _ = try await beginRecordingSession(record: record)
        } catch {
            await handleRecordingStartFailure(error)
        }
    }

    func startMeeting(config: MeetingConfig) async {
        if let activeMeeting, activeMeeting.isActive {
            return
        }

        resetLiveSessionState()

        do {
            var effectiveConfig = config
            if effectiveConfig.autoRecommendedSkillIDs.isEmpty {
                effectiveConfig.autoRecommendedSkillIDs = recommendedSkillIDs(for: effectiveConfig.topic)
            }
            let record = try await MeetingStorage.shared.createMeeting(config: effectiveConfig)
            _ = try await beginRecordingSession(record: record)
        } catch {
            await handleRecordingStartFailure(error)
        }
    }

    func stopMeeting() async {
        guard var record = activeMeeting, record.state == .recording else { return }
        meetingStartThinkingTask?.cancel()
        meetingStartThinkingTask = nil

        do {
            let finalWAVURL = try await MeetingStorage.shared.recordingURL(for: record.id)
            try await audioCapture.stopCapture(finalWAVURL: finalWAVURL)
            await DoubaoStreamingASRClient.shared.stop()
        } catch {
            record.lastError = error.localizedDescription
        }

        audioCapture.onMixedPCMChunk = nil
        audioInputModeError = nil
        realtimeASRState = .idle
        realtimeASRMessage = nil
        pendingSentenceBySpeaker.removeAll(keepingCapacity: false)

        record.state = .processing
        record.endedAt = Date()
        activeMeeting = record
        do {
            try await persist(record: record, keepActiveMeeting: true, refreshRecentMeetings: true)
        } catch {
            lastOperationError = error.localizedDescription
        }

        enqueuePostMeetingAnalysis(meetingID: record.id)
    }

    func retryPostAnalysis(meetingID: String) async {
        guard var record = await MeetingStorage.shared.meeting(id: meetingID) else { return }
        record.state = .processing
        record.lastError = nil
        record.notes.append("手动重跑总结：\(ISO8601DateFormatter().string(from: Date()))")
        do {
            try await persist(record: record, keepActiveMeeting: activeMeeting?.id == meetingID, refreshRecentMeetings: true)
        } catch {
            lastOperationError = error.localizedDescription
        }
        enqueuePostMeetingAnalysis(
            meetingID: meetingID,
            forceSummaryRefresh: true,
            forceTranscriptRefresh: true
        )
    }

    @discardableResult
    func importTranscriptMedia(fileURL: URL, topic: String) async -> Bool {
        guard fileURL.isFileURL else {
            lastOperationError = "只支持上传本地音频或视频文件。"
            return false
        }
        guard settings.objectStorageConfig.isConfigured else {
            lastOperationError = "请先在会议设置中配置对象存储（TOS + STS），上传转录需要先把音频上传到可访问地址。"
            return false
        }
        guard settings.memoConfig.isConfigured else {
            lastOperationError = "请先在会议设置中配置豆包妙记 submit/query，上传转录才能执行离线转录。"
            return false
        }
        guard !isImportingTranscriptMedia else {
            return false
        }

        isImportingTranscriptMedia = true
        defer { isImportingTranscriptMedia = false }

        let resolvedTopic = importedMeetingTopic(for: fileURL, override: topic)
        let meetingID = UUID().uuidString

        do {
            let importedAsset = try await MeetingImportedTranscriptPreparationService.shared.prepareImport(
                from: fileURL,
                meetingID: meetingID
            )
            let totalSeconds = max(1, Int(ceil(importedAsset.durationSeconds)))
            let finishedAt = Date()
            let startedAt = finishedAt.addingTimeInterval(-Double(totalSeconds))
            let markdownURL = try await MeetingStorage.shared.markdownURL(for: meetingID)

            var record = MeetingRecord(
                id: meetingID,
                topic: resolvedTopic,
                isTopicUserProvided: !topic.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                state: .processing,
                createdAt: startedAt,
                endedAt: finishedAt,
                audioRelativePath: MeetingStorage.shared.relativePath(for: importedAsset.preparedAudioURL),
                sourceMediaRelativePath: MeetingStorage.shared.relativePath(for: importedAsset.sourceMediaURL),
                sourceMediaKind: importedAsset.sourceKind,
                sourceMediaDisplayName: importedAsset.displayName,
                markdownRelativePath: MeetingStorage.shared.relativePath(for: markdownURL),
                durationMinutes: max(1, Int(ceil(importedAsset.durationSeconds / 60.0))),
                autoRecommendedSkillIDs: recommendedSkillIDs(for: resolvedTopic)
            )
            record.notes.append("已从本地\(importedAsset.sourceKind.displayName)导入转录：\(importedAsset.displayName)")

            try await persist(record: record, keepActiveMeeting: false, refreshRecentMeetings: true)
            lastOperationError = nil
            enqueuePostMeetingAnalysis(meetingID: meetingID)
            return true
        } catch {
            lastOperationError = error.localizedDescription
            return false
        }
    }

    func openMeeting(id: String) async -> MeetingRecord? {
        await MeetingStorage.shared.meeting(id: id)
    }

    func triggerManualThinking() async {
        await triggerThinking(reason: .manual)
    }

    func captureRecentFocus() async {
        guard var record = activeMeeting, record.state == .recording else { return }
        guard let annotation = recentContextAnnotation(for: record) else { return }

        if record.annotations.contains(where: { existing in
            existing.kind == .focus
                && existing.source == .recentContext
                && existing.sourceSegmentIDs == annotation.sourceSegmentIDs
        }) {
            return
        }

        record.annotations.append(annotation)
        do {
            try await persist(record: record, keepActiveMeeting: true)
        } catch {
            lastOperationError = error.localizedDescription
        }
    }

    func toggleFocus(segmentID: String) async {
        guard var record = activeMeeting, record.state == .recording else { return }

        if let index = record.annotations.firstIndex(where: {
            $0.kind == .focus && $0.source == .transcriptSegment && $0.sourceSegmentIDs == [segmentID]
        }) {
            record.annotations.remove(at: index)
        } else {
            guard let segment = record.transcript.first(where: { $0.id == segmentID }) else { return }
            record.annotations.append(
                MeetingAnnotation(
                    kind: .focus,
                    createdAt: Date(),
                    timecodeMs: max(0, segment.startTimeMs),
                    text: segment.text,
                    sourceSegmentIDs: [segmentID],
                    source: .transcriptSegment
                )
            )
        }

        do {
            try await persist(record: record, keepActiveMeeting: true)
        } catch {
            lastOperationError = error.localizedDescription
        }
    }

    func addNote(_ text: String, linkedSegmentID: String? = nil) async {
        guard var record = activeMeeting, record.state == .recording else { return }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        if let linkedSegmentID,
           record.noteAnnotations.contains(where: { $0.sourceSegmentIDs.contains(linkedSegmentID) }) {
            return
        }

        record.annotations.append(
            makeNoteAnnotation(
                record: record,
                text: trimmed,
                source: .manualNote,
                linkedSegmentID: linkedSegmentID
            )
        )

        do {
            try await persist(record: record, keepActiveMeeting: true)
        } catch {
            lastOperationError = error.localizedDescription
        }
    }

    func addNoteAttachments(
        from sourceURLs: [URL],
        preferredKind: MeetingNoteAttachmentKind,
        text: String = "",
        linkedSegmentID: String? = nil
    ) async {
        await importNoteAttachments(
            from: sourceURLs,
            preferredKind: preferredKind,
            text: text,
            source: .attachmentImport,
            linkedSegmentID: linkedSegmentID
        )
    }

    func captureScreenshotNote(text: String = "", linkedSegmentID: String? = nil) async {
#if canImport(AppKit)
        guard let activeMeeting, activeMeeting.state == .recording else { return }
        isImportingNoteAttachment = true
        defer { isImportingNoteAttachment = false }

        let temporaryURL = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("myisland-meeting-shot-\(UUID().uuidString).png")
        defer {
            try? FileManager.default.removeItem(at: temporaryURL)
        }

        let result = await ProcessExecutor.shared.runWithResult(
            "/usr/sbin/screencapture",
            arguments: ["-i", temporaryURL.path]
        )
        if case .failure(let error) = result, !FileManager.default.fileExists(atPath: temporaryURL.path) {
            if case .executionFailed(_, _, _) = error {
                return
            }
            lastOperationError = error.localizedDescription
            return
        }

        guard FileManager.default.fileExists(atPath: temporaryURL.path),
              let fileAttributes = try? FileManager.default.attributesOfItem(atPath: temporaryURL.path),
              let fileSize = fileAttributes[.size] as? NSNumber,
              fileSize.intValue > 0 else {
            return
        }

        await importNoteAttachments(
            from: [temporaryURL],
            preferredKind: .screenshot,
            text: text,
            source: .screenshotCapture,
            linkedSegmentID: linkedSegmentID
        )
#endif
    }

    func updateAudioInputMode(_ inputMode: MeetingAudioInputMode) async {
        let effectiveMode: MeetingAudioInputMode
        if activeMeeting?.state == .recording {
            effectiveMode = await audioCapture.updateInputMode(inputMode)
        } else {
            effectiveMode = inputMode
        }
        settings.audioInputMode = effectiveMode
        audioInputModeError = Self.audioInputModeFallbackErrorMessage(
            requestedMode: inputMode,
            effectiveMode: effectiveMode
        )
    }

    func openAudioCapturePermissionSettings() {
#if canImport(AppKit)
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") else {
            return
        }
        NSWorkspace.shared.open(url)
#endif
    }

    func isTranscriptFocused(_ segmentID: String, in meeting: MeetingRecord) -> Bool {
        meeting.focusAnnotations.contains { annotation in
            annotation.sourceSegmentIDs.contains(segmentID)
        }
    }

    func isTranscriptNoted(_ segmentID: String, in meeting: MeetingRecord) -> Bool {
        meeting.noteAnnotations.contains { annotation in
            annotation.sourceSegmentIDs.contains(segmentID)
        }
    }

    private func resetLiveSessionState() {
        activeMeeting = nil
        activeAdviceCards = []
        lastOperationError = nil
        audioInputModeError = nil
        realtimeASRState = .idle
        realtimeASRMessage = nil
        activeASRDiagnosticsURL = nil
        isGeneratingThinking = false
        meetingStartThinkingTask?.cancel()
        meetingStartThinkingTask = nil
        silenceDetector.reset()
        ruleCooldowns.removeAll()
    }

    private func beginRecordingSession(record: MeetingRecord) async throws -> MeetingRecord {
        var record = record
        let finalWAVURL = try await MeetingStorage.shared.recordingURL(for: record.id)
        let rawPCMURL = try await MeetingStorage.shared.rawPCMURL(for: record.id)
        let transcriptLogURL = try await MeetingStorage.shared.transcriptLogURL(for: record.id)
        let markdownURL = try await MeetingStorage.shared.markdownURL(for: record.id)
        let asrDiagnosticsURL = try await MeetingStorage.shared.asrDiagnosticsLogURL(for: record.id)

        record.audioRelativePath = MeetingStorage.shared.relativePath(for: finalWAVURL)
        record.markdownRelativePath = MeetingStorage.shared.relativePath(for: markdownURL)
        silenceDetector.begin(at: record.createdAt)
        activeMeeting = record
        activeASRDiagnosticsURL = asrDiagnosticsURL
        pendingSentenceBySpeaker.removeAll(keepingCapacity: true)
        try await resetASRDiagnosticsLog()
        try await persist(record: record, keepActiveMeeting: true, refreshRecentMeetings: true)

        if settings.streamingConfig.isConfigured {
            realtimeASRState = .connecting
            realtimeASRMessage = "实时字幕连接中"
            try await appendASRDiagnostic("connecting.start")

            do {
                try await DoubaoStreamingASRClient.shared.start(
                    config: settings.streamingConfig,
                    onEvent: { [weak self] event in
                        Task { @MainActor [weak self] in
                            await self?.handleRealtimeASREvent(event)
                        }
                    },
                    onSegments: { [weak self] segments in
                        Task { @MainActor [weak self] in
                            await self?.ingestLiveSegments(segments)
                        }
                    }
                )
            } catch {
                realtimeASRState = .failed
                realtimeASRMessage = humanReadableASRMessage(for: error.localizedDescription)
                try await appendASRDiagnostic("connecting.failed \(error.localizedDescription)")
            }
        } else {
            realtimeASRState = .failed
            realtimeASRMessage = "实时字幕未配置，已继续本地录音"
            try await appendASRDiagnostic("config.missing")
        }

        audioCapture.onMixedPCMChunk = { [weak self] data in
            Task { @MainActor [weak self] in
                await self?.handleMixedPCMChunk(data)
            }
        }

        let requestedAudioInputMode = settings.audioInputMode
        let effectiveAudioInputMode = try await audioCapture.startCapture(
            rawPCMURL: rawPCMURL,
            transcriptLogURL: transcriptLogURL,
            inputMode: requestedAudioInputMode
        )
        settings.audioInputMode = effectiveAudioInputMode
        audioInputModeError = Self.audioInputModeFallbackErrorMessage(
            requestedMode: requestedAudioInputMode,
            effectiveMode: effectiveAudioInputMode
        )

        scheduleMeetingStartThinking()
        return record
    }

    private func syncCalendar(record: MeetingRecord) async -> MeetingRecord {
        var updated = record

        guard updated.state == .scheduled else {
            updated.calendarSyncState = updated.calendarSyncEnabled ? .pending : .disabled
            return updated
        }

        guard updated.calendarSyncEnabled else {
            await MeetingCalendarService.shared.remove(eventIdentifier: updated.calendarEventIdentifier)
            updated.calendarEventIdentifier = nil
            updated.calendarSyncState = .disabled
            return updated
        }

        let result = await MeetingCalendarService.shared.sync(record: updated)
        updated.calendarEventIdentifier = result.eventIdentifier
        updated.calendarSyncState = result.state
        if let errorMessage = result.errorMessage, !errorMessage.isEmpty {
            lastOperationError = errorMessage
        }
        return updated
    }

    private func recentContextAnnotation(for record: MeetingRecord) -> MeetingAnnotation? {
        let segments = record.transcript
            .filter { $0.isFinal && !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            .sorted { lhs, rhs in
                if lhs.startTimeMs == rhs.startTimeMs {
                    return lhs.endTimeMs < rhs.endTimeMs
                }
                return lhs.startTimeMs < rhs.startTimeMs
            }

        guard let latest = segments.last else { return nil }

        var selected = [latest]
        for segment in segments.dropLast().reversed() {
            if selected.count >= 2 {
                break
            }
            if latest.endTimeMs - segment.startTimeMs <= 30_000 {
                selected.insert(segment, at: 0)
            }
        }

        return MeetingAnnotation(
            kind: .focus,
            createdAt: Date(),
            timecodeMs: selected.first?.startTimeMs ?? latest.startTimeMs,
            text: selected.map(\.text).joined(separator: "\n"),
            sourceSegmentIDs: selected.map(\.id),
            source: .recentContext
        )
    }

    private func handleRecordingStartFailure(_ error: Error) async {
        meetingStartThinkingTask?.cancel()
        meetingStartThinkingTask = nil
        audioCapture.onMixedPCMChunk = nil
        await DoubaoStreamingASRClient.shared.stop()
        realtimeASRState = .failed
        realtimeASRMessage = error.localizedDescription
        lastOperationError = error.localizedDescription
        audioInputModeError = nil

        if var record = activeMeeting {
            record.state = .failed
            record.lastError = error.localizedDescription
            try? await persist(record: record, keepActiveMeeting: false, refreshRecentMeetings: true)
        }
        activeMeeting = nil
        pendingSentenceBySpeaker.removeAll(keepingCapacity: false)
    }

    // MARK: - Live segment aggregation

    /// Collapses Doubao's word-level segments into one sentence row per
    /// speaker. The server emits a stream of short `definite=true` utterances
    /// (often 1–3 characters each) plus a growing `definite=false` hypothesis
    /// of the active utterance; rendering each of those as its own transcript
    /// row produces a token-by-token UX. This method rewrites the incoming
    /// segment so that all fragments belonging to the same sentence share the
    /// same row id, text, and time range. A new row is opened only when:
    ///
    ///   1. the speaker changes (each speaker has its own bucket),
    ///   2. the gap since the last fragment > `sentenceGapMs`, or
    ///   3. the accumulated text already ended with a sentence terminator.
    ///
    /// When the server omits `speaker_id`, unknown-speaker segments are still
    /// aggregated under the `"speaker_unknown"` key so the UI falls back to
    /// "说话人1" instead of the unnumbered "说话人".
    private func normalizeSegmentForAggregation(_ segment: TranscriptSegment) -> TranscriptSegment {
        var incoming = segment
        if incoming.speakerLabel == nil {
            incoming.speakerLabel = "speaker_unknown"
        }
        let speakerKey = incoming.speakerLabel ?? "speaker_unknown"

        let shouldStartNew: Bool
        if let pending = pendingSentenceBySpeaker[speakerKey] {
            let gap = incoming.startTimeMs - pending.latestEndMs
            let endsWithTerminator = pending.text.last
                .map { Self.sentenceTerminators.contains($0) } ?? false
            shouldStartNew = gap > Self.sentenceGapMs || endsWithTerminator
        } else {
            shouldStartNew = true
        }

        if shouldStartNew {
            let fresh = PendingSentence(
                rowID: incoming.id,
                text: incoming.text,
                startTimeMs: incoming.startTimeMs,
                endTimeMs: incoming.endTimeMs,
                speakerLabel: speakerKey,
                latestEndMs: max(incoming.endTimeMs, incoming.startTimeMs)
            )
            pendingSentenceBySpeaker[speakerKey] = fresh
            return incoming
        }

        // Merge into the pending sentence for this speaker.
        var pending = pendingSentenceBySpeaker[speakerKey]!
        pending.text = Self.mergeSentenceText(existing: pending.text, incoming: incoming.text)
        pending.endTimeMs = max(pending.endTimeMs, incoming.endTimeMs)
        pending.latestEndMs = max(pending.latestEndMs, incoming.endTimeMs)
        pendingSentenceBySpeaker[speakerKey] = pending

        // Rewrite the outgoing segment so the ingest loop upserts into the
        // same transcript row as all other fragments of this sentence.
        incoming.id = pending.rowID
        incoming.text = pending.text
        incoming.startTimeMs = pending.startTimeMs
        incoming.endTimeMs = pending.endTimeMs
        return incoming
    }

    /// Decides how to combine an incoming text fragment with the existing
    /// pending-sentence text. Handles three cases:
    ///
    /// 1. The incoming text is a *refinement* of the pending text (common
    ///    when the server re-emits a growing hypothesis): if the incoming
    ///    starts with the pending text or shares a sufficient prefix AND is
    ///    longer, it *replaces* the pending text.
    /// 2. The pending text already contains the incoming text as a suffix:
    ///    return pending unchanged to avoid double-appending.
    /// 3. Otherwise append, inserting a space only when needed for Latin
    ///    scripts (CJK adjacency does not require spacing).
    private static func mergeSentenceText(existing: String, incoming: String) -> String {
        guard !incoming.isEmpty else { return existing }
        guard !existing.isEmpty else { return incoming }

        if incoming.count > existing.count,
           incoming.hasPrefix(existing) {
            return incoming
        }
        if existing.hasSuffix(incoming) || existing.contains(incoming) {
            return existing
        }

        // Share a 2+ character prefix AND incoming is longer → treat as
        // refined hypothesis replacing prior partial.
        if incoming.count > existing.count {
            let commonPrefixLength = zip(existing, incoming)
                .prefix(while: { $0 == $1 }).count
            if commonPrefixLength >= 2 {
                return incoming
            }
        }

        let needsSpace: Bool = {
            guard let lastExisting = existing.last,
                  let firstIncoming = incoming.first else { return false }
            return !isCJK(lastExisting) && !isCJK(firstIncoming)
        }()
        return existing + (needsSpace ? " " : "") + incoming
    }

    private static func isCJK(_ character: Character) -> Bool {
        character.unicodeScalars.contains { scalar in
            (0x4E00...0x9FFF).contains(scalar.value) ||
                (0x3040...0x30FF).contains(scalar.value) ||
                (0xAC00...0xD7AF).contains(scalar.value)
        }
    }

    private func scheduleMeetingStartThinking() {
        meetingStartThinkingTask?.cancel()
        meetingStartThinkingTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: Self.automaticAdviceStartupDelayNanoseconds)
            guard !Task.isCancelled else { return }
            await self?.triggerThinking(reason: .meetingStart)
        }
    }

    private func ingestLiveSegments(_ segments: [TranscriptSegment]) async {
        guard var record = activeMeeting else { return }

        var changed = false
        for rawSegment in segments {
            // Collapse incremental partials into a single ongoing row per speaker.
            // Without this, each ASR frame (definite=false) creates a new row
            // because the fallback segment id embeds `start_time`, which changes
            // between partials.
            let segment = normalizeSegmentForAggregation(rawSegment)

            if let transcriptIndex = record.transcript.firstIndex(where: { $0.id == segment.id }) {
                if record.transcript[transcriptIndex] != segment {
                    record.transcript[transcriptIndex] = segment
                    changed = true
                }
            } else {
                record.transcript.append(segment)
                changed = true
            }

            let span = SpeakerSpan(
                id: segment.id,
                speakerLabel: segment.speakerLabel ?? "speaker_unknown",
                startTimeMs: segment.startTimeMs,
                endTimeMs: segment.endTimeMs,
                gender: segment.gender,
                speechRate: segment.speechRate,
                volume: segment.volume,
                emotion: segment.emotion
            )

            if let spanIndex = record.speakerSpans.firstIndex(where: { $0.id == segment.id }) {
                if record.speakerSpans[spanIndex] != span {
                    record.speakerSpans[spanIndex] = span
                    changed = true
                }
            } else {
                record.speakerSpans.append(span)
                changed = true
            }
        }

        guard changed else { return }

        record.transcript = MeetingMarkdownRenderer.canonicalTranscript(from: record.transcript)
        record.speakerSpans.sort { $0.startTimeMs < $1.startTimeMs }

        do {
            try await persist(record: record, keepActiveMeeting: true)
            try await appendTranscriptLog(segments)
        } catch {
            logger.error("Failed to persist live transcript: \(error.localizedDescription, privacy: .public)")
        }

        await evaluateAdviceIfNeeded(record: record)
    }

    private func handleRealtimeASREvent(_ event: DoubaoStreamingASRClient.Event) async {
        switch event {
        case .connecting(let connectID):
            realtimeASRState = .connecting
            realtimeASRMessage = "实时字幕连接中"
            try? await appendASRDiagnostic("connecting \(connectID)")
        case .requestSent:
            realtimeASRState = .ready
            realtimeASRMessage = "实时字幕已连接"
            try? await appendASRDiagnostic("request.sent")
        case .ready:
            realtimeASRState = .ready
            realtimeASRMessage = "实时字幕已连接"
            try? await appendASRDiagnostic("session.ready")
        case .audioBuffered(let bytes, let totalBytes):
            try? await appendASRDiagnostic("audio.buffered bytes=\(bytes) total=\(totalBytes)")
        case .firstAudioSent(let bytes):
            try? await appendASRDiagnostic("audio.first_sent bytes=\(bytes)")
        case .audioSent(let bytes, let isLast):
            try? await appendASRDiagnostic("audio.sent bytes=\(bytes) last=\(isLast)")
        case .receiving:
            realtimeASRState = .receiving
            realtimeASRMessage = "实时字幕识别中"
            try? await appendASRDiagnostic("response.first_received")
        case .responsePayload(let summary):
            try? await appendASRDiagnostic("response.payload \(summary)")
        case .segmentsReceived(let count):
            realtimeASRState = .receiving
            realtimeASRMessage = "实时字幕识别中"
            try? await appendASRDiagnostic("response.segments count=\(count)")
        case .failed(_, let message):
            realtimeASRState = .failed
            realtimeASRMessage = humanReadableASRMessage(for: message)
            try? await appendASRDiagnostic("failed \(message)")
        case .closed(let reason):
            try? await appendASRDiagnostic("closed \(reason)")
        }
    }

    private func handleMixedPCMChunk(_ data: Data) async {
        if settings.streamingConfig.isConfigured && realtimeASRState != .failed {
            do {
                try await DoubaoStreamingASRClient.shared.appendAudioChunk(data)
            } catch {
                logger.warning("Failed to send ASR audio chunk: \(error.localizedDescription, privacy: .public)")
            }
        }

        if silenceDetector.processPCM16(data), !isGeneratingThinking {
            await triggerThinking(reason: .silence)
        }
    }

    private func evaluateAdviceIfNeeded(record: MeetingRecord) async {
        guard !isGeneratingThinking else { return }
        let context = MeetingAdviceEngine.buildTriggerContext(from: record.transcript)
        let firedRules = MeetingAdviceEngine.firedRules(context: context)
        guard let rule = firedRules.first(where: { shouldFire($0) }) else { return }
        guard Self.shouldAllowAdviceTrigger(reason: .rule(rule), meetingStartedAt: record.createdAt) else { return }

        isGeneratingThinking = true
        defer { isGeneratingThinking = false }

        let generatedCards = await MeetingAdviceEngine.generateAdviceCards(
            topic: record.topic,
            triggerRule: rule,
            recentSegments: record.transcript,
            installedSkills: installedSkills,
            selectedSkillIDs: record.effectiveSkillIDs,
            config: settings.agentModelConfig
        )
        guard let card = generatedCards.first else { return }

        ruleCooldowns[rule.id] = Date()
        activeAdviceCards = [card] + activeAdviceCards

        var updated = record
        updated.adviceCards.insert(card, at: 0)
        try? await persist(record: updated, keepActiveMeeting: true)
    }

    private func triggerThinking(reason: MeetingThinkingReason) async {
        guard var record = activeMeeting, record.state == .recording, !isGeneratingThinking else { return }
        guard Self.shouldAllowAdviceTrigger(reason: reason, meetingStartedAt: record.createdAt) else { return }

        isGeneratingThinking = true
        defer { isGeneratingThinking = false }

        let meetingMarkdown = renderMeetingMarkdown(for: record)
        let cards = await MeetingAdviceEngine.generateThinkingCards(
            topic: record.topic,
            reason: reason,
            meetingMarkdown: meetingMarkdown,
            recentSegments: record.transcript,
            installedSkills: installedSkills,
            selectedSkillIDs: record.selectedSkillIDs,
            autoRecommendedSkillIDs: record.autoRecommendedSkillIDs,
            config: settings.agentModelConfig
        )
        guard !cards.isEmpty else { return }

        activeAdviceCards = cards + activeAdviceCards
        record.adviceCards.insert(contentsOf: cards, at: 0)
        try? await persist(record: record, keepActiveMeeting: true)
    }

    private func shouldFire(_ rule: MeetingTriggerRule) -> Bool {
        MeetingAdviceEngine.shouldFire(rule: rule, lastFiredAt: ruleCooldowns[rule.id])
    }

    private func appendTranscriptLog(_ segments: [TranscriptSegment]) async throws {
        guard let record = activeMeeting else { return }
        let logURL = try await MeetingStorage.shared.transcriptLogURL(for: record.id)
        if !FileManager.default.fileExists(atPath: logURL.path) {
            FileManager.default.createFile(atPath: logURL.path, contents: Data())
        }

        let handle = try FileHandle(forWritingTo: logURL)
        try handle.seekToEnd()
        for segment in segments {
            let data = try transcriptLogEncoder.encode(segment)
            try handle.write(contentsOf: data)
            try handle.write(contentsOf: Data([0x0A]))
        }
        try handle.close()
    }

    private func resetASRDiagnosticsLog() async throws {
        guard let activeASRDiagnosticsURL else { return }
        let created = FileManager.default.createFile(atPath: activeASRDiagnosticsURL.path, contents: Data())
        if !created, FileManager.default.fileExists(atPath: activeASRDiagnosticsURL.path) {
            try Data().write(to: activeASRDiagnosticsURL, options: [.atomic])
        }
    }

    private func appendASRDiagnostic(_ message: String) async throws {
        guard let activeASRDiagnosticsURL else { return }
        if !FileManager.default.fileExists(atPath: activeASRDiagnosticsURL.path) {
            FileManager.default.createFile(atPath: activeASRDiagnosticsURL.path, contents: Data())
        }

        let line = "\(ISO8601DateFormatter().string(from: Date())) \(message)\n"
        let handle = try FileHandle(forWritingTo: activeASRDiagnosticsURL)
        try handle.seekToEnd()
        try handle.write(contentsOf: Data(line.utf8))
        try handle.close()
    }

    private func runPostMeetingAnalysis(
        meetingID: String,
        forceSummaryRefresh: Bool,
        forceTranscriptRefresh: Bool
    ) async {
        guard !Task.isCancelled else { return }
        guard var record = await MeetingStorage.shared.meeting(id: meetingID) else { return }
        if record.autoRecommendedSkillIDs.isEmpty {
            record.autoRecommendedSkillIDs = recommendedSkillIDs(for: record.topic)
        }

        await refreshImportedAudioIfNeeded(for: &record, forceTranscriptRefresh: forceTranscriptRefresh)
        let audioURL = await recoverLocalAudioIfNeeded(for: &record)
        let processed = await MeetingPostProcessingEngine.shared.process(
            record: record,
            localAudioURL: audioURL,
            installedSkills: installedSkills,
            objectStorageConfig: settings.objectStorageConfig,
            memoConfig: settings.memoConfig,
            agentConfig: settings.agentModelConfig,
            forceSummaryRefresh: forceSummaryRefresh,
            forceTranscriptRefresh: forceTranscriptRefresh
        )

        do {
            try await persist(record: processed, keepActiveMeeting: false, refreshRecentMeetings: true)
            if activeMeeting?.id == meetingID {
                activeMeeting = nil
                activeAdviceCards = []
            }
        } catch {
            lastOperationError = error.localizedDescription
        }
    }

    private func enqueuePostMeetingAnalysis(
        meetingID: String,
        forceSummaryRefresh: Bool = false,
        forceTranscriptRefresh: Bool = false
    ) {
        postProcessingTasks[meetingID]?.cancel()
        postProcessingTasks[meetingID] = Task { [weak self] in
            guard let self else { return }
            await self.runPostMeetingAnalysis(
                meetingID: meetingID,
                forceSummaryRefresh: forceSummaryRefresh,
                forceTranscriptRefresh: forceTranscriptRefresh
            )
            await MainActor.run {
                self.postProcessingTasks.removeValue(forKey: meetingID)
            }
        }
    }

    private func refreshImportedAudioIfNeeded(
        for record: inout MeetingRecord,
        forceTranscriptRefresh: Bool
    ) async {
        guard record.sourceMediaRelativePath?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false else {
            return
        }

        let currentAudioRelativePath = record.audioRelativePath?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let currentAudioIsWAV = currentAudioRelativePath.lowercased().hasSuffix(".wav")
        let currentAudioExists: Bool = {
            guard !currentAudioRelativePath.isEmpty else {
                return false
            }
            let currentAudioURL = MeetingStorage.shared.absolutePath(for: currentAudioRelativePath)
            return FileManager.default.fileExists(atPath: currentAudioURL.path)
        }()

        guard forceTranscriptRefresh || !currentAudioIsWAV || !currentAudioExists else {
            return
        }

        do {
            guard let preparedAudioURL = try await MeetingImportedTranscriptPreparationService.shared.reprepareAudio(for: record) else {
                return
            }
            let preparedAudioRelativePath = MeetingStorage.shared.relativePath(for: preparedAudioURL)
            let audioChanged = preparedAudioRelativePath != currentAudioRelativePath || !currentAudioIsWAV

            record.audioRelativePath = preparedAudioRelativePath
            if audioChanged {
                record.uploadedAudioObjectKey = nil
                record.uploadedAudioRemoteURL = nil
                record.notes.append("已重新生成兼容离线转录的 WAV 音频。")
            }
        } catch {
            record.notes.append("重新生成导入转录音频失败：\(error.localizedDescription)")
        }
    }

    private func recoverLocalAudioIfNeeded(for record: inout MeetingRecord) async -> URL? {
        let expectedAudioURL: URL? = {
            guard let relativePath = record.audioRelativePath?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !relativePath.isEmpty else {
                return nil
            }
            return MeetingStorage.shared.absolutePath(for: relativePath)
        }()
        let missingAudioBeforeRecovery = expectedAudioURL.map { !FileManager.default.fileExists(atPath: $0.path) } ?? false

        do {
            let recoveredAudioURL = try await MeetingStorage.shared.ensureLocalAudioAsset(for: record)
            if let recoveredAudioURL,
               expectedAudioURL?.path != recoveredAudioURL.path {
                record.audioRelativePath = MeetingStorage.shared.relativePath(for: recoveredAudioURL)
            }
            if missingAudioBeforeRecovery,
               let expectedAudioURL,
               let recoveredAudioURL,
               FileManager.default.fileExists(atPath: recoveredAudioURL.path) {
                record.notes.append("检测到 \(expectedAudioURL.lastPathComponent) 缺失，已恢复本地录音文件。")
            }
            return recoveredAudioURL
        } catch {
            record.notes.append("恢复本地录音文件失败：\(error.localizedDescription)")
            return expectedAudioURL.flatMap { url in
                FileManager.default.fileExists(atPath: url.path) ? url : nil
            }
        }
    }

    private func persist(
        record: MeetingRecord,
        keepActiveMeeting: Bool,
        refreshRecentMeetings: Bool = false
    ) async throws {
        if record.state != .scheduled {
            let markdown = renderMeetingMarkdown(for: record)
            try await MeetingStorage.shared.writeMeetingMarkdown(markdown, meetingID: record.id)
        }
        try await MeetingStorage.shared.save(record: record)
        if keepActiveMeeting {
            activeMeeting = record
        }
        if refreshRecentMeetings {
            await reloadMeetings()
        }
    }

    private func renderMeetingMarkdown(for record: MeetingRecord) -> String {
        MeetingMarkdownRenderer.render(record: record, installedSkills: installedSkills)
    }

    private func syncCatalogInstalls(entries: [MeetingSkillCatalogEntry], force: Bool) async {
        isSyncingCatalogSkills = true
        defer { isSyncingCatalogSkills = false }

        do {
            let result = try await MeetingSkillCatalogService.shared.syncCatalogInstalls(entries: entries, force: force)
            applyCatalogSyncResult(result)
        } catch {
            lastOperationError = error.localizedDescription
        }
    }

    private func applyCatalogSyncResult(_ result: MeetingSkillCatalogSyncResult) {
        catalogEntries = result.catalogEntries
        installedSkills = result.installedSkills

        let unavailableCount = result.unsupportedRepoFullNames.count
        let failedCount = result.failedRepoErrors.count
        var parts = ["已本地化 \(result.installedSkills.count)/\(result.installableCatalogCount) 个兼容 skill"]
        if unavailableCount > 0 {
            parts.append("\(unavailableCount) 个不兼容")
        }
        if failedCount > 0 {
            parts.append("\(failedCount) 个待重试")
        }
        skillCatalogStatusText = parts.joined(separator: " · ")
    }

    private func humanReadableASRMessage(for rawMessage: String) -> String {
        if rawMessage.localizedCaseInsensitiveContains("quota exceeded for types: concurrency") {
            return "实时字幕不可用：豆包流式并发额度已耗尽，请增购并发或切换到已开通的实时资源。"
        }
        if rawMessage.localizedCaseInsensitiveContains("access denied") {
            return "实时字幕不可用：当前资源没有调用权限，请检查豆包控制台授权。"
        }
        if rawMessage.localizedCaseInsensitiveContains("requested grant not found") {
            return "实时字幕不可用：鉴权失败，请检查 App ID、Access Token 和 Resource ID。"
        }
        return "实时字幕不可用：\(rawMessage)"
    }

    private func importNoteAttachments(
        from sourceURLs: [URL],
        preferredKind: MeetingNoteAttachmentKind,
        text: String,
        source: MeetingAnnotationSource,
        linkedSegmentID: String?
    ) async {
        guard var record = activeMeeting, record.state == .recording else { return }
        let validURLs = sourceURLs.filter { $0.isFileURL }
        guard !validURLs.isEmpty else { return }
        if let linkedSegmentID,
           record.noteAnnotations.contains(where: { $0.sourceSegmentIDs.contains(linkedSegmentID) }) {
            return
        }

        isImportingNoteAttachment = true
        defer { isImportingNoteAttachment = false }

        var attachments: [MeetingNoteAttachment] = []
        var importFailures: [String] = []

        for sourceURL in validURLs {
            do {
                let attachment = try await importAttachment(
                    from: sourceURL,
                    preferredKind: preferredKind,
                    meetingID: record.id
                )
                attachments.append(attachment)
            } catch {
                importFailures.append("\(sourceURL.lastPathComponent)：\(error.localizedDescription)")
            }
        }

        guard !attachments.isEmpty else {
            if !importFailures.isEmpty {
                lastOperationError = importFailures.joined(separator: "\n")
            }
            return
        }

        record.annotations.append(
            makeNoteAnnotation(
                record: record,
                text: text,
                source: source,
                attachments: attachments,
                linkedSegmentID: linkedSegmentID
            )
        )

        do {
            try await persist(record: record, keepActiveMeeting: true)
            lastOperationError = importFailures.isEmpty ? nil : importFailures.joined(separator: "\n")
        } catch {
            lastOperationError = error.localizedDescription
        }
    }

    private func importAttachment(
        from sourceURL: URL,
        preferredKind: MeetingNoteAttachmentKind,
        meetingID: String
    ) async throws -> MeetingNoteAttachment {
        let destinationURL = try await MeetingStorage.shared.attachmentURL(
            for: meetingID,
            preferredFilename: sourceURL.lastPathComponent
        )
        try FileManager.default.copyItem(at: sourceURL, to: destinationURL)

        let markdown: String
        do {
            markdown = try await MeetingMarkItDownService.shared.convert(fileURL: destinationURL)
        } catch {
            markdown = fallbackAttachmentMarkdown(for: destinationURL, error: error)
        }

        return MeetingNoteAttachment(
            kind: inferAttachmentKind(for: destinationURL, preferredKind: preferredKind),
            displayName: sourceURL.lastPathComponent,
            relativePath: MeetingStorage.shared.relativePath(for: destinationURL),
            extractedMarkdown: markdown
        )
    }

    private func makeNoteAnnotation(
        record: MeetingRecord,
        text: String,
        source: MeetingAnnotationSource,
        attachments: [MeetingNoteAttachment] = [],
        linkedSegmentID: String? = nil
    ) -> MeetingAnnotation {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let annotationText: String
        if !trimmed.isEmpty {
            annotationText = trimmed
        } else if attachments.count == 1, let attachment = attachments.first {
            annotationText = "附件：\(attachment.displayName)"
        } else if !attachments.isEmpty {
            annotationText = "附件：\(attachments.count) 个文件"
        } else {
            annotationText = ""
        }

        let linkedSegment = linkedSegmentID.flatMap { segmentID in
            record.transcript.first(where: { $0.id == segmentID })
        }
        let timecodeMs = linkedSegment?.startTimeMs
            ?? record.transcript.last?.endTimeMs
            ?? max(0, Int(Date().timeIntervalSince(record.createdAt) * 1_000))
        let annotationSource = linkedSegment == nil ? source : .transcriptComment
        return MeetingAnnotation(
            kind: .note,
            createdAt: Date(),
            timecodeMs: timecodeMs,
            text: annotationText,
            sourceSegmentIDs: linkedSegment.map { [$0.id] } ?? [],
            source: annotationSource,
            attachments: attachments
        )
    }

    private func inferAttachmentKind(
        for fileURL: URL,
        preferredKind: MeetingNoteAttachmentKind
    ) -> MeetingNoteAttachmentKind {
        if preferredKind == .screenshot {
            return .screenshot
        }

        let imageExtensions: Set<String> = ["png", "jpg", "jpeg", "gif", "heic", "webp", "tiff", "bmp"]
        if imageExtensions.contains(fileURL.pathExtension.lowercased()) {
            return .image
        }
        return preferredKind
    }

    private func fallbackAttachmentMarkdown(for fileURL: URL, error: Error) -> String {
        if let text = try? String(contentsOf: fileURL, encoding: .utf8) {
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty {
                return trimmed
            }
        }

        return """
        > MarkItDown 转换失败：\(error.localizedDescription)
        > 原文件：\(fileURL.lastPathComponent)
        """
    }

    private func importedMeetingTopic(for fileURL: URL, override rawTopic: String) -> String {
        let trimmed = rawTopic.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty {
            return trimmed
        }

        let filename = fileURL.deletingPathExtension().lastPathComponent
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return filename.isEmpty ? MeetingRecord.untitledTopicPlaceholder : filename
    }
}
