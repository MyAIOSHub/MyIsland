//
//  ClipboardMonitor.swift
//  MyIsland
//
//  Polls NSPasteboard.general for global clipboard changes.
//

import AppKit

@MainActor
final class ClipboardMonitor {
    static let shared = ClipboardMonitor()

    private let pasteboard = NSPasteboard.general
    private var lastChangeCount = NSPasteboard.general.changeCount
    private var timer: Timer?
    private var suppressedChanges = 0

    private init() {}

    func start() {
        guard timer == nil else { return }

        lastChangeCount = pasteboard.changeCount
        let timer = Timer.scheduledTimer(withTimeInterval: 0.4, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.checkPasteboard()
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    func suppressNextChanges(_ count: Int = 1) {
        suppressedChanges += max(0, count)
    }

    private func checkPasteboard() {
        let currentChangeCount = pasteboard.changeCount
        guard currentChangeCount != lastChangeCount else { return }

        let delta = max(1, currentChangeCount - lastChangeCount)
        lastChangeCount = currentChangeCount

        if suppressedChanges > 0 {
            if suppressedChanges >= delta {
                suppressedChanges -= delta
                return
            }
            suppressedChanges = 0
        }

        guard let payload = ClipboardParser.parse(pasteboard) else { return }
        let sourceAppName = FrontmostAppTracker.shared.lastExternalApplicationName

        Task {
            await ClipboardStore.shared.capture(payload, sourceAppName: sourceAppName)
        }
    }
}
