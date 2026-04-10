//
//  BrowserSessionMonitor.swift
//  MyIsland
//
//  Manages browser extension AI chat and summary task state
//

import Combine
import Foundation
import SwiftUI

extension Notification.Name {
    static let browserSummaryCompleted = Notification.Name("MyIslandBrowserSummaryCompleted")
}

@MainActor
class BrowserSessionMonitor: ObservableObject {
    static let shared = BrowserSessionMonitor()

    @Published var conversations: [BrowserConversation] = []
    @Published var summaryTasks: [BrowserSummaryTask] = []
    @Published var hasUnreadNotification: Bool = false

    private let maxConversations = 20
    private let maxTasks = 10
    private var cleanupTimer: Timer?

    /// Archived IDs — hidden until the item transitions back to running/active
    private var archivedIds: Set<String> = []

    private init() {}

    // MARK: - Lifecycle

    func startCleanup() {
        cleanupTimer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.removeExpired()
            }
        }
    }

    // MARK: - Event Handling

    func handleEvent(_ event: BrowserEventType) {
        let retention = TimeInterval(AppSettings.browserRetentionMinutes * 60)

        switch event {
        case .conversationUpdated(let conv):
            // Skip archived
            guard !archivedIds.contains(conv.conversationId) else { return }
            // Skip too old
            guard Date().timeIntervalSince(conv.updatedAt) < retention else { return }
            upsertConversation(conv)

        case .summaryStarted(let task):
            // Unarchive if restarted
            archivedIds.remove(task.taskId)
            upsertTask(task)

        case .summaryCompleted(let task):
            // Skip archived
            guard !archivedIds.contains(task.taskId) else { return }
            // Skip too old
            if let completed = task.completedAt {
                guard Date().timeIntervalSince(completed) < retention else { return }
            }
            upsertTask(task)
            if task.isDone {
                hasUnreadNotification = true
                NotificationCenter.default.post(name: .browserSummaryCompleted, object: nil)
            }
        }
    }

    // MARK: - Archive

    func archiveConversation(_ id: String) {
        archivedIds.insert(id)
        conversations.removeAll { $0.conversationId == id }
    }

    func archiveTask(_ id: String) {
        archivedIds.insert(id)
        summaryTasks.removeAll { $0.taskId == id }
    }

    // MARK: - Expiry Cleanup

    private func removeExpired() {
        let retention = TimeInterval(AppSettings.browserRetentionMinutes * 60)
        let cutoff = Date().addingTimeInterval(-retention)

        conversations.removeAll { $0.updatedAt < cutoff }

        summaryTasks.removeAll { task in
            guard !task.isRunning else { return false }
            guard let completed = task.completedAt else { return false }
            return completed < cutoff
        }
    }

    // MARK: - Conversation Management

    private func upsertConversation(_ conv: BrowserConversation) {
        if let idx = conversations.firstIndex(where: { $0.conversationId == conv.conversationId }) {
            conversations[idx] = conv
        } else {
            conversations.append(conv)
        }
        conversations.sort { $0.updatedAt > $1.updatedAt }
        if conversations.count > maxConversations {
            conversations = Array(conversations.prefix(maxConversations))
        }
    }

    // MARK: - Task Management

    private func upsertTask(_ task: BrowserSummaryTask) {
        if let idx = summaryTasks.firstIndex(where: { $0.taskId == task.taskId }) {
            summaryTasks[idx] = task
        } else {
            summaryTasks.insert(task, at: 0)
        }
        if summaryTasks.count > maxTasks {
            summaryTasks = Array(summaryTasks.prefix(maxTasks))
        }
    }

    // MARK: - Actions

    func markNotificationRead() {
        hasUnreadNotification = false
    }

    func openConversation(_ conv: BrowserConversation) {
        guard let url = URL(string: conv.link), !conv.link.isEmpty else { return }
        NSWorkspace.shared.open(url)
    }
}
