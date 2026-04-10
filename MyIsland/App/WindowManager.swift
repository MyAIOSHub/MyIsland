//
//  WindowManager.swift
//  MyIsland
//
//  Manages the notch window lifecycle
//

import AppKit
import CoreGraphics
import os.log

enum NotchWindowSetupReason {
    case initialLaunch
    case screenParametersChanged
    case mouseScreenChanged

    var shouldSuppressNotificationSound: Bool {
        switch self {
        case .initialLaunch:
            return false
        case .screenParametersChanged, .mouseScreenChanged:
            return true
        }
    }
}

/// Logger for window management
private let logger = Logger(subsystem: "com.myisland", category: "Window")

/// Log all current windows and their sizes (NSApp + Quartz)
func logAllWindows() {
    print("[My Island] === Window Report ===")
    for window in NSApp.windows {
        print("  Window: '\(window.title)' frame=\(window.frame) visible=\(window.isVisible) level=\(window.level.rawValue)")
    }
    // Also check via Quartz
    if let windowList = CGWindowListCopyWindowInfo(.optionAll, kCGNullWindowID) as? [[String: Any]] {
        for w in windowList {
            let owner = w["kCGWindowOwnerName"] as? String ?? ""
            if owner.contains("Claude") && owner.contains("Island") {
                let bounds = w["kCGWindowBounds"] as? [String: Any] ?? [:]
                print("  [Quartz] \(owner): W=\(bounds["Width"] ?? "?") H=\(bounds["Height"] ?? "?") X=\(bounds["X"] ?? "?") Y=\(bounds["Y"] ?? "?") Layer=\(w["kCGWindowLayer"] ?? "?")")
            }
        }
    }
    print("[My Island] === End Window Report ===")
}

class WindowManager {
    private static var suppressNotificationSoundUntil = Date.distantPast
    private static let notificationSoundSuppressionDuration: TimeInterval = 1.5

    private(set) var windowController: NotchWindowController?

    /// Track last screen frame to skip unnecessary recreations
    private var lastScreenFrame: NSRect = .zero

    /// Track current screen for mouse-follow detection
    private var currentScreenID: CGDirectDisplayID?
    private var mouseMonitor: Any?

    static var isSuppressingNotificationSound: Bool {
        Date() < suppressNotificationSoundUntil
    }

    /// Start monitoring mouse position for screen changes (automatic mode)
    func startMouseScreenMonitoring() {
        stopMouseScreenMonitoring()
        // Check every mouse move if screen changed
        mouseMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.mouseMoved]) { [weak self] _ in
            guard ScreenSelector.shared.selectionMode == .automatic else { return }
            let mouseLocation = NSEvent.mouseLocation
            guard let mouseScreen = NSScreen.screens.first(where: { $0.frame.contains(mouseLocation) }),
                  let screenNumber = mouseScreen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID else { return }
            if screenNumber != self?.currentScreenID {
                self?.currentScreenID = screenNumber
                DispatchQueue.main.async {
                    _ = self?.setupNotchWindow(reason: .mouseScreenChanged)
                }
            }
        }
    }

    func stopMouseScreenMonitoring() {
        if let monitor = mouseMonitor {
            NSEvent.removeMonitor(monitor)
            mouseMonitor = nil
        }
    }

    /// Set up or recreate the notch window
    func setupNotchWindow(reason: NotchWindowSetupReason = .initialLaunch) -> NotchWindowController? {
        // Use ScreenSelector for screen selection
        let screenSelector = ScreenSelector.shared
        screenSelector.refreshScreens()

        guard let screen = screenSelector.selectedScreen else {
            logger.warning("No screen found")
            return nil
        }

        // Skip recreation if screen frame hasn't changed (e.g. sleep/wake)
        if windowController != nil && screen.frame == lastScreenFrame {
            logger.debug("Screen frame unchanged, skipping window recreation")
            return windowController
        }

        if reason.shouldSuppressNotificationSound {
            Self.suppressNotificationSoundUntil = Date().addingTimeInterval(Self.notificationSoundSuppressionDuration)
        }

        lastScreenFrame = screen.frame

        if let existingController = windowController {
            existingController.window?.orderOut(nil)
            existingController.window?.close()
            windowController = nil
        }

        windowController = NotchWindowController(screen: screen)
        windowController?.showWindow(nil)

        return windowController
    }
}
