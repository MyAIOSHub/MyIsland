//
//  ClipboardPasteCoordinator.swift
//  MyIsland
//
//  Shared clipboard restore/paste logic used by clipboard history and voice input.
//

import AppKit

@MainActor
final class ClipboardPasteCoordinator {
    static let shared = ClipboardPasteCoordinator()

    private let pasteboard = NSPasteboard.general

    private init() {}

    func restore(entryId: String) async {
        guard let payload = await ClipboardStore.shared.payload(for: entryId) else { return }
        guard write(payload: payload) else { return }
        try? await ClipboardStore.shared.promote(entryId: entryId)
    }

    func pasteNow(entryId: String) async {
        guard let payload = await ClipboardStore.shared.payload(for: entryId) else { return }
        guard write(payload: payload) else { return }
        try? await ClipboardStore.shared.promote(entryId: entryId)
        await pasteCurrentClipboardToTrackedApp()
    }

    func pasteTextTemporarily(_ text: String, to app: NSRunningApplication?) async {
        let snapshot = clonePasteboardItems()
        guard write(payload: .text(text)) else { return }

        await activate(app ?? FrontmostAppTracker.shared.lastExternalApplication)
        postPasteShortcut()

        try? await Task.sleep(for: .milliseconds(500))
        restorePasteboardItems(snapshot)
    }

    private func write(payload: ClipboardPayload) -> Bool {
        ClipboardMonitor.shared.suppressNextChanges()
        pasteboard.clearContents()

        switch payload {
        case .text(let text):
            return pasteboard.setString(text, forType: .string)

        case .image(let asset):
            guard let image = NSImage(data: asset.pngData) else { return false }
            return pasteboard.writeObjects([image])

        case .files(let files):
            let urls = files.map { $0.url as NSURL }
            return pasteboard.writeObjects(urls)
        }
    }

    private func pasteCurrentClipboardToTrackedApp() async {
        guard AXIsProcessTrusted() else { return }
        let targetApp = FrontmostAppTracker.shared.lastExternalApplication
        await activate(targetApp)
        postPasteShortcut()
    }

    private func activate(_ app: NSRunningApplication?) async {
        guard let app else { return }
        _ = app.activate()
        try? await Task.sleep(for: .milliseconds(200))
    }

    private func postPasteShortcut() {
        guard AXIsProcessTrusted(),
              let source = CGEventSource(stateID: .hidSystemState),
              let keyDown = CGEvent(keyboardEventSource: source, virtualKey: 9, keyDown: true),
              let keyUp = CGEvent(keyboardEventSource: source, virtualKey: 9, keyDown: false) else {
            return
        }

        keyDown.flags = .maskCommand
        keyDown.post(tap: .cghidEventTap)
        keyUp.flags = .maskCommand
        keyUp.post(tap: .cghidEventTap)
    }

    private func clonePasteboardItems() -> [NSPasteboardItem] {
        guard let items = pasteboard.pasteboardItems else { return [] }

        return items.map { item in
            let copy = NSPasteboardItem()
            for type in item.types {
                if let data = item.data(forType: type) {
                    copy.setData(data, forType: type)
                } else if let string = item.string(forType: type) {
                    copy.setString(string, forType: type)
                } else if let propertyList = item.propertyList(forType: type) {
                    copy.setPropertyList(propertyList, forType: type)
                }
            }
            return copy
        }
    }

    private func restorePasteboardItems(_ items: [NSPasteboardItem]) {
        ClipboardMonitor.shared.suppressNextChanges()
        pasteboard.clearContents()
        guard !items.isEmpty else { return }
        _ = pasteboard.writeObjects(items)
    }
}
