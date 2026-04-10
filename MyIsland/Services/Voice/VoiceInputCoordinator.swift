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
    private var processingTask: Task<Void, Never>?  // Cloud ASR processing task

    // Fn key press mode detection
    private var fnPressTime: Date?
    private var holdDetectionTask: Task<Void, Never>?
    private var isHoldMode: Bool = false
    private let holdThreshold: TimeInterval = 0.3  // 300ms to distinguish click vs hold

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
                    scheduleReset()
                    return
                }
            } else if micStatus != .authorized {
                voiceState = .error("需要麦克风权限")
                scheduleReset()
                return
            }

            let speechStatus = await VoiceSpeechManager.requestAuthorization()
            if speechStatus != .authorized {
                voiceState = .error("需要语音识别权限")
                scheduleReset()
                return
            }

            // Auto-fix Fn key setting to prevent emoji picker interference
            Self.disableFnEmojiPicker()

            hotkeyManager.startListening()
        }
    }

    /// Disable Fn key emoji picker if currently enabled
    private static func disableFnEmojiPicker() {
        let currentValue = UserDefaults(suiteName: "com.apple.HIToolbox")?.integer(forKey: "AppleFnUsageType") ?? -1
        if currentValue != 0 {
            // 0 = Do Nothing, 1 = Change Input Source, 2 = Show Emoji & Symbols, 3 = Start Dictation
            let task = Process()
            task.executableURL = URL(fileURLWithPath: "/usr/bin/defaults")
            task.arguments = ["write", "com.apple.HIToolbox", "AppleFnUsageType", "-int", "0"]
            try? task.run()
            task.waitUntilExit()
            logger.info("[Voice] Disabled Fn emoji picker (was: \(currentValue))")
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
        // Hotkey press/release — supports both click-toggle and hold modes
        hotkeyManager.$isHotkeyPressed
            .removeDuplicates()
            .sink { [weak self] pressed in
                guard let self, self.isEnabled else { return }
                if pressed {
                    self.handleFnPressed()
                } else {
                    self.handleFnReleased()
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

    // MARK: - Fn Key Press/Release Handling

    private func handleFnPressed() {
        // If recording in click-toggle mode, second click ends session
        if voiceState == .recording && !isHoldMode {
            endSession()
            return
        }

        // If in any non-idle state (processing, error, etc.), cancel
        if voiceState != .idle {
            cancelSession()
            return
        }

        // Idle state: start hold detection timer
        fnPressTime = Date()
        holdDetectionTask?.cancel()
        holdDetectionTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(300))
            guard !Task.isCancelled else { return }
            guard let self else { return }
            // 300ms elapsed with Fn still held → long-press mode
            self.isHoldMode = true
            self.beginSession()
        }
    }

    private func handleFnReleased() {
        holdDetectionTask?.cancel()
        holdDetectionTask = nil

        if isHoldMode && voiceState == .recording {
            // Long-press mode: release ends recording
            endSession()
        } else if let pressTime = fnPressTime,
                  Date().timeIntervalSince(pressTime) < holdThreshold,
                  voiceState == .idle {
            // Quick click (<300ms): start recording in toggle mode
            isHoldMode = false
            beginSession()
        }

        fnPressTime = nil
    }

    private func resetFnState() {
        isHoldMode = false
        fnPressTime = nil
        holdDetectionTask?.cancel()
        holdDetectionTask = nil
    }

    // MARK: - Session Flow

    /// Current ASR mode for the active session
    private var currentASRMode: ASRMode {
        ASRPostProcessor.shared.resolveMode(for: capturedApp)
    }

    private func beginSession() {
        guard voiceState == .idle else { return }

        // Check accessibility permission
        if !AXIsProcessTrusted() {
            let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue(): true] as CFDictionary
            AXIsProcessTrustedWithOptions(options)
            voiceState = .error("需要辅助功能权限")
            scheduleReset()
            return
        }

        // Check microphone permission
        let micStatus = AVCaptureDevice.authorizationStatus(for: .audio)
        if micStatus == .notDetermined {
            Task {
                let granted = await AVCaptureDevice.requestAccess(for: .audio)
                if granted { self.beginSession() }  // Retry after grant
                else {
                    self.voiceState = .error("需要麦克风权限")
                    self.scheduleReset()
                }
            }
            return
        } else if micStatus != .authorized {
            voiceState = .error("需要麦克风权限")
            scheduleReset()
            // Open System Settings → Privacy → Microphone
            if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone") {
                NSWorkspace.shared.open(url)
            }
            return
        }

        // Capture frontmost app
        if let frontApp = NSWorkspace.shared.frontmostApplication {
            capturedAppIcon = frontApp.icon
            capturedApp = frontApp
            let name = frontApp.localizedName ?? "unknown"
            let pid = frontApp.processIdentifier
            logger.info("[Voice] Captured frontmost app: \(name, privacy: .public) (pid: \(pid))")
        }

        let mode = currentASRMode
        logger.info("[Voice] ASR mode: \(mode.rawValue, privacy: .public)")

        // Non-fast modes: collect audio buffers for cloud ASR
        audioRecorder.collectBuffers = (mode != .fast)

        // Start recording
        do {
            try audioRecorder.startRecording()
        } catch {
            logger.error("[Voice] Failed to start recording: \(error, privacy: .public)")
            voiceState = .error("麦克风错误")
            scheduleReset()
            return
        }

        if mode == .fast {
            // Fast mode: use Apple SpeechRecognizer for real-time streaming
            audioRecorder.onBuffer = { [weak self] buffer in
                self?.speechManager.appendBuffer(buffer)
            }
            speechManager.startStreaming()
        } else {
            // Non-fast: just record, no Apple ASR
            audioRecorder.onBuffer = nil
        }

        voiceState = .recording
        logger.info("[Voice] Recording started")
    }

    private func endSession() {
        resetFnState()
        let mode = currentASRMode
        audioRecorder.stopRecording()
        voiceState = .processing

        if mode == .fast {
            // Fast mode: wait for Apple SpeechRecognizer final result
            speechManager.stopStreaming()
            let currentPartial = speechManager.partialText
            logger.info("[Voice] Recording stopped (fast), partialText: '\(currentPartial, privacy: .public)'")

            // Safety timeout
            resetTask?.cancel()
            resetTask = Task {
                try? await Task.sleep(for: .seconds(5))
                guard !Task.isCancelled else { return }
                if self.voiceState == .processing {
                    let partial = self.speechManager.partialText
                    self.speechManager.cancel()
                    if !partial.isEmpty {
                        self.handleFinalResult(partial)
                    } else {
                        self.voiceState = .error("识别超时")
                        self.scheduleReset()
                    }
                }
            }
        } else {
            // Non-fast: send recorded audio to Dashscope ASR + LLM
            logger.info("[Voice] Recording stopped (cloud), sending to Dashscope...")
            let audioData = audioRecorder.getRecordedWAVData()
            audioRecorder.clearBuffers()

            guard let audioData, !audioData.isEmpty else {
                voiceState = .error("录音数据为空")
                scheduleReset()
                return
            }

            logger.info("[Voice] Audio data: \(audioData.count) bytes")
            let targetApp = self.capturedApp

            processingTask = Task {
                guard !Task.isCancelled else { return }
                let result = await ASRPostProcessor.shared.process(audioData: audioData, mode: mode)
                guard !Task.isCancelled else { return }
                if result.isEmpty {
                    voiceState = .error("识别失败")
                } else {
                    pasteText(result, to: targetApp)
                    voiceState = .success(result)
                }
                scheduleReset()
            }
        }
    }

    /// Handle Apple SpeechRecognizer result (fast mode only)
    private func handleFinalResult(_ text: String) {
        guard !text.isEmpty else {
            voiceState = .error("未识别到语音")
            scheduleReset()
            return
        }

        logger.info("[Voice] Fast result: '\(text, privacy: .public)'")
        pasteText(text, to: capturedApp)
        voiceState = .success(text)
        scheduleReset()
    }

    /// Paste text via clipboard + Cmd+V, which is reliable for all apps and languages
    private func pasteText(_ text: String, to app: NSRunningApplication?) {
        guard AXIsProcessTrusted() else {
            logger.error("[Voice] Accessibility not granted, cannot paste")
            return
        }

        if let app {
            let name = app.localizedName ?? "unknown"
            logger.info("[Voice] Target app for paste: '\(name, privacy: .public)'")
        }
        Task {
            await ClipboardPasteCoordinator.shared.pasteTextTemporarily(text, to: app)
        }
    }

    // MARK: - Cancel

    private func cancelSession() {
        resetFnState()
        resetTask?.cancel()
        processingTask?.cancel()
        processingTask = nil
        audioRecorder.stopRecording()
        audioRecorder.clearBuffers()
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
