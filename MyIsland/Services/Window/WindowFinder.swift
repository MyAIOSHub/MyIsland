//
//  WindowFinder.swift
//  MyIsland
//
//  Finds windows using yabai (if available) or native macOS APIs
//

import AppKit
import Foundation

/// Information about a window (from yabai or CGWindowList)
struct YabaiWindow: Sendable {
    let id: Int
    let pid: Int
    let title: String
    let space: Int
    let isVisible: Bool
    let hasFocus: Bool

    nonisolated init?(from dict: [String: Any]) {
        guard let id = dict["id"] as? Int,
              let pid = dict["pid"] as? Int else { return nil }

        self.id = id
        self.pid = pid
        self.title = dict["title"] as? String ?? ""
        self.space = dict["space"] as? Int ?? 0
        self.isVisible = dict["is-visible"] as? Bool ?? false
        self.hasFocus = dict["has-focus"] as? Bool ?? false
    }

    /// Init from CGWindowList info
    nonisolated init?(fromCG dict: [String: Any]) {
        guard let id = dict[kCGWindowNumber as String] as? Int,
              let pid = dict[kCGWindowOwnerPID as String] as? Int else { return nil }

        self.id = id
        self.pid = pid
        self.title = dict[kCGWindowName as String] as? String ?? ""
        self.space = 0 // CGWindowList doesn't provide space info
        let layer = dict[kCGWindowLayer as String] as? Int ?? 0
        self.isVisible = layer == 0
        self.hasFocus = false
    }
}

/// Known terminal app bundle identifiers
private let terminalBundleIDs: Set<String> = [
    "com.apple.Terminal",
    "com.googlecode.iterm2",
    "net.kovidgoyal.kitty",
    "io.alacritty",
    "org.alacritty",
    "com.github.wez.wezterm",
    "co.zeit.hyper",
]

/// Finds windows using yabai or native macOS APIs
actor WindowFinder {
    static let shared = WindowFinder()

    private var yabaiPath: String?
    private var isAvailableCache: Bool?

    private init() {}

    /// Check if yabai is available (caches result)
    func isYabaiAvailable() -> Bool {
        if let cached = isAvailableCache { return cached }

        let paths = ["/opt/homebrew/bin/yabai", "/usr/local/bin/yabai"]
        for path in paths {
            if FileManager.default.isExecutableFile(atPath: path) {
                yabaiPath = path
                isAvailableCache = true
                return true
            }
        }
        isAvailableCache = false
        return false
    }

    /// Get the yabai path if available
    func getYabaiPath() -> String? {
        _ = isYabaiAvailable()
        return yabaiPath
    }

    /// Get all windows from yabai
    func getAllWindows() async -> [YabaiWindow] {
        if isYabaiAvailable(), let path = yabaiPath {
            do {
                let output = try await ProcessExecutor.shared.run(path, arguments: ["-m", "query", "--windows"])
                guard let data = output.data(using: .utf8),
                      let jsonArray = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
                    return []
                }
                return jsonArray.compactMap { YabaiWindow(from: $0) }
            } catch {
                return []
            }
        }

        // Fallback: use CGWindowList
        return getAllWindowsNative()
    }

    /// Get all windows using native CGWindowList API (no yabai needed)
    nonisolated func getAllWindowsNative() -> [YabaiWindow] {
        guard let windowList = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] else {
            return []
        }
        return windowList.compactMap { YabaiWindow(fromCG: $0) }
    }

    /// Get the current space number
    nonisolated func getCurrentSpace(windows: [YabaiWindow]) -> Int? {
        windows.first(where: { $0.hasFocus })?.space
    }

    /// Find windows for a terminal PID
    nonisolated func findWindows(forTerminalPid pid: Int, windows: [YabaiWindow]) -> [YabaiWindow] {
        windows.filter { $0.pid == pid }
    }

    /// Find tmux window (title contains "tmux")
    nonisolated func findTmuxWindow(forTerminalPid pid: Int, windows: [YabaiWindow]) -> YabaiWindow? {
        windows.first { $0.pid == pid && $0.title.lowercased().contains("tmux") }
    }

    /// Find any non-Claude window for a terminal
    nonisolated func findNonClaudeWindow(forTerminalPid pid: Int, windows: [YabaiWindow]) -> YabaiWindow? {
        windows.first { $0.pid == pid && !$0.title.contains("✳") }
    }

    /// Find a terminal window by PID using native APIs
    nonisolated func findTerminalApp(forPid pid: Int) -> NSRunningApplication? {
        NSWorkspace.shared.runningApplications.first { app in
            guard let bundleID = app.bundleIdentifier else { return false }
            return terminalBundleIDs.contains(bundleID) && app.processIdentifier == pid
        }
    }
}
