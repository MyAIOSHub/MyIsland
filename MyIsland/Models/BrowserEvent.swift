//
//  BrowserEvent.swift
//  MyIsland
//
//  Data models for browser extension events
//

import Foundation

// MARK: - Wire Format (JSON from HTTP)

struct BrowserEventEnvelope: Codable {
    let type: String
    let payload: [String: AnyCodable]
}

// MARK: - Parsed Event Types

enum BrowserEventType {
    case conversationUpdated(BrowserConversation)
    case summaryStarted(BrowserSummaryTask)
    case summaryCompleted(BrowserSummaryTask)
}

// MARK: - Browser Conversation

struct BrowserConversation: Identifiable, Equatable {
    let conversationId: String
    let platform: String
    let title: String
    let link: String
    let messageCount: Int
    let lastMessageSender: String?
    let lastMessageContent: String?
    let updatedAt: Date

    var id: String { conversationId }

    var platformIcon: String {
        switch platform {
        case "chatgpt": return "bubble.left.and.text.bubble.right"
        case "claude": return "sparkle"
        case "gemini": return "diamond"
        case "deepseek": return "magnifyingglass"
        case "qwen": return "cloud"
        case "doubao": return "text.bubble"
        case "yuanbao": return "yensign.circle"
        case "kimi": return "moon"
        default: return "globe"
        }
    }

    var platformDisplayName: String {
        switch platform {
        case "chatgpt": return "ChatGPT"
        case "claude": return "Claude"
        case "gemini": return "Gemini"
        case "deepseek": return "DeepSeek"
        case "qwen": return "通义千问"
        case "doubao": return "豆包"
        case "yuanbao": return "元宝"
        case "kimi": return "Kimi"
        default: return platform.capitalized
        }
    }
}

// MARK: - Browser Summary Task

struct BrowserSummaryTask: Identifiable, Equatable {
    let taskId: String
    let mode: String
    let topic: String?
    let status: String
    let summary: String?
    let conversationCount: Int?
    let startedAt: Date?
    let completedAt: Date?

    var id: String { taskId }

    var modeDisplayName: String {
        switch mode {
        case "weekly": return "周报总结"
        case "topic": return "主题分析"
        case "psychology": return "心理洞察"
        default: return mode
        }
    }

    var modeIcon: String {
        switch mode {
        case "weekly": return "calendar.badge.clock"
        case "topic": return "text.magnifyingglass"
        case "psychology": return "brain.head.profile"
        default: return "doc.text"
        }
    }

    var isRunning: Bool { status == "running" }
    var isDone: Bool { status == "done" }
    var isError: Bool { status == "error" }
}

// MARK: - Parsing

extension BrowserEventType {
    static func parse(envelope: BrowserEventEnvelope) -> BrowserEventType? {
        let p = envelope.payload
        let iso = ISO8601DateFormatter()

        switch envelope.type {
        case "conversation_updated":
            guard let convId = p["conversationId"]?.value as? String,
                  let platform = p["platform"]?.value as? String,
                  let title = p["title"]?.value as? String else { return nil }

            let link = p["link"]?.value as? String ?? ""
            let messageCount = (p["messageCount"]?.value as? Int) ?? 0
            var lastSender: String?
            var lastContent: String?
            if let lastMsg = p["lastMessage"]?.value as? [String: Any] {
                lastSender = lastMsg["sender"] as? String
                lastContent = lastMsg["content"] as? String
            }
            let updatedAt = (p["updatedAt"]?.value as? String).flatMap { iso.date(from: $0) } ?? Date()

            return .conversationUpdated(BrowserConversation(
                conversationId: convId, platform: platform, title: title,
                link: link, messageCount: messageCount,
                lastMessageSender: lastSender, lastMessageContent: lastContent,
                updatedAt: updatedAt
            ))

        case "summary_started":
            guard let taskId = p["taskId"]?.value as? String,
                  let mode = p["mode"]?.value as? String else { return nil }

            return .summaryStarted(BrowserSummaryTask(
                taskId: taskId, mode: mode, topic: p["topic"]?.value as? String,
                status: "running", summary: nil,
                conversationCount: p["conversationCount"]?.value as? Int,
                startedAt: (p["startedAt"]?.value as? String).flatMap { iso.date(from: $0) },
                completedAt: nil
            ))

        case "summary_completed":
            guard let taskId = p["taskId"]?.value as? String,
                  let mode = p["mode"]?.value as? String else { return nil }

            return .summaryCompleted(BrowserSummaryTask(
                taskId: taskId, mode: mode, topic: p["topic"]?.value as? String,
                status: (p["status"]?.value as? String) ?? "done",
                summary: p["summary"]?.value as? String,
                conversationCount: nil,
                startedAt: nil,
                completedAt: (p["completedAt"]?.value as? String).flatMap { iso.date(from: $0) }
            ))

        default:
            return nil
        }
    }
}
