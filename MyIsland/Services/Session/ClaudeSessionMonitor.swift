//
//  ClaudeSessionMonitor.swift
//  MyIsland
//
//  MainActor wrapper around SessionStore for UI binding.
//  Publishes SessionState arrays for SwiftUI observation.
//

import AppKit
import Combine
import Foundation

@MainActor
class ClaudeSessionMonitor: ObservableObject {
    @Published var instances: [SessionState] = []
    @Published var pendingInstances: [SessionState] = []

    private var cancellables = Set<AnyCancellable>()

    init() {
        SessionStore.shared.sessionsPublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] sessions in
                self?.updateFromSessions(sessions)
            }
            .store(in: &cancellables)

        InterruptWatcherManager.shared.delegate = self
    }

    // MARK: - Monitoring Lifecycle

    func startMonitoring() {
        HookSocketServer.shared.start(
            onEvent: { [weak self] event in
                Task {
                    await SessionStore.shared.process(.hookReceived(event))
                }

                // Sound: user prompt submitted
                if event.event == "UserPromptSubmit" {
                    Task { @MainActor in
                        self?.onUserPromptSubmitted()
                    }
                }

                // Sound: task error — detect via error status in PostToolUse
                if event.event == "PostToolUse", event.status == "error" {
                    Task { @MainActor in
                        SoundPlayer.shared.play(.taskError)
                    }
                }

                if event.sessionPhase == .processing {
                    Task { @MainActor in
                        InterruptWatcherManager.shared.startWatching(
                            sessionId: event.sessionId,
                            cwd: event.cwd
                        )
                    }
                }

                if event.status == "ended" {
                    Task { @MainActor in
                        InterruptWatcherManager.shared.stopWatching(sessionId: event.sessionId)
                    }
                }

                if event.event == "Stop" {
                    HookSocketServer.shared.cancelPendingPermissions(sessionId: event.sessionId)
                }

                if event.event == "PostToolUse", let toolUseId = event.toolUseId {
                    HookSocketServer.shared.cancelPendingPermission(toolUseId: toolUseId)
                }
            },
            onPermissionFailure: { sessionId, toolUseId in
                Task {
                    await SessionStore.shared.process(
                        .permissionSocketFailed(sessionId: sessionId, toolUseId: toolUseId)
                    )
                }
            }
        )
    }

    func stopMonitoring() {
        HookSocketServer.shared.stop()
    }

    // MARK: - Permission Handling

    func approvePermission(sessionId: String) {
        Task {
            guard let session = await SessionStore.shared.session(for: sessionId),
                  let permission = session.activePermission else {
                return
            }

            HookSocketServer.shared.respondToPermission(
                toolUseId: permission.toolUseId,
                decision: "allow"
            )

            await SessionStore.shared.process(
                .permissionApproved(sessionId: sessionId, toolUseId: permission.toolUseId)
            )
        }
    }

    func denyPermission(sessionId: String, reason: String?) {
        Task {
            guard let session = await SessionStore.shared.session(for: sessionId),
                  let permission = session.activePermission else {
                return
            }

            HookSocketServer.shared.respondToPermission(
                toolUseId: permission.toolUseId,
                decision: "deny",
                reason: reason
            )

            await SessionStore.shared.process(
                .permissionDenied(sessionId: sessionId, toolUseId: permission.toolUseId, reason: reason)
            )
        }
    }

    /// Archive (remove) a session from the instances list
    func archiveSession(sessionId: String) {
        Task {
            await SessionStore.shared.process(.sessionEnded(sessionId: sessionId))
        }
    }

    // MARK: - Question Response

    /// Respond to an AskUserQuestion by focusing the source app and typing the option number
    func respondToQuestion(session: SessionState, optionIndex: Int) {
        let optionNumber = optionIndex + 1  // 1-based

        Task {
            // Focus the source terminal/app
            if let bundleId = session.sourceApp.bundleIdentifier,
               let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleId) {
                let config = NSWorkspace.OpenConfiguration()
                config.activates = true
                try? await NSWorkspace.shared.openApplication(at: url, configuration: config)
            } else if let pid = session.pid {
                _ = await YabaiController.shared.focusWindow(forClaudePid: pid)
            } else {
                _ = await YabaiController.shared.focusWindow(forWorkingDirectory: session.cwd)
            }

            // Wait for window to gain focus
            try? await Task.sleep(for: .milliseconds(300))

            // Type the option number + Enter
            Self.typeOptionNumber(optionNumber)
        }
    }

    /// Simulate typing a number and pressing Enter via CGEvent
    private static func typeOptionNumber(_ number: Int) {
        guard AXIsProcessTrusted() else { return }
        guard let source = CGEventSource(stateID: .hidSystemState) else { return }

        // Map digit to virtual key code (18=1, 19=2, ..., 25=8, 26=9, 29=0)
        let digitKeyCodes: [Int: UInt16] = [
            1: 18, 2: 19, 3: 20, 4: 21, 5: 23, 6: 22, 7: 26, 8: 28, 9: 25, 0: 29
        ]

        // Type each digit of the number
        let digits = String(number)
        for char in digits {
            guard let digit = Int(String(char)),
                  let keyCode = digitKeyCodes[digit] else { continue }
            if let keyDown = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: true),
               let keyUp = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: false) {
                keyDown.post(tap: .cghidEventTap)
                keyUp.post(tap: .cghidEventTap)
            }
        }

        // Press Enter (keyCode 36)
        if let keyDown = CGEvent(keyboardEventSource: source, virtualKey: 36, keyDown: true),
           let keyUp = CGEvent(keyboardEventSource: source, virtualKey: 36, keyDown: false) {
            keyDown.post(tap: .cghidEventTap)
            keyUp.post(tap: .cghidEventTap)
        }
    }

    // MARK: - State Update

    /// Previous phases for detecting transitions and triggering sounds
    private var previousPhases: [String: SessionPhase] = [:]

    /// Spam detection: timestamps of recent user messages
    private var recentUserMessageTimes: [Date] = []

    private func updateFromSessions(_ sessions: [SessionState]) {
        // Detect phase transitions for sound playback
        for session in sessions {
            let prevPhase = previousPhases[session.sessionId]
            let newPhase = session.phase

            // Filter out context resume transitions (auto-recovery, not real completions)
            let isContextResume = session.lastMessage?.hasPrefix("I'll continue") == true
                || session.lastMessage?.hasPrefix("Continuing from") == true
                || (prevPhase == .compacting && newPhase == .processing)

            if prevPhase == nil {
                // New session
                SoundPlayer.shared.play(.sessionStart)
            } else if prevPhase != newPhase && !isContextResume {
                switch newPhase {
                case .waitingForInput:
                    SoundPlayer.shared.play(.taskComplete)
                case .waitingForApproval:
                    SoundPlayer.shared.play(.approvalNeeded)
                case .compacting:
                    SoundPlayer.shared.play(.contextLimit)
                default:
                    break
                }
            }

            previousPhases[session.sessionId] = newPhase
        }

        // Clean up phases for removed sessions
        let activeIds = Set(sessions.map(\.sessionId))
        previousPhases = previousPhases.filter { activeIds.contains($0.key) }

        instances = sessions
        pendingInstances = sessions.filter { $0.needsAttention }
    }

    /// Called when a user submits a prompt — play acknowledge sound and check for spam
    func onUserPromptSubmitted() {
        SoundPlayer.shared.play(.taskAcknowledge)

        // Spam detection: 3+ messages in 10 seconds
        let now = Date()
        recentUserMessageTimes.append(now)
        recentUserMessageTimes = recentUserMessageTimes.filter { now.timeIntervalSince($0) < 10 }
        if recentUserMessageTimes.count >= 3 {
            SoundPlayer.shared.play(.spamDetection)
        }
    }

    // MARK: - History Loading (for UI)

    /// Request history load for a session
    func loadHistory(sessionId: String, cwd: String) {
        Task {
            await SessionStore.shared.process(.loadHistory(sessionId: sessionId, cwd: cwd))
        }
    }
}

// MARK: - Interrupt Watcher Delegate

extension ClaudeSessionMonitor: JSONLInterruptWatcherDelegate {
    nonisolated func didDetectInterrupt(sessionId: String) {
        Task {
            await SessionStore.shared.process(.interruptDetected(sessionId: sessionId))
        }

        Task { @MainActor in
            InterruptWatcherManager.shared.stopWatching(sessionId: sessionId)
        }
    }
}
