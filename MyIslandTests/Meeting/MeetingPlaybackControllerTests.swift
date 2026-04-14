import Foundation
import XCTest
@testable import My_Island

final class MeetingPlaybackControllerTests: XCTestCase {
    func testResolvePrefersExistingLocalAudioFile() throws {
        let tempDirectory = makeTemporaryDirectory()
        let audioURL = tempDirectory.appendingPathComponent("meeting/master.wav")
        try FileManager.default.createDirectory(at: audioURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("wave".utf8).write(to: audioURL)

        let record = MeetingRecord(
            id: "meeting-1",
            topic: "本地录音会议",
            state: .completed,
            createdAt: Date(),
            audioRelativePath: "meeting/master.wav",
            uploadedAudioRemoteURL: "https://example.com/fallback.wav"
        )

        let asset = MeetingPlayableAsset.resolve(
            for: record,
            resolveRelativePath: { relativePath in
                tempDirectory.appendingPathComponent(relativePath)
            }
        )

        XCTAssertEqual(asset?.source, .localFile)
        XCTAssertEqual(asset?.url, audioURL)
    }

    func testResolveFallsBackToRemoteURLWhenLocalAudioMissing() {
        let record = MeetingRecord(
            id: "meeting-1",
            topic: "远端录音会议",
            state: .completed,
            createdAt: Date(),
            audioRelativePath: "meeting/missing.wav",
            uploadedAudioRemoteURL: "https://example.com/fallback.wav"
        )

        let asset = MeetingPlayableAsset.resolve(
            for: record,
            resolveRelativePath: { _ in
                URL(fileURLWithPath: "/tmp/definitely-missing.wav")
            }
        )

        XCTAssertEqual(asset?.source, .remoteURL)
        XCTAssertEqual(asset?.url.absoluteString, "https://example.com/fallback.wav")
    }

    func testResolveReturnsNilWhenNoPlayableAssetExists() {
        let record = MeetingRecord(
            id: "meeting-1",
            topic: "空会议",
            state: .completed,
            createdAt: Date()
        )

        XCTAssertNil(MeetingPlayableAsset.resolve(for: record))
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
