import AppKit
import Combine

@MainActor
final class VoiceHotkeyManager: ObservableObject {
    @Published private(set) var isHotkeyPressed: Bool = false
    @Published private(set) var isEscPressed: Bool = false

    private var keyDownMonitor: Any?
    private var keyUpMonitor: Any?
    private var flagsMonitor: Any?
    private var escMonitor: Any?

    var hotkeyCode: UInt16 = 63  // Fn key
    var useFlagsChanged: Bool = true

    func startListening() {
        stopListening()

        if useFlagsChanged {
            flagsMonitor = NSEvent.addGlobalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
                Task { @MainActor in
                    guard let self else { return }
                    let fnPressed = event.modifierFlags.contains(.function)
                    if fnPressed != self.isHotkeyPressed {
                        self.isHotkeyPressed = fnPressed
                    }
                }
            }
        } else {
            keyDownMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
                Task { @MainActor in
                    guard let self, event.keyCode == self.hotkeyCode else { return }
                    if !self.isHotkeyPressed {
                        self.isHotkeyPressed = true
                    }
                }
            }
            keyUpMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyUp) { [weak self] event in
                Task { @MainActor in
                    guard let self, event.keyCode == self.hotkeyCode else { return }
                    if self.isHotkeyPressed {
                        self.isHotkeyPressed = false
                    }
                }
            }
        }

        // ESC key monitor (keyCode 53)
        escMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            Task { @MainActor in
                guard let self, event.keyCode == 53 else { return }
                self.isEscPressed = true
                // Reset immediately so next ESC press can be detected
                self.isEscPressed = false
            }
        }
    }

    func stopListening() {
        if let m = keyDownMonitor { NSEvent.removeMonitor(m) }
        if let m = keyUpMonitor { NSEvent.removeMonitor(m) }
        if let m = flagsMonitor { NSEvent.removeMonitor(m) }
        if let m = escMonitor { NSEvent.removeMonitor(m) }
        keyDownMonitor = nil
        keyUpMonitor = nil
        flagsMonitor = nil
        escMonitor = nil
    }

    deinit {
        if let m = keyDownMonitor { NSEvent.removeMonitor(m) }
        if let m = keyUpMonitor { NSEvent.removeMonitor(m) }
        if let m = flagsMonitor { NSEvent.removeMonitor(m) }
        if let m = escMonitor { NSEvent.removeMonitor(m) }
    }
}
