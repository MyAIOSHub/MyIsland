//
//  HookInstaller.swift
//  MyIsland
//
//  Auto-installs CLI hooks for Claude Code, Codex, Gemini CLI, Copilot
//

import Foundation

// MARK: - Hook Target

enum HookTarget: String, CaseIterable {
    case claude
    case codex
    case gemini
    case copilot

    var displayName: String {
        switch self {
        case .claude:  return "Claude Code"
        case .codex:   return "Codex"
        case .gemini:  return "Gemini CLI"
        case .copilot: return "Copilot"
        }
    }

    /// Path to the settings/hooks config file
    var settingsURL: URL {
        let home = FileManager.default.homeDirectoryForCurrentUser
        switch self {
        case .claude:
            return home.appendingPathComponent(".claude/settings.json")
        case .codex:
            return home.appendingPathComponent(".codex/hooks.json")
        case .gemini:
            return home.appendingPathComponent(".gemini/settings.json")
        case .copilot:
            return home.appendingPathComponent(".github-copilot/hooks.json")
        }
    }

    /// Directory for hook scripts
    var hooksDir: URL {
        let home = FileManager.default.homeDirectoryForCurrentUser
        switch self {
        case .claude:
            return home.appendingPathComponent(".claude/hooks")
        case .codex:
            return home.appendingPathComponent(".codex/hooks")
        case .gemini:
            return home.appendingPathComponent(".gemini/hooks")
        case .copilot:
            return home.appendingPathComponent(".github-copilot/hooks")
        }
    }

    /// Source identifier for the bridge command
    var sourceId: String { rawValue }

    /// The marker string used to identify our hooks
    var hookMarker: String { "myisland-state.py" }
}

// MARK: - HookInstaller

struct HookInstaller {

    // MARK: - Public API (with target)

    static func installIfNeeded(target: HookTarget = .claude) {
        let hooksDir = target.hooksDir
        let pythonScript = hooksDir.appendingPathComponent("myisland-state.py")
        let settings = target.settingsURL

        // Ensure hooks directory exists
        try? FileManager.default.createDirectory(
            at: hooksDir,
            withIntermediateDirectories: true
        )

        // Ensure parent directory of settings exists
        let settingsParent = settings.deletingLastPathComponent()
        try? FileManager.default.createDirectory(
            at: settingsParent,
            withIntermediateDirectories: true
        )

        // Copy hook script
        if let bundled = Bundle.main.url(forResource: "myisland-state", withExtension: "py") {
            try? FileManager.default.removeItem(at: pythonScript)
            try? FileManager.default.copyItem(at: bundled, to: pythonScript)
            try? FileManager.default.setAttributes(
                [.posixPermissions: 0o755],
                ofItemAtPath: pythonScript.path
            )
        }

        updateSettings(at: settings, target: target)
    }

    static func isInstalled(target: HookTarget = .claude) -> Bool {
        let settings = target.settingsURL

        guard let data = try? Data(contentsOf: settings),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let hooks = json["hooks"] as? [String: Any] else {
            return false
        }

        for (_, value) in hooks {
            if let entries = value as? [[String: Any]] {
                for entry in entries {
                    if let entryHooks = entry["hooks"] as? [[String: Any]] {
                        for hook in entryHooks {
                            if let cmd = hook["command"] as? String,
                               cmd.contains(target.hookMarker) {
                                return true
                            }
                        }
                    }
                }
            }
        }
        return false
    }

