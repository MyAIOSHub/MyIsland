//
//  ClaudeDesktopSession.swift
//  MyIsland
//
//  Data model for Claude Desktop App sessions
//

import Foundation

enum ClaudeDesktopSessionType: String, Equatable {
    case claudeCode
    case cowork
}

struct ClaudeDesktopSession: Identifiable, Equatable {
    let sessionId: String
    let sessionType: ClaudeDesktopSessionType
    let title: String
    let model: String?
    let cwd: String
    let lastActivityAt: Date
    let isArchived: Bool
    let completedTurns: Int?
    let initialMessage: String?

    var id: String { sessionId }

    var typeIcon: String {
        switch sessionType {
        case .claudeCode: return "terminal"
        case .cowork: return "person.2.badge.gearshape"
        }
    }

    var typeDisplayName: String {
        switch sessionType {
        case .claudeCode: return "Claude Code"
        case .cowork: return "Cowork"
        }
    }

    var isRecentlyActive: Bool {
        Date().timeIntervalSince(lastActivityAt) < 300
    }

    /// Short model name for display
    var modelShortName: String? {
        guard let m = model else { return nil }
        if m.contains("opus") { return "Opus" }
        if m.contains("sonnet") { return "Sonnet" }
        if m.contains("haiku") { return "Haiku" }
        return m.components(separatedBy: "-").first?.capitalized
    }

    /// Project name from cwd
    var projectName: String {
        if sessionType == .cowork {
            // cwd is "/sessions/process-name", use title instead
            return title
        }
        return URL(fileURLWithPath: cwd).lastPathComponent
    }
}
