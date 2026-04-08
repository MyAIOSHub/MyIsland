//
//  SessionState.swift
//  MyIsland
//
//  Unified state model for a Claude session.
//  Consolidates all state that was previously spread across multiple components.
//

import Foundation

/// Where a session was launched from
enum SessionSourceApp: String, Equatable, Sendable {
    case terminal       // Plain terminal (Terminal.app, iTerm2, etc.)
    case claudeCode     // Claude Code CLI
    case claudeDesktop  // Claude Desktop app
    case codexCLI       // Codex CLI
    case codexDesktop   // Codex Desktop app
    case geminiCLI      // Gemini CLI
    case copilotCLI     // GitHub Copilot CLI
    case antigravity    // Antigravity IDE
    case tmux           // tmux session
    case unknown

    var displayName: String {
        switch self {
        case .terminal:      return "终端"
        case .claudeCode:    return "Claude Code"
        case .claudeDesktop: return "Claude App"
        case .codexCLI:      return "Codex"
        case .codexDesktop:  return "Codex App"
        case .geminiCLI:     return "Gemini"
        case .copilotCLI:    return "Copilot"
        case .antigravity:   return "Antigravity"
        case .tmux:          return "tmux"
        case .unknown:       return "未知"
        }
    }

    var iconName: String {
        switch self {
        case .terminal:      return "terminal"
        case .claudeCode:    return "terminal.fill"
        case .claudeDesktop: return "message"
        case .codexCLI:      return "chevron.left.forwardslash.chevron.right"
        case .codexDesktop:  return "chevron.left.forwardslash.chevron.right"
        case .geminiCLI:     return "sparkle"
        case .copilotCLI:    return "airplane"
        case .antigravity:   return "atom"
        case .tmux:          return "rectangle.split.2x1"
        case .unknown:       return "questionmark.circle"
        }
    }

    /// Whether this source supports direct TTY input
    var supportsTTYInput: Bool {
        switch self {
        case .terminal, .tmux, .claudeCode, .codexCLI, .geminiCLI, .copilotCLI: return true
        default: return false
        }
    }

    /// Bundle identifier to activate when jumping to reply
    var bundleIdentifier: String? {
        switch self {
        case .claudeDesktop: return "com.anthropic.claudefordesktop"
        case .claudeCode:    return "com.anthropic.claudefordesktop"
        case .codexDesktop:  return "com.openai.codex"
        case .codexCLI:      return "com.openai.codex"
        case .antigravity:   return "com.google.antigravity"
        default: return nil
        }
    }

    /// Detect source from hook event's source field (preferred) or process tree (fallback)
    static func detect(source: String?, pid: Int, tree: [Int: ProcessInfo]) -> SessionSourceApp {
        // Prefer hook-reported source (reliable, no process tree guessing)
        if let source, !source.isEmpty, source != "unknown" {
            switch source {
            case "claude":         return .claudeCode
            case "codex":          return .codexCLI
            case "gemini":         return .geminiCLI
            case "github-copilot": return .copilotCLI
            default: break
            }
        }

        // Fallback: walk process tree
        return detectFromProcessTree(pid: pid, tree: tree)
    }

    /// Legacy detection by walking the process tree from the given PID
    static func detect(pid: Int, tree: [Int: ProcessInfo]) -> SessionSourceApp {
        return detect(source: nil, pid: pid, tree: tree)
    }

    private static func detectFromProcessTree(pid: Int, tree: [Int: ProcessInfo]) -> SessionSourceApp {
        var current = pid
        var depth = 0

        while current > 1 && depth < 20 {
            guard let info = tree[current] else { break }
            let cmd = info.command.lowercased()

            if cmd.contains("claude") && (cmd.contains("helper") || cmd.contains("electron") || cmd.contains("disclaimer")) {
                return .claudeDesktop
            }
            if cmd.contains("codex") && !cmd.contains("hooks") {
                if cmd.contains("app-server") || cmd.contains("/applications/codex") {
                    return .codexDesktop
                }
            }
            if cmd.contains("antigravity") {
                return .antigravity
            }
            if cmd.contains("tmux") {
                return .tmux
            }
            if cmd.contains("terminal") || cmd.contains("iterm") || cmd.contains("warp")
                || cmd.contains("ghostty") || cmd.contains("kitty") || cmd.contains("alacritty") {
                return .terminal
            }

            current = info.ppid
            depth += 1
        }

        return .unknown
    }
}

