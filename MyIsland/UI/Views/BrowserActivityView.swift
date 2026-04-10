//
//  BrowserActivityView.swift
//  MyIsland
//
//  Browser AI chat conversations and summary tasks display
//

import SwiftUI

struct BrowserActivityView: View {
    @ObservedObject var viewModel: NotchViewModel
    @ObservedObject private var monitor = BrowserSessionMonitor.shared
    @ObservedObject private var desktopWatcher = ClaudeDesktopWatcher.shared

    private var isEmpty: Bool {
        monitor.conversations.isEmpty && monitor.summaryTasks.isEmpty && desktopWatcher.sessions.isEmpty
    }

    var body: some View {
        if isEmpty {
            emptyState
        } else {
            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: DesignTokens.Spacing.sm) {
                    // Claude Desktop sessions
                    if !desktopWatcher.sessions.isEmpty {
                        claudeDesktopSection
                    }

                    // Summary tasks (if any)
                    if !monitor.summaryTasks.isEmpty {
                        summarySection
                    }

                    // Browser conversations
                    if !monitor.conversations.isEmpty {
                        conversationSection
                    }
                }
                .padding(.vertical, DesignTokens.Spacing.xxs)
            }
            .scrollBounceBehavior(.basedOnSize)
        }
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: DesignTokens.Spacing.sm) {
            Image(systemName: "globe")
                .font(.system(size: 24))
                .foregroundColor(DesignTokens.Text.quaternary)
            Text("暂无外部活动")
                .font(DesignTokens.Font.heading())
                .foregroundColor(DesignTokens.Text.tertiary)
            Text("Claude Desktop 和浏览器 AI 对话会显示在这里")
                .font(DesignTokens.Font.caption())
                .foregroundColor(DesignTokens.Text.quaternary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Claude Desktop Section

    private var claudeDesktopSection: some View {
        LazyVStack(spacing: 2) {
            ForEach(desktopWatcher.sessions) { session in
                ClaudeDesktopRow(session: session)
            }
        }
    }

    // MARK: - Summary Section

    private var summarySection: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.xxs) {
            ForEach(monitor.summaryTasks) { task in
                SummaryTaskCard(task: task, onArchive: { monitor.archiveTask(task.taskId) })
            }
        }
    }

    // MARK: - Conversation Section

    private var conversationSection: some View {
        LazyVStack(spacing: 2) {
            ForEach(monitor.conversations) { conv in
                ConversationRow(
                    conversation: conv,
                    onTap: { monitor.openConversation(conv) },
                    onArchive: { monitor.archiveConversation(conv.conversationId) }
                )
            }
        }
    }
}

// MARK: - Conversation Row

private struct ConversationRow: View {
    let conversation: BrowserConversation
    let onTap: () -> Void
    var onArchive: (() -> Void)?

    @State private var isHovered = false

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 10) {
                // Platform icon
                Image(systemName: conversation.platformIcon)
                    .font(.system(size: 12))
                    .foregroundColor(DesignTokens.Text.secondary)
                    .frame(width: 16)

                // Content
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: DesignTokens.Spacing.xs) {
                        Text(conversation.title)
                            .font(DesignTokens.Font.heading())
                            .foregroundColor(DesignTokens.Text.primary)
                            .lineLimit(1)

                        // Platform badge
                        Text(conversation.platformDisplayName)
                            .font(.system(size: 8, weight: .medium))
                            .foregroundColor(DesignTokens.Text.tertiary)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 2)
                            .background(Capsule().fill(DesignTokens.Surface.elevated))
                    }

                    // Last message preview
                    if let content = conversation.lastMessageContent {
                        HStack(spacing: DesignTokens.Spacing.xxs) {
                            if let sender = conversation.lastMessageSender {
                                Text(sender == "user" ? "你：" : "AI：")
                                    .font(DesignTokens.Font.body())
                                    .foregroundColor(DesignTokens.Text.secondary)
                            }
                            Text(content)
                                .font(DesignTokens.Font.body())
                                .foregroundColor(DesignTokens.Text.tertiary)
                                .lineLimit(1)
                        }
                    }
                }

                Spacer(minLength: 0)

                // Time + archive
                VStack(alignment: .trailing, spacing: 2) {
                    Text(relativeTime(conversation.updatedAt))
                        .font(DesignTokens.Font.caption())
                        .foregroundColor(DesignTokens.Text.quaternary)

                    if isHovered, let onArchive {
                        Button(action: onArchive) {
                            Image(systemName: "archivebox")
                                .font(.system(size: 10))
                                .foregroundColor(DesignTokens.Text.tertiary)
                        }
                        .buttonStyle(.plain)
                        .transition(.opacity)
                    } else {
                        Text("\(conversation.messageCount)")
                            .font(.system(size: 10, weight: .medium, design: .monospaced))
                            .foregroundColor(DesignTokens.Text.tertiary)
                    }
                }
                .animation(.easeInOut(duration: 0.15), value: isHovered)
            }
            .padding(.horizontal, DesignTokens.Spacing.md)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: DesignTokens.Radius.xl)
                    .fill(isHovered ? DesignTokens.Surface.elevated : Color.clear)
            )
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
    }
}

// MARK: - Summary Task Card

private struct SummaryTaskCard: View {
    let task: BrowserSummaryTask
    var onArchive: (() -> Void)?

    @State private var isHovered = false

