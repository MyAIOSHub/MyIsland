//
//  ClaudeInstancesView.swift
//  MyIsland
//
//  Minimal instances list matching Dynamic Island aesthetic
//

import Combine
import SwiftUI

struct ClaudeInstancesView: View {
    @ObservedObject var sessionMonitor: ClaudeSessionMonitor
    @ObservedObject var viewModel: NotchViewModel

    @State private var showAll = false

    private static let maxVisibleSessions = 5

    var body: some View {
        if sessionMonitor.instances.isEmpty {
            emptyState
        } else {
            instancesList
        }
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: DesignTokens.Spacing.sm) {
            Text("暂无会话")
                .font(DesignTokens.Font.heading())
                .foregroundColor(DesignTokens.Text.tertiary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Instances List

    /// Priority: active (approval/processing/compacting) > waitingForInput > idle
    /// Secondary sort: by last user message date (stable - doesn't change when agent responds)
    /// Note: approval requests stay in their date-based position to avoid layout shift
    private var sortedInstances: [SessionState] {
        sessionMonitor.instances.sorted { a, b in
            let priorityA = phasePriority(a.phase)
            let priorityB = phasePriority(b.phase)
            if priorityA != priorityB {
                return priorityA < priorityB
            }
            // Sort by last user message date (more recent first)
            // Fall back to lastActivity if no user messages yet
            let dateA = a.lastUserMessageDate ?? a.lastActivity
            let dateB = b.lastUserMessageDate ?? b.lastActivity
            return dateA > dateB
        }
    }

    /// Lower number = higher priority
    /// Approval requests share priority with processing to maintain stable ordering
    private func phasePriority(_ phase: SessionPhase) -> Int {
        switch phase {
        case .waitingForApproval, .processing, .compacting: return 0
        case .waitingForInput: return 1
        case .idle, .ended: return 2
        }
    }

    private var displayedInstances: [SessionState] {
        if showAll {
            return sortedInstances
        }
        return Array(sortedInstances.prefix(Self.maxVisibleSessions))
    }

    private var instancesList: some View {
        ScrollView(.vertical, showsIndicators: false) {
            LazyVStack(spacing: 2) {
                ForEach(displayedInstances) { session in
                    InstanceRow(
                        session: session,
                        onFocus: { focusSession(session) },
                        onChat: { openChat(session) },
                        onArchive: { archiveSession(session) },
                        onApprove: { approveSession(session) },
                        onReject: { rejectSession(session) },
                        onSelectOption: { qIdx, oIdx in
                            selectOption(session, questionIndex: qIdx, optionIndex: oIdx)
                        }
                    )
                    .id(session.stableId)
                }

                // Show all button when there are more sessions
                if !showAll && sortedInstances.count > Self.maxVisibleSessions {
                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            showAll = true
                        }
                    } label: {
                        Text("显示全部 \(sortedInstances.count) 个会话")
                            .font(.system(size: 10, weight: .medium, design: .monospaced))
                            .foregroundStyle(DesignTokens.Text.secondary)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, DesignTokens.Spacing.xs)
                    }
                    .buttonStyle(.plain)
                    .onHover { hovering in
                        if hovering {
                            NSCursor.pointingHand.push()
                        } else {
                            NSCursor.pop()
                        }
                    }
                }
            }
            .padding(.vertical, 4)
        }
        .scrollBounceBehavior(.basedOnSize)
    }

    // MARK: - Actions

    private func focusSession(_ session: SessionState) {
        guard session.isInTmux else { return }

        Task {
            if let pid = session.pid {
                _ = await YabaiController.shared.focusWindow(forClaudePid: pid)
            } else {
                _ = await YabaiController.shared.focusWindow(forWorkingDirectory: session.cwd)
            }
        }
    }

    private func openChat(_ session: SessionState) {
        viewModel.showChat(for: session)
    }

    private func approveSession(_ session: SessionState) {
        sessionMonitor.approvePermission(sessionId: session.sessionId)
    }

    private func rejectSession(_ session: SessionState) {
        sessionMonitor.denyPermission(sessionId: session.sessionId, reason: nil)
    }

    private func archiveSession(_ session: SessionState) {
        sessionMonitor.archiveSession(sessionId: session.sessionId)
    }

    private func selectOption(_ session: SessionState, questionIndex: Int, optionIndex: Int) {
        sessionMonitor.respondToQuestion(session: session, optionIndex: optionIndex)
    }
}

// MARK: - Instance Row

