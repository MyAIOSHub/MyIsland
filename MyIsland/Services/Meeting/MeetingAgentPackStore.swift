import Foundation

struct MeetingRuntimeSkillDefinition: Codable, Equatable, Identifiable, Sendable {
    var id: String
    var title: String
    var summary: String
    var relativePath: String
    var sourceRefs: [String]
    var tags: [String]
}

struct MeetingAgoraRoomDefinition: Codable, Equatable, Identifiable, Sendable {
    var id: String { room.rawValue }
    var room: MeetingAgoraRoom
    var title: String
    var summary: String
    var relativePath: String
}

struct MeetingAgentPackManifest: Codable, Equatable, Sendable {
    var runtimeSkills: [MeetingRuntimeSkillDefinition]
    var agoraRooms: [MeetingAgoraRoomDefinition]
}

struct MeetingAgentPackStore {
    static let shared = MeetingAgentPackStore()

    private let packDirectoryURL: URL?
    private let loadedManifest: MeetingAgentPackManifest

    init(
        packDirectoryURL: URL? = MeetingAgentPackStore.defaultPackDirectoryURL()
    ) {
        self.packDirectoryURL = packDirectoryURL
        self.loadedManifest = Self.loadManifest(from: packDirectoryURL)
    }

    static func defaultPackDirectoryURL() -> URL? {
        Bundle.main.resourceURL?.appendingPathComponent("MeetingAgentPack", isDirectory: true)
    }

    var manifest: MeetingAgentPackManifest {
        loadedManifest
    }

    var runtimeSkillDefinitions: [MeetingRuntimeSkillDefinition] {
        manifest.runtimeSkills
    }

    func runtimeSkillDefinition(id: String) -> MeetingRuntimeSkillDefinition? {
        manifest.runtimeSkills.first(where: { $0.id == id })
    }

    func runtimeSkillDocument(for id: String) -> String {
        guard let definition = runtimeSkillDefinition(id: id) else {
            return fallbackRuntimeSkillDocument(id: id, title: id, summary: "围绕当前会议给出结构化问题、反例和下一步动作。")
        }

        if let content = loadDocument(relativePath: definition.relativePath) {
            return content
        }

        return fallbackRuntimeSkillDocument(
            id: definition.id,
            title: definition.title,
            summary: definition.summary
        )
    }

    func agoraRoomDefinition(_ room: MeetingAgoraRoom) -> MeetingAgoraRoomDefinition? {
        manifest.agoraRooms.first(where: { $0.room == room })
    }

    func agoraRoomDocument(for room: MeetingAgoraRoom) -> String {
        if let definition = agoraRoomDefinition(room),
           let content = loadDocument(relativePath: definition.relativePath) {
            return content
        }

        let summary = agoraRoomDefinition(room)?.summary ?? "围绕当前会议触发更锐利的讨论与追问。"
        return """
        # \(room.displayName)

        \(summary)

        输出要求：
        - 观点短促，适合会议中实时阅读
        - 优先暴露真正冲突点，而不是做温和总结
        - 最后给一句可直接照读的追问
        """
    }

    private static func loadManifest(from packDirectoryURL: URL?) -> MeetingAgentPackManifest {
        if let packDirectoryURL,
           let data = try? Data(contentsOf: packDirectoryURL.appendingPathComponent("manifest.json")),
           let manifest = try? JSONDecoder().decode(MeetingAgentPackManifest.self, from: data) {
            return manifest
        }

        return Self.fallbackManifest
    }

    private func loadDocument(relativePath: String) -> String? {
        guard let packDirectoryURL else { return nil }
        let url = packDirectoryURL.appendingPathComponent(relativePath)
        guard FileManager.default.fileExists(atPath: url.path),
              let content = try? String(contentsOf: url, encoding: .utf8) else {
            return nil
        }
        return content
    }

    private func fallbackRuntimeSkillDocument(id: String, title: String, summary: String) -> String {
        """
        ---
        id: \(id)
        title: \(title)
        ---

        # 任务
        \(summary)

        # 输出
        - corePoint
        - challenge
        - evidenceNeeded
        - followUpLine

        # 约束
        - 不复述原文
        - 只给最关键的一条判断
        - 下一句必须适合会议里直接说出口
        """
    }

