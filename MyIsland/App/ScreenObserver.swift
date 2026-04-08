//
//  ScreenObserver.swift
//  MyIsland
//
//  Monitors screen configuration changes
//

import AppKit

class ScreenObserver {
    private var observer: Any?
    private let onScreenChange: () -> Void

    /// Debounce timer to coalesce rapid screen change notifications (e.g. sleep/wake)
    private var debounceTimer: Timer?
    private let debounceInterval: TimeInterval = 0.5

    init(onScreenChange: @escaping () -> Void) {
        self.onScreenChange = onScreenChange
        startObserving()
    }

    deinit {
        stopObserving()
    }

    private func startObserving() {
        observer = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.scheduleScreenChange()
        }
    }

    private func scheduleScreenChange() {
        debounceTimer?.invalidate()
        debounceTimer = Timer.scheduledTimer(withTimeInterval: debounceInterval, repeats: false) { [weak self] _ in
            self?.onScreenChange()
        }
    }

    private func stopObserving() {
        debounceTimer?.invalidate()
        if let observer = observer {
            NotificationCenter.default.removeObserver(observer)
        }
    }
}
