import Foundation
import XCTest
@testable import My_Island

final class MeetingSkillLibraryTests: XCTestCase {
    func testParseAwesomeIndexAssignsCatalogSubagentMetadata() {
        let markdown = """
        ## Personas
        - [Elon Musk Skill](https://github.com/alchaincyf/elon-musk-skill) - First principles and manufacturing rigor.
        """

        let entries = MeetingSkillCatalogService.parseCatalogEntries(
            markdown: markdown,
            sourceIndexURL: "https://example.com/index"
        )

        XCTAssertEqual(entries.count, 1)
        XCTAssertEqual(entries[0].subagentName, "Personas")
        XCTAssertEqual(entries[0].subagentID, "catalog:personas")
    }

    func testCurrentInstalledSkillsBackfillsLegacyCatalogSkillMetadataFromCachedCatalog() async {
        let baseURL = makeTemporaryDirectory()
        let skillsURL = baseURL.appendingPathComponent("Skills", isDirectory: true)
        try? FileManager.default.createDirectory(at: skillsURL, withIntermediateDirectories: true)

        let legacyInstalledJSON = """
        [
          {
            "id": "alchaincyf/elon-musk-skill",
            "catalogEntryID": "alchaincyf/elon-musk-skill",
            "defaultBranch": "main",
            "description": "First principles",
            "displayName": "Elon Musk Skill",
            "installedAt": "2026-04-11T14:00:00Z",
            "localSnapshotDirectory": "Skills/alchaincyf__elon-musk-skill",
            "readmeRelativePath": null,
            "repoFullName": "alchaincyf/elon-musk-skill",
            "repoURL": "https://github.com/alchaincyf/elon-musk-skill",
            "skillMarkdown": "# SKILL\\nThink from first principles.",
            "skillRelativePath": "Skills/alchaincyf__elon-musk-skill/SKILL.md",
            "sourceIndexURL": "https://example.com/index"
          }
        ]
        """
        try? legacyInstalledJSON.data(using: .utf8)?.write(
            to: skillsURL.appendingPathComponent("installed-skills.json"),
            options: [.atomic]
        )

        let catalogEntries = [
            MeetingSkillCatalogEntry(
                category: "Personas",
                title: "Elon Musk Skill",
                repoURL: "https://github.com/alchaincyf/elon-musk-skill",
                repoFullName: "alchaincyf/elon-musk-skill",
                description: "First principles",
                sourceIndexURL: "https://example.com/index"
            )
        ]
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let catalogData = try? encoder.encode(catalogEntries)
        try? catalogData?.write(
            to: skillsURL.appendingPathComponent("catalog-cache.json"),
            options: [.atomic]
        )

        let service = MeetingSkillCatalogService(baseDirectoryURL: baseURL)
        let installs = await service.currentInstalledSkills()

        XCTAssertEqual(installs.count, 1)
        XCTAssertEqual(installs[0].subagentName, "Personas")
        XCTAssertEqual(installs[0].subagentID, "catalog:personas")
        XCTAssertEqual(installs[0].sourceKind, .catalog)
        XCTAssertFalse(installs[0].isEditable)
    }

    func testCreateUserSubagentAndCustomSkillPersistAcrossReload() async throws {
        let baseURL = makeTemporaryDirectory()
        let service = MeetingSkillCatalogService(baseDirectoryURL: baseURL)

        let subagent = try await service.createUserSubagent(
            name: "增长策略",
            description: "聚焦增长假设与投放节奏。"
        )
        let createdSkill = try await service.createCustomSkill(
            subagentID: subagent.id,
            name: "增长复盘",
            description: "审查增长实验、渠道和转化。",
            skillMarkdown: "# SKILL\n聚焦增长复盘。"
        )

        let reloaded = MeetingSkillCatalogService(baseDirectoryURL: baseURL)
        let subagents = await reloaded.currentUserSubagents()
        let installs = await reloaded.currentInstalledSkills()

        XCTAssertEqual(subagents.count, 1)
        XCTAssertEqual(subagents[0].name, "增长策略")
        XCTAssertEqual(installs.count, 1)
        XCTAssertEqual(installs[0].sourceKind, .user)
        XCTAssertTrue(installs[0].isEditable)
        XCTAssertEqual(installs[0].subagentID, subagent.id)
        XCTAssertEqual(installs[0].subagentName, "增长策略")
        XCTAssertTrue(
            FileManager.default.fileExists(
                atPath: baseURL.appendingPathComponent(createdSkill.skillRelativePath).path
            )
        )
    }

