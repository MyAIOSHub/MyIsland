import Foundation
import XCTest
@testable import My_Island

final class MeetingAgentPackTests: XCTestCase {
    func testPackStoreLoadsManifestRuntimeSkillsAndRooms() throws {
        let directory = makeTemporaryDirectory()
        try FileManager.default.createDirectory(
            at: directory.appendingPathComponent("runtime-skills", isDirectory: true),
            withIntermediateDirectories: true
        )
        try FileManager.default.createDirectory(
            at: directory.appendingPathComponent("agora-rooms", isDirectory: true),
            withIntermediateDirectories: true
        )

        let manifest = MeetingAgentPackManifest(
            runtimeSkills: [
                MeetingRuntimeSkillDefinition(
                    id: "meeting-socratic",
                    title: "Socratic",
                    summary: "Question assumptions.",
                    relativePath: "runtime-skills/meeting-socratic.md",
                    sourceRefs: ["skillcollection/ljg-learn"],
                    tags: ["questioning"]
                )
            ],
            agoraRooms: [
                MeetingAgoraRoomDefinition(
                    room: .forge,
                    title: "Forge",
                    summary: "Pressure-test the discussion.",
                    relativePath: "agora-rooms/forge.md"
                )
            ]
        )

        let manifestData = try JSONEncoder().encode(manifest)
        try manifestData.write(to: directory.appendingPathComponent("manifest.json"))
        try "# Socratic".write(
            to: directory.appendingPathComponent("runtime-skills/meeting-socratic.md"),
            atomically: true,
            encoding: .utf8
        )
        try "# Forge".write(
            to: directory.appendingPathComponent("agora-rooms/forge.md"),
            atomically: true,
            encoding: .utf8
        )

        let store = MeetingAgentPackStore(packDirectoryURL: directory)

        XCTAssertEqual(store.runtimeSkillDefinitions.map(\.id), ["meeting-socratic"])
        XCTAssertEqual(store.runtimeSkillDocument(for: "meeting-socratic"), "# Socratic")
        XCTAssertEqual(store.agoraRoomDocument(for: .forge), "# Forge")
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