    var body: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.xs) {
            // Header
            HStack(spacing: DesignTokens.Spacing.sm) {
                Image(systemName: task.modeIcon)
                    .font(.system(size: 12))
                    .foregroundColor(statusColor)

                Text(task.modeDisplayName)
                    .font(DesignTokens.Font.label())
                    .foregroundColor(DesignTokens.Text.primary)

                if let topic = task.topic {
                    Text("· \(topic)")
                        .font(DesignTokens.Font.body())
                        .foregroundColor(DesignTokens.Text.secondary)
                        .lineLimit(1)
                }

                Spacer()

                // Archive button (non-running, on hover)
                if !task.isRunning && isHovered, let onArchive {
                    Button(action: onArchive) {
                        Image(systemName: "archivebox")
                            .font(.system(size: 10))
                            .foregroundColor(DesignTokens.Text.tertiary)
                    }
                    .buttonStyle(.plain)
                    .transition(.opacity)
                }

                // Status badge
                statusBadge
            }

            // Summary preview (if done)
            if task.isDone, let summary = task.summary, !summary.isEmpty {
                Text(summary)
                    .font(DesignTokens.Font.body())
                    .foregroundColor(DesignTokens.Text.secondary)
                    .lineLimit(3)
            }

            // Error message
            if task.isError {
                Text("总结失败")
                    .font(DesignTokens.Font.caption())
                    .foregroundColor(TerminalColors.red)
            }
        }
        .padding(DesignTokens.Spacing.md)
        .background(
            RoundedRectangle(cornerRadius: DesignTokens.Radius.lg)
                .fill(DesignTokens.Surface.elevated)
                .overlay(
                    RoundedRectangle(cornerRadius: DesignTokens.Radius.lg)
                        .strokeBorder(DesignTokens.Border.subtle, lineWidth: 1)
                )
        )
        .onHover { isHovered = $0 }
        .animation(.easeInOut(duration: 0.15), value: isHovered)
    }

    private var statusColor: Color {
        if task.isRunning { return TerminalColors.blue }
        if task.isDone { return TerminalColors.green }
        if task.isError { return TerminalColors.red }
        return DesignTokens.Text.tertiary
    }

    @ViewBuilder
    private var statusBadge: some View {
        if task.isRunning {
            HStack(spacing: 4) {
                ProgressView()
                    .scaleEffect(0.4)
                    .frame(width: 10, height: 10)
                Text("生成中")
                    .font(DesignTokens.Font.caption())
                    .foregroundColor(TerminalColors.blue)
            }
        } else if task.isDone {
            HStack(spacing: 4) {
                Image(systemName: "checkmark")
                    .font(.system(size: 8, weight: .bold))
                Text("完成")
                    .font(DesignTokens.Font.caption())
            }
            .foregroundColor(TerminalColors.green)
        } else if task.isError {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 9))
                .foregroundColor(TerminalColors.red)
        }
    }
}

// MARK: - Claude Desktop Row

private struct ClaudeDesktopRow: View {
    let session: ClaudeDesktopSession

    @State private var isHovered = false

    var body: some View {
        HStack(spacing: 10) {
            // Type icon with activity indicator
            ZStack {
                Image(systemName: session.typeIcon)
                    .font(.system(size: 12))
                    .foregroundColor(session.isRecentlyActive ? TerminalColors.prompt : DesignTokens.Text.secondary)
                    .frame(width: 16)

                if session.isRecentlyActive {
                    Circle()
                        .fill(TerminalColors.green)
                        .frame(width: 5, height: 5)
                        .offset(x: 8, y: -6)
                }
            }

            // Content
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: DesignTokens.Spacing.xs) {
                    Text(session.title)
                        .font(DesignTokens.Font.heading())
                        .foregroundColor(DesignTokens.Text.primary)
                        .lineLimit(1)

                    // Type + model badge
                    HStack(spacing: 3) {
                        Text(session.typeDisplayName)
                            .font(.system(size: 8, weight: .medium))
                        if let model = session.modelShortName {
                            Text("·")
                                .font(.system(size: 8))
                            Text(model)
                                .font(.system(size: 8, weight: .medium))
                        }
                    }
                    .foregroundColor(DesignTokens.Text.tertiary)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2)
                    .background(Capsule().fill(DesignTokens.Surface.elevated))
                }

                // Subtitle: initial message or project path
                if let msg = session.initialMessage, !msg.isEmpty {
                    Text(msg)
                        .font(DesignTokens.Font.body())
                        .foregroundColor(DesignTokens.Text.tertiary)
                        .lineLimit(1)
                } else {
                    Text(session.projectName)
                        .font(DesignTokens.Font.body())
                        .foregroundColor(DesignTokens.Text.tertiary)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 0)

            // Time + turns
            VStack(alignment: .trailing, spacing: 2) {
                Text(relativeTime(session.lastActivityAt))
                    .font(DesignTokens.Font.caption())
                    .foregroundColor(DesignTokens.Text.quaternary)
                if let turns = session.completedTurns, turns > 0 {
                    Text("\(turns) turns")
                        .font(.system(size: 10, weight: .medium, design: .monospaced))
                        .foregroundColor(DesignTokens.Text.tertiary)
                }
            }
        }
        .padding(.horizontal, DesignTokens.Spacing.md)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: DesignTokens.Radius.xl)
                .fill(isHovered ? DesignTokens.Surface.elevated : Color.clear)
        )
        .onHover { isHovered = $0 }
    }
}

// MARK: - Relative Time Helper

private func relativeTime(_ date: Date) -> String {
    let interval = Date().timeIntervalSince(date)
    if interval < 60 { return "刚刚" }
    if interval < 3600 { return "\(Int(interval / 60))分钟前" }
    if interval < 86400 { return "\(Int(interval / 3600))小时前" }
    return "\(Int(interval / 86400))天前"
}
