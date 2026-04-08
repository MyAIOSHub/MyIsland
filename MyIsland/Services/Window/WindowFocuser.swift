//
//  WindowFocuser.swift
//  MyIsland
//
//  Focuses windows using yabai or native macOS APIs
//

import AppKit
import Foundation

/// Focuses windows using yabai or NSRunningApplication
actor WindowFocuser {
    static let shared = WindowFocuser()

    private init() {}

    /// Focus a window by ID (yabai only)
    func focusWindow(id: Int) async -> Bool {
        guard let yabaiPath = await WindowFinder.shared.getYabaiPath() else { return false }

        do {
            _ = try await ProcessExecutor.shared.run(yabaiPath, arguments: [
                "-m", "window", "--focus", String(id)
            ])
            return true
        } catch {
            return false
        }
    }

    /// Focus a terminal by its PID using native macOS APIs
    func focusTerminalNative(pid: Int) async -> Bool {
        let apps = NSWorkspace.shared.runningApplications
        if let app = apps.first(where: { $0.processIdentifier == pid }) {
            return app.activate()
        }
        return false
    }

    /// Focus the tmux window for a terminal
    func focusTmuxWindow(terminalPid: Int, windows: [YabaiWindow]) async -> Bool {
        // Try yabai first
        if await WindowFinder.shared.isYabaiAvailable() {
            if let tmuxWindow = WindowFinder.shared.findTmuxWindow(forTerminalPid: terminalPid, windows: windows) {
                return await focusWindow(id: tmuxWindow.id)
            }
            if let window = WindowFinder.shared.findNonClaudeWindow(forTerminalPid: terminalPid, windows: windows) {
                return await focusWindow(id: window.id)
            }
        }

        // Fallback: activate the terminal app natively
        return await focusTerminalNative(pid: terminalPid)
    }
}