    static func uninstall(target: HookTarget = .claude) {
        let hooksDir = target.hooksDir
        let pythonScript = hooksDir.appendingPathComponent("myisland-state.py")
        let settings = target.settingsURL

        try? FileManager.default.removeItem(at: pythonScript)

        guard let data = try? Data(contentsOf: settings),
              var json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              var hooks = json["hooks"] as? [String: Any] else {
            return
        }

        for (event, value) in hooks {
            if var entries = value as? [[String: Any]] {
                entries.removeAll { entry in
                    if let entryHooks = entry["hooks"] as? [[String: Any]] {
                        return entryHooks.contains { hook in
                            let cmd = hook["command"] as? String ?? ""
                            return cmd.contains(target.hookMarker)
                        }
                    }
                    return false
                }

                if entries.isEmpty {
                    hooks.removeValue(forKey: event)
                } else {
                    hooks[event] = entries
                }
            }
        }

        if hooks.isEmpty {
            json.removeValue(forKey: "hooks")
        } else {
            json["hooks"] = hooks
        }

        if let data = try? JSONSerialization.data(
            withJSONObject: json,
            options: [.prettyPrinted, .sortedKeys]
        ) {
            try? data.write(to: settings)
        }
    }

    // MARK: - Private

    private static func updateSettings(at settingsURL: URL, target: HookTarget) {
        var json: [String: Any] = [:]
        if let data = try? Data(contentsOf: settingsURL),
           let existing = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            json = existing
        }

        let python = detectPython()
        let scriptPath: String
        switch target {
        case .claude:
            scriptPath = "~/.claude/hooks/myisland-state.py"
        case .codex:
            scriptPath = "~/.codex/hooks/myisland-state.py"
        case .gemini:
            scriptPath = "~/.gemini/hooks/myisland-state.py"
        case .copilot:
            scriptPath = "~/.github-copilot/hooks/myisland-state.py"
        }

        let command = "\(python) \(scriptPath)"
        let hookEntry: [[String: Any]] = [["type": "command", "command": command]]
        let hookEntryWithTimeout: [[String: Any]] = [["type": "command", "command": command, "timeout": 86400]]
        let withMatcher: [[String: Any]] = [["matcher": "*", "hooks": hookEntry]]
        let withMatcherAndTimeout: [[String: Any]] = [["matcher": "*", "hooks": hookEntryWithTimeout]]
        let withoutMatcher: [[String: Any]] = [["hooks": hookEntry]]
        let preCompactConfig: [[String: Any]] = [
            ["matcher": "auto", "hooks": hookEntry],
            ["matcher": "manual", "hooks": hookEntry]
        ]

        var hooks = json["hooks"] as? [String: Any] ?? [:]

        let hookEvents: [(String, [[String: Any]])] = [
            ("UserPromptSubmit", withoutMatcher),
            ("PreToolUse", withMatcher),
            ("PostToolUse", withMatcher),
            ("PermissionRequest", withMatcherAndTimeout),
            ("Notification", withMatcher),
            ("Stop", withoutMatcher),
            ("SubagentStop", withoutMatcher),
            ("SessionStart", withoutMatcher),
            ("SessionEnd", withoutMatcher),
            ("PreCompact", preCompactConfig),
        ]

        for (event, config) in hookEvents {
            if var existingEvent = hooks[event] as? [[String: Any]] {
                let hasOurHook = existingEvent.contains { entry in
                    if let entryHooks = entry["hooks"] as? [[String: Any]] {
                        return entryHooks.contains { h in
                            let cmd = h["command"] as? String ?? ""
                            return cmd.contains(target.hookMarker)
                        }
                    }
                    return false
                }
                if !hasOurHook {
                    existingEvent.append(contentsOf: config)
                    hooks[event] = existingEvent
                }
            } else {
                hooks[event] = config
            }
        }

        json["hooks"] = hooks

        if let data = try? JSONSerialization.data(
            withJSONObject: json,
            options: [.prettyPrinted, .sortedKeys]
        ) {
            // Atomic write: temp file + rename to prevent corruption
            let tempURL = settingsURL.deletingLastPathComponent().appendingPathComponent(".settings.json.tmp")
            try? data.write(to: tempURL)
            try? FileManager.default.replaceItemAt(settingsURL, withItemAt: tempURL)
        }
    }

    private static func detectPython() -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/which")
        process.arguments = ["python3"]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice

        do {
            try process.run()
            process.waitUntilExit()
            if process.terminationStatus == 0 {
                return "python3"
            }
        } catch {}

        return "python"
    }
}
