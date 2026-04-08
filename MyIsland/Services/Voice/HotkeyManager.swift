import AppKit
import Combine

@MainActor
final class VoiceHotkeyManager: ObservableObject {
    @Published private(set) var isHotkeyPressed: Bool = false
    @Published private(set) var isEscPressed: Bool = false

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
            // Fallback: keyDown/keyUp for Fn keyCode
            flagsMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.keyDown, .keyUp]) { [weak self] event in
                Task { @MainActor in
                    guard let self, event.keyCode == self.hotkeyCode else { return }
                    self.isHotkeyPressed = (event.type == .keyDown)
                }
            }
        }

        // ESC key monitor (keyCode 53)
        escMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            Task { @MainActor in
                guard let self, event.keyCode == 53 else { return }
                self.isEscPressed = true
                self.isEscPressed = false
            }
        }
    }

    func stopListening() {
        if let m = flagsMonitor { NSEvent.removeMonitor(m) }
        if let m = escMonitor { NSEvent.removeMonitor(m) }
        flagsMonitor = nil
        escMonitor = nil
    }

    deinit {
        if let m = flagsMonitor { NSEvent.removeMonitor(m) }
        if let m = escMonitor { NSEvent.removeMonitor(m) }
    }
}
