//
//  Settings.swift
//  MyIsland
//
//  App settings manager using UserDefaults
//

import Foundation

/// Available notification sounds
enum NotificationSound: String, CaseIterable {
    case none = "None"
    case pop = "Pop"
    case ping = "Ping"
    case tink = "Tink"
    case glass = "Glass"
    case blow = "Blow"
    case bottle = "Bottle"
    case frog = "Frog"
    case funk = "Funk"
    case hero = "Hero"
    case morse = "Morse"
    case purr = "Purr"
    case sosumi = "Sosumi"
    case submarine = "Submarine"
    case basso = "Basso"

    /// The system sound name to use with NSSound, or nil for no sound
    var soundName: String? {
        self == .none ? nil : rawValue
    }
}

enum AppSettings {
    private static let defaults = UserDefaults.standard

    // MARK: - Keys

    private enum Keys {
        static let notificationSound = "notificationSound"
        static let autoExpandNotch = "autoExpandNotch"
        static let verboseMode = "verboseMode"
    }

    // MARK: - Notch Behavior

    /// Whether the notch auto-expands when sessions need attention (default: off)
    static var autoExpandNotch: Bool {
        get { defaults.object(forKey: Keys.autoExpandNotch) as? Bool ?? false }
        set { defaults.set(newValue, forKey: Keys.autoExpandNotch) }
    }

    /// Whether to show verbose tool call details (default: off)
    static var verboseMode: Bool {
        get { defaults.object(forKey: Keys.verboseMode) as? Bool ?? false }
        set { defaults.set(newValue, forKey: Keys.verboseMode) }
    }

    // MARK: - Notification Sound

    /// The sound to play when Claude finishes and is ready for input
    static var notificationSound: NotificationSound {
        get {
            guard let rawValue = defaults.string(forKey: Keys.notificationSound),
                  let sound = NotificationSound(rawValue: rawValue) else {
                return .pop // Default to Pop
            }
            return sound
        }
        set {
            defaults.set(newValue.rawValue, forKey: Keys.notificationSound)
        }
    }
}
