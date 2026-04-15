import SwiftUI

struct MeetingSettingsView: View {
    @ObservedObject var viewModel: NotchViewModel
    @ObservedObject private var settings = MeetingSettingsStore.shared
    @ObservedObject private var coordinator = MeetingCoordinator.shared

    @State private var expandedSubagentIDs: Set<String> = []
    @State private var editorSheet: MeetingSkillLibraryEditorSheet?
    @State private var importRepoURL = ""
    @State private var isImportingRepo = false
    @State private var isReparsingMemoSummaries = false
    @State private var lastReparseStatsMessage: String?

    private var catalogGroups: [MeetingCatalogSubagentGroup] {
        MeetingSkillCatalogService.catalogSubagentGroups(
            entries: coordinator.catalogEntries,
            installedSkills: coordinator.installedSkills
        )
    }

    private var userGroups: [MeetingInstalledSkillSubagentGroup] {
        MeetingSkillCatalogService.userSubagentGroups(
            subagents: coordinator.userSubagents,
            installedSkills: coordinator.installedSkills
        )
    }

    private var importedGroups: [MeetingInstalledSkillSubagentGroup] {
        MeetingSkillCatalogService.importedSubagentGroups(
            installedSkills: coordinator.installedSkills
        )
    }

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: DesignTokens.Spacing.md) {
                header
                streamingSection
                memoSection
                objectStorageSection
                agentSection
                skillLibrarySection
                maintenanceSection
            }
            .padding(DesignTokens.Spacing.md)
        }
        .background(Color.black)
        .sheet(item: $editorSheet) { sheet in
            editorView(for: sheet)
        }
    }

    private var header: some View {
        HStack(spacing: DesignTokens.Spacing.sm) {
            Button {
                withAnimation(.easeInOut(duration: 0.25)) {
                    viewModel.contentType = .meetingHub
                }
            } label: {
                Image(systemName: "chevron.left")
                    .foregroundColor(.white.opacity(0.72))
            }
            .buttonStyle(.plain)

            Text("会议设置")
                .font(DesignTokens.Font.title())
                .foregroundColor(DesignTokens.Text.primary)

            Spacer()
        }
    }

    private var streamingSection: some View {
        MeetingSettingsCard(title: "豆包流式 ASR") {
            MeetingLabeledField(title: "Endpoint", text: $settings.streamingEndpoint)
            MeetingLabeledField(title: "App ID", text: $settings.streamingAppID)
            MeetingLabeledField(title: "Access Token", text: $settings.streamingAccessToken)
            MeetingLabeledField(title: "Resource ID", text: $settings.streamingResourceID)
            MeetingLabeledField(title: "Language", text: $settings.streamingLanguage)
            Text("当前实现跟随官方 v3 大模型流式协议，使用 `X-Api-App-Key / X-Api-Access-Key / X-Api-Resource-Id` 头。")
                .font(DesignTokens.Font.caption())
                .foregroundColor(DesignTokens.Text.tertiary)
            Text("当前默认实时资源是 `volc.bigasr.sauc.duration`（会议长音频，多人区分能力更强）。说话人识别需保持 Language 留空或 `zh-CN`，并依赖服务端返回 speaker 字段；如果 AppID 未开通 duration，可在火山控制台申请后在此输入框覆盖。")
                .font(DesignTokens.Font.caption())
                .foregroundColor(DesignTokens.Text.tertiary)
            Text("如果看到 `quota exceeded for types: concurrency`，说明当前豆包流式并发额度不足，需要在火山控制台增购并发，或切换到你已开通的其他实时 resource ID。")
                .font(DesignTokens.Font.caption())
                .foregroundColor(DesignTokens.Text.tertiary)
            Text("Secret Key 不在这条 token 鉴权链路里使用。")
                .font(DesignTokens.Font.caption())
                .foregroundColor(DesignTokens.Text.tertiary)
        }
    }

    private var memoSection: some View {
        MeetingSettingsCard(title: "豆包妙记") {
            MeetingLabeledField(title: "Submit URL", text: $settings.memoSubmitURL)
            MeetingLabeledField(title: "Query URL", text: $settings.memoQueryURL)
            MeetingLabeledField(title: "App ID", text: $settings.memoAppID)
            MeetingLabeledField(title: "Access Token", text: $settings.memoAccessToken)
            MeetingLabeledField(title: "Resource ID", text: $settings.memoResourceID)
            Text("妙记官方 `lark submit/query` 接口同样使用 App ID + Access Token。")
                .font(DesignTokens.Font.caption())
                .foregroundColor(DesignTokens.Text.tertiary)
            Text("妙记提交接口要求可访问的离线文件 URL。这里保留 submit/query 配置，会后会先把录音上传到 TOS，再把临时下载 URL 提交给妙记。")
                .font(DesignTokens.Font.caption())
                .foregroundColor(DesignTokens.Text.tertiary)
        }
    }

    private var objectStorageSection: some View {
        MeetingSettingsCard(title: "对象存储（TOS）") {
            MeetingLabeledField(title: "STS URL", text: $settings.objectStorageSTSURL)
            MeetingLabeledField(title: "STS Bearer Token", text: $settings.objectStorageSTSBearerToken)
            MeetingLabeledField(title: "Access Key ID", text: $settings.objectStorageAccessKeyID)
            MeetingLabeledField(title: "Secret Access Key", text: $settings.objectStorageSecretAccessKey)
            MeetingLabeledField(title: "Session Token", text: $settings.objectStorageSessionToken)
            MeetingLabeledField(title: "Bucket", text: $settings.objectStorageBucket)
            MeetingLabeledField(title: "Region", text: $settings.objectStorageRegion)
            MeetingLabeledField(title: "Endpoint", text: $settings.objectStorageEndpoint)
            MeetingLabeledField(title: "Key Prefix", text: $settings.objectStorageKeyPrefix)
            Text("STS 接口需要返回 accessKeyId、secretAccessKey、sessionToken、bucket、region、endpoint、keyPrefix。")
                .font(DesignTokens.Font.caption())
                .foregroundColor(DesignTokens.Text.tertiary)
            Text("如果完整填写了 Access Key ID / Secret Access Key / Bucket / Region / Endpoint，运行时会直接使用这组 TOS 凭证，不再依赖 STS。")
                .font(DesignTokens.Font.caption())
                .foregroundColor(DesignTokens.Text.tertiary)
            Text("会后处理会把录音上传到 `meetings/{yyyy}/{meetingID}/master.<ext>`，然后生成临时下载 URL 供妙记拉取。")
                .font(DesignTokens.Font.caption())
                .foregroundColor(DesignTokens.Text.tertiary)
        }
    }

    private var agentSection: some View {
        MeetingSettingsCard(title: "会议 Agent 模型（百炼兼容）") {
            MeetingLabeledField(title: "Base URL", text: $settings.agentBaseURL)
            MeetingLabeledField(title: "API Key", text: $settings.agentAPIKey)
            MeetingLabeledField(title: "Model", text: $settings.agentModel)
            MeetingLabeledField(title: "System Prompt", text: $settings.agentSystemPrompt, axis: .vertical)
            Stepper(value: $settings.agentMaxVisibleViewpoints, in: 2...5) {
                Text("最多展示 \(settings.maxVisibleViewpoints) 个观点")
                    .font(DesignTokens.Font.body())
                    .foregroundColor(DesignTokens.Text.secondary)
            }
            Text("当前默认走百炼 OpenAI-compatible 兼容接口，可直接配置 `https://dashscope.aliyuncs.com/compatible-mode/v1`。")
                .font(DesignTokens.Font.caption())
                .foregroundColor(DesignTokens.Text.tertiary)
            Text("运行时会优先调用项目内置的 normalized meeting skills、vendored agora0411 和 skillcollection 快照。")
                .font(DesignTokens.Font.caption())
                .foregroundColor(DesignTokens.Text.tertiary)
        }
    }

    private var maintenanceSection: some View {
        MeetingSettingsCard(title: "维护") {
            VStack(alignment: .leading, spacing: DesignTokens.Spacing.sm) {
                HStack {
                    Button {
                        Task {
                            isReparsingMemoSummaries = true
                            let stats = await coordinator.reparseStoredMemoSummaries()
                            isReparsingMemoSummaries = false
                            lastReparseStatsMessage =
                                "扫描 \(stats.attempted) 场会议 — 已修正 \(stats.refreshed) 场，未变 \(stats.skippedUnchanged) 场，无原始数据 \(stats.skippedNoPayload) 场，失败 \(stats.failed) 场。"
                        }
                    } label: {
                        Text(isReparsingMemoSummaries ? "重新解析中…" : "重新解析历史会议总结")
                            .font(DesignTokens.Font.caption())
                            .foregroundColor(.white)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(
                                Capsule().fill(isReparsingMemoSummaries ? Color.gray : TerminalColors.blue)
                            )
                    }
                    .buttonStyle(.plain)
                    .disabled(isReparsingMemoSummaries)
                    Spacer()
                }

                Text("用最新的 parser 重新读取每场会议磁盘上保存的妙记 payload，把因旧 bug 丢失的全文总结 / 章节 / 待办字段补回去。无需重新上传音频。")
                    .font(DesignTokens.Font.caption())
                    .foregroundColor(DesignTokens.Text.tertiary)

                if let message = lastReparseStatsMessage {
                    Text(message)
                        .font(DesignTokens.Font.caption())
                        .foregroundColor(DesignTokens.Text.secondary)
                }
            }
        }
    }

    private var skillLibrarySection: some View {
        MeetingSettingsCard(title: "Skill 目录") {
            HStack(spacing: DesignTokens.Spacing.sm) {
                Button {
                    coordinator.clearLastOperationError()
                    editorSheet = .createSubagent
                } label: {
                    Text("新建 Subagent")
                        .font(DesignTokens.Font.caption())
                        .foregroundColor(.white)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(
                            Capsule().fill(TerminalColors.blue)
                        )
                }
                .buttonStyle(.plain)

                Spacer()

                Button {
                    Task { await coordinator.refreshCatalog() }
                } label: {
                    Text(coordinator.isRefreshingCatalog ? "同步中..." : "刷新并同步")
                        .font(DesignTokens.Font.caption())
                        .foregroundColor(.white)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(
                            Capsule().fill(coordinator.isRefreshingCatalog ? DesignTokens.Text.tertiary : TerminalColors.green)
                        )
                }
                .buttonStyle(.plain)
                .disabled(coordinator.isRefreshingCatalog)
            }

            HStack(spacing: DesignTokens.Spacing.sm) {
                TextField("导入 GitHub repo，例如 https://github.com/dontbesilent2025/claude-skills", text: $importRepoURL)
                    .textFieldStyle(MeetingFieldStyle())

                Button {
                    let repoURL = importRepoURL.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !repoURL.isEmpty else { return }
                    Task {
                        isImportingRepo = true
                        let didImport = await coordinator.importGitHubSkills(repoURL: repoURL)
                        isImportingRepo = false
                        if didImport {
                            importRepoURL = ""
                        }
                    }
                } label: {
                    Text(isImportingRepo ? "导入中..." : "导入 Repo")
                        .font(DesignTokens.Font.caption())
                        .foregroundColor(.white)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(
                            Capsule().fill(isImportingRepo ? DesignTokens.Text.tertiary : TerminalColors.blue)
                        )
                }
                .buttonStyle(.plain)
                .disabled(isImportingRepo || importRepoURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }

            if let error = coordinator.lastOperationError, !error.isEmpty {
                Text(error)
                    .font(DesignTokens.Font.caption())
                    .foregroundColor(Color(red: 0.96, green: 0.45, blue: 0.45))
            }

            if let status = coordinator.skillCatalogStatusText, !status.isEmpty {
                Text(status)
                    .font(DesignTokens.Font.caption())
                    .foregroundColor(DesignTokens.Text.tertiary)
            }

            userSubagentsSection
            importedSubagentsSection
            catalogSubagentsSection
        }
    }

    private var userSubagentsSection: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.sm) {
            Text("我的 Subagents")
                .font(DesignTokens.Font.heading())
                .foregroundColor(DesignTokens.Text.primary)

            if userGroups.isEmpty {
                Text("暂无自建 Subagent。新建后可以在每个 Subagent 下添加本地 Skill。")
                    .font(DesignTokens.Font.body())
                    .foregroundColor(DesignTokens.Text.tertiary)
            } else {
                ForEach(userGroups) { group in
                    userSubagentCard(group)
                }
            }
        }
    }

    private var catalogSubagentsSection: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.sm) {
            Text("索引 Subagents")
                .font(DesignTokens.Font.heading())
                .foregroundColor(DesignTokens.Text.primary)

            if catalogGroups.isEmpty {
                Text("目录为空时会自动拉取 awesome 索引，并把兼容 skill 预先本地化到本机。会议运行时不会依赖外部仓库路径，而是使用项目内置 vendor pack。")
                    .font(DesignTokens.Font.body())
                    .foregroundColor(DesignTokens.Text.tertiary)
            } else {
                ForEach(catalogGroups) { group in
                    catalogSubagentCard(group)
                }
            }
        }
    }

    private var importedSubagentsSection: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.sm) {
            Text("已导入 Subagents")
                .font(DesignTokens.Font.heading())
                .foregroundColor(DesignTokens.Text.primary)

            if importedGroups.isEmpty {
                Text("支持导入根目录 `SKILL.md` 仓库，也支持 `skills/*/SKILL.md` 的 skill pack。")
                    .font(DesignTokens.Font.body())
                    .foregroundColor(DesignTokens.Text.tertiary)
            } else {
                ForEach(importedGroups) { group in
                    importedSubagentCard(group)
                }
            }
        }
    }

    private func userSubagentCard(_ group: MeetingInstalledSkillSubagentGroup) -> some View {
        let expanded = expandedSubagentIDs.contains(group.id)

        return VStack(alignment: .leading, spacing: DesignTokens.Spacing.sm) {
            HStack(alignment: .top, spacing: DesignTokens.Spacing.sm) {
                Image(systemName: expanded ? "chevron.down" : "chevron.right")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(DesignTokens.Text.tertiary)
                    .padding(.top, 3)

                VStack(alignment: .leading, spacing: 4) {
                    Text(group.subagent.name)
                        .font(DesignTokens.Font.label())
                        .foregroundColor(DesignTokens.Text.primary)
                    if !group.subagent.description.isEmpty {
                        Text(group.subagent.description)
                            .font(DesignTokens.Font.body())
                            .foregroundColor(DesignTokens.Text.secondary)
                            .lineLimit(2)
                    }
                    HStack(spacing: DesignTokens.Spacing.xs) {
                        metadataBadge(group.subagent.sourceKind.displayName, color: TerminalColors.blue)
                        metadataBadge("\(group.skills.count) 个 Skill", color: DesignTokens.Text.tertiary)
                    }
                }

                Spacer()

                if group.skills.isEmpty {
                    Button {
                        Task { await coordinator.deleteUserSubagent(id: group.subagent.id) }
                    } label: {
                        Text("删除")
                            .font(DesignTokens.Font.caption())
                            .foregroundColor(.white)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 5)
                            .background(
                                Capsule().fill(Color(red: 0.76, green: 0.28, blue: 0.31))
                            )
                    }
                    .buttonStyle(.plain)
                }
            }
            .contentShape(Rectangle())
            .onTapGesture {
                toggleSubagent(group.id)
            }

            if expanded {
                Divider().background(DesignTokens.Border.subtle)

                HStack {
                    Button {
                        coordinator.clearLastOperationError()
                        editorSheet = .createSkill(subagentID: group.subagent.id)
                    } label: {
                        Text("新建 Skill")
                            .font(DesignTokens.Font.caption())
                            .foregroundColor(.white)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 5)
                            .background(
                                Capsule().fill(TerminalColors.green)
                            )
                    }
                    .buttonStyle(.plain)

                    Spacer()
                }

                if group.skills.isEmpty {
                    Text("这个 Subagent 还没有 Skill。")
                        .font(DesignTokens.Font.body())
                        .foregroundColor(DesignTokens.Text.tertiary)
                } else {
                    ForEach(group.skills) { skill in
                        userSkillRow(skill)
                    }
                }
            }
        }
        .padding(DesignTokens.Spacing.md)
        .background(
            RoundedRectangle(cornerRadius: DesignTokens.Radius.lg)
                .fill(DesignTokens.Surface.elevated)
        )
    }

    private func catalogSubagentCard(_ group: MeetingCatalogSubagentGroup) -> some View {
        let expanded = expandedSubagentIDs.contains(group.id)

        return VStack(alignment: .leading, spacing: DesignTokens.Spacing.sm) {
            HStack(alignment: .top, spacing: DesignTokens.Spacing.sm) {
                Image(systemName: expanded ? "chevron.down" : "chevron.right")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(DesignTokens.Text.tertiary)
                    .padding(.top, 3)

                VStack(alignment: .leading, spacing: 4) {
                    Text(group.subagent.name)
                        .font(DesignTokens.Font.label())
                        .foregroundColor(DesignTokens.Text.primary)
                    if !group.subagent.description.isEmpty {
                        Text(group.subagent.description)
                            .font(DesignTokens.Font.body())
                            .foregroundColor(DesignTokens.Text.secondary)
                            .lineLimit(2)
                    }
                    HStack(spacing: DesignTokens.Spacing.xs) {
                        metadataBadge(group.subagent.sourceKind.displayName, color: TerminalColors.blue)
                        metadataBadge("\(group.installedCount)/\(group.entries.count) 已安装", color: DesignTokens.Text.tertiary)
                    }
                }

                Spacer()
            }
            .contentShape(Rectangle())
            .onTapGesture {
                toggleSubagent(group.id)
            }

            if expanded {
                Divider().background(DesignTokens.Border.subtle)
                ForEach(group.entries) { entry in
                    catalogSkillRow(entry)
                }
            }
        }
        .padding(DesignTokens.Spacing.md)
        .background(
            RoundedRectangle(cornerRadius: DesignTokens.Radius.lg)
                .fill(DesignTokens.Surface.elevated)
        )
    }

    private func importedSubagentCard(_ group: MeetingInstalledSkillSubagentGroup) -> some View {
        let expanded = expandedSubagentIDs.contains(group.id)

        return VStack(alignment: .leading, spacing: DesignTokens.Spacing.sm) {
            HStack(alignment: .top, spacing: DesignTokens.Spacing.sm) {
                Image(systemName: expanded ? "chevron.down" : "chevron.right")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(DesignTokens.Text.tertiary)
                    .padding(.top, 3)

                VStack(alignment: .leading, spacing: 4) {
                    Text(group.subagent.name)
                        .font(DesignTokens.Font.label())
                        .foregroundColor(DesignTokens.Text.primary)
                    if !group.subagent.description.isEmpty {
                        Text(group.subagent.description)
                            .font(DesignTokens.Font.body())
                            .foregroundColor(DesignTokens.Text.secondary)
                            .lineLimit(2)
                    }
                    HStack(spacing: DesignTokens.Spacing.xs) {
                        metadataBadge(group.subagent.sourceKind.displayName, color: TerminalColors.blue)
                        metadataBadge("\(group.skills.count) 个 Skill", color: DesignTokens.Text.tertiary)
                    }
                }

                Spacer()
            }
            .contentShape(Rectangle())
            .onTapGesture {
                toggleSubagent(group.id)
            }

            if expanded {
                Divider().background(DesignTokens.Border.subtle)
                ForEach(group.skills) { skill in
                    importedSkillRow(skill)
                }
            }
        }
        .padding(DesignTokens.Spacing.md)
        .background(
            RoundedRectangle(cornerRadius: DesignTokens.Radius.lg)
                .fill(DesignTokens.Surface.elevated)
        )
    }

    private func userSkillRow(_ skill: MeetingSkillInstall) -> some View {
        HStack(alignment: .top, spacing: DesignTokens.Spacing.sm) {
            VStack(alignment: .leading, spacing: 2) {
                Text(skill.displayName)
                    .font(DesignTokens.Font.label())
                    .foregroundColor(DesignTokens.Text.primary)
                Text(skill.description.isEmpty ? "暂无描述" : skill.description)
                    .font(DesignTokens.Font.body())
                    .foregroundColor(DesignTokens.Text.secondary)
                    .lineLimit(2)
            }

            Spacer()

            HStack(spacing: DesignTokens.Spacing.xs) {
                metadataBadge("已安装", color: TerminalColors.green)

                Button {
                    coordinator.clearLastOperationError()
                    editorSheet = .editSkill(skillID: skill.id)
                } label: {
                    Text("编辑")
                        .font(DesignTokens.Font.caption())
                        .foregroundColor(.white)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 5)
                        .background(Capsule().fill(TerminalColors.blue))
                }
                .buttonStyle(.plain)

                Button {
                    Task { await coordinator.uninstallSkill(id: skill.id) }
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
        .padding(.vertical, 4)
    }

    private func catalogSkillRow(_ entry: MeetingSkillCatalogEntry) -> some View {
        let installed = coordinator.installedSkills.contains(where: { $0.repoFullName == entry.repoFullName })
        let isUnavailable = !entry.isInstallable
        let isBusy = coordinator.isRefreshingCatalog || coordinator.isSyncingCatalogSkills

        return HStack(alignment: .top, spacing: DesignTokens.Spacing.sm) {
            VStack(alignment: .leading, spacing: 2) {
                Text(entry.title)
                    .font(DesignTokens.Font.label())
                    .foregroundColor(DesignTokens.Text.primary)
                Text(entry.description)
                    .font(DesignTokens.Font.body())
                    .foregroundColor(DesignTokens.Text.secondary)
                    .lineLimit(2)
            }

            Spacer()

            let label = installed ? "已安装" : (isUnavailable ? "不支持" : (isBusy ? "同步中" : "安装"))
            let color: Color = installed
                ? TerminalColors.green
                : (isUnavailable ? DesignTokens.Text.tertiary : TerminalColors.blue)

            Button {
                Task {
                    if !installed && !isUnavailable {
                        await coordinator.installSkill(entry)
                    }
                }
            } label: {
                Text(label)
                    .font(DesignTokens.Font.caption())
                    .foregroundColor(.white)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 5)
                    .background(Capsule().fill(color))
            }
            .buttonStyle(.plain)
            .disabled(installed || isUnavailable || isBusy)
        }
        .padding(.vertical, 4)
    }

    private func importedSkillRow(_ skill: MeetingSkillInstall) -> some View {
        HStack(alignment: .top, spacing: DesignTokens.Spacing.sm) {
            VStack(alignment: .leading, spacing: 2) {
                Text(skill.displayName)
                    .font(DesignTokens.Font.label())
                    .foregroundColor(DesignTokens.Text.primary)
                Text(skill.description.isEmpty ? "暂无描述" : skill.description)
                    .font(DesignTokens.Font.body())
                    .foregroundColor(DesignTokens.Text.secondary)
                    .lineLimit(2)
            }

            Spacer()

            HStack(spacing: DesignTokens.Spacing.xs) {
                metadataBadge("已导入", color: TerminalColors.green)

                Button {
                    Task { await coordinator.uninstallSkill(id: skill.id) }
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
        .padding(.vertical, 4)
    }

    private func metadataBadge(_ text: String, color: Color) -> some View {
        Text(text)
            .font(DesignTokens.Font.caption())
            .foregroundColor(.white)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(
                Capsule().fill(color.opacity(0.9))
            )
    }

    private func toggleSubagent(_ id: String) {
        if expandedSubagentIDs.contains(id) {
            expandedSubagentIDs.remove(id)
        } else {
            expandedSubagentIDs.insert(id)
        }
    }

    @ViewBuilder
    private func editorView(for sheet: MeetingSkillLibraryEditorSheet) -> some View {
        switch sheet {
        case .createSubagent:
            MeetingSubagentEditorView(mode: .create) { name, description in
                await coordinator.createUserSubagent(name: name, description: description)
            }
        case .createSkill(let subagentID):
            MeetingSkillEditorView(
                mode: .create(defaultSubagentID: subagentID),
                userSubagents: coordinator.userSubagents
            ) { targetSubagentID, name, description, markdown in
                await coordinator.createCustomSkill(
                    subagentID: targetSubagentID,
                    name: name,
                    description: description,
                    skillMarkdown: markdown
                )
            }
        case .editSkill(let skillID):
            if let skill = coordinator.installedSkills.first(where: { $0.id == skillID && $0.sourceKind == .user }) {
                MeetingSkillEditorView(
                    mode: .edit(skill: skill),
                    userSubagents: coordinator.userSubagents
                ) { targetSubagentID, name, description, markdown in
                    await coordinator.updateCustomSkill(
                        id: skill.id,
                        subagentID: targetSubagentID,
                        name: name,
                        description: description,
                        skillMarkdown: markdown
                    )
                }
            } else {
                Text("Skill 不存在")
                    .font(DesignTokens.Font.body())
                    .foregroundColor(DesignTokens.Text.primary)
                    .padding()
                    .frame(minWidth: 420, minHeight: 180)
                    .background(Color.black)
            }
        }
    }
}

private struct MeetingSettingsCard<Content: View>: View {
    let title: String
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.sm) {
            Text(title)
                .font(DesignTokens.Font.heading())
                .foregroundColor(DesignTokens.Text.primary)
            content
        }
        .padding(DesignTokens.Spacing.md)
        .background(
            RoundedRectangle(cornerRadius: DesignTokens.Radius.xl)
                .fill(DesignTokens.Surface.base)
        )
    }
}

private struct MeetingLabeledField: View {
    let title: String
    @Binding var text: String
    var axis: Axis = .horizontal

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(DesignTokens.Font.caption())
                .foregroundColor(DesignTokens.Text.tertiary)
            if axis == .vertical {
                TextField(title, text: $text, axis: axis)
                    .textFieldStyle(MeetingFieldStyle())
                    .lineLimit(4...8)
            } else {
                TextField(title, text: $text, axis: axis)
                    .textFieldStyle(MeetingFieldStyle())
                    .lineLimit(1)
            }
        }
    }
}