struct InstanceRow: View {
    let session: SessionState
    let onFocus: () -> Void
    let onChat: () -> Void
    let onArchive: () -> Void
    let onApprove: () -> Void
    let onReject: () -> Void
    var onSelectOption: ((Int, Int) -> Void)?

    @State private var isHovered = false
    @State private var isExpanded = false
    @State private var spinnerPhase = 0
    @State private var isYabaiAvailable = false

    private let claudeOrange = TerminalColors.prompt
    private let spinnerSymbols = ["·", "✢", "✳", "∗", "✻", "✽"]
    private let spinnerTimer = Timer.publish(every: 0.15, on: .main, in: .common).autoconnect()

    /// Whether this session is actively doing work
    private var isActivelyProcessing: Bool {
        session.phase == .processing || session.phase == .compacting
    }

    /// The most recent active tool execution
    private var currentToolExecution: ToolExecution? {
        session.toolHistory.last(where: { $0.isActive })
    }

    /// Whether we're showing the approval UI
    private var isWaitingForApproval: Bool {
        session.phase.isWaitingForApproval
    }

    /// Whether the pending tool requires interactive input (not just approve/deny)
    private var isInteractiveTool: Bool {
        guard let toolName = session.pendingToolName else { return false }
        return toolName == "AskUserQuestion"
    }

    var body: some View {
        VStack(spacing: 0) {
            // Main row
            HStack(alignment: .center, spacing: 10) {
                // State indicator on left
                stateIndicator
                    .frame(width: 14)

                // Text content
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(session.displayTitle)
                            .font(DesignTokens.Font.heading())
                            .foregroundColor(DesignTokens.Text.primary)
                            .lineLimit(1)

                        // Source app badge
                        if session.sourceApp != .unknown {
                            HStack(spacing: 2) {
                                Image(systemName: session.sourceApp.iconName)
                                    .font(.system(size: 7))
                                Text(session.sourceApp.displayName)
                                    .font(.system(size: 8, weight: .medium))
                            }
                            .foregroundColor(DesignTokens.Text.tertiary)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 2)
                            .background(Capsule().fill(DesignTokens.Surface.elevated))
                        }
                    }

                    // Show current tool if actively processing
                    if isActivelyProcessing, let currentTool = currentToolExecution {
                        HStack(spacing: 4) {
                            Text(MCPToolFormatter.formatToolName(currentTool.toolName))
                                .font(.system(size: 11, weight: .medium, design: .monospaced))
                                .foregroundColor(claudeOrange)
                            if let input = currentTool.toolInput {
                                Text(input)
                                    .font(.system(size: 11, design: .monospaced))
                                    .foregroundColor(DesignTokens.Text.secondary)
                                    .lineLimit(1)
                            }
                            Text(currentTool.elapsed)
                                .font(.system(size: 10))
                                .foregroundColor(DesignTokens.Text.tertiary)
                        }
                    }
                    // Show tool call when waiting for approval, otherwise last activity
                    else if isWaitingForApproval, let toolName = session.pendingToolName {
                        // Show tool name in amber + input on same line
                        HStack(spacing: 4) {
                            Text(MCPToolFormatter.formatToolName(toolName))
                                .font(.system(size: 11, weight: .medium, design: .monospaced))
                                .foregroundColor(TerminalColors.amber.opacity(0.9))
                            if isInteractiveTool {
                                Text("需要你的输入")
                                    .font(.system(size: 11))
                                    .foregroundColor(DesignTokens.Text.secondary)
                                    .lineLimit(1)
                            } else if let input = session.pendingToolInput {
                                Text(input)
                                    .font(.system(size: 11))
                                    .foregroundColor(DesignTokens.Text.secondary)
                                    .lineLimit(1)
                            }
                        }
                    } else if let role = session.lastMessageRole {
                        switch role {
                        case "tool":
                            // Tool call - show tool name + input
                            HStack(spacing: 4) {
                                if let toolName = session.lastToolName {
                                    Text(MCPToolFormatter.formatToolName(toolName))
                                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                                        .foregroundColor(DesignTokens.Text.secondary)
                                }
                                if let input = session.lastMessage {
                                    Text(input)
                                        .font(.system(size: 11))
                                        .foregroundColor(DesignTokens.Text.tertiary)
                                        .lineLimit(1)
                                }
                            }
                        case "user":
                            // User message - prefix with "You:"
                            HStack(spacing: 4) {
                                Text("你：")
                                    .font(.system(size: 11, weight: .medium))
                                    .foregroundColor(DesignTokens.Text.secondary)
                                if let msg = session.lastMessage {
                                    Text(msg)
                                        .font(.system(size: 11))
                                        .foregroundColor(DesignTokens.Text.tertiary)
                                        .lineLimit(1)
                                }
                            }
                        default:
                            // Assistant message - just show text
                            if let msg = session.lastMessage {
                                Text(msg)
                                    .font(.system(size: 11))
                                    .foregroundColor(DesignTokens.Text.tertiary)
                                    .lineLimit(1)
                            }
                        }
                    } else if let lastMsg = session.lastMessage {
                        Text(lastMsg)
                            .font(.system(size: 11))
                            .foregroundColor(DesignTokens.Text.tertiary)
                            .lineLimit(1)
                    }
                }

