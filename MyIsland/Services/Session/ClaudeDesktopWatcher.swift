//
//  ClaudeDesktopWatcher.swift
//  MyIsland
//
//  Polls Claude Desktop App session files to detect active sessions
//

import Combine
import Foundation
import os.log

@MainActor
class ClaudeDesktopWatcher: ObservableObject {
    static let shared = ClaudeDesktopWatcher()

    @Published var sessions: [ClaudeDesktopSession] = []

    private var timer: Timer?
    private let pollInterval: TimeInterval = 3.0
    private let maxAge: TimeInterval = 3600  // Only scan files modified within 1 hour
    private let logger = Logger(subsystem: "app.myisland.macos", category: "ClaudeDesktopWatcher")

    private var claudeAppSupportDir: URL? {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
            .appendingPathComponent("Claude")
    }

    private init() {}

    // MARK: - Public API

    func start() {
        guard claudeAppSupportDir != nil else {
            logger.info("Claude Desktop not found, skipping watcher")
            return
        }
        timer = Timer.scheduledTimer(withTimeInterval: pollInterval, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.scan()
            }
        }
        scan()  // Initial scan
        logger.info("ClaudeDesktopWatcher started")
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    // MARK: - Scanning

    private func scan() {
        guard let baseDir = claudeAppSupportDir else { return }
        let fm = FileManager.default

        var found: [ClaudeDesktopSession] = []
        let now = Date()

        // Scan both session types
        let dirs: [(String, ClaudeDesktopSessionType)] = [
            ("claude-code-sessions", .claudeCode),
            ("local-agent-mode-sessions", .cowork),
        ]

        for (dirName, sessionType) in dirs {
            let typeDir = baseDir.appendingPathComponent(dirName)
            guard fm.fileExists(atPath: typeDir.path) else { continue }

            // Enumerate userId dirs
            guard let userDirs = try? fm.contentsOfDirectory(at: typeDir, includingPropertiesForKeys: nil) else { continue }

            for userDir in userDirs where userDir.hasDirectoryPath {
                // Enumerate workspaceId dirs
                guard let workDirs = try? fm.contentsOfDirectory(at: userDir, includingPropertiesForKeys: nil) else { continue }

                for workDir in workDirs where workDir.hasDirectoryPath {
                    // Find local_*.json files
                    guard let files = try? fm.contentsOfDirectory(at: workDir, includingPropertiesForKeys: [.contentModificationDateKey]) else { continue }

                    for file in files {
                        guard file.lastPathComponent.hasPrefix("local_"),
                              file.pathExtension == "json" else { continue }

                        // Check modification time — skip old files
                        if let attrs = try? fm.attributesOfItem(atPath: file.path),
                           let modDate = attrs[.modificationDate] as? Date,
                           now.timeIntervalSince(modDate) > maxAge {
                            continue
                        }

                        // Parse session
                        if let session = parseSessionFile(file, type: sessionType) {
                            if !session.isArchived {
                                found.append(session)
                            }
                        }
                    }
                }
            }
        }

        // Sort by lastActivityAt descending
        found.sort { $0.lastActivityAt > $1.lastActivityAt }

        // Only update if changed
        if found != sessions {
            sessions = found
        }
    }

    // MARK: - Parsing

    private func parseSessionFile(_ url: URL, type: ClaudeDesktopSessionType) -> ClaudeDesktopSession? {
        guard let data = try? Data(contentsOf: url),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let sessionId = json["sessionId"] as? String else { return nil }

        let title = (json["title"] as? String) ?? "Untitled"
        let model = json["model"] as? String
        let cwd = (json["cwd"] as? String) ?? ""
        let isArchived = (json["isArchived"] as? Bool) ?? false
        let completedTurns = json["completedTurns"] as? Int
        let initialMessage = json["initialMessage"] as? String

        // lastActivityAt is milliseconds since epoch
        let lastActivityMs = (json["lastActivityAt"] as? Double) ?? 0
        let lastActivityAt = Date(timeIntervalSince1970: lastActivityMs / 1000.0)

        return ClaudeDesktopSession(
            sessionId: sessionId,
            sessionType: type,
            title: title,
            model: model,
            cwd: cwd,
            lastActivityAt: lastActivityAt,
            isArchived: isArchived,
            completedTurns: completedTurns,
            initialMessage: initialMessage
        )
    }
}
