import AppKit
import SwiftUI

@MainActor
final class MeetingArchiveWindowController: NSWindowController, NSWindowDelegate {
    let viewModel: MeetingArchiveViewModel

    init(selectedMeetingID: String? = nil) {
        self.viewModel = MeetingArchiveViewModel(selectedMeetingID: selectedMeetingID)

        let initialFrame = NSRect(x: 0, y: 0, width: 1200, height: 820)
        let window = NSWindow(
            contentRect: initialFrame,
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.title = "会议总览"
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.isMovableByWindowBackground = true
        window.minSize = NSSize(width: 960, height: 640)
        window.backgroundColor = .black
        window.collectionBehavior = [.moveToActiveSpace]
        window.isReleasedWhenClosed = false
        window.center()

        super.init(window: window)

        let rootView = MeetingArchiveView(viewModel: viewModel)
        let hostingController = NSHostingController(rootView: rootView)
        window.contentViewController = hostingController
        window.delegate = self

        viewModel.onRequestClose = { [weak window] in
            window?.close()
        }
        viewModel.onRequestMeetingHub = {
            AppDelegate.shared?.showMeetingHub()
        }
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func show(selectedMeetingID: String?) {
        viewModel.focus(meetingID: selectedMeetingID)
        showWindow(nil)
        window?.centerIfNeeded()
        window?.makeKeyAndOrderFront(nil)
        NSApplication.shared.activate(ignoringOtherApps: true)
    }
}

private extension NSWindow {
    func centerIfNeeded() {
        if frame.origin == .zero {
            center()
        }
    }
}
