import Foundation
import os.log

actor MeetingStorage {
    static let shared = MeetingStorage()
    nonisolated static let logger = Logger(subsystem: "com.myisland", category: "MeetingStorage")

    private let fileManager: FileManager
    nonisolated let baseDirectoryURL: URL
    private var meetings: [MeetingRecord] = []
    private var hasStarted = false

    private let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }()

    private let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()

    init(
        fileManager: FileManager = .default,
        baseDirectoryURL: URL? = nil
    ) {
        self.fileManager = fileManager
        self.baseDirectoryURL = baseDirectoryURL ?? Self.baseDirectoryURL(fileManager: fileManager)
    }

    nonisolated static func baseDirectoryURL(fileManager: FileManager = .default) -> URL {
        let bundleIdentifier = Bundle.main.bundleIdentifier ?? "app.myisland.macos"
        let supportURL = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory())
        return supportURL
            .appendingPathComponent(bundleIdentifier, isDirectory: true)
            .appendingPathComponent("Meetings", isDirectory: true)
    }

    func start() async {
        guard !hasStarted else { return }
        hasStarted = true

        do {
            try ensureDirectories()
            try loadIndex()
            try normalizeLoadedMeetingsIfNeeded()
        } catch {
            Self.logger.error("Failed to start meeting storage: \(error.localizedDescription, privacy: .public)")
            meetings = []
        }
    }

    func allMeetings() async -> [MeetingRecord] {
        await start()
        return meetings.sorted { lhs, rhs in
            let lhsDate = sortDate(for: lhs)
            let rhsDate = sortDate(for: rhs)
            if lhsDate == rhsDate {
                return lhs.id > rhs.id
            }
            return lhsDate > rhsDate
        }
    }

    func meeting(id: String) async -> MeetingRecord? {
        await start()
        return meetings.first(where: { $0.id == id })
    }

    func createMeeting(config: MeetingConfig) async throws -> MeetingRecord {
        await start()

        let trimmedTopic = config.topic.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedDuration = max(config.durationMinutes, 1)
        let calendarSyncState: MeetingCalendarSyncState = {
            guard config.scheduledAt != nil else { return .disabled }
            return config.calendarSyncEnabled ? .pending : .disabled
        }()
        var record = MeetingRecord(
            topic: trimmedTopic.isEmpty ? MeetingRecord.untitledTopicPlaceholder : trimmedTopic,
            isTopicUserProvided: !trimmedTopic.isEmpty,
            state: config.scheduledAt == nil ? .recording : .scheduled,
            createdAt: config.createdAt,
            scheduledAt: config.scheduledAt,
            durationMinutes: normalizedDuration,
            calendarSyncState: calendarSyncState,
            calendarSyncEnabled: config.calendarSyncEnabled,
            selectedSkillIDs: config.selectedSkillIDs,
            autoRecommendedSkillIDs: config.autoRecommendedSkillIDs
        )

        try ensureMeetingDirectory(for: record.id)
        meetings.insert(record, at: 0)
        try persist(record: record)
        return record
    }

    func save(record: MeetingRecord) async throws {
        await start()
        if let index = meetings.firstIndex(where: { $0.id == record.id }) {
            meetings[index] = record
        } else {
            meetings.insert(record, at: 0)
        }
        try persist(record: record)
    }

    func deleteMeeting(id: String) async throws {
        await start()
        meetings.removeAll { $0.id == id }
        try persistIndex()

        let meetingDirectory = meetingDirectoryURL(meetingID: id)
        if fileManager.fileExists(atPath: meetingDirectory.path) {
            try fileManager.removeItem(at: meetingDirectory)
        }
    }

    func recordingURL(for meetingID: String) async throws -> URL {
        try ensureMeetingDirectory(for: meetingID)
        return meetingDirectoryURL(meetingID: meetingID).appendingPathComponent("master.wav")
    }

    func markdownURL(for meetingID: String) async throws -> URL {
        try ensureMeetingDirectory(for: meetingID)
        return meetingDirectoryURL(meetingID: meetingID).appendingPathComponent("meeting.md")
    }

    func rawPCMURL(for meetingID: String) async throws -> URL {
        try ensureMeetingDirectory(for: meetingID)
        return meetingDirectoryURL(meetingID: meetingID).appendingPathComponent("capture.pcm")
    }

    func ensureLocalAudioAsset(for record: MeetingRecord) async throws -> URL? {
        let resolvedWAVURL: URL
        if let relativePath = record.audioRelativePath?.trimmingCharacters(in: .whitespacesAndNewlines),
           !relativePath.isEmpty {
            resolvedWAVURL = absolutePath(for: relativePath)
        } else {
            resolvedWAVURL = try await recordingURL(for: record.id)
        }

        if fileManager.fileExists(atPath: resolvedWAVURL.path) {
            return resolvedWAVURL
        }

        let rawURL = try await rawPCMURL(for: record.id)
        guard fileManager.fileExists(atPath: rawURL.path) else {
            return nil
        }

        let pcmData = try Data(contentsOf: rawURL)
        guard !pcmData.isEmpty else {
            return nil
        }

        let wavData = MeetingPCMConverter.wrapPCM16AsWAV(pcmData, sampleRate: 16000, channels: 1)
        try fileManager.createDirectory(at: resolvedWAVURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try wavData.write(to: resolvedWAVURL, options: [.atomic])
        return resolvedWAVURL
    }

    func transcriptLogURL(for meetingID: String) async throws -> URL {
        try ensureMeetingDirectory(for: meetingID)
        return meetingDirectoryURL(meetingID: meetingID).appendingPathComponent("transcript-live.jsonl")
    }

    func sourceMediaURL(for meetingID: String, preferredFilename: String) async throws -> URL {
        try ensureMeetingDirectory(for: meetingID)
        let directoryURL = importedMediaDirectoryURL(meetingID: meetingID)
        try fileManager.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        return directoryURL.appendingPathComponent("source-\(sanitizeFilename(preferredFilename))")
    }

    func preparedAudioURL(
        for meetingID: String,
        fileExtension: String = "m4a"
    ) async throws -> URL {
        try ensureMeetingDirectory(for: meetingID)
        let directoryURL = importedMediaDirectoryURL(meetingID: meetingID)
        try fileManager.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        let normalizedExtension = fileExtension.trimmingCharacters(in: CharacterSet(charactersIn: "."))
        let effectiveExtension = normalizedExtension.isEmpty ? "m4a" : normalizedExtension
        return directoryURL.appendingPathComponent("prepared-audio.\(effectiveExtension)")
    }

    func attachmentURL(for meetingID: String, preferredFilename: String) async throws -> URL {
        try ensureMeetingDirectory(for: meetingID)
        let directoryURL = attachmentsDirectoryURL(meetingID: meetingID)
        try fileManager.createDirectory(at: directoryURL, withIntermediateDirectories: true)

        let sanitizedFilename = sanitizeFilename(preferredFilename)
        let uniqueFilename = "\(UUID().uuidString)-\(sanitizedFilename)"
        return directoryURL.appendingPathComponent(uniqueFilename)
    }

    func asrDiagnosticsLogURL(for meetingID: String) async throws -> URL {
        try ensureMeetingDirectory(for: meetingID)
        return meetingDirectoryURL(meetingID: meetingID).appendingPathComponent("asr-diagnostics.log")
    }

    func meetingDirectory(meetingID: String) async throws -> URL {
        try ensureMeetingDirectory(for: meetingID)
        return meetingDirectoryURL(meetingID: meetingID)
    }

    func writeMeetingMarkdown(_ markdown: String, meetingID: String) async throws {
        let url = try await markdownURL(for: meetingID)
        try Data(markdown.utf8).write(to: url, options: [.atomic])
    }

    func writeMeetingDiagnosticData(_ data: Data, meetingID: String, filename: String) async throws {
        try ensureMeetingDirectory(for: meetingID)
        let url = meetingDirectoryURL(meetingID: meetingID).appendingPathComponent(filename)
        try data.write(to: url, options: [.atomic])
    }

    nonisolated func relativePath(for absoluteURL: URL) -> String {
        absoluteURL.path.replacingOccurrences(of: baseDirectoryURL.path + "/", with: "")
    }

    nonisolated func absolutePath(for relativePath: String) -> URL {
        baseDirectoryURL.appendingPathComponent(relativePath)
    }

    // MARK: - Persistence

    private var indexURL: URL {
        baseDirectoryURL.appendingPathComponent("meetings.json")
    }

    private func ensureDirectories() throws {
        try fileManager.createDirectory(at: baseDirectoryURL, withIntermediateDirectories: true)
    }

    private func ensureMeetingDirectory(for meetingID: String) throws {
        try fileManager.createDirectory(at: meetingDirectoryURL(meetingID: meetingID), withIntermediateDirectories: true)
    }

    private func meetingDirectoryURL(meetingID: String) -> URL {
        baseDirectoryURL.appendingPathComponent(meetingID, isDirectory: true)
    }

    private func attachmentsDirectoryURL(meetingID: String) -> URL {
        meetingDirectoryURL(meetingID: meetingID).appendingPathComponent("Attachments", isDirectory: true)
    }

    private func importedMediaDirectoryURL(meetingID: String) -> URL {
        meetingDirectoryURL(meetingID: meetingID).appendingPathComponent("ImportedMedia", isDirectory: true)
    }

    private func recordURL(for meetingID: String) -> URL {
        meetingDirectoryURL(meetingID: meetingID).appendingPathComponent("record.json")
    }

    private func persist(record: MeetingRecord) throws {
        try persistIndex()

        let detailData = try encoder.encode(record)
        try detailData.write(to: recordURL(for: record.id), options: [.atomic])
    }

    private func loadIndex() throws {
        guard fileManager.fileExists(atPath: indexURL.path) else {
            meetings = []
            return
        }

        let data = try Data(contentsOf: indexURL)
        meetings = try decoder.decode([MeetingRecord].self, from: data)
    }

    private func persistIndex() throws {
        let data = try encoder.encode(meetings)
        try data.write(to: indexURL, options: [.atomic])
    }

    private func normalizeLoadedMeetingsIfNeeded() throws {
        var changedRecords: [MeetingRecord] = []

        for index in meetings.indices {
            guard shouldBackfillTopic(for: meetings[index]) else { continue }
            meetings[index].topic = MeetingAutoTitleBuilder.buildTitle(for: meetings[index])
            changedRecords.append(meetings[index])
        }

        guard !changedRecords.isEmpty else { return }

        try persistIndex()
        for record in changedRecords {
            let detailData = try encoder.encode(record)
            try detailData.write(to: recordURL(for: record.id), options: [.atomic])
        }
    }

    private func shouldBackfillTopic(for record: MeetingRecord) -> Bool {
        guard !record.isTopicUserProvided else { return false }
        guard MeetingRecord.isUntitledPlaceholder(record.topic) else { return false }

        if let summaryBundle = record.summaryBundle {
            let summaryText = summaryBundle.fullSummary.trimmingCharacters(in: .whitespacesAndNewlines)
            if !summaryText.isEmpty || !summaryBundle.chapterSummaries.isEmpty || !summaryBundle.processHighlights.isEmpty {
                return true
            }
        }

        return !record.transcript.isEmpty
    }

    private func sortDate(for record: MeetingRecord) -> Date {
        switch record.state {
        case .scheduled:
            return record.scheduledAt ?? record.createdAt
        case .completed, .failed, .processing:
            return record.endedAt ?? record.createdAt
        case .recording, .draft:
            return record.createdAt
        }
    }

    private func sanitizeFilename(_ filename: String) -> String {
        let trimmed = filename.trimmingCharacters(in: .whitespacesAndNewlines)
        let fallback = "attachment"
        let base = trimmed.isEmpty ? fallback : trimmed
        let invalidCharacters = CharacterSet(charactersIn: "/:\\?%*|\"<>")
        let sanitized = base.unicodeScalars.map { scalar in
            invalidCharacters.contains(scalar) ? "-" : String(scalar)
        }.joined()
        return sanitized.isEmpty ? fallback : sanitized
    }
}
