import Foundation
import XCTest
@testable import My_Island

final class MeetingIdentityTests: XCTestCase {
    func testSavingUpdatedMeetingDoesNotCreateDuplicateHistoryItems() async throws {
        let baseURL = makeTemporaryDirectory()
        let storage = MeetingStorage(baseDirectoryURL: baseURL)

        var record = try await storage.createMeeting(
            config: MeetingConfig(topic: "产品评审", createdAt: Date(timeIntervalSince1970: 1_700_000_000))
        )
        record.state = .completed
        record.endedAt = Date(timeIntervalSince1970: 1_700_000_600)
        try await storage.save(record: record)

        let meetings = await storage.allMeetings()
        XCTAssertEqual(meetings.count, 1)
        XCTAssertEqual(meetings[0].id, record.id)
        XCTAssertEqual(meetings[0].state, .completed)
    }

    func testStartingSameTopicTwiceCreatesTwoDistinctMeetings() async throws {
        let baseURL = makeTemporaryDirectory()
        let storage = MeetingStorage(baseDirectoryURL: baseURL)

        let first = try await storage.createMeeting(
            config: MeetingConfig(topic: "增长复盘", createdAt: Date(timeIntervalSince1970: 1_700_000_000))
        )
        var completedFirst = first
        completedFirst.state = .completed
        try await storage.save(record: completedFirst)

        let second = try await storage.createMeeting(
            config: MeetingConfig(topic: "增长复盘", createdAt: Date(timeIntervalSince1970: 1_700_000_120))
        )

        let meetings = await storage.allMeetings()
        XCTAssertEqual(meetings.count, 2)
        XCTAssertNotEqual(first.id, second.id)
        XCTAssertEqual(Set(meetings.map(\.id)), Set([first.id, second.id]))
    }

    func testProcessingMeetingDoesNotBlockStartingNextMeeting() {
        let processingMeeting = MeetingRecord(
            topic: "会后处理中",
            state: .processing,
            createdAt: Date(timeIntervalSince1970: 1_700_000_000)
        )

        XCTAssertFalse(processingMeeting.isActive)
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
