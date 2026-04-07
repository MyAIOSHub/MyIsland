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
import os.log

private let logger = Logger(subsystem: "com.myisland", category: "Voice")

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
            let name = frontApp.localizedName ?? "unknown"
            let pid = frontApp.processIdentifier
            logger.info("[Voice] Captured frontmost app: \(name, privacy: .public) (pid: \(pid))")
        }

        // Start recording
        do {
            try audioRecorder.startRecording()
        } catch {
            logger.error("[Voice] Failed to start recording: \(error, privacy: .public)")
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
        logger.info("[Voice] Recording started")
    }

    private func endSession() {
        audioRecorder.stopRecording()
        speechManager.stopStreaming()
        voiceState = .processing
        let currentPartial = speechManager.partialText
        logger.info("[Voice] Recording stopped, processing... (partialText: '\(currentPartial, privacy: .public)')")

        // Safety timeout: if no final result within 5 seconds, use partial text or show error
        resetTask?.cancel()
        resetTask = Task {
            try? await Task.sleep(for: .seconds(5))
            guard !Task.isCancelled else { return }
            // Still processing after timeout - use partial text if available
            if self.voiceState == .processing {
                let partial = self.speechManager.partialText
                logger.info("[Voice] Processing timeout, partialText: '\(partial, privacy: .public)'")
                self.speechManager.cancel()
                if !partial.isEmpty {
                    self.handleFinalResult(partial)
                } else {
                    self.voiceState = .error("识别超时")
                    self.scheduleReset()
                }
            }
        }
    }

    private func handleFinalResult(_ text: String) {
        guard !text.isEmpty else {
            voiceState = .error("未识别到语音")
            scheduleReset()
            return
        }

        logger.info("[Voice] Final result: '\(text, privacy: .public)'")

        let targetApp = self.capturedApp
        let appName = targetApp?.localizedName ?? "nil"
        let axTrusted = AXIsProcessTrusted()
        logger.info("[Voice] Target app: \(appName, privacy: .public), AXTrusted: \(axTrusted)")

        // Directly paste to the target app (skip tmux for non-terminal apps)
        pasteText(text, to: targetApp)

        voiceState = .success(text)
        scheduleReset()
    }

    /// Paste text via clipboard + Cmd+V, which is reliable for all apps and languages
    private func pasteText(_ text: String, to app: NSRunningApplication?) {
        guard AXIsProcessTrusted() else {
            logger.error("[Voice] Accessibility not granted, cannot paste")
            return
        }

        // Save current clipboard content
        let pasteboard = NSPasteboard.general
        let previousContents = pasteboard.string(forType: .string)

        // Set transcribed text to clipboard
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
        logger.info("[Voice] Clipboard set, text length: \(text.count)")

        // Restore focus to the original app
        if let app {
            let activated = app.activate(options: .activateIgnoringOtherApps)
            let name = app.localizedName ?? "unknown"
            logger.info("[Voice] Activated app '\(name, privacy: .public)': \(activated)")
            // Give the app time to gain focus
            usleep(200_000) // 200ms
        } else {
            logger.warning("[Voice] No target app to activate")
        }

        // Simulate Cmd+V paste
        guard let source = CGEventSource(stateID: .hidSystemState) else {
            logger.error("[Voice] Failed to create CGEventSource")
            return
        }
        guard let keyDown = CGEvent(keyboardEventSource: source, virtualKey: 9, keyDown: true),
              let keyUp = CGEvent(keyboardEventSource: source, virtualKey: 9, keyDown: false) else {
            logger.error("[Voice] Failed to create CGEvent for Cmd+V")
            return
        }
        keyDown.flags = .maskCommand
        keyDown.post(tap: .cghidEventTap)
        keyUp.flags = .maskCommand
        keyUp.post(tap: .cghidEventTap)
        logger.info("[Voice] Cmd+V paste event posted")

        // Restore previous clipboard after a short delay
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            if let previous = previousContents {
                pasteboard.clearContents()
                pasteboard.setString(previous, forType: .string)
            }
        }
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
