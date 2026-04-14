import Foundation
import XCTest
@testable import My_Island

final class MeetingSkillImportTests: XCTestCase {
    func testInstallSnapshotPersistsSkillFilesAndMetadata() async throws {
        let baseURL = makeTemporaryDirectory()
        let service = MeetingSkillCatalogService(baseDirectoryURL: baseURL)
        let entry = MeetingSkillCatalogEntry(
            category: "Personas",
            title: "Elon Musk Skill",
            repoURL: "https://github.com/alchaincyf/elon-musk-skill",
            repoFullName: "alchaincyf/elon-musk-skill",
            description: "First principles",
            sourceIndexURL: "https://example.com/index"
        )

        let install = try await service.installSnapshot(
            entry: entry,
            defaultBranch: "main",
            skillMarkdown: "# SKILL\nThink from first principles.",
            readmeMarkdown: "# README",
            installedAt: Date(timeIntervalSince1970: 1_700_000_000)
        )

        let skillURL = baseURL
            .appendingPathComponent("Skills", isDirectory: true)
            .appendingPathComponent("alchaincyf__elon-musk-skill", isDirectory: true)
            .appendingPathComponent("SKILL.md")
        let readmeURL = baseURL
            .appendingPathComponent("Skills", isDirectory: true)
            .appendingPathComponent("alchaincyf__elon-musk-skill", isDirectory: true)
            .appendingPathComponent("README.md")

        XCTAssertEqual(install.repoFullName, "alchaincyf/elon-musk-skill")
        XCTAssertEqual(install.defaultBranch, "main")
        XCTAssertTrue(FileManager.default.fileExists(atPath: skillURL.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: readmeURL.path))

        let persisted = await service.currentInstalledSkills()
        XCTAssertEqual(persisted.map(\.id), ["alchaincyf/elon-musk-skill"])
    }

    func testInstallSnapshotRejectsEmptySkillMarkdown() async throws {
        let service = MeetingSkillCatalogService(baseDirectoryURL: makeTemporaryDirectory())
        let entry = MeetingSkillCatalogEntry(
            category: "Personas",
            title: "Broken Skill",
            repoURL: "https://github.com/example/broken-skill",
            repoFullName: "example/broken-skill",
            description: "Broken",
            sourceIndexURL: "https://example.com/index"
        )

        await XCTAssertThrowsErrorAsync {
            _ = try await service.installSnapshot(
                entry: entry,
                defaultBranch: "main",
                skillMarkdown: "   ",
                readmeMarkdown: nil,
                installedAt: .distantPast
            )
        } verify: { error in
            guard case MeetingSkillCatalogService.SkillCatalogError.missingSkillFile(let repo) = error else {
                return XCTFail("Expected missingSkillFile, got \(error)")
            }
            XCTAssertEqual(repo, "example/broken-skill")
        }
    }