    func testUpdateCustomSkillRewritesMetadataAndSkillFile() async throws {
        let baseURL = makeTemporaryDirectory()
        let service = MeetingSkillCatalogService(baseDirectoryURL: baseURL)
        let subagent = try await service.createUserSubagent(
            name: "增长策略",
            description: "聚焦增长假设与投放节奏。"
        )
        let createdSkill = try await service.createCustomSkill(
            subagentID: subagent.id,
            name: "增长复盘",
            description: "审查增长实验、渠道和转化。",
            skillMarkdown: "# SKILL\n聚焦增长复盘。"
        )

        let updated = try await service.updateCustomSkill(
            id: createdSkill.id,
            subagentID: subagent.id,
            name: "增长策略复盘",
            description: "更新后的描述。",
            skillMarkdown: "# SKILL\n聚焦增长策略复盘。"
        )

        let installs = await service.currentInstalledSkills()

        XCTAssertEqual(updated.displayName, "增长策略复盘")
        XCTAssertEqual(installs.first?.displayName, "增长策略复盘")
        XCTAssertEqual(installs.first?.description, "更新后的描述。")
        let savedMarkdown = try String(
            contentsOf: baseURL.appendingPathComponent(updated.skillRelativePath),
            encoding: .utf8
        )
        XCTAssertEqual(savedMarkdown, "# SKILL\n聚焦增长策略复盘。")
    }

    func testDeleteUserSubagentRejectsWhenItStillContainsSkills() async throws {
        let baseURL = makeTemporaryDirectory()
        let service = MeetingSkillCatalogService(baseDirectoryURL: baseURL)
        let subagent = try await service.createUserSubagent(
            name: "商业判断",
            description: "讨论商业模式和定价。"
        )
        _ = try await service.createCustomSkill(
            subagentID: subagent.id,
            name: "定价评论",
            description: "审查定价和价值证明。",
            skillMarkdown: "# SKILL\n关注定价。"
        )

        do {
            try await service.deleteUserSubagent(id: subagent.id)
            XCTFail("Expected deleteUserSubagent to throw")
        } catch let error as MeetingSkillCatalogService.SkillCatalogError {
            guard case .subagentNotEmpty(let subagentName) = error else {
                return XCTFail("Unexpected error: \(error)")
            }
            XCTAssertEqual(subagentName, "商业判断")
        } catch {
            XCTFail("Unexpected error type: \(error)")
        }
    }

    func testDeleteEmptyUserSubagentSucceeds() async throws {
        let baseURL = makeTemporaryDirectory()
        let service = MeetingSkillCatalogService(baseDirectoryURL: baseURL)
        let subagent = try await service.createUserSubagent(
            name: "会议复盘",
            description: "聚焦复盘。"
        )

        try await service.deleteUserSubagent(id: subagent.id)

        let subagents = await service.currentUserSubagents()
        XCTAssertTrue(subagents.isEmpty)
    }

    func testCreateCustomSkillRejectsDuplicateNameInSameSubagent() async throws {
        let baseURL = makeTemporaryDirectory()
        let service = MeetingSkillCatalogService(baseDirectoryURL: baseURL)
        let subagent = try await service.createUserSubagent(
            name: "增长策略",
            description: "聚焦增长假设与投放节奏。"
        )
        _ = try await service.createCustomSkill(
            subagentID: subagent.id,
            name: "增长复盘",
            description: "审查增长实验、渠道和转化。",
            skillMarkdown: "# SKILL\n聚焦增长复盘。"
        )

        do {
            _ = try await service.createCustomSkill(
                subagentID: subagent.id,
                name: "增长复盘",
                description: "重复的名字。",
                skillMarkdown: "# SKILL\n重复。"
            )
            XCTFail("Expected createCustomSkill to throw")
        } catch let error as MeetingSkillCatalogService.SkillCatalogError {
            guard case .duplicateSkillName(let name) = error else {
                return XCTFail("Unexpected error: \(error)")
            }
            XCTAssertEqual(name, "增长复盘")
        } catch {
            XCTFail("Unexpected error type: \(error)")
        }
    }