/// Complete state for a single Claude session
/// This is the single source of truth - all state reads and writes go through SessionStore
struct SessionState: Equatable, Identifiable, Sendable {
    // MARK: - Identity

    let sessionId: String
    let cwd: String
    let projectName: String

    // MARK: - Instance Metadata

    var pid: Int?
    var tty: String?
    var isInTmux: Bool
    var sourceApp: SessionSourceApp

    // MARK: - State Machine

    /// Current phase in the session lifecycle
    var phase: SessionPhase

    // MARK: - Chat History

    /// All chat items for this session (replaces ChatHistoryManager.histories)
    var chatItems: [ChatHistoryItem]

    // MARK: - Tool Tracking

    /// Unified tool tracker (replaces 6+ dictionaries in ChatHistoryManager)
    var toolTracker: ToolTracker

    // MARK: - Subagent State

    /// State for Task tools and their nested subagent tools
    var subagentState: SubagentState

    // MARK: - Conversation Info (from JSONL parsing)

    var conversationInfo: ConversationInfo

    // MARK: - Clear Reconciliation

    /// When true, the next file update should reconcile chatItems with parser state
    /// This removes pre-/clear items that no longer exist in the JSONL
    var needsClearReconciliation: Bool

    // MARK: - Tool History

    /// Chronological history of tool executions for activity display
    var toolHistory: [ToolExecution] = []

    /// Number of tools currently running
    var activeToolCount: Int { toolHistory.filter(\.isActive).count }

    /// Total number of completed tool executions
    var completedToolCount: Int { toolHistory.filter { !$0.isActive }.count }

    /// Total files modified (unique file_path values from Edit/Write tools)
    var filesModifiedCount: Int {
        Set(toolHistory.compactMap { exec in
            guard exec.toolName == "Edit" || exec.toolName == "Write" else { return nil as String? }
            return exec.toolInput
        }).count
    }

    /// Total messages exchanged (user + assistant messages in chatItems)
    var messagesExchangedCount: Int {
        chatItems.filter { item in
            switch item.type {
            case .user, .assistant: return true
            default: return false
            }
        }.count
    }

    // MARK: - Timestamps

    var lastActivity: Date
    var createdAt: Date

    // MARK: - Identifiable

    var id: String { sessionId }

    // MARK: - Initialization

    nonisolated init(
        sessionId: String,
        cwd: String,
        projectName: String? = nil,
        pid: Int? = nil,
        tty: String? = nil,
        isInTmux: Bool = false,
        sourceApp: SessionSourceApp = .unknown,
        phase: SessionPhase = .idle,
        chatItems: [ChatHistoryItem] = [],
        toolTracker: ToolTracker = ToolTracker(),
        subagentState: SubagentState = SubagentState(),
        conversationInfo: ConversationInfo = ConversationInfo(
            summary: nil, lastMessage: nil, lastMessageRole: nil,
            lastToolName: nil, firstUserMessage: nil, lastUserMessageDate: nil
        ),
        needsClearReconciliation: Bool = false,
        toolHistory: [ToolExecution] = [],
        lastActivity: Date = Date(),
        createdAt: Date = Date()
    ) {
        self.sessionId = sessionId
        self.cwd = cwd
        self.projectName = projectName ?? URL(fileURLWithPath: cwd).lastPathComponent
        self.pid = pid
        self.tty = tty
        self.isInTmux = isInTmux
        self.sourceApp = sourceApp
        self.phase = phase
        self.chatItems = chatItems
        self.toolTracker = toolTracker
        self.subagentState = subagentState
        self.conversationInfo = conversationInfo
        self.needsClearReconciliation = needsClearReconciliation
        self.toolHistory = toolHistory
        self.lastActivity = lastActivity
        self.createdAt = createdAt
    }

    // MARK: - Derived Properties

    /// Whether this session needs user attention
    var needsAttention: Bool {
        phase.needsAttention
    }

    /// The active permission context, if any
    var activePermission: PermissionContext? {
        if case .waitingForApproval(let ctx) = phase {
            return ctx
        }
        return nil
    }

    // MARK: - UI Convenience Properties

    /// Stable identity for SwiftUI (combines PID and sessionId for animation stability)
    var stableId: String {
        if let pid = pid {
            return "\(pid)-\(sessionId)"
        }
        return sessionId
    }

    /// Display title: project name for main sessions, sessionId for subagents
    var displayTitle: String {
        if sessionId.hasPrefix("agent-") {
            return sessionId
        }
        return projectName
    }

