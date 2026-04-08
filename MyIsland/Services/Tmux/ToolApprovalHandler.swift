//
//  ToolApprovalHandler.swift
//  MyIsland
//
//  Handles Claude tool approval operations via tmux
//

import Foundation
import os.log

/// Handles tool approval and rejection for Claude instances
actor ToolApprovalHandler {
    static let shared = ToolApprovalHandler()

    /// Logger for tool approval (nonisolated static for cross-context access)
    nonisolated static let logger = Logger(subsystem: "com.myisland", category: "Approval")

    private init() {}

    /// Approve a tool once (sends '1' + Enter)
    func approveOnce(target: TmuxTarget) async -> Bool {
        await sendKeys(to: target, keys: "1", pressEnter: true)
    }

    /// Approve a tool always (sends '2' + Enter)
    func approveAlways(target: TmuxTarget) async -> Bool {
        await sendKeys(to: target, keys: "2", pressEnter: true)
    }

    /// Reject a tool with optional message
    func reject(target: TmuxTarget, message: String? = nil) async -> Bool {
        // First send 'n' + Enter to reject
        guard await sendKeys(to: target, keys: "n", pressEnter: true) else {
            return false
        }

        // If there's a message, send it after a brief delay
        if let message = message, !message.isEmpty {
            try? await Task.sleep(for: .milliseconds(100))
            return await sendKeys(to: target, keys: message, pressEnter: true)
        }

        return true
    }

    /// Send a message to a tmux target
    func sendMessage(_ message: String, to target: TmuxTarget) async -> Bool {
        await sendKeys(to: target, keys: message, pressEnter: true)
    }

    /// Send a message directly to a TTY device (no tmux required)
    /// Works by opening the TTY device file and writing the message + newline
    func sendViaTTY(_ message: String, tty: String) async -> Bool {
        guard !tty.isEmpty else { return false }

        // SessionStore strips "/dev/" prefix, restore it if needed
        let ttyPath = tty.hasPrefix("/dev/") ? tty : "/dev/" + tty
        let fd = open(ttyPath, O_WRONLY | O_NONBLOCK)
        guard fd >= 0 else {
            Self.logger.error("Failed to open TTY \(tty, privacy: .public): errno \(errno)")
            return false
        }
        defer { Darwin.close(fd) }

        // Send message followed by newline (simulates typing + Enter)
        let payload = message + "\n"
        guard let data = payload.data(using: .utf8) else { return false }

        let result = data.withUnsafeBytes { bytes -> Int in
            guard let base = bytes.baseAddress else { return -1 }
            return write(fd, base, data.count)
        }

        if result < 0 {
            Self.logger.error("Failed to write to TTY \(tty, privacy: .public): errno \(errno)")
            return false
        }

        Self.logger.debug("Sent \(result) bytes via TTY \(tty, privacy: .public)")
        return true
    }

    // MARK: - Private Methods

    private func sendKeys(to target: TmuxTarget, keys: String, pressEnter: Bool) async -> Bool {
        guard let tmuxPath = await TmuxPathFinder.shared.getTmuxPath() else {
            return false
        }

        // tmux send-keys needs literal text and Enter as separate arguments
        // Use -l flag to send keys literally (prevents interpreting special chars)
        let targetStr = target.targetString
        let textArgs = ["send-keys", "-t", targetStr, "-l", keys]

        do {
            Self.logger.debug("Sending text to \(targetStr, privacy: .public)")
            _ = try await ProcessExecutor.shared.run(tmuxPath, arguments: textArgs)

            // Send Enter as a separate command if needed
            if pressEnter {
                Self.logger.debug("Sending Enter key")
                let enterArgs = ["send-keys", "-t", targetStr, "Enter"]
                _ = try await ProcessExecutor.shared.run(tmuxPath, arguments: enterArgs)
            }
            return true
        } catch {
            Self.logger.error("Error: \(error.localizedDescription, privacy: .public)")
            return false
        }
    }
}
