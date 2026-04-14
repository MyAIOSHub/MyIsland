import Foundation
import os.log

actor MeetingSkillCatalogService {
    static let shared = MeetingSkillCatalogService()
    nonisolated static let logger = Logger(subsystem: "com.myisland", category: "MeetingSkills")

    static let awesomeIndexURL = "https://raw.githubusercontent.com/dy9759/awesome-persona-distill-skills0410/main/README.md"

    private let fileManager: FileManager
    private let session: URLSession
    nonisolated let baseDirectoryURL: URL
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

    private var installedSkills: [MeetingSkillInstall] = []
    private var userSubagents: [MeetingSkillSubagent] = []
    private var hasStarted = false

    init(
        fileManager: FileManager = .default,
        session: URLSession = .shared,
        baseDirectoryURL: URL? = nil
    ) {
        self.fileManager = fileManager
        self.session = session
        self.baseDirectoryURL = baseDirectoryURL ?? MeetingStorage.baseDirectoryURL(fileManager: fileManager)
    }

    enum SkillCatalogError: LocalizedError {
        case invalidIndexURL
        case invalidGitHubURL(String)
        case missingSkillFile(String)
        case missingImportableSkills(String)
        case invalidResponse
        case invalidSubagentName
        case invalidSkillName
        case duplicateSubagentName(String)
        case duplicateSkillName(String)
        case subagentNotFound(String)
        case subagentNotEmpty(String)
        case skillNotEditable(String)

        var errorDescription: String? {
            switch self {
            case .invalidIndexURL:
                return "技能索引地址无效。"
            case .invalidGitHubURL(let url):
                return "暂不支持的 GitHub 技能地址：\(url)"
            case .missingSkillFile(let repo):
                return "\(repo) 缺少根目录 SKILL.md，无法安装。"
            case .missingImportableSkills(let repo):
                return "\(repo) 没有找到可导入的 SKILL.md。"
            case .invalidResponse:
                return "技能目录响应无效。"
            case .invalidSubagentName:
                return "Subagent 名称不能为空。"
            case .invalidSkillName:
                return "Skill 名称和正文不能为空。"
            case .duplicateSubagentName(let name):
                return "已存在同名 Subagent：\(name)"
            case .duplicateSkillName(let name):
                return "当前 Subagent 下已存在同名 Skill：\(name)"
            case .subagentNotFound(let id):
                return "找不到对应的 Subagent：\(id)"
            case .subagentNotEmpty(let name):
                return "Subagent “\(name)” 下还有 Skill，不能删除。"
            case .skillNotEditable(let id):
                return "当前 Skill 不支持编辑：\(id)"
            }
        }
    }

    nonisolated static func skillsDirectoryURL(
        baseDirectoryURL: URL? = nil,
        fileManager: FileManager = .default
    ) -> URL {
        let baseURL = baseDirectoryURL ?? MeetingStorage.baseDirectoryURL(fileManager: fileManager)
        return baseURL.appendingPathComponent("Skills", isDirectory: true)
    }

    func start() async {
        guard !hasStarted else { return }
        hasStarted = true

        do {
            try fileManager.createDirectory(at: skillsDirectoryURL, withIntermediateDirectories: true)
            try loadInstalledSkills()
            try loadUserSubagents()
            try normalizeLoadedSkillsIfNeeded()
        } catch {
            Self.logger.error("Failed to load installed meeting skills: \(error.localizedDescription, privacy: .public)")
            installedSkills = []
            userSubagents = []
        }
    }

    func currentInstalledSkills() async -> [MeetingSkillInstall] {
        await start()
        return installedSkills.sorted { $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending }
    }

    func currentUserSubagents() async -> [MeetingSkillSubagent] {
        await start()
        return sortedUserSubagents()
    }

    func refreshCatalog() async throws -> [MeetingSkillCatalogEntry] {
        guard let url = URL(string: Self.awesomeIndexURL) else {
            throw SkillCatalogError.invalidIndexURL
        }
        let (data, response) = try await session.data(from: url)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw SkillCatalogError.invalidResponse
        }
        let markdown = String(decoding: data, as: UTF8.self)
        let entries = Self.parseCatalogEntries(markdown: markdown, sourceIndexURL: Self.awesomeIndexURL)
        let catalogData = try encoder.encode(entries)
        try catalogData.write(to: catalogCacheURL, options: [.atomic])
        return entries
    }

    func cachedCatalog() async -> [MeetingSkillCatalogEntry] {
        await start()
        guard fileManager.fileExists(atPath: catalogCacheURL.path),
              let data = try? Data(contentsOf: catalogCacheURL),
              let entries = try? decoder.decode([MeetingSkillCatalogEntry].self, from: data) else {
            return []
        }
        return entries
    }

    func refreshCatalogAndSyncInstalls(force: Bool = false) async throws -> MeetingSkillCatalogSyncResult {
        let entries = try await refreshCatalog()
        return try await syncCatalogInstalls(entries: entries, force: force)
    }

    func syncCatalogInstalls(
        entries: [MeetingSkillCatalogEntry]? = nil,
        force: Bool = false
    ) async throws -> MeetingSkillCatalogSyncResult {
        await start()

        let cachedEntries = await cachedCatalog()
        var catalogEntries = entries ?? cachedEntries
        let initiallyInstalled = Set(installedSkills.map(\.id))
        var newlyInstalledRepoFullNames: [String] = []
        var unsupportedRepoFullNames: [String] = []
        var failedRepoErrors: [String: String] = [:]

        guard !catalogEntries.isEmpty else {
            return MeetingSkillCatalogSyncResult(
                catalogEntries: [],
                installedSkills: sortedInstalledSkills(),
                newlyInstalledRepoFullNames: [],
                unsupportedRepoFullNames: [],
                failedRepoErrors: [:]
            )
        }

        for index in catalogEntries.indices {
            let entry = catalogEntries[index]

            if !force && installedSkills.contains(where: { $0.id == entry.repoFullName }) {
                continue
            }

            if !entry.isInstallable && !force {
                continue
            }

            do {
                let install = try await install(entry: entry)
                catalogEntries[index].isInstallable = true
                if !initiallyInstalled.contains(install.id) {
                    newlyInstalledRepoFullNames.append(install.repoFullName)
                }
            } catch SkillCatalogError.missingSkillFile {
                catalogEntries[index].isInstallable = false
                unsupportedRepoFullNames.append(entry.repoFullName)
            } catch {
                failedRepoErrors[entry.repoFullName] = error.localizedDescription
            }
        }

        try persistCatalog(entries: catalogEntries)

        return MeetingSkillCatalogSyncResult(
            catalogEntries: catalogEntries,
            installedSkills: sortedInstalledSkills(),
            newlyInstalledRepoFullNames: newlyInstalledRepoFullNames.sorted(),
            unsupportedRepoFullNames: unsupportedRepoFullNames.sorted(),
            failedRepoErrors: failedRepoErrors
        )
    }

    func install(entry: MeetingSkillCatalogEntry) async throws -> MeetingSkillInstall {
        await start()
        let repo = try parseRepoInfo(entry.repoURL)
        let branch = try await fetchDefaultBranch(repoFullName: repo.fullName)
        let skillMarkdown = try await fetchRawGitHubFile(repoFullName: repo.fullName, branch: branch, path: "SKILL.md")
        let readmeMarkdown = try? await fetchRawGitHubFile(repoFullName: repo.fullName, branch: branch, path: "README.md")
        return try await installSnapshot(
            entry: entry,
            defaultBranch: branch,
            skillMarkdown: skillMarkdown,
            readmeMarkdown: readmeMarkdown
        )
    }

    func installSnapshot(
        entry: MeetingSkillCatalogEntry,
        defaultBranch: String,
        skillMarkdown: String,
        readmeMarkdown: String? = nil,
        installedAt: Date = Date()
    ) async throws -> MeetingSkillInstall {
        await start()
        let repo = try parseRepoInfo(entry.repoURL)
        let trimmedSkill = skillMarkdown.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedSkill.isEmpty else {
            throw SkillCatalogError.missingSkillFile(repo.fullName)
        }

        let snapshotDirectory = skillsDirectoryURL.appendingPathComponent(repo.slug, isDirectory: true)
        try fileManager.createDirectory(at: snapshotDirectory, withIntermediateDirectories: true)

        let skillURL = snapshotDirectory.appendingPathComponent("SKILL.md")
        try trimmedSkill.write(to: skillURL, atomically: true, encoding: .utf8)

        var readmeRelativePath: String?
        if let readmeMarkdown, !readmeMarkdown.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            let readmeURL = snapshotDirectory.appendingPathComponent("README.md")
            try readmeMarkdown.write(to: readmeURL, atomically: true, encoding: .utf8)
            readmeRelativePath = "Skills/\(repo.slug)/README.md"
        }

        let install = MeetingSkillInstall(
            id: repo.fullName,
            catalogEntryID: entry.id,
            displayName: entry.title,
            repoURL: entry.repoURL,
            repoFullName: repo.fullName,
            installedAt: installedAt,
            skillRelativePath: "Skills/\(repo.slug)/SKILL.md",
            readmeRelativePath: readmeRelativePath,
            localSnapshotDirectory: "Skills/\(repo.slug)",
            defaultBranch: defaultBranch,
            sourceIndexURL: entry.sourceIndexURL,
            description: entry.description,
            skillMarkdown: trimmedSkill,
            subagentID: entry.subagentID,
            subagentName: entry.subagentName,
            sourceKind: .catalog,
            isEditable: false
        )

        if let index = installedSkills.firstIndex(where: { $0.id == install.id }) {
            installedSkills[index] = install
        } else {
            installedSkills.append(install)
        }
        try persistInstalledSkills()
        return install
    }

    func importGitHubRepository(repoURL: String) async throws -> [MeetingSkillInstall] {
        await start()

        let repo = try parseRepoInfo(repoURL)
        let defaultBranch = try await fetchDefaultBranch(repoFullName: repo.fullName)
        let importedSubagentID = "imported:\(repo.slug)"
        let importedSubagentName = repo.repositoryName
        var installs: [MeetingSkillInstall] = []

        let packEntries = try await fetchGitHubDirectoryEntries(
            repoFullName: repo.fullName,
            branch: defaultBranch,
            path: "skills"
        )
        .filter { $0.type == "dir" }
        .sorted { lhs, rhs in
            lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
        }

        for entry in packEntries {
            let skillPath = "\(entry.path)/SKILL.md"
            guard let markdown = try? await fetchRawGitHubFile(
                repoFullName: repo.fullName,
                branch: defaultBranch,
                path: skillPath
            ) else {
                continue
            }

            let readmePath = "\(entry.path)/README.md"
            let install = try installImportedSnapshot(
                repo: repo,
                repoURL: repoURL,
                defaultBranch: defaultBranch,
                subagentID: importedSubagentID,
                subagentName: importedSubagentName,
                skillIdentifierSuffix: entry.path,
                fallbackName: entry.name,
                descriptionFallback: "导入自 \(repo.fullName)",
                skillMarkdown: markdown,
                readmeMarkdown: try? await fetchRawGitHubFile(
                    repoFullName: repo.fullName,
                    branch: defaultBranch,
                    path: readmePath
                )
            )
            installs.append(install)
        }

        if let rootMarkdown = try? await fetchRawGitHubFile(
            repoFullName: repo.fullName,
            branch: defaultBranch,
            path: "SKILL.md"
        ) {
            let install = try installImportedSnapshot(
                repo: repo,
                repoURL: repoURL,
                defaultBranch: defaultBranch,
                subagentID: importedSubagentID,
                subagentName: importedSubagentName,
                skillIdentifierSuffix: "root",
                fallbackName: repo.repositoryName,
                descriptionFallback: "导入自 \(repo.fullName)",
                skillMarkdown: rootMarkdown,
                readmeMarkdown: try? await fetchRawGitHubFile(
                    repoFullName: repo.fullName,
                    branch: defaultBranch,
                    path: "README.md"
                )
            )
            installs.append(install)
        }

        guard !installs.isEmpty else {
            throw SkillCatalogError.missingImportableSkills(repo.fullName)
        }

        try persistInstalledSkills()
        return installs.sorted {
            $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending
        }
    }

    func createUserSubagent(name: String, description: String) async throws -> MeetingSkillSubagent {
        await start()

        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else {
            throw SkillCatalogError.invalidSubagentName
        }

        let lookup = MeetingSkillIdentity.normalizedLookupName(trimmedName)
        if userSubagents.contains(where: {
            MeetingSkillIdentity.normalizedLookupName($0.name) == lookup
        }) {
            throw SkillCatalogError.duplicateSubagentName(trimmedName)
        }

        let subagent = MeetingSkillSubagent(
            id: "user-subagent:\(UUID().uuidString.lowercased())",
            name: trimmedName,
            description: description.trimmingCharacters(in: .whitespacesAndNewlines),
            sourceKind: .user,
            sortOrder: (userSubagents.map(\.sortOrder).max() ?? -1) + 1
        )
        userSubagents.append(subagent)
        try persistUserSubagents()
        return subagent
    }

    func deleteUserSubagent(id: String) async throws {
        await start()

        guard let subagent = userSubagents.first(where: { $0.id == id }) else {
            throw SkillCatalogError.subagentNotFound(id)
        }
        if installedSkills.contains(where: { $0.sourceKind == .user && $0.subagentID == id }) {
            throw SkillCatalogError.subagentNotEmpty(subagent.name)
        }

        userSubagents.removeAll { $0.id == id }
        try persistUserSubagents()
    }

    func createCustomSkill(
        subagentID: String,
        name: String,
        description: String,
        skillMarkdown: String
    ) async throws -> MeetingSkillInstall {
        await start()

        let subagent = try requireUserSubagent(id: subagentID)
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedMarkdown = skillMarkdown.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty, !trimmedMarkdown.isEmpty else {
            throw SkillCatalogError.invalidSkillName
        }
        try validateUniqueUserSkillName(trimmedName, subagentID: subagentID, excludingID: nil)

        let skillID = "custom-skill:\(UUID().uuidString.lowercased())"
        let folderName = "custom/\(skillID.replacingOccurrences(of: ":", with: "-"))"
        let relativeDirectory = "Skills/\(folderName)"
        let snapshotDirectoryURL = baseDirectoryURL.appendingPathComponent(relativeDirectory, isDirectory: true)
        try fileManager.createDirectory(at: snapshotDirectoryURL, withIntermediateDirectories: true)
        try trimmedMarkdown.write(
            to: snapshotDirectoryURL.appendingPathComponent("SKILL.md"),
            atomically: true,
            encoding: .utf8
        )

        let install = MeetingSkillInstall(
            id: skillID,
            catalogEntryID: skillID,
            displayName: trimmedName,
            repoURL: "custom://\(skillID)",
            repoFullName: skillID,
            installedAt: Date(),
            skillRelativePath: "\(relativeDirectory)/SKILL.md",
            readmeRelativePath: nil,
            localSnapshotDirectory: relativeDirectory,
            defaultBranch: "local",
            sourceIndexURL: "user://local",
            description: description.trimmingCharacters(in: .whitespacesAndNewlines),
            skillMarkdown: trimmedMarkdown,
            subagentID: subagent.id,
            subagentName: subagent.name,
            sourceKind: .user,
            isEditable: true
        )

        installedSkills.append(install)
        try persistInstalledSkills()
        return install
    }

    func updateCustomSkill(
        id: String,
        subagentID: String,
        name: String,
        description: String,
        skillMarkdown: String
    ) async throws -> MeetingSkillInstall {
        await start()

        guard let index = installedSkills.firstIndex(where: { $0.id == id }) else {
            throw SkillCatalogError.skillNotEditable(id)
        }
        guard installedSkills[index].sourceKind == .user, installedSkills[index].isEditable else {
            throw SkillCatalogError.skillNotEditable(id)
        }

        let subagent = try requireUserSubagent(id: subagentID)
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedMarkdown = skillMarkdown.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty, !trimmedMarkdown.isEmpty else {
            throw SkillCatalogError.invalidSkillName
        }
        try validateUniqueUserSkillName(trimmedName, subagentID: subagentID, excludingID: id)

        var install = installedSkills[index]
        let snapshotDirectoryURL = baseDirectoryURL.appendingPathComponent(install.localSnapshotDirectory, isDirectory: true)
        try fileManager.createDirectory(at: snapshotDirectoryURL, withIntermediateDirectories: true)
        try trimmedMarkdown.write(
            to: snapshotDirectoryURL.appendingPathComponent("SKILL.md"),
            atomically: true,
            encoding: .utf8
        )

        install.displayName = trimmedName
        install.description = description.trimmingCharacters(in: .whitespacesAndNewlines)
        install.skillMarkdown = trimmedMarkdown
        install.subagentID = subagent.id
        install.subagentName = subagent.name
        install.installedAt = Date()
        installedSkills[index] = install
        try persistInstalledSkills()
        return install
    }

    func removeInstall(id: String) async throws {
        await start()
        guard let install = installedSkills.first(where: { $0.id == id }) else { return }
        let snapshotDirectory = baseDirectoryURL.appendingPathComponent(install.localSnapshotDirectory, isDirectory: true)
        if fileManager.fileExists(atPath: snapshotDirectory.path) {
            try fileManager.removeItem(at: snapshotDirectory)
        }
        installedSkills.removeAll { $0.id == id }
        try persistInstalledSkills()
    }

    private var skillsDirectoryURL: URL {
        Self.skillsDirectoryURL(baseDirectoryURL: baseDirectoryURL, fileManager: fileManager)
    }

    private var installedSkillsURL: URL {
        skillsDirectoryURL.appendingPathComponent("installed-skills.json")
    }

    private var userSubagentsURL: URL {
        skillsDirectoryURL.appendingPathComponent("user-subagents.json")
    }

    private var catalogCacheURL: URL {
        skillsDirectoryURL.appendingPathComponent("catalog-cache.json")
    }

    private func loadInstalledSkills() throws {
        guard fileManager.fileExists(atPath: installedSkillsURL.path) else {
            installedSkills = []
            return
        }

        let data = try Data(contentsOf: installedSkillsURL)
        installedSkills = try decoder.decode([MeetingSkillInstall].self, from: data)
    }

    private func loadUserSubagents() throws {
        guard fileManager.fileExists(atPath: userSubagentsURL.path) else {
            userSubagents = []
            return
        }

        let data = try Data(contentsOf: userSubagentsURL)
        userSubagents = try decoder.decode([MeetingSkillSubagent].self, from: data)
    }

    private func persistInstalledSkills() throws {
        let data = try encoder.encode(installedSkills)
        try data.write(to: installedSkillsURL, options: [.atomic])
    }

    private func persistUserSubagents() throws {
        let data = try encoder.encode(userSubagents)
        try data.write(to: userSubagentsURL, options: [.atomic])
    }

    private func persistCatalog(entries: [MeetingSkillCatalogEntry]) throws {
        let data = try encoder.encode(entries)
        try data.write(to: catalogCacheURL, options: [.atomic])
    }

    private func sortedInstalledSkills() -> [MeetingSkillInstall] {
        installedSkills.sorted { $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending }
    }

    private func sortedUserSubagents() -> [MeetingSkillSubagent] {
        userSubagents.sorted { lhs, rhs in
            if lhs.sortOrder == rhs.sortOrder {
                return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
            }
            return lhs.sortOrder < rhs.sortOrder
        }
    }

    private func normalizeLoadedSkillsIfNeeded() throws {
        let cachedEntries = loadCachedCatalogEntries()
        let entriesByID = Dictionary(uniqueKeysWithValues: cachedEntries.map { ($0.id, $0) })
        let entriesByRepo = Dictionary(uniqueKeysWithValues: cachedEntries.map { ($0.repoFullName, $0) })
        var changed = false

        for install in installedSkills where install.sourceKind == .user {
            let trimmedName = install.subagentName.trimmingCharacters(in: .whitespacesAndNewlines)
            guard install.subagentID != MeetingSkillIdentity.defaultUserSubagentID, !trimmedName.isEmpty else {
                continue
            }
            if !userSubagents.contains(where: { $0.id == install.subagentID }) {
                userSubagents.append(
                    MeetingSkillSubagent(
                        id: install.subagentID,
                        name: trimmedName,
                        description: "",
                        sourceKind: .user,
                        sortOrder: userSubagents.count
                    )
                )
                changed = true
            }
        }

        let userSubagentsByID = Dictionary(uniqueKeysWithValues: userSubagents.map { ($0.id, $0) })

        for index in installedSkills.indices {
            let original = installedSkills[index]
            var normalized = original

            switch original.sourceKind {
            case .catalog:
                let entry = entriesByID[original.catalogEntryID] ?? entriesByRepo[original.repoFullName]
                let expectedName = entry?.subagentName ?? MeetingSkillCatalogEntry.defaultCatalogSubagentName
                let expectedID = entry?.subagentID ?? MeetingSkillCatalogEntry.defaultCatalogSubagentID
                normalized.subagentName = expectedName
                normalized.subagentID = expectedID
                normalized.isEditable = false
            case .imported:
                normalized.isEditable = false
                if normalized.subagentName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    normalized.subagentName = "已导入"
                }
                if normalized.subagentID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    normalized.subagentID = "imported:default"
                }
            case .user:
                normalized.isEditable = true
                if let subagent = userSubagentsByID[normalized.subagentID] {
                    normalized.subagentName = subagent.name
                } else if normalized.subagentName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    normalized.subagentName = MeetingSkillIdentity.defaultUserSubagentName
                    normalized.subagentID = MeetingSkillIdentity.defaultUserSubagentID
                }
            }

            if normalized != original {
                installedSkills[index] = normalized
                changed = true
            }
        }

        if changed {
            try persistInstalledSkills()
            try persistUserSubagents()
        }
    }

    private func loadCachedCatalogEntries() -> [MeetingSkillCatalogEntry] {
        guard fileManager.fileExists(atPath: catalogCacheURL.path),
              let data = try? Data(contentsOf: catalogCacheURL),
              let entries = try? decoder.decode([MeetingSkillCatalogEntry].self, from: data) else {
            return []
        }
        return entries
    }

    private func requireUserSubagent(id: String) throws -> MeetingSkillSubagent {
        guard let subagent = userSubagents.first(where: { $0.id == id && $0.sourceKind == .user }) else {
            throw SkillCatalogError.subagentNotFound(id)
        }
        return subagent
    }

    private func validateUniqueUserSkillName(_ name: String, subagentID: String, excludingID: String?) throws {
        let lookup = MeetingSkillIdentity.normalizedLookupName(name)
        let duplicate = installedSkills.contains { install in
            guard install.sourceKind == .user, install.subagentID == subagentID else { return false }
            if let excludingID, install.id == excludingID { return false }
            return MeetingSkillIdentity.normalizedLookupName(install.displayName) == lookup
        }
        if duplicate {
            throw SkillCatalogError.duplicateSkillName(name)
        }
    }

    private struct RepoInfo {
        let fullName: String
        let slug: String

        var repositoryName: String {
            fullName.split(separator: "/").last.map(String.init) ?? fullName
        }
    }

    private struct GitHubContentEntry: Decodable {
        let name: String
        let path: String
        let type: String
    }

    static func parseCatalogEntries(markdown: String, sourceIndexURL: String) -> [MeetingSkillCatalogEntry] {
        let lines = markdown.components(separatedBy: .newlines)
        var currentCategory = ""
        var entries: [MeetingSkillCatalogEntry] = []

        let pattern = #"- \[([^\]]+)\]\((https://github\.com/[^)]+)\) - (.+)"#
        let regex = try? NSRegularExpression(pattern: pattern)

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.hasPrefix("## ") {
                currentCategory = String(trimmed.dropFirst(3))
                continue
            }

            guard let regex else { continue }
            let range = NSRange(location: 0, length: trimmed.utf16.count)
            guard let match = regex.firstMatch(in: trimmed, range: range),
                  match.numberOfRanges == 4,
                  let titleRange = Range(match.range(at: 1), in: trimmed),
                  let urlRange = Range(match.range(at: 2), in: trimmed),
                  let descRange = Range(match.range(at: 3), in: trimmed) else {
                continue
            }

            let title = String(trimmed[titleRange])
            let repoURL = String(trimmed[urlRange])
            let description = String(trimmed[descRange])
            guard let repoInfo = try? parseRepoInfo(repoURL) else { continue }

            entries.append(
                MeetingSkillCatalogEntry(
                    category: currentCategory,
                    title: title,
                    repoURL: repoURL,
                    repoFullName: repoInfo.fullName,
                    description: description,
                    sourceIndexURL: sourceIndexURL,
                    isInstallable: true
                )
            )
        }

        return entries
    }

    static func catalogSubagentGroups(
        entries: [MeetingSkillCatalogEntry],
        installedSkills: [MeetingSkillInstall]
    ) -> [MeetingCatalogSubagentGroup] {
        let installedCatalogIDs = Set(
            installedSkills
                .filter { $0.sourceKind == .catalog }
                .map(\.repoFullName)
        )
        var orderedIDs: [String] = []
        var groupedEntries: [String: [MeetingSkillCatalogEntry]] = [:]

        for entry in entries {
            if groupedEntries[entry.subagentID] == nil {
                orderedIDs.append(entry.subagentID)
            }
            groupedEntries[entry.subagentID, default: []].append(entry)
        }

        return orderedIDs.compactMap { subagentID in
            guard let bucket = groupedEntries[subagentID], let first = bucket.first else { return nil }
            let sortedEntries = bucket.sorted { lhs, rhs in
                lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending
            }
            let installedCount = sortedEntries.reduce(into: 0) { count, entry in
                if installedCatalogIDs.contains(entry.repoFullName) {
                    count += 1
                }
            }
            return MeetingCatalogSubagentGroup(
                subagent: MeetingSkillSubagent(
                    id: first.subagentID,
                    name: first.subagentName,
                    description: first.category,
                    sourceKind: .catalog
                ),
                entries: sortedEntries,
                installedCount: installedCount
            )
        }
    }

    static func userSubagentGroups(
        subagents: [MeetingSkillSubagent],
        installedSkills: [MeetingSkillInstall]
    ) -> [MeetingInstalledSkillSubagentGroup] {
        let groupedSkills = Dictionary(grouping: installedSkills.filter { $0.sourceKind == .user }) { $0.subagentID }
        return subagents
            .sorted { lhs, rhs in
                if lhs.sortOrder == rhs.sortOrder {
                    return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
                }
                return lhs.sortOrder < rhs.sortOrder
            }
            .map { subagent in
                MeetingInstalledSkillSubagentGroup(
                    subagent: subagent,
                    skills: (groupedSkills[subagent.id] ?? []).sorted {
                        $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending
                    }
                )
            }
    }

    static func importedSubagentGroups(
        installedSkills: [MeetingSkillInstall]
    ) -> [MeetingInstalledSkillSubagentGroup] {
        let groupedSkills = Dictionary(grouping: installedSkills.filter { $0.sourceKind == .imported }) { $0.subagentID }

        return groupedSkills.keys.sorted().compactMap { subagentID in
            guard let skills = groupedSkills[subagentID], let first = skills.first else { return nil }
            return MeetingInstalledSkillSubagentGroup(
                subagent: MeetingSkillSubagent(
                    id: subagentID,
                    name: first.subagentName,
                    description: first.repoFullName,
                    sourceKind: .imported
                ),
                skills: skills.sorted {
                    $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending
                }
            )
        }
    }

    private static func parseRepoInfo(_ repoURL: String) throws -> RepoInfo {
        guard let url = URL(string: repoURL),
              let host = url.host,
              host.contains("github.com") else {
            throw SkillCatalogError.invalidGitHubURL(repoURL)
        }

        let parts = url.pathComponents.filter { $0 != "/" }
        guard parts.count >= 2 else {
            throw SkillCatalogError.invalidGitHubURL(repoURL)
        }

        let owner = parts[0]
        let repo = parts[1]
        return RepoInfo(fullName: "\(owner)/\(repo)", slug: "\(owner)__\(repo)")
    }

    private func parseRepoInfo(_ repoURL: String) throws -> RepoInfo {
        try Self.parseRepoInfo(repoURL)
    }

    private func fetchDefaultBranch(repoFullName: String) async throws -> String {
        let url = URL(string: "https://api.github.com/repos/\(repoFullName)")!
        let (data, _) = try await session.data(from: url)
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let branch = json["default_branch"] as? String else {
            throw SkillCatalogError.invalidResponse
        }
        return branch
    }

    private func fetchGitHubDirectoryEntries(
        repoFullName: String,
        branch: String,
        path: String
    ) async throws -> [GitHubContentEntry] {
        let encodedPath = path.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? path
        let url = URL(string: "https://api.github.com/repos/\(repoFullName)/contents/\(encodedPath)?ref=\(branch)")!
        let (data, response) = try await session.data(from: url)
        guard let http = response as? HTTPURLResponse else {
            throw SkillCatalogError.invalidResponse
        }
        if http.statusCode == 404 {
            return []
        }
        guard http.statusCode == 200 else {
            throw SkillCatalogError.invalidResponse
        }
        return try JSONDecoder().decode([GitHubContentEntry].self, from: data)
    }

    private func fetchRawGitHubFile(repoFullName: String, branch: String, path: String) async throws -> String {
        let url = URL(string: "https://raw.githubusercontent.com/\(repoFullName)/\(branch)/\(path)")!
        let (data, response) = try await session.data(from: url)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw SkillCatalogError.missingSkillFile(repoFullName)
        }
        return String(decoding: data, as: UTF8.self)
    }

    private func installImportedSnapshot(
        repo: RepoInfo,
        repoURL: String,
        defaultBranch: String,
        subagentID: String,
        subagentName: String,
        skillIdentifierSuffix: String,
        fallbackName: String,
        descriptionFallback: String,
        skillMarkdown: String,
        readmeMarkdown: String?
    ) throws -> MeetingSkillInstall {
        let trimmedSkill = skillMarkdown.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedSkill.isEmpty else {
            throw SkillCatalogError.missingImportableSkills(repo.fullName)
        }

        let folderSlug = MeetingSkillIdentity.slug(from: skillIdentifierSuffix)
        let relativeDirectory = "Skills/imported/\(repo.slug)/\(folderSlug.isEmpty ? "root" : folderSlug)"
        let snapshotDirectory = baseDirectoryURL.appendingPathComponent(relativeDirectory, isDirectory: true)
        try fileManager.createDirectory(at: snapshotDirectory, withIntermediateDirectories: true)
        try trimmedSkill.write(
            to: snapshotDirectory.appendingPathComponent("SKILL.md"),
            atomically: true,
            encoding: .utf8
        )

        var readmeRelativePath: String?
        if let readmeMarkdown {
            let trimmedReadme = readmeMarkdown.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmedReadme.isEmpty {
                try trimmedReadme.write(
                    to: snapshotDirectory.appendingPathComponent("README.md"),
                    atomically: true,
                    encoding: .utf8
                )
                readmeRelativePath = "\(relativeDirectory)/README.md"
            }
        }

        let install = MeetingSkillInstall(
            id: "imported:\(repo.fullName):\(skillIdentifierSuffix)",
            catalogEntryID: "imported:\(repo.fullName):\(skillIdentifierSuffix)",
            displayName: inferredSkillDisplayName(from: trimmedSkill, fallback: fallbackName),
            repoURL: repoURL,
            repoFullName: repo.fullName,
            installedAt: Date(),
            skillRelativePath: "\(relativeDirectory)/SKILL.md",
            readmeRelativePath: readmeRelativePath,
            localSnapshotDirectory: relativeDirectory,
            defaultBranch: defaultBranch,
            sourceIndexURL: "import://\(repo.fullName)",
            description: inferredSkillDescription(from: trimmedSkill, fallback: descriptionFallback),
            skillMarkdown: trimmedSkill,
            subagentID: subagentID,
            subagentName: subagentName,
            sourceKind: .imported,
            isEditable: false
        )

        if let index = installedSkills.firstIndex(where: { $0.id == install.id }) {
            installedSkills[index] = install
        } else {
            installedSkills.append(install)
        }
        return install
    }

    private func inferredSkillDisplayName(from markdown: String, fallback: String) -> String {
        for rawLine in markdown.components(separatedBy: .newlines) {
            let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            guard line.hasPrefix("# ") else { continue }
            let title = line.replacingOccurrences(of: "# ", with: "").trimmingCharacters(in: .whitespacesAndNewlines)
            if !title.isEmpty {
                return title
            }
        }
        return fallback.replacingOccurrences(of: "-", with: " ")
    }

    private func inferredSkillDescription(from markdown: String, fallback: String) -> String {
        for rawLine in markdown.components(separatedBy: .newlines) {
            let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !line.isEmpty else { continue }
            if line.hasPrefix("#") || line.hasPrefix("-") || line.hasPrefix("*") {
                continue
            }
            return String(line.prefix(120))
        }
        return fallback
    }

}