    /// Best hint for matching window title
    var windowHint: String {
        conversationInfo.summary ?? projectName
    }

    /// Pending tool name if waiting for approval
    var pendingToolName: String? {
        activePermission?.toolName
    }

    /// Pending tool use ID
    var pendingToolId: String? {
        activePermission?.toolUseId
    }

    /// Formatted pending tool input for display
    var pendingToolInput: String? {
        activePermission?.formattedInput
    }

    /// Parse AskUserQuestion tool_input into structured questions
    var pendingQuestions: [QuestionItem]? {
        guard let permission = activePermission,
              permission.toolName == "AskUserQuestion",
              let input = permission.toolInput,
              let questionsRaw = input["questions"]?.value as? [[String: Any]] else { return nil }
        return questionsRaw.compactMap { q -> QuestionItem? in
            guard let question = q["question"] as? String else { return nil }
            var options: [QuestionOption] = []
            if let opts = q["options"] as? [[String: Any]] {
                options = opts.compactMap { opt in
                    guard let label = opt["label"] as? String else { return nil }
                    return QuestionOption(label: label, description: opt["description"] as? String)
                }
            }
            return QuestionItem(question: question, header: q["header"] as? String, options: options)
        }
    }

    /// Last message content
    var lastMessage: String? {
        conversationInfo.lastMessage
    }

    /// Last message role
    var lastMessageRole: String? {
        conversationInfo.lastMessageRole
    }

    /// Last tool name
    var lastToolName: String? {
        conversationInfo.lastToolName
    }

    /// Summary
    var summary: String? {
        conversationInfo.summary
    }

    /// First user message
    var firstUserMessage: String? {
        conversationInfo.firstUserMessage
    }

    /// Last user message date
    var lastUserMessageDate: Date? {
        conversationInfo.lastUserMessageDate
    }

    /// Whether the session can be interacted with
    var canInteract: Bool {
        phase.needsAttention
    }
}

// MARK: - Tool Tracker

/// Unified tool tracking - replaces multiple dictionaries in ChatHistoryManager
struct ToolTracker: Equatable, Sendable {
    /// Tools currently in progress, keyed by tool_use_id
    var inProgress: [String: ToolInProgress]

    /// All tool IDs we've seen (for deduplication)
    var seenIds: Set<String>

    /// Last JSONL file offset for incremental parsing
    var lastSyncOffset: UInt64

    /// Last sync timestamp
    var lastSyncTime: Date?

    nonisolated init(
        inProgress: [String: ToolInProgress] = [:],
        seenIds: Set<String> = [],
        lastSyncOffset: UInt64 = 0,
        lastSyncTime: Date? = nil
    ) {
        self.inProgress = inProgress
        self.seenIds = seenIds
        self.lastSyncOffset = lastSyncOffset
        self.lastSyncTime = lastSyncTime
    }

    /// Mark a tool ID as seen, returns true if it was new
    nonisolated mutating func markSeen(_ id: String) -> Bool {
        seenIds.insert(id).inserted
    }

    /// Check if a tool ID has been seen
    nonisolated func hasSeen(_ id: String) -> Bool {
        seenIds.contains(id)
    }

    /// Start tracking a tool
    nonisolated mutating func startTool(id: String, name: String) {
        guard markSeen(id) else { return }
        inProgress[id] = ToolInProgress(
            id: id,
            name: name,
            startTime: Date(),
            phase: .running
        )
    }

    /// Complete a tool
    nonisolated mutating func completeTool(id: String, success: Bool) {
        inProgress.removeValue(forKey: id)
    }
}

/// A tool currently in progress
struct ToolInProgress: Equatable, Sendable {
    let id: String
    let name: String
    let startTime: Date
    var phase: ToolInProgressPhase
}

/// Phase of a tool in progress
enum ToolInProgressPhase: Equatable, Sendable {
    case starting
    case running
    case pendingApproval
}

// MARK: - Subagent State

/// State for Task (subagent) tools
struct SubagentState: Equatable, Sendable {
    /// Active Task tools, keyed by task tool_use_id
    var activeTasks: [String: TaskContext]

    /// Ordered stack of active task IDs (most recent last) - used for proper tool assignment
    /// When multiple Tasks run in parallel, we use insertion order rather than timestamps
    var taskStack: [String]

    /// Mapping of agentId to Task description (for AgentOutputTool display)
    var agentDescriptions: [String: String]