    private static let fallbackManifest = MeetingAgentPackManifest(
        runtimeSkills: [
            .init(id: "meeting-socratic", title: "Socratic", summary: "追问定义、前提和反事实。", relativePath: "runtime-skills/meeting-socratic.md", sourceRefs: ["skillcollection/ljg-learn"], tags: ["questioning", "clarification"]),
            .init(id: "meeting-first-principles", title: "First Principles", summary: "拆到不可再分的关键约束和本质变量。", relativePath: "runtime-skills/meeting-first-principles.md", sourceRefs: ["skillcollection/ljg-think", "skillcollection/ljg-rank"], tags: ["principles", "decomposition"]),
            .init(id: "meeting-jtbd", title: "JTBD", summary: "追问用户工作和真实替代方案。", relativePath: "runtime-skills/meeting-jtbd.md", sourceRefs: ["internal"], tags: ["user", "jtbd"]),
            .init(id: "meeting-critic", title: "Critic", summary: "找出当前论证最脆弱的一环和反例。", relativePath: "runtime-skills/meeting-critic.md", sourceRefs: ["agora/forge"], tags: ["critic", "risk"]),
            .init(id: "meeting-tradeoff", title: "Tradeoff", summary: "明确取舍，不让方案评审停在口号。", relativePath: "runtime-skills/meeting-tradeoff.md", sourceRefs: ["internal"], tags: ["tradeoff", "decision"]),
            .init(id: "meeting-roundtable", title: "Roundtable", summary: "构造有张力的多角色对打。", relativePath: "runtime-skills/meeting-roundtable.md", sourceRefs: ["skillcollection/ljg-roundtable", "agora/atelier"], tags: ["roundtable", "debate"]),
            .init(id: "meeting-decision", title: "Decision", summary: "推动拍板，明确是否继续和为什么。", relativePath: "runtime-skills/meeting-decision.md", sourceRefs: ["agora/forge"], tags: ["decision"]),
            .init(id: "meeting-execution", title: "Execution", summary: "把卡点拆成 owner、依赖和下一步。", relativePath: "runtime-skills/meeting-execution.md", sourceRefs: ["internal"], tags: ["execution"]),
            .init(id: "meeting-risk", title: "Risk", summary: "从失败路径、代价和副作用做预演。", relativePath: "runtime-skills/meeting-risk.md", sourceRefs: ["agora/forge"], tags: ["risk"]),
            .init(id: "meeting-business", title: "Business", summary: "判断做出来有没有商业意义。", relativePath: "runtime-skills/meeting-business.md", sourceRefs: ["skillcollection/ljg-invest", "agora/bazaar"], tags: ["business"]),
            .init(id: "meeting-retrospective", title: "Retrospective", summary: "提炼可复用经验和失误模式。", relativePath: "runtime-skills/meeting-retrospective.md", sourceRefs: ["internal"], tags: ["retro"]),
            .init(id: "meeting-synthesizer", title: "Synthesizer", summary: "去重冲突、收敛总评和下一步。", relativePath: "runtime-skills/meeting-synthesizer.md", sourceRefs: ["skillcollection/ljg-writes", "agora/atelier"], tags: ["synthesis"]),
            .init(id: "meeting-unit-economics", title: "Unit Economics", summary: "评估收入、成本和可持续性。", relativePath: "runtime-skills/meeting-unit-economics.md", sourceRefs: ["agora/bazaar", "skillcollection/market-sizing"], tags: ["business", "unit-economics"]),
            .init(id: "meeting-moat", title: "Moat", summary: "检查优势是否可复利、可持续。", relativePath: "runtime-skills/meeting-moat.md", sourceRefs: ["agora/bazaar"], tags: ["business", "moat"]),
            .init(id: "meeting-five-whys", title: "Five Whys", summary: "沿着症状持续追问到根因。", relativePath: "runtime-skills/meeting-five-whys.md", sourceRefs: ["internal"], tags: ["root-cause"]),
            .init(id: "meeting-pattern", title: "Pattern", summary: "抽取可复用的成功模式。", relativePath: "runtime-skills/meeting-pattern.md", sourceRefs: ["internal"], tags: ["pattern"]),
            .init(id: "meeting-antipattern", title: "AntiPattern", summary: "指出正在重复出现的坏模式。", relativePath: "runtime-skills/meeting-antipattern.md", sourceRefs: ["internal"], tags: ["antipattern"]),
            .init(id: "meeting-analogies", title: "Analogies", summary: "借相邻领域的类比打开发散。", relativePath: "runtime-skills/meeting-analogies.md", sourceRefs: ["internal"], tags: ["analogy"]),
            .init(id: "meeting-divergence", title: "Divergence", summary: "在保持边界的前提下拉开新角度。", relativePath: "runtime-skills/meeting-divergence.md", sourceRefs: ["agora/atelier"], tags: ["divergence"])
        ],
        agoraRooms: [
            .init(room: .forge, title: "Forge", summary: "适合需求澄清、方案评审和风险推演，重点打磨问题定义和方案强度。", relativePath: "agora-rooms/forge.md"),
            .init(room: .bazaar, title: "Bazaar", summary: "适合商业判断、资源配置和 ROI 讨论，重点检查价值闭环。", relativePath: "agora-rooms/bazaar.md"),
            .init(room: .atelier, title: "Atelier", summary: "适合发散、破冰和提词板，重点产出可直接接话的下一句。", relativePath: "agora-rooms/atelier.md"),
            .init(room: .clinic, title: "Clinic", summary: "适合低能量、复盘和心理阻滞，重点拆出真实阻滞点。", relativePath: "agora-rooms/clinic.md"),
            .init(room: .hearth, title: "Hearth", summary: "适合协作冲突和关系摩擦，重点修正协作接口与预期。", relativePath: "agora-rooms/hearth.md"),
            .init(room: .oracle, title: "Oracle", summary: "适合强方向判断和拍板场景，重点迫使团队给出明确选择。", relativePath: "agora-rooms/oracle.md")
        ]
    )
}
