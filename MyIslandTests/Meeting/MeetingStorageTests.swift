import Foundation
import XCTest
@testable import My_Island

final class MeetingStorageTests: XCTestCase {
    func testCreateMeetingPersistsIndexAndRecordDetail() async throws {
        let baseURL = makeTemporaryDirectory()
        let storage = MeetingStorage(baseDirectoryURL: baseURL)
        let createdAt = Date(timeIntervalSince1970: 1_700_000_123)

        let record = try await storage.createMeeting(
            config: MeetingConfig(
                topic: "增长复盘",
                selectedSkillIDs: ["alchaincyf/elon-musk-skill"],
                createdAt: createdAt
            )
        )

        let indexURL = baseURL.appendingPathComponent("meetings.json")
        let detailURL = baseURL
            .appendingPathComponent(record.id, isDirectory: true)
            .appendingPathComponent("record.json")

        XCTAssertTrue(FileManager.default.fileExists(atPath: indexURL.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: detailURL.path))

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        let indexData = try Data(contentsOf: indexURL)
        let all = try decoder.decode([MeetingRecord].self, from: indexData)
        XCTAssertEqual(all.count, 1)
        XCTAssertEqual(all[0].topic, "增长复盘")
        XCTAssertEqual(all[0].selectedSkillIDs, ["alchaincyf/elon-musk-skill"])

        let detailData = try Data(contentsOf: detailURL)
        let detail = try decoder.decode(MeetingRecord.self, from: detailData)
        XCTAssertEqual(detail.id, record.id)
        XCTAssertEqual(detail.state, .recording)
    }

    func testCreateScheduledMeetingPersistsScheduleCalendarAndAnnotationMetadata() async throws {
        let baseURL = makeTemporaryDirectory()
        let storage = MeetingStorage(baseDirectoryURL: baseURL)
        let createdAt = Date(timeIntervalSince1970: 1_700_000_123)
        let scheduledAt = Date(timeIntervalSince1970: 1_700_003_723)

        let record = try await storage.createMeeting(
            config: MeetingConfig(
                topic: "预约评审",
                createdAt: createdAt,
                scheduledAt: scheduledAt,
                durationMinutes: 45,
                calendarSyncEnabled: true
            )
        )

        XCTAssertEqual(record.state, .scheduled)
        XCTAssertEqual(record.scheduledAt, scheduledAt)
        XCTAssertEqual(record.durationMinutes, 45)
        XCTAssertEqual(record.calendarSyncState, .pending)
        XCTAssertTrue(record.calendarSyncEnabled)
        XCTAssertEqual(record.annotations, [])
    }

    func testSavingRecordPreservesFocusAndNoteAnnotations() async throws {
        let baseURL = makeTemporaryDirectory()
        let storage = MeetingStorage(baseDirectoryURL: baseURL)

        var record = try await storage.createMeeting(
            config: MeetingConfig(topic: "产品评审", createdAt: Date(timeIntervalSince1970: 1_700_000_123))
        )
        record.annotations = [
            MeetingAnnotation(
                id: "focus-1",
                kind: .focus,
                createdAt: Date(timeIntervalSince1970: 1_700_000_200),
                timecodeMs: 12_000,
                text: "先把问题定义锁住。",
                sourceSegmentIDs: ["seg-1", "seg-2"],
                source: .recentContext
            ),
            MeetingAnnotation(
                id: "note-1",
                kind: .note,
                createdAt: Date(timeIntervalSince1970: 1_700_000_240),
                timecodeMs: 15_000,
                text: "后续需要补用户证据。",
                sourceSegmentIDs: [],
                source: .manualNote,
                attachments: [
                    MeetingNoteAttachment(
                        id: "attachment-1",
                        kind: .file,
                        displayName: "roadmap.pdf",
                        relativePath: "meeting-assets/roadmap.pdf",
                        extractedMarkdown: "# 路线图\n\n- 收敛问题\n- 确认 owner"
                    )
                ]
            )
        ]

        try await storage.save(record: record)

        let reloaded = await storage.meeting(id: record.id)
        let unwrapped = try XCTUnwrap(reloaded)
        XCTAssertEqual(unwrapped.annotations.count, 2)
        XCTAssertEqual(unwrapped.annotations[0].kind, .focus)
        XCTAssertEqual(unwrapped.annotations[0].sourceSegmentIDs, ["seg-1", "seg-2"])
        XCTAssertEqual(unwrapped.annotations[1].kind, .note)
        XCTAssertEqual(unwrapped.annotations[1].text, "后续需要补用户证据。")
        XCTAssertEqual(unwrapped.annotations[1].attachments.count, 1)
        XCTAssertEqual(unwrapped.annotations[1].attachments[0].displayName, "roadmap.pdf")
        XCTAssertTrue(unwrapped.annotations[1].attachments[0].extractedMarkdown.contains("路线图"))
    }

    func testRelativeAndAbsolutePathRoundTripUnderInjectedBaseDirectory() {
        let baseURL = makeTemporaryDirectory()
        let storage = MeetingStorage(baseDirectoryURL: baseURL)
        let absolute = baseURL.appendingPathComponent("meeting-1/master.wav")

        let relative = storage.relativePath(for: absolute)

        XCTAssertEqual(relative, "meeting-1/master.wav")
        XCTAssertEqual(storage.absolutePath(for: relative), absolute)
    }