private enum MeetingSkillLibraryEditorSheet: Identifiable {
    case createSubagent
    case createSkill(subagentID: String)
    case editSkill(skillID: String)

    var id: String {
        switch self {
        case .createSubagent:
            return "create-subagent"
        case .createSkill(let subagentID):
            return "create-skill-\(subagentID)"
        case .editSkill(let skillID):
            return "edit-skill-\(skillID)"
        }
    }
}

private enum MeetingSubagentEditorMode {
    case create

    var title: String {
        "新建 Subagent"
    }
}

private struct MeetingSubagentEditorView: View {
    let mode: MeetingSubagentEditorMode
    let onSave: @Sendable (String, String) async -> Bool

    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var coordinator = MeetingCoordinator.shared
    @State private var name = ""
    @State private var description = ""
    @State private var isSaving = false

    var body: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.md) {
            Text(mode.title)
                .font(DesignTokens.Font.title())
                .foregroundColor(DesignTokens.Text.primary)

            MeetingLabeledField(title: "名称", text: $name)
            MeetingLabeledField(title: "简述", text: $description, axis: .vertical)

            if let error = coordinator.lastOperationError, !error.isEmpty {
                Text(error)
                    .font(DesignTokens.Font.caption())
                    .foregroundColor(Color(red: 0.96, green: 0.45, blue: 0.45))
            }

            HStack {
                Spacer()
                Button("取消") {
                    dismiss()
                }
                .buttonStyle(.plain)
                .foregroundColor(DesignTokens.Text.secondary)

                Button {
                    Task {
                        isSaving = true
                        let didSave = await onSave(name, description)
                        isSaving = false
                        if didSave {
                            dismiss()
                        }
                    }
                } label: {
                    Text(isSaving ? "保存中..." : "保存")
                        .font(DesignTokens.Font.label())
                        .foregroundColor(.white)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(
                            RoundedRectangle(cornerRadius: DesignTokens.Radius.lg)
                                .fill(TerminalColors.blue)
                        )
                }
                .buttonStyle(.plain)
                .disabled(isSaving || name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(DesignTokens.Spacing.md)
        .frame(minWidth: 480, minHeight: 260, alignment: .topLeading)
        .background(Color.black)
        .onAppear {
            coordinator.clearLastOperationError()
        }
    }
}

private enum MeetingSkillEditorMode {
    case create(defaultSubagentID: String)
    case edit(skill: MeetingSkillInstall)

    var title: String {
        switch self {
        case .create:
            return "新建 Skill"
        case .edit:
            return "编辑 Skill"
        }
    }
}

private struct MeetingSkillEditorView: View {
    let mode: MeetingSkillEditorMode
    let userSubagents: [MeetingSkillSubagent]
    let onSave: @Sendable (String, String, String, String) async -> Bool

    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var coordinator = MeetingCoordinator.shared
    @State private var selectedSubagentID: String
    @State private var name: String
    @State private var description: String
    @State private var markdown: String
    @State private var isSaving = false

    init(
        mode: MeetingSkillEditorMode,
        userSubagents: [MeetingSkillSubagent],
        onSave: @escaping @Sendable (String, String, String, String) async -> Bool
    ) {
        self.mode = mode
        self.userSubagents = userSubagents
        self.onSave = onSave

        switch mode {
        case .create(let defaultSubagentID):
            _selectedSubagentID = State(initialValue: defaultSubagentID)
            _name = State(initialValue: "")
            _description = State(initialValue: "")
            _markdown = State(initialValue: "# SKILL\n")
        case .edit(let skill):
            _selectedSubagentID = State(initialValue: skill.subagentID)
            _name = State(initialValue: skill.displayName)
            _description = State(initialValue: skill.description)
            _markdown = State(initialValue: skill.skillMarkdown)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.md) {
            Text(mode.title)
                .font(DesignTokens.Font.title())
                .foregroundColor(DesignTokens.Text.primary)

            VStack(alignment: .leading, spacing: 4) {
                Text("归属 Subagent")
                    .font(DesignTokens.Font.caption())
                    .foregroundColor(DesignTokens.Text.tertiary)
                Picker("归属 Subagent", selection: $selectedSubagentID) {
                    ForEach(userSubagents) { subagent in
                        Text(subagent.name).tag(subagent.id)
                    }
                }
                .pickerStyle(.menu)
            }

            MeetingLabeledField(title: "名称", text: $name)
            MeetingLabeledField(title: "描述", text: $description, axis: .vertical)

            VStack(alignment: .leading, spacing: 4) {
                Text("SKILL.md")
                    .font(DesignTokens.Font.caption())
                    .foregroundColor(DesignTokens.Text.tertiary)
                TextEditor(text: $markdown)
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundColor(DesignTokens.Text.primary)
                    .frame(minHeight: 220)
                    .padding(8)
                    .background(
                        RoundedRectangle(cornerRadius: DesignTokens.Radius.lg)
                            .fill(DesignTokens.Surface.base)
                            .overlay(
                                RoundedRectangle(cornerRadius: DesignTokens.Radius.lg)
                                    .strokeBorder(DesignTokens.Border.standard, lineWidth: 1)
                            )
                    )
            }

            if let error = coordinator.lastOperationError, !error.isEmpty {
                Text(error)
                    .font(DesignTokens.Font.caption())
                    .foregroundColor(Color(red: 0.96, green: 0.45, blue: 0.45))
            }

            HStack {
                Spacer()
                Button("取消") {
                    dismiss()
                }
                .buttonStyle(.plain)
                .foregroundColor(DesignTokens.Text.secondary)

                Button {
                    Task {
                        isSaving = true
                        let didSave = await onSave(selectedSubagentID, name, description, markdown)
                        isSaving = false
                        if didSave {
                            dismiss()
                        }
                    }
                } label: {
                    Text(isSaving ? "保存中..." : "保存")
                        .font(DesignTokens.Font.label())
                        .foregroundColor(.white)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(
                            RoundedRectangle(cornerRadius: DesignTokens.Radius.lg)
                                .fill(TerminalColors.blue)
                        )
                }
                .buttonStyle(.plain)
                .disabled(
                    isSaving ||
                    userSubagents.isEmpty ||
                    selectedSubagentID.isEmpty ||
                    name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
                    markdown.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                )
            }
        }
        .padding(DesignTokens.Spacing.md)
        .frame(minWidth: 560, minHeight: 520, alignment: .topLeading)
        .background(Color.black)
        .onAppear {
            coordinator.clearLastOperationError()
        }
    }
}