                Spacer(minLength: 0)

                // Action icons or approval buttons
                if isWaitingForApproval && isInteractiveTool {
                    // Interactive tools like AskUserQuestion - show chat + terminal buttons
                    HStack(spacing: 8) {
                        IconButton(icon: "bubble.left") {
                            onChat()
                        }

                        // Go to Terminal button (only if yabai available)
                        if isYabaiAvailable {
                            TerminalButton(
                                isEnabled: session.isInTmux,
                                onTap: { onFocus() }
                            )
                        }
                    }
                    .transition(.opacity.combined(with: .scale(scale: 0.9)))
                } else if isWaitingForApproval {
                    InlineApprovalButtons(
                        onChat: onChat,
                        onApprove: onApprove,
                        onReject: onReject
                    )
                    .transition(.opacity.combined(with: .scale(scale: 0.9)))
                } else {
                    HStack(spacing: 8) {
                        // Chat icon - always show
                        IconButton(icon: "bubble.left") {
                            onChat()
                        }

                        // Focus icon (only for tmux instances with yabai)
                        if session.isInTmux && isYabaiAvailable {
                            IconButton(icon: "eye") {
                                onFocus()
                            }
                        }

                        // Archive button - only for idle or completed sessions
                        if session.phase == .idle || session.phase == .waitingForInput {
                            IconButton(icon: "archivebox") {
                                onArchive()
                            }
                        }
                    }
                    .transition(.opacity.combined(with: .scale(scale: 0.9)))
                }
            }
            .padding(.leading, 8)
            .padding(.trailing, 14)
            .padding(.vertical, 10)

            // AskUserQuestion options (auto-expanded)
            if isInteractiveTool, let questions = session.pendingQuestions, !questions.isEmpty {
                AskUserQuestionOptionsView(
                    questions: questions,
                    onSelectOption: onSelectOption,
                    onJumpToSource: { onFocus() }
                )
                .padding(.horizontal, 12)
                .padding(.bottom, 8)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
            // Collapsible detail section
            else if isExpanded || isActivelyProcessing {
                instanceDetailSection
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .contentShape(Rectangle())
        .onTapGesture(count: 1) {
            onChat()
        }
        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: isWaitingForApproval)
        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: isActivelyProcessing)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(isHovered ? DesignTokens.Surface.elevated : Color.clear)
        )
        .onHover { isHovered = $0 }
        .task {
            isYabaiAvailable = await WindowFinder.shared.isYabaiAvailable()
        }
    }

    // MARK: - Detail Section

    @ViewBuilder
    private var instanceDetailSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            // Session stats bar
            HStack(spacing: 12) {
                sessionStatItem(
                    icon: "wrench",
                    value: "\(session.toolHistory.count)",
                    label: "工具"
                )
                sessionStatItem(
                    icon: "doc",
                    value: "\(session.filesModifiedCount)",
                    label: "文件"
                )
                sessionStatItem(
                    icon: "bubble.left.and.bubble.right",
                    value: "\(session.messagesExchangedCount)",
                    label: "消息"
                )
                Spacer()
            }
            .padding(.horizontal, 12)

            // Activity timeline
            if !session.toolHistory.isEmpty {
                ActivityTimelineView(
                    toolHistory: session.toolHistory,
                    isProcessing: isActivelyProcessing
                )
            }
        }
        .padding(.bottom, 8)
    }

    private func sessionStatItem(icon: String, value: String, label: String) -> some View {
        HStack(spacing: 3) {
            Image(systemName: icon)
                .font(.system(size: 9))
                .foregroundColor(DesignTokens.Text.tertiary)
            Text(value)
                .font(.system(size: 10, weight: .medium, design: .monospaced))
                .foregroundColor(DesignTokens.Text.secondary)
            Text(label)
                .font(.system(size: 10))
                .foregroundColor(DesignTokens.Text.tertiary)
        }
    }

    @ViewBuilder
    private var stateIndicator: some View {
        switch session.phase {
        case .processing, .compacting:
            Text(spinnerSymbols[spinnerPhase % spinnerSymbols.count])
                .font(.system(size: 12, weight: .bold))
                .foregroundColor(claudeOrange)
                .onReceive(spinnerTimer) { _ in
                    spinnerPhase = (spinnerPhase + 1) % spinnerSymbols.count
                }
        case .waitingForApproval:
            Text(spinnerSymbols[spinnerPhase % spinnerSymbols.count])
                .font(.system(size: 12, weight: .bold))
                .foregroundColor(TerminalColors.amber)
                .onReceive(spinnerTimer) { _ in
                    spinnerPhase = (spinnerPhase + 1) % spinnerSymbols.count
                }
        case .waitingForInput:
            Circle()
                .fill(TerminalColors.green)
                .frame(width: 6, height: 6)
        case .idle, .ended:
            Circle()
                .fill(Color.white.opacity(0.2))
                .frame(width: 6, height: 6)
        }
    }

}