    func testCreateMeetingWithBlankTopicMarksRecordAsAutoNamedCandidate() async throws {
        let baseURL = makeTemporaryDirectory()
        let storage = MeetingStorage(baseDirectoryURL: baseURL)

        let record = try await storage.createMeeting(
            config: MeetingConfig(topic: "   ", createdAt: Date(timeIntervalSince1970: 1_700_000_123))
        )

        XCTAssertEqual(record.topic, MeetingRecord.untitledTopicPlaceholder)
        XCTAssertFalse(record.isTopicUserProvided)
    }

    func testLoadingHistoricalUntitledMeetingBackfillsTopicFromSummary() async throws {
        let baseURL = makeTemporaryDirectory()
        let storage = MeetingStorage(baseDirectoryURL: baseURL)
        var components = DateComponents()
        components.calendar = Calendar(identifier: .gregorian)
        components.timeZone = .autoupdatingCurrent
        components.year = 2026
        components.month = 4
        components.day = 11
        components.hour = 9
        let createdAt = components.date ?? Date(timeIntervalSince1970: 0)
        let historicalRecord = MeetingRecord(
            id: "historical-meeting",
            topic: MeetingRecord.untitledTopicPlaceholder,
            isTopicUserProvided: false,
            state: .completed,
            createdAt: createdAt,
            summaryBundle: MeetingSummaryBundle(
                fullSummary: "会议围绕美国住宅VPN方案、VPS采购与浏览器隔离策略展开讨论，重点比较成本与稳定性。",
                source: "memo-lark"
            )
        )

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601

        try FileManager.default.createDirectory(
            at: baseURL.appendingPathComponent(historicalRecord.id, isDirectory: true),
            withIntermediateDirectories: true
        )
        try encoder.encode([historicalRecord]).write(
            to: baseURL.appendingPathComponent("meetings.json"),
            options: [.atomic]
        )
        try encoder.encode(historicalRecord).write(
            to: baseURL
                .appendingPathComponent(historicalRecord.id, isDirectory: true)
                .appendingPathComponent("record.json"),
            options: [.atomic]
        )

        await storage.start()
        let reloaded = await storage.allMeetings()

        XCTAssertEqual(reloaded.first?.topic, "美国住宅VPN方案 2026-04-11")
    }

    func testSavingRecordPersistsImportedMediaMetadata() async throws {
        let baseURL = makeTemporaryDirectory()
        let storage = MeetingStorage(baseDirectoryURL: baseURL)

        var record = try await storage.createMeeting(
            config: MeetingConfig(topic: "导入会议", createdAt: Date(timeIntervalSince1970: 1_700_000_123))
        )
        record.state = .processing
        record.sourceMediaRelativePath = "meeting-assets/source.mov"
        record.sourceMediaKind = .video
        record.sourceMediaDisplayName = "source.mov"
        try await storage.save(record: record)

        let reloaded = await storage.meeting(id: record.id)
        XCTAssertEqual(reloaded?.sourceMediaRelativePath, "meeting-assets/source.mov")
        XCTAssertEqual(reloaded?.sourceMediaKind, .video)
        XCTAssertEqual(reloaded?.sourceMediaDisplayName, "source.mov")
    }

    func testAllMeetingsSortsCompletedRecordsByEndedAt() async throws {
        let baseURL = makeTemporaryDirectory()
        let storage = MeetingStorage(baseDirectoryURL: baseURL)

        var first = try await storage.createMeeting(
            config: MeetingConfig(topic: "更早创建", createdAt: Date(timeIntervalSince1970: 1_700_000_000))
        )
        first.state = .completed
        first.endedAt = Date(timeIntervalSince1970: 1_700_000_600)
        try await storage.save(record: first)

        var second = try await storage.createMeeting(
            config: MeetingConfig(topic: "更晚结束", createdAt: Date(timeIntervalSince1970: 1_699_999_000))
        )
        second.state = .completed
        second.endedAt = Date(timeIntervalSince1970: 1_700_001_000)
        try await storage.save(record: second)

        let meetings = await storage.allMeetings()
        XCTAssertEqual(meetings.map(\.id), [second.id, first.id])
    }

    func testEnsureLocalAudioAssetRecoversMissingWAVFromRawPCM() async throws {
        let baseURL = makeTemporaryDirectory()
        let storage = MeetingStorage(baseDirectoryURL: baseURL)
        let record = try await storage.createMeeting(
            config: MeetingConfig(topic: "恢复录音", createdAt: Date(timeIntervalSince1970: 1_700_000_123))
        )

        let rawURL = try await storage.rawPCMURL(for: record.id)
        try Data([0x00, 0x01, 0x02, 0x03]).write(to: rawURL, options: [.atomic])

        var brokenRecord = record
        brokenRecord.audioRelativePath = "missing/master.wav"

        let recoveredURL = try await storage.ensureLocalAudioAsset(for: brokenRecord)

        let unwrappedURL = try XCTUnwrap(recoveredURL)
        XCTAssertTrue(FileManager.default.fileExists(atPath: unwrappedURL.path))
        let recoveredData = try Data(contentsOf: unwrappedURL)
        XCTAssertEqual(String(decoding: recoveredData.prefix(4), as: UTF8.self), "RIFF")
    }

    private func makeTemporaryDirectory() -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        addTeardownBlock {
            try? FileManager.default.removeItem(at: url)
        }
        return url
    }
}
