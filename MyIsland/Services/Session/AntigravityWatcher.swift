//
//  AntigravityWatcher.swift
//  MyIsland
//
//  Watches Antigravity (Google's VS Code fork) built-in Gemini agent sessions
//  by polling the workspace state.vscdb SQLite databases for chat session changes.
//

import AppKit
import Foundation
import os.log

/// Monitors Antigravity's built-in agent for active chat/agent sessions.
///
/// Antigravity stores chat sessions in per-workspace SQLite databases at:
///   ~/Library/Application Support/Antigravity/User/workspaceStorage/<id>/state.vscdb
///
/// We watch these files for modifications and read the `chat.ChatSessionStore.index` key
/// to detect active agent sessions.
final class AntigravityWatcher {
    static let shared = AntigravityWatcher()

    private let logger = Logger(subsystem: "com.myisland", category: "AntigravityWatcher")
    private let fileManager = FileManager.default
    private var pollTimer: Timer?
    private var lastKnownSessions: Set<String> = []
    private var isRunning = false

    var onSessionEvent: ((AntigravitySessionEvent) -> Void)?

    // MARK: - Paths

    private var supportDir: String {
        let home = fileManager.homeDirectoryForCurrentUser.path
        return "\(home)/Library/Application Support/Antigravity"
    }

    private var workspaceStorageDir: String {
        "\(supportDir)/User/workspaceStorage"
    }

    // MARK: - Public API

    var isEnabled: Bool {
        get { UserDefaults.standard.bool(forKey: "antigravityHookEnabled") }
        set {
            UserDefaults.standard.set(newValue, forKey: "antigravityHookEnabled")
            if newValue { start() } else { stop() }
        }
    }

    /// Whether Antigravity.app is installed
    var isInstalled: Bool {
        NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.google.antigravity") != nil
    }

    /// Whether Antigravity is currently running
    var isAppRunning: Bool {
        NSWorkspace.shared.runningApplications.contains {
            $0.bundleIdentifier == "com.google.antigravity"
        }
    }

    func start() {
        guard !isRunning else { return }
        guard isEnabled else { return }

        isRunning = true
        logger.info("Starting Antigravity watcher")

        // Poll every 3 seconds for session changes
        pollTimer = Timer.scheduledTimer(withTimeInterval: 3.0, repeats: true) { [weak self] _ in
            self?.pollSessions()
        }
        // Immediate first poll
        pollSessions()
    }

    func stop() {
        pollTimer?.invalidate()
        pollTimer = nil
        isRunning = false
        lastKnownSessions.removeAll()
        logger.info("Stopped Antigravity watcher")
    }

    // MARK: - Polling

    private func pollSessions() {
        guard isAppRunning else { return }

        let stateDBs = findStateDBs()
        var currentSessions = Set<String>()

        for dbPath in stateDBs {
            let sessions = readChatSessions(from: dbPath)
            for session in sessions {
                currentSessions.insert(session.id)
            }
        }

        // Detect new sessions
        let newSessions = currentSessions.subtracting(lastKnownSessions)
        for sid in newSessions {
            logger.info("New Antigravity agent session: \(sid)")
            onSessionEvent?(.sessionStarted(sessionId: sid))
        }

        // Detect ended sessions
        let endedSessions = lastKnownSessions.subtracting(currentSessions)
        for sid in endedSessions {
            logger.info("Antigravity agent session ended: \(sid)")
            onSessionEvent?(.sessionEnded(sessionId: sid))
        }

        lastKnownSessions = currentSessions
    }

    // MARK: - SQLite Reading

    private func findStateDBs() -> [String] {
        guard fileManager.fileExists(atPath: workspaceStorageDir) else { return [] }

        var results: [String] = []
        if let dirs = try? fileManager.contentsOfDirectory(atPath: workspaceStorageDir) {
            for dir in dirs {
                let dbPath = "\(workspaceStorageDir)/\(dir)/state.vscdb"
                if fileManager.fileExists(atPath: dbPath) {
                    // Only check recently modified DBs (within last hour)
                    if let attrs = try? fileManager.attributesOfItem(atPath: dbPath),
                       let modDate = attrs[.modificationDate] as? Date,
                       Date().timeIntervalSince(modDate) < 3600 {
                        results.append(dbPath)
                    }
                }
            }
        }
        return results
    }

    private func readChatSessions(from dbPath: String) -> [AntigravitySession] {
        // Use sqlite3 command-line tool to read the database
        // This avoids linking SQLite directly
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/sqlite3")
        process.arguments = [
            dbPath,
            "SELECT value FROM ItemTable WHERE key = 'chat.ChatSessionStore.index'"
        ]

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice

        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            return []
        }

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        guard let jsonStr = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
              !jsonStr.isEmpty,
              let jsonData = jsonStr.data(using: .utf8),
              let root = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any],
              let entries = root["entries"] as? [String: Any] else {
            return []
        }

        return entries.compactMap { (key, value) -> AntigravitySession? in
            guard let info = value as? [String: Any] else { return nil }
            let isAgent = info["isAgent"] as? Bool ?? false
            // Only track agent sessions (not regular chat)
            let title = info["title"] as? String
            return AntigravitySession(
                id: key,
                title: title,
                isAgent: isAgent
            )
        }
    }
}

// MARK: - Models

struct AntigravitySession {
    let id: String
    let title: String?
    let isAgent: Bool
}

enum AntigravitySessionEvent {
    case sessionStarted(sessionId: String)
    case sessionEnded(sessionId: String)
}
