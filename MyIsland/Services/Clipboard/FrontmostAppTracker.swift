//
//  FrontmostAppTracker.swift
//  MyIsland
//
//  Tracks the most recent non-MyIsland foreground app for clipboard attribution and paste targeting.
//

import AppKit

@MainActor
final class FrontmostAppTracker {
    static let shared = FrontmostAppTracker()

    private(set) var lastExternalApplication: NSRunningApplication?
    private var observer: NSObjectProtocol?

    private init() {}

    var lastExternalApplicationName: String? {
        lastExternalApplication?.localizedName
    }

    func start() {
        guard observer == nil else { return }

        if let app = NSWorkspace.shared.frontmostApplication {
            updateTrackedApplication(app)
        }

        observer = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else {
                return
            }
            Task { @MainActor [weak self] in
                self?.updateTrackedApplication(app)
            }
        }
    }

    func stop() {
        if let observer {
            NSWorkspace.shared.notificationCenter.removeObserver(observer)
        }
        observer = nil
    }

    private func updateTrackedApplication(_ app: NSRunningApplication) {
        guard shouldTrack(app) else { return }
        lastExternalApplication = app
    }

    private func shouldTrack(_ app: NSRunningApplication) -> Bool {
        let bundleIdentifier = app.bundleIdentifier ?? ""
        let ownBundleIdentifier = Bundle.main.bundleIdentifier ?? "app.myisland.macos"
        return bundleIdentifier != ownBundleIdentifier
    }
}