    func testSyncCatalogInstallsAllSupportedSkillsAndMarksUnsupportedEntries() async throws {
        let baseURL = makeTemporaryDirectory()
        let session = makeStubSession()
        StubURLProtocol.requestedURLs = []
        StubURLProtocol.handlers = [
            "https://api.github.com/repos/example/alpha-skill": .json(["default_branch": "main"]),
            "https://raw.githubusercontent.com/example/alpha-skill/main/SKILL.md": .text("# SKILL\nAlpha advice."),
            "https://raw.githubusercontent.com/example/alpha-skill/main/README.md": .text("# Alpha"),
            "https://api.github.com/repos/example/beta-skill": .json(["default_branch": "main"]),
            "https://raw.githubusercontent.com/example/beta-skill/main/SKILL.md": .status(404),
            "https://api.github.com/repos/example/gamma-skill": .json(["default_branch": "main"]),
            "https://raw.githubusercontent.com/example/gamma-skill/main/SKILL.md": .text("# SKILL\nGamma advice."),
            "https://raw.githubusercontent.com/example/gamma-skill/main/README.md": .status(404)
        ]

        let service = MeetingSkillCatalogService(session: session, baseDirectoryURL: baseURL)
        let entries = [
            makeEntry(repoFullName: "example/alpha-skill", title: "Alpha Skill"),
            makeEntry(repoFullName: "example/beta-skill", title: "Beta Skill"),
            makeEntry(repoFullName: "example/gamma-skill", title: "Gamma Skill")
        ]

        let result = try await service.syncCatalogInstalls(entries: entries)

        XCTAssertEqual(result.installedSkills.map(\.repoFullName).sorted(), ["example/alpha-skill", "example/gamma-skill"])
        XCTAssertEqual(result.newlyInstalledRepoFullNames.sorted(), ["example/alpha-skill", "example/gamma-skill"])
        XCTAssertEqual(result.unsupportedRepoFullNames, ["example/beta-skill"])
        XCTAssertEqual(result.catalogEntries.map(\.repoFullName), ["example/alpha-skill", "example/beta-skill", "example/gamma-skill"])
        XCTAssertEqual(result.catalogEntries.map(\.isInstallable), [true, false, true])

        let persisted = await service.currentInstalledSkills()
        XCTAssertEqual(persisted.map(\.repoFullName).sorted(), ["example/alpha-skill", "example/gamma-skill"])
    }

    func testSyncCatalogSkipsAlreadyInstalledSkillsWhenNotForced() async throws {
        let baseURL = makeTemporaryDirectory()
        let session = makeStubSession()
        let service = MeetingSkillCatalogService(session: session, baseDirectoryURL: baseURL)
        let entry = makeEntry(repoFullName: "example/existing-skill", title: "Existing Skill")

        _ = try await service.installSnapshot(
            entry: entry,
            defaultBranch: "main",
            skillMarkdown: "# SKILL\nExisting advice.",
            readmeMarkdown: "# README",
            installedAt: Date(timeIntervalSince1970: 1_700_000_000)
        )

        StubURLProtocol.requestedURLs = []
        StubURLProtocol.handlers = [:]

        let result = try await service.syncCatalogInstalls(entries: [entry], force: false)

        XCTAssertEqual(result.installedSkills.map(\.repoFullName), ["example/existing-skill"])
        XCTAssertTrue(result.newlyInstalledRepoFullNames.isEmpty)
        XCTAssertTrue(result.unsupportedRepoFullNames.isEmpty)
        XCTAssertTrue(StubURLProtocol.requestedURLs.isEmpty)
    }

    func testImportGitHubRepositorySupportsRootSkillLayout() async throws {
        let baseURL = makeTemporaryDirectory()
        let session = makeStubSession()
        StubURLProtocol.requestedURLs = []
        StubURLProtocol.handlers = [
            "https://api.github.com/repos/example/root-skill": .json(["default_branch": "main"]),
            "https://api.github.com/repos/example/root-skill/contents/skills?ref=main": .status(404),
            "https://raw.githubusercontent.com/example/root-skill/main/SKILL.md": .text("# Root Skill\nDirect repo skill body."),
            "https://raw.githubusercontent.com/example/root-skill/main/README.md": .text("# README")
        ]

        let service = MeetingSkillCatalogService(session: session, baseDirectoryURL: baseURL)
        let installs = try await service.importGitHubRepository(
            repoURL: "https://github.com/example/root-skill"
        )

        XCTAssertEqual(installs.count, 1)
        XCTAssertEqual(installs[0].sourceKind, .imported)
        XCTAssertEqual(installs[0].subagentID, "imported:example__root-skill")
        XCTAssertEqual(installs[0].subagentName, "root-skill")
        XCTAssertTrue(installs[0].skillRelativePath.contains("Skills/imported/example__root-skill/root"))
    }

