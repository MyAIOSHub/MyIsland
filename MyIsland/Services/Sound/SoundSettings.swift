//
//  SoundSettings.swift
//  MyIsland
//
//  Per-category sound settings with UserDefaults persistence
//

import Combine
import Foundation

/// Categories of sound events
enum SoundCategory: String, CaseIterable, Sendable {
    case sessionStart
    case taskComplete
    case taskError
    case approvalNeeded
    case taskAcknowledge
    case contextLimit
    case spamDetection

    /// Chinese display name
    var displayName: String {
        switch self {
        case .sessionStart:    return "会话开始"
        case .taskComplete:    return "任务完成"
        case .taskError:       return "任务错误"
        case .approvalNeeded:  return "需要审批"
        case .taskAcknowledge: return "任务确认"
        case .contextLimit:    return "上下文限制"
        case .spamDetection:   return "连续提交检测"
        }
    }

    /// Chinese description
    var displayDescription: String {
        switch self {
        case .sessionStart:    return "新的 Claude / Codex / Gemini 会话"
        case .taskComplete:    return "AI 完成了本轮回复"
        case .taskError:       return "工具失败或 API 错误"
        case .approvalNeeded:  return "等待权限审批或回答问题"
        case .taskAcknowledge: return "你发送了一条消息"
        case .contextLimit:    return "上下文窗口压缩中"
        case .spamDetection:   return "10 秒内发了 3+ 条消息"
        }
    }

    /// Section grouping
    var section: SoundSection {
        switch self {
        case .sessionStart, .taskComplete, .taskError:
            return .session
        case .approvalNeeded, .taskAcknowledge:
            return .interaction
        case .contextLimit, .spamDetection:
            return .system
        }
    }

    /// System sound name
    var systemSoundName: String {
        switch self {
        case .sessionStart:    return "Glass"
        case .taskComplete:    return "Hero"
        case .taskError:       return "Basso"
        case .approvalNeeded:  return "Ping"
        case .taskAcknowledge: return "Tink"
        case .contextLimit:    return "Purr"
        case .spamDetection:   return "Funk"
        }
    }
}

/// Section grouping for sound categories
enum SoundSection: String, CaseIterable {
    case session
    case interaction
    case system

    var displayName: String {
        switch self {
        case .session:     return "会话"
        case .interaction: return "交互"
        case .system:      return "系统"
        }
    }

    var categories: [SoundCategory] {
        SoundCategory.allCases.filter { $0.section == self }
    }
}

/// Observable sound settings with UserDefaults persistence
@MainActor
class SoundSettings: ObservableObject {
    static let shared = SoundSettings()

    // MARK: - Published State

    @Published var isEnabled: Bool = true {
        didSet { save() }
    }

    @Published var volume: Float = 0.3 {
        didSet { save() }
    }

    // Per-category toggles
    @Published var sessionStartEnabled: Bool = true { didSet { save() } }
    @Published var taskCompleteEnabled: Bool = true { didSet { save() } }
    @Published var taskErrorEnabled: Bool = true { didSet { save() } }
    @Published var approvalNeededEnabled: Bool = true { didSet { save() } }
    @Published var taskAcknowledgeEnabled: Bool = false { didSet { save() } }
    @Published var contextLimitEnabled: Bool = true { didSet { save() } }
    @Published var spamDetectionEnabled: Bool = true { didSet { save() } }

    // Probe filter
    @Published var autoDetectProbes: Bool = true { didSet { save() } }

    /// Suppress sounds when a terminal is focused on the current space
    @Published var suppressWhenTerminalFocused: Bool = false { didSet { save() } }

    // MARK: - Keys

    private enum Keys {
        static let isEnabled = "sound.isEnabled"
        static let volume = "sound.volume"
        static let sessionStart = "sound.sessionStart"
        static let taskComplete = "sound.taskComplete"
        static let taskError = "sound.taskError"
        static let approvalNeeded = "sound.approvalNeeded"
        static let taskAcknowledge = "sound.taskAcknowledge"
        static let contextLimit = "sound.contextLimit"
        static let spamDetection = "sound.spamDetection"
        static let autoDetectProbes = "sound.autoDetectProbes"
        static let suppressWhenTerminalFocused = "sound.suppressWhenTerminalFocused"
    }

    // MARK: - Init

