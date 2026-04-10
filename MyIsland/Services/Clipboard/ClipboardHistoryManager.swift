//
//  ClipboardHistoryManager.swift
//  MyIsland
//
//  MainActor wrapper for clipboard history UI binding and actions.
//

import Combine
import Foundation

@MainActor
final class ClipboardHistoryManager: ObservableObject {
    static let shared = ClipboardHistoryManager()

    @Published private(set) var entries: [ClipboardEntry] = []

    private var cancellables = Set<AnyCancellable>()

    private init() {
        ClipboardStore.shared.entriesPublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] entries in
                self?.entries = entries
            }
            .store(in: &cancellables)
    }

    func start() {
        Task {
            await ClipboardStore.shared.start()
        }
    }

    func recentEntries(limit: Int) -> [ClipboardEntry] {
        Array(entries.prefix(limit))
    }

    func restore(entryId: String) {
        Task { @MainActor in
            await ClipboardPasteCoordinator.shared.restore(entryId: entryId)
        }
    }

    func pasteNow(entryId: String) {
        Task { @MainActor in
            await ClipboardPasteCoordinator.shared.pasteNow(entryId: entryId)
        }
    }

    func delete(entryId: String) {
        Task {
            try? await ClipboardStore.shared.delete(entryId: entryId)
        }
    }

    func clearAll() {
        Task {
            try? await ClipboardStore.shared.clearAll()
        }
    }
}
