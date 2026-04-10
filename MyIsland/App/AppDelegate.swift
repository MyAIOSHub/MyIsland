import AppKit
import Sparkle
import SwiftUI
import UserNotifications

private enum UpdateNotificationIdentifiers {
    static let readyRequest = "app.myisland.macos.update.ready"
    static let readyCategory = "app.myisland.macos.update.ready.category"
    static let installAction = "app.myisland.macos.update.install.action"
}

class AppDelegate: NSObject, NSApplicationDelegate, UNUserNotificationCenterDelegate {
    private var windowManager: WindowManager?
    private var screenObserver: ScreenObserver?
    private var updateCheckTimer: Timer?

    static var shared: AppDelegate?
    let updater: SPUUpdater
    private let userDriver: NotchUserDriver

    var windowController: NotchWindowController? {
        windowManager?.windowController
    }

    override init() {
        userDriver = NotchUserDriver()
        updater = SPUUpdater(
            hostBundle: Bundle.main,
            applicationBundle: Bundle.main,
            userDriver: userDriver,
            delegate: nil
        )
        super.init()
        AppDelegate.shared = self

        do {
            try updater.start()
        } catch {
            print("Failed to start Sparkle updater: \(error)")
        }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        if !ensureSingleInstance() {
            NSApplication.shared.terminate(nil)
            return
        }

        configureUpdateNotifications()

        // Install hooks for all supported CLI tools
        for target in HookTarget.allCases {
            HookInstaller.installIfNeeded(target: target)
        }

        // Prompt for accessibility permission if not granted
        if !AXIsProcessTrusted() {
            let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue(): true] as CFDictionary
            AXIsProcessTrustedWithOptions(options)
        }

        // Start voice input if enabled in settings
        if VoiceInputCoordinator.shared.isEnabled {
            VoiceInputCoordinator.shared.start()
        }

        FrontmostAppTracker.shared.start()
        ClipboardHistoryManager.shared.start()
        ClipboardMonitor.shared.start()

        // Start browser event server for extension integration
        BrowserEventServer.shared.start { event in
            Task { @MainActor in
                BrowserSessionMonitor.shared.handleEvent(event)
            }
        }
        BrowserSessionMonitor.shared.startCleanup()

        // Start Claude Desktop session watcher
        ClaudeDesktopWatcher.shared.start()

        NSApplication.shared.setActivationPolicy(.accessory)

        windowManager = WindowManager()
        _ = windowManager?.setupNotchWindow()
        windowManager?.startMouseScreenMonitoring()

        screenObserver = ScreenObserver { [weak self] in
            self?.handleScreenChange()
        }

        // Log all windows after setup
        logAllWindows()

        if updater.canCheckForUpdates {
            updater.checkForUpdates()
        }

        updateCheckTimer = Timer.scheduledTimer(withTimeInterval: 3600, repeats: true) { [weak self] _ in
            guard let updater = self?.updater, updater.canCheckForUpdates else { return }
            updater.checkForUpdates()
        }
    }

    private func handleScreenChange() {
        _ = windowManager?.setupNotchWindow(reason: .screenParametersChanged)
    }

    func applicationWillTerminate(_ notification: Notification) {
        updateCheckTimer?.invalidate()
        screenObserver = nil
        ClipboardMonitor.shared.stop()
        FrontmostAppTracker.shared.stop()
    }

    private func ensureSingleInstance() -> Bool {
        let bundleID = Bundle.main.bundleIdentifier ?? "app.myisland.macos"
        let runningApps = NSWorkspace.shared.runningApplications.filter {
            $0.bundleIdentifier == bundleID
        }

        if runningApps.count > 1 {
            if let existingApp = runningApps.first(where: { $0.processIdentifier != getpid() }) {
                existingApp.activate()
            }
            return false
        }

        return true
    }

    private func configureUpdateNotifications() {
        let center = UNUserNotificationCenter.current()
        center.delegate = self

        let installAction = UNNotificationAction(
            identifier: UpdateNotificationIdentifiers.installAction,
            title: String(localized: "update.installRelaunch"),
            options: [.foreground]
        )
        let readyCategory = UNNotificationCategory(
            identifier: UpdateNotificationIdentifiers.readyCategory,
            actions: [installAction],
            intentIdentifiers: []
        )
        center.setNotificationCategories([readyCategory])
    }

    func scheduleUpdateReadyNotification(version: String) {
        let center = UNUserNotificationCenter.current()
        center.getNotificationSettings { [weak self] settings in
            switch settings.authorizationStatus {
            case .authorized, .provisional, .ephemeral:
                self?.enqueueUpdateReadyNotification(version: version)
            case .notDetermined:
                center.requestAuthorization(options: [.alert, .sound]) { granted, error in
                    if let error {
                        print("Failed to request notification authorization: \(error)")
                    }
                    guard granted else { return }
                    self?.enqueueUpdateReadyNotification(version: version)
                }
            case .denied:
                break
            @unknown default:
                break
            }
        }
    }

    func clearUpdateReadyNotifications() {
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: [UpdateNotificationIdentifiers.readyRequest])
        center.removeDeliveredNotifications(withIdentifiers: [UpdateNotificationIdentifiers.readyRequest])
    }

    private func enqueueUpdateReadyNotification(version: String) {
        clearUpdateReadyNotifications()

        let content = UNMutableNotificationContent()
        content.title = String(localized: "update.readyTitle")
        let bodyFormat = String(localized: "update.readyBody")
        content.body = String(format: bodyFormat, locale: Locale.current, version)
        content.sound = .default
        content.categoryIdentifier = UpdateNotificationIdentifiers.readyCategory

        let request = UNNotificationRequest(
            identifier: UpdateNotificationIdentifiers.readyRequest,
            content: content,
            trigger: UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false)
        )

        UNUserNotificationCenter.current().add(request) { error in
            if let error {
                print("Failed to schedule update notification: \(error)")
            }
        }
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound])
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        defer { completionHandler() }

        guard response.notification.request.identifier == UpdateNotificationIdentifiers.readyRequest else {
            return
        }

        switch response.actionIdentifier {
        case UNNotificationDefaultActionIdentifier, UpdateNotificationIdentifiers.installAction:
            Task { @MainActor in
                UpdateManager.shared.installAndRelaunch()
            }
        default:
            break
        }
    }
}