// MARK: - Inline Approval Buttons

/// Compact inline approval buttons with staggered animation
struct InlineApprovalButtons: View {
    let onChat: () -> Void
    let onApprove: () -> Void
    let onReject: () -> Void

    @State private var showChatButton = false
    @State private var showDenyButton = false
    @State private var showAllowButton = false

    var body: some View {
        HStack(spacing: 6) {
            // Chat button
            IconButton(icon: "bubble.left") {
                onChat()
            }
            .opacity(showChatButton ? 1 : 0)
            .scaleEffect(showChatButton ? 1 : 0.8)

            Button {
                onReject()
            } label: {
                Text("拒绝")
                    .font(DesignTokens.Font.body())
                    .foregroundColor(DesignTokens.Text.secondary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(DesignTokens.Surface.hover)
                    .clipShape(Capsule())
            }
            .buttonStyle(.plain)
            .opacity(showDenyButton ? 1 : 0)
            .scaleEffect(showDenyButton ? 1 : 0.8)

            Button {
                onApprove()
            } label: {
                Text("允许")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.black)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(Color.white.opacity(0.9))
                    .clipShape(Capsule())
            }
            .buttonStyle(.plain)
            .opacity(showAllowButton ? 1 : 0)
            .scaleEffect(showAllowButton ? 1 : 0.8)
        }
        .onAppear {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.7).delay(0.0)) {
                showChatButton = true
            }
            withAnimation(.spring(response: 0.3, dampingFraction: 0.7).delay(0.05)) {
                showDenyButton = true
            }
            withAnimation(.spring(response: 0.3, dampingFraction: 0.7).delay(0.1)) {
                showAllowButton = true
            }
        }
    }
}

// MARK: - Icon Button

struct IconButton: View {
    let icon: String
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button {
            action()
        } label: {
            Image(systemName: icon)
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(isHovered ? DesignTokens.Text.primary : DesignTokens.Text.tertiary)
                .frame(width: 24, height: 24)
                .background(
                    RoundedRectangle(cornerRadius: DesignTokens.Radius.md)
                        .fill(isHovered ? DesignTokens.Surface.hover : Color.clear)
                )
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
    }
}

// MARK: - Compact Terminal Button (inline in description)

struct CompactTerminalButton: View {
    let isEnabled: Bool
    let onTap: () -> Void

    var body: some View {
        Button {
            if isEnabled {
                onTap()
            }
        } label: {
            HStack(spacing: 2) {
                Image(systemName: "terminal")
                    .font(.system(size: 8, weight: .medium))
                Text("跳转终端")
                    .font(.system(size: 10, weight: .medium))
            }
            .foregroundColor(isEnabled ? .white.opacity(0.9) : .white.opacity(0.3))
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(isEnabled ? Color.white.opacity(0.15) : Color.white.opacity(0.05))
            .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Terminal Button

struct TerminalButton: View {
    let isEnabled: Bool
    let onTap: () -> Void

    var body: some View {
        Button {
            if isEnabled {
                onTap()
            }
        } label: {
            HStack(spacing: 3) {
                Image(systemName: "terminal")
                    .font(.system(size: 9, weight: .medium))
                Text("终端")
                    .font(.system(size: 11, weight: .medium))
            }
            .foregroundColor(isEnabled ? .black : .white.opacity(0.4))
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(isEnabled ? Color.white.opacity(0.95) : Color.white.opacity(0.1))
            .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}