    func testImportGitHubRepositorySupportsSkillsPackLayout() async throws {
        let baseURL = makeTemporaryDirectory()
        let session = makeStubSession()
        StubURLProtocol.requestedURLs = []
        StubURLProtocol.handlers = [
            "https://api.github.com/repos/dontbesilent2025/claude-skills": .json(["default_branch": "main"]),
            "https://api.github.com/repos/dontbesilent2025/claude-skills/contents/skills?ref=main": .text("""
            [
              {"name":"first-principles","path":"skills/first-principles","type":"dir"},
              {"name":"roundtable","path":"skills/roundtable","type":"dir"}
            ]
            """),
            "https://raw.githubusercontent.com/dontbesilent2025/claude-skills/main/skills/first-principles/SKILL.md": .text("# First Principles\n拆出底层约束。"),
            "https://raw.githubusercontent.com/dontbesilent2025/claude-skills/main/skills/first-principles/README.md": .status(404),
            "https://raw.githubusercontent.com/dontbesilent2025/claude-skills/main/skills/roundtable/SKILL.md": .text("# Roundtable\n拉出不同立场。"),
            "https://raw.githubusercontent.com/dontbesilent2025/claude-skills/main/skills/roundtable/README.md": .status(404),
            "https://raw.githubusercontent.com/dontbesilent2025/claude-skills/main/SKILL.md": .status(404)
        ]

        let service = MeetingSkillCatalogService(session: session, baseDirectoryURL: baseURL)
        let installs = try await service.importGitHubRepository(
            repoURL: "https://github.com/dontbesilent2025/claude-skills"
        )

        XCTAssertEqual(installs.count, 2)
        XCTAssertEqual(Set(installs.map(\.displayName)), ["First Principles", "Roundtable"])
        XCTAssertTrue(installs.allSatisfy { $0.sourceKind == .imported })
        XCTAssertTrue(installs.allSatisfy { $0.subagentID == "imported:dontbesilent2025__claude-skills" })
        XCTAssertTrue(installs.allSatisfy { $0.subagentName == "claude-skills" })
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

    private func makeStubSession() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StubURLProtocol.self]
        return URLSession(configuration: configuration)
    }

    private func makeEntry(repoFullName: String, title: String) -> MeetingSkillCatalogEntry {
        let repoURL = "https://github.com/\(repoFullName)"
        return MeetingSkillCatalogEntry(
            category: "Personas",
            title: title,
            repoURL: repoURL,
            repoFullName: repoFullName,
            description: "\(title) description",
            sourceIndexURL: "https://example.com/index"
        )
    }
}

private func XCTAssertThrowsErrorAsync(
    _ expression: @escaping () async throws -> Void,
    verify: @escaping (Error) -> Void
) async {
    do {
        try await expression()
        XCTFail("Expected error")
    } catch {
        verify(error)
    }
}

private final class StubURLProtocol: URLProtocol {
    enum StubResponse {
        case text(String, statusCode: Int = 200)
        case json([String: Any], statusCode: Int = 200)
        case status(Int)
    }

    static var handlers: [String: StubResponse] = [:]
    static var requestedURLs: [String] = []

    override class func canInit(with request: URLRequest) -> Bool {
        true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        guard let url = request.url else {
            client?.urlProtocol(self, didFailWithError: URLError(.badURL))
            return
        }

        let key = url.absoluteString
        Self.requestedURLs.append(key)

        let response = Self.handlers[key] ?? .status(404)
        let payload: Data
        let statusCode: Int

        switch response {
        case .text(let body, let code):
            payload = Data(body.utf8)
            statusCode = code
        case .json(let json, let code):
            payload = (try? JSONSerialization.data(withJSONObject: json, options: [])) ?? Data()
            statusCode = code
        case .status(let code):
            payload = Data()
            statusCode = code
        }

        let http = HTTPURLResponse(url: url, statusCode: statusCode, httpVersion: nil, headerFields: nil)!
        client?.urlProtocol(self, didReceive: http, cacheStoragePolicy: .notAllowed)
        if !payload.isEmpty {
            client?.urlProtocol(self, didLoad: payload)
        }
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}
