//
//  VoiceInputCoordinator.swift
//  MyIsland
//
//  Orchestrates: Fn key → record → transcribe → send to active Claude session
//

import AppKit
import Combine
import AVFoundation
import Speech

// MARK: - Voice Input State

enum VoiceInputState: Equatable {
    case idle
    case recording
    case processing
    case sending
    case success(String)
    case error(String)
}

// MARK: - VoiceInputCoordinator

@MainActor
final class VoiceInputCoordinator: ObservableObject {
    static let shared = VoiceInputCoordinator()

    // Sub-components
    let hotkeyManager = VoiceHotkeyManager()
    let audioRecorder = VoiceAudioRecorder()
    let speechManager = VoiceSpeechManager()

    // State
    @Published private(set) var voiceState: VoiceInputState = .idle
    @Published private(set) var capturedAppIcon: NSImage?
    private var capturedApp: NSRunningApplication?
    @Published var isEnabled: Bool = false {
        didSet {
            UserDefaults.standard.set(isEnabled, forKey: "voiceInputEnabled")
            if isEnabled { start() } else { stop() }
        }
    }

    private var cancellables = Set<AnyCancellable>()
    private var resetTask: Task<Void, Never>?

    private init() {
        if UserDefaults.standard.object(forKey: "voiceInputEnabled") == nil {
            isEnabled = true
            UserDefaults.standard.set(true, forKey: "voiceInputEnabled")
        } else {
            isEnabled = UserDefaults.standard.bool(forKey: "voiceInputEnabled")
        }
        setupBindings()
    }

    // MARK: - Lifecycle

    func start() {
        guard isEnabled else { return }

        Task {
            // Request permissions
            let micStatus = AVCaptureDevice.authorizationStatus(for: .audio)
            if micStatus == .notDetermined {
                let granted = await AVCaptureDevice.requestAccess(for: .audio)
                if !granted {
                    voiceState = .error("需要麦克风权限")
                    return
                }
            } else if micStatus != .authorized {
                voiceState = .error("需要麦克风权限")
                return
            }

            let speechStatus = await VoiceSpeechManager.requestAuthorization()
            if speechStatus != .authorized {
                voiceState = .error("需要语音识别权限")
                return
            }

            hotkeyManager.startListening()
        }
    }

    func stop() {
        hotkeyManager.stopListening()
        if audioRecorder.isRecording {
            audioRecorder.stopRecording()
        }
        speechManager.cancel()
        voiceState = .idle
        capturedAppIcon = nil
        capturedApp = nil
    }

    // MARK: - Bindings

    private func setupBindings() {
        // Hotkey press/release
        hotkeyManager.$isHotkeyPressed
            .removeDuplicates()
            .sink { [weak self] pressed in
                guard let self, self.isEnabled else { return }
                if pressed {
                    if self.voiceState == .idle {
                        self.beginSession()
                    } else {
                        // Pressing fn again during any active state cancels
                        self.cancelSession()
                    }
                } else if self.voiceState == .recording {
                    self.endSession()
                }
            }
            .store(in: &cancellables)

        // ESC key cancels voice input
        hotkeyManager.$isEscPressed
            .filter { $0 }
            .sink { [weak self] _ in
                guard let self, self.voiceState != .idle else { return }
                self.cancelSession()
            }
            .store(in: &cancellables)

        // Final transcription result
        speechManager.$finalText
            .compactMap { $0 }
            .sink { [weak self] text in
                guard let self else { return }
                self.handleFinalResult(text)
            }
            .store(in: &cancellables)

        // Forward audio level changes for UI refresh
        audioRecorder.$audioLevels
            .throttle(for: .milliseconds(33), scheduler: DispatchQueue.main, latest: true)
            .sink { [weak self] _ in
                self?.objectWillChange.send()
            }
            .store(in: &cancellables)
    }

    // MARK: - Session Flow

    private func beginSession() {
        guard voiceState == .idle else { return }

        // Capture frontmost app so we can restore focus after transcription
        if let frontApp = NSWorkspace.shared.frontmostApplication {
            capturedAppIcon = frontApp.icon
            capturedApp = frontApp
        }

        // Start recording
        do {
            try audioRecorder.startRecording()
        } catch {
            voiceState = .error("麦克风错误")
            scheduleReset()
            return
        }

        // Wire audio to speech
        audioRecorder.onBuffer = { [weak self] buffer in
            self?.speechManager.appendBuffer(buffer)
        }

        // Start streaming recognition
        speechManager.startStreaming()
        voiceState = .recording
    }

    private func endSession() {
        audioRecorder.stopRecording()
        speechManager.stopStreaming()
        voiceState = .processing
    }

    private func handleFinalResult(_ text: String) {
        guard !text.isEmpty else {
            voiceState = .error("未识别到语音")
            scheduleReset()
            return
        }

        // Directly send text to the active Claude session (no clipboard)
        Task {
            let sent = await sendToActiveSession(text)
            if !sent {
                // Restore focus to the app that was active when recording started
                if let app = self.capturedApp {
                    app.activate()
                    // Brief delay to let the app gain focus before typing
                    try? await Task.sleep(for: .milliseconds(100))
                }
                await MainActor.run {
                    self.simulateTyping(text)
                }
            }
        }

        voiceState = .success(text)
        scheduleReset()
    }

    /// Type text character by character via CGEvent (no clipboard involved)
    private func simulateTyping(_ text: String) {
        let source = CGEventSource(stateID: .hidSystemState)
        for char in text.utf16 {
            let keyDown = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: true)
            keyDown?.keyboardSetUnicodeString(stringLength: 1, unicodeString: [char])
            keyDown?.post(tap: .cghidEventTap)

            let keyUp = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: false)
            keyUp?.post(tap: .cghidEventTap)
        }
    }

    // MARK: - Send to Session

    private func sendToActiveSession(_ text: String) async -> Bool {
        // Find the most recently active session that accepts input
        let monitor = await MainActor.run { () -> ClaudeSessionMonitor? in
            // Access through NotchView's session monitor is tricky from here
            // Use a simpler approach: search tmux panes directly
            return nil
        }

        // Search for tmux pane running claude
        guard let tmuxPath = await TmuxPathFinder.shared.getTmuxPath() else {
            return false
        }

        // List all tmux panes and find ones running claude
        guard let output = try? await ProcessExecutor.shared.run(
            tmuxPath,
            arguments: ["list-panes", "-a", "-F", "#{session_name}:#{window_index}.#{pane_index} #{pane_current_command} #{pane_tty}"]
        ), !output.isEmpty else { return false }

        // Find first pane running claude
        for line in output.components(separatedBy: "\n") {
            let parts = line.split(separator: " ", maxSplits: 2)
            guard parts.count >= 2 else { continue }
            let target = String(parts[0])
            let command = String(parts[1]).lowercased()

            if command.contains("claude") || command.contains("codex") {
                if let tmuxTarget = TmuxTarget(from: target) {
                    return await ToolApprovalHandler.shared.sendMessage(text, to: tmuxTarget)
                }
            }
        }

        return false
    }

    // MARK: - Cancel

    private func cancelSession() {
        resetTask?.cancel()
        audioRecorder.stopRecording()
        speechManager.cancel()
        voiceState = .idle
        capturedAppIcon = nil
        capturedApp = nil
    }

    // MARK: - Reset

    private func scheduleReset() {
        resetTask?.cancel()
        resetTask = Task {
            try? await Task.sleep(for: .seconds(2.5))
            guard !Task.isCancelled else { return }
            voiceState = .idle
            capturedAppIcon = nil
            capturedApp = nil
        }
    }
}