    func testCatalogSubagentGroupsAggregateEntriesAndInstalledCounts() {
        let entries = [
            MeetingSkillCatalogEntry(
                category: "Personas",
                title: "Elon Musk Skill",
                repoURL: "https://github.com/alchaincyf/elon-musk-skill",
                repoFullName: "alchaincyf/elon-musk-skill",
                description: "First principles",
                sourceIndexURL: "https://example.com/index"
            ),
            MeetingSkillCatalogEntry(
                category: "Strategy",
                title: "Business Planner",
                repoURL: "https://github.com/example/business-plan-skill",
                repoFullName: "example/business-plan-skill",
                description: "Business planning",
                sourceIndexURL: "https://example.com/index"
            )
        ]
        let installs = [
            MeetingSkillInstall(
                id: "alchaincyf/elon-musk-skill",
                catalogEntryID: "alchaincyf/elon-musk-skill",
                displayName: "Elon Musk Skill",
                repoURL: "https://github.com/alchaincyf/elon-musk-skill",
                repoFullName: "alchaincyf/elon-musk-skill",
                installedAt: .distantPast,
                skillRelativePath: "Skills/alchaincyf__elon-musk-skill/SKILL.md",
                readmeRelativePath: nil,
                localSnapshotDirectory: "Skills/alchaincyf__elon-musk-skill",
                defaultBranch: "main",
                sourceIndexURL: "https://example.com/index",
                description: "First principles",
                skillMarkdown: "# SKILL\nThink from first principles.",
                subagentID: "catalog:personas",
                subagentName: "Personas",
                sourceKind: .catalog,
                isEditable: false
            )
        ]

        let groups = MeetingSkillCatalogService.catalogSubagentGroups(
            entries: entries,
            installedSkills: installs
        )

        XCTAssertEqual(groups.map(\.subagent.name), ["Personas", "Strategy"])
        XCTAssertEqual(groups.map(\.installedCount), [1, 0])
        XCTAssertEqual(groups.map { $0.entries.count }, [1, 1])
    }

    func testImportedSubagentGroupsAggregateImportedSkillsByRepo() {
        let installs = [
            MeetingSkillInstall(
                id: "imported:dontbesilent2025/claude-skills:skills/first-principles",
                catalogEntryID: "imported:dontbesilent2025/claude-skills:skills/first-principles",
                displayName: "First Principles",
                repoURL: "https://github.com/dontbesilent2025/claude-skills",
                repoFullName: "dontbesilent2025/claude-skills",
                installedAt: .distantPast,
                skillRelativePath: "Skills/imported/dontbesilent2025__claude-skills/skills-first-principles/SKILL.md",
                readmeRelativePath: nil,
                localSnapshotDirectory: "Skills/imported/dontbesilent2025__claude-skills/skills-first-principles",
                defaultBranch: "main",
                sourceIndexURL: "import://dontbesilent2025/claude-skills",
                description: "拆出底层约束。",
                skillMarkdown: "# First Principles\n拆出底层约束。",
                subagentID: "imported:dontbesilent2025__claude-skills",
                subagentName: "claude-skills",
                sourceKind: .imported,
                isEditable: false
            ),
            MeetingSkillInstall(
                id: "imported:dontbesilent2025/claude-skills:skills/roundtable",
                catalogEntryID: "imported:dontbesilent2025/claude-skills:skills/roundtable",
                displayName: "Roundtable",
                repoURL: "https://github.com/dontbesilent2025/claude-skills",
                repoFullName: "dontbesilent2025/claude-skills",
                installedAt: .distantPast,
                skillRelativePath: "Skills/imported/dontbesilent2025__claude-skills/skills-roundtable/SKILL.md",
                readmeRelativePath: nil,
                localSnapshotDirectory: "Skills/imported/dontbesilent2025__claude-skills/skills-roundtable",
                defaultBranch: "main",
                sourceIndexURL: "import://dontbesilent2025/claude-skills",
                description: "拉出不同立场。",
                skillMarkdown: "# Roundtable\n拉出不同立场。",
                subagentID: "imported:dontbesilent2025__claude-skills",
                subagentName: "claude-skills",
                sourceKind: .imported,
                isEditable: false
            )
        ]

        let groups = MeetingSkillCatalogService.importedSubagentGroups(installedSkills: installs)

        XCTAssertEqual(groups.count, 1)
        XCTAssertEqual(groups[0].subagent.name, "claude-skills")
        XCTAssertEqual(groups[0].skills.map(\.displayName), ["First Principles", "Roundtable"])
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