    private init() {
        load()
    }

    // MARK: - Per-Category Access

    func isEnabled(for category: SoundCategory) -> Bool {
        switch category {
        case .sessionStart:    return sessionStartEnabled
        case .taskComplete:    return taskCompleteEnabled
        case .taskError:       return taskErrorEnabled
        case .approvalNeeded:  return approvalNeededEnabled
        case .taskAcknowledge: return taskAcknowledgeEnabled
        case .contextLimit:    return contextLimitEnabled
        case .spamDetection:   return spamDetectionEnabled
        }
    }

    func setEnabled(_ enabled: Bool, for category: SoundCategory) {
        switch category {
        case .sessionStart:    sessionStartEnabled = enabled
        case .taskComplete:    taskCompleteEnabled = enabled
        case .taskError:       taskErrorEnabled = enabled
        case .approvalNeeded:  approvalNeededEnabled = enabled
        case .taskAcknowledge: taskAcknowledgeEnabled = enabled
        case .contextLimit:    contextLimitEnabled = enabled
        case .spamDetection:   spamDetectionEnabled = enabled
        }
    }

    func binding(for category: SoundCategory) -> Bool {
        isEnabled(for: category)
    }

    // MARK: - Persistence

    private func save() {
        let defaults = UserDefaults.standard
        defaults.set(isEnabled, forKey: Keys.isEnabled)
        defaults.set(volume, forKey: Keys.volume)
        defaults.set(sessionStartEnabled, forKey: Keys.sessionStart)
        defaults.set(taskCompleteEnabled, forKey: Keys.taskComplete)
        defaults.set(taskErrorEnabled, forKey: Keys.taskError)
        defaults.set(approvalNeededEnabled, forKey: Keys.approvalNeeded)
        defaults.set(taskAcknowledgeEnabled, forKey: Keys.taskAcknowledge)
        defaults.set(contextLimitEnabled, forKey: Keys.contextLimit)
        defaults.set(spamDetectionEnabled, forKey: Keys.spamDetection)
        defaults.set(autoDetectProbes, forKey: Keys.autoDetectProbes)
        defaults.set(suppressWhenTerminalFocused, forKey: Keys.suppressWhenTerminalFocused)
    }

    /// Whether sounds should be suppressed right now
    var shouldSuppressSound: Bool {
        suppressWhenTerminalFocused && TerminalVisibilityDetector.isTerminalVisibleOnCurrentSpace()
    }

    private func load() {
        let defaults = UserDefaults.standard

        // Only load if values have been previously saved
        if defaults.object(forKey: Keys.isEnabled) != nil {
            isEnabled = defaults.bool(forKey: Keys.isEnabled)
        }
        if defaults.object(forKey: Keys.volume) != nil {
            volume = defaults.float(forKey: Keys.volume)
        }
        if defaults.object(forKey: Keys.sessionStart) != nil {
            sessionStartEnabled = defaults.bool(forKey: Keys.sessionStart)
        }
        if defaults.object(forKey: Keys.taskComplete) != nil {
            taskCompleteEnabled = defaults.bool(forKey: Keys.taskComplete)
        }
        if defaults.object(forKey: Keys.taskError) != nil {
            taskErrorEnabled = defaults.bool(forKey: Keys.taskError)
        }
        if defaults.object(forKey: Keys.approvalNeeded) != nil {
            approvalNeededEnabled = defaults.bool(forKey: Keys.approvalNeeded)
        }
        if defaults.object(forKey: Keys.taskAcknowledge) != nil {
            taskAcknowledgeEnabled = defaults.bool(forKey: Keys.taskAcknowledge)
        }
        if defaults.object(forKey: Keys.contextLimit) != nil {
            contextLimitEnabled = defaults.bool(forKey: Keys.contextLimit)
        }
        if defaults.object(forKey: Keys.spamDetection) != nil {
            spamDetectionEnabled = defaults.bool(forKey: Keys.spamDetection)
        }
        if defaults.object(forKey: Keys.autoDetectProbes) != nil {
            autoDetectProbes = defaults.bool(forKey: Keys.autoDetectProbes)
        }
        if defaults.object(forKey: Keys.suppressWhenTerminalFocused) != nil {
            suppressWhenTerminalFocused = defaults.bool(forKey: Keys.suppressWhenTerminalFocused)
        }
    }
}