    nonisolated init(activeTasks: [String: TaskContext] = [:], taskStack: [String] = [], agentDescriptions: [String: String] = [:]) {
        self.activeTasks = activeTasks
        self.taskStack = taskStack
        self.agentDescriptions = agentDescriptions
    }

    /// Whether there's an active subagent
    nonisolated var hasActiveSubagent: Bool {
        !activeTasks.isEmpty
    }

    /// Start tracking a Task tool
    nonisolated mutating func startTask(taskToolId: String, description: String? = nil) {
        activeTasks[taskToolId] = TaskContext(
            taskToolId: taskToolId,
            startTime: Date(),
            agentId: nil,
            description: description,
            subagentTools: []
        )
    }

    /// Stop tracking a Task tool
    nonisolated mutating func stopTask(taskToolId: String) {
        activeTasks.removeValue(forKey: taskToolId)
    }

    /// Set the agentId for a Task (called when agent file is discovered)
    nonisolated mutating func setAgentId(_ agentId: String, for taskToolId: String) {
        activeTasks[taskToolId]?.agentId = agentId
        if let description = activeTasks[taskToolId]?.description {
            agentDescriptions[agentId] = description
        }
    }

    /// Add a subagent tool to a specific Task by ID
    nonisolated mutating func addSubagentToolToTask(_ tool: SubagentToolCall, taskId: String) {
        activeTasks[taskId]?.subagentTools.append(tool)
    }

    /// Set all subagent tools for a specific Task (used when updating from agent file)
    nonisolated mutating func setSubagentTools(_ tools: [SubagentToolCall], for taskId: String) {
        activeTasks[taskId]?.subagentTools = tools
    }

    /// Add a subagent tool to the most recent active Task
    nonisolated mutating func addSubagentTool(_ tool: SubagentToolCall) {
        // Find most recent active task (for parallel Task support)
        guard let mostRecentTaskId = activeTasks.keys.max(by: {
            (activeTasks[$0]?.startTime ?? .distantPast) < (activeTasks[$1]?.startTime ?? .distantPast)
        }) else { return }

        activeTasks[mostRecentTaskId]?.subagentTools.append(tool)
    }

    /// Update the status of a subagent tool across all active Tasks
    nonisolated mutating func updateSubagentToolStatus(toolId: String, status: ToolStatus) {
        for taskId in activeTasks.keys {
            if let index = activeTasks[taskId]?.subagentTools.firstIndex(where: { $0.id == toolId }) {
                activeTasks[taskId]?.subagentTools[index].status = status
                return
            }
        }
    }
}

/// Context for an active Task tool
struct TaskContext: Equatable, Sendable {
    let taskToolId: String
    let startTime: Date
    var agentId: String?
    var description: String?
    var subagentTools: [SubagentToolCall]
}

// MARK: - Tool Execution History

/// Represents a single tool execution for activity timeline display
struct ToolExecution: Identifiable, Equatable, Sendable {
    let id: UUID
    let toolUseId: String
    let toolName: String
    let toolInput: String?
    let startedAt: Date
    var completedAt: Date?
    var result: String?

    var isActive: Bool { completedAt == nil }

    /// Human-readable elapsed time
    var elapsed: String {
        let reference = completedAt ?? Date()
        let interval = reference.timeIntervalSince(startedAt)
        if interval < 1 { return "<1s" }
        if interval < 60 { return "\(Int(interval))s" }
        if interval < 3600 { return "\(Int(interval / 60))m \(Int(interval.truncatingRemainder(dividingBy: 60)))s" }
        return "\(Int(interval / 3600))h \(Int((interval.truncatingRemainder(dividingBy: 3600)) / 60))m"
    }

    /// Time since completion (or since start if still active)
    var timeAgo: String {
        let reference = completedAt ?? startedAt
        let interval = Date().timeIntervalSince(reference)
        if interval < 1 { return "now" }
        if interval < 60 { return "\(Int(interval))s ago" }
        if interval < 3600 { return "\(Int(interval / 60))m ago" }
        return "\(Int(interval / 3600))h ago"
    }

    nonisolated init(
        id: UUID = UUID(),
        toolUseId: String,
        toolName: String,
        toolInput: String? = nil,
        startedAt: Date = Date(),
        completedAt: Date? = nil,
        result: String? = nil
    ) {
        self.id = id
        self.toolUseId = toolUseId
        self.toolName = toolName
        self.toolInput = toolInput
        self.startedAt = startedAt
        self.completedAt = completedAt
        self.result = result
    }
}
