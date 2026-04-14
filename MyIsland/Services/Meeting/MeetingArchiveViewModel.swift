import AppKit
import Combine
import Foundation

@MainActor
final class MeetingArchiveViewModel: ObservableObject {
    @Published var selectedMeetingID: String?
    @Published var searchQuery: String = "" {
        didSet {
            rebuildDerivedState()
        }
    }
    @Published var activeFilter: MeetingArchiveFilter = .all {
        didSet {
            rebuildDerivedState()
        }
    }
    @Published var activeInspectorTab: MeetingArchiveInspectorTab = .chapterSummary
    @Published private(set) var groupedMeetings: [MeetingArchiveGroup] = []
    @Published private(set) var listItems: [MeetingArchiveListItem] = []
    @Published private(set) var selectedListItem: MeetingArchiveListItem?

    private let coordinator: MeetingCoordinator
    private var mergedMeetings: [MeetingRecord] = []
    private var cancellables = Set<AnyCancellable>()

    var onRequestClose: (() -> Void)?
    var onRequestMeetingHub: (() -> Void)?

    init(
        coordinator: MeetingCoordinator? = nil,
        selectedMeetingID: String? = nil
    ) {
        self.coordinator = coordinator ?? MeetingCoordinator.shared
        self.selectedMeetingID = selectedMeetingID
        bindCoordinator()
    }

    var selectedMeeting: MeetingRecord? {
        selectedListItem?.record
    }

    func focus(meetingID: String?) {
        if let meetingID {
            selectedMeetingID = meetingID
        }
        rebuildDerivedState()
    }

    func closeWindow() {
        onRequestClose?()
    }

    func openMeetingHub() {
        onRequestMeetingHub?()
    }

    func copySummary(for record: MeetingRecord) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(summaryText(for: record), forType: .string)
    }

    func openMarkdown(for record: MeetingRecord) {
        guard let markdownRelativePath = record.markdownRelativePath else { return }
        let url = MeetingStorage.shared.absolutePath(for: markdownRelativePath)
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        NSWorkspace.shared.open(url)
    }

    func revealMeetingFiles(for record: MeetingRecord) {
        if let sourceMediaRelativePath = record.sourceMediaRelativePath {
            let sourceMediaURL = MeetingStorage.shared.absolutePath(for: sourceMediaRelativePath)
            if FileManager.default.fileExists(atPath: sourceMediaURL.path) {
                NSWorkspace.shared.activateFileViewerSelecting([sourceMediaURL])
                return
            }
        }

        if let markdownRelativePath = record.markdownRelativePath {
            let markdownURL = MeetingStorage.shared.absolutePath(for: markdownRelativePath)
            if FileManager.default.fileExists(atPath: markdownURL.path) {
                NSWorkspace.shared.activateFileViewerSelecting([markdownURL])
                return
            }
        }

        if let audioRelativePath = record.audioRelativePath {
            let audioURL = MeetingStorage.shared.absolutePath(for: audioRelativePath)
            if FileManager.default.fileExists(atPath: audioURL.path) {
                NSWorkspace.shared.activateFileViewerSelecting([audioURL])
                return
            }
        }

        Task {
            guard let directoryURL = try? await MeetingStorage.shared.meetingDirectory(meetingID: record.id) else { return }
            NSWorkspace.shared.activateFileViewerSelecting([directoryURL])
        }
    }

    func retrySummary(for record: MeetingRecord) {
        Task {
            await coordinator.retryPostAnalysis(meetingID: record.id)
        }
    }

    func refreshMeetings() {
        Task {
            await coordinator.reloadMeetings()
        }
    }

    func summaryText(for record: MeetingRecord) -> String {
        if let summary = record.summaryBundle?.fullSummary.trimmingCharacters(in: .whitespacesAndNewlines),
           !summary.isEmpty {
            return summary
        }

        if let chapter = record.summaryBundle?.chapterSummaries.first {
            let chapterSummary = chapter.summary.trimmingCharacters(in: .whitespacesAndNewlines)
            if !chapterSummary.isEmpty {
                return chapterSummary
            }
        }

        if let note = record.noteAnnotations.first?.summaryText(in: record.transcript).trimmingCharacters(in: .whitespacesAndNewlines),
           !note.isEmpty {
            return note
        }

        if let transcript = record.transcript.last(where: { !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) {
            return transcript.text
        }

        return "暂无摘要"
    }

    private func bindCoordinator() {
        coordinator.$recentMeetings
            .combineLatest(coordinator.$activeMeeting)
            .sink { [weak self] recentMeetings, activeMeeting in
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    mergedMeetings = Self.mergeMeetings(
                        recentMeetings: recentMeetings,
                        activeMeeting: activeMeeting
                    )
                    rebuildDerivedState()
                }
            }
            .store(in: &cancellables)
    }

    private func rebuildDerivedState() {
        let items = MeetingArchiveIndex.buildListItems(
            meetings: mergedMeetings,
            filter: activeFilter,
            searchQuery: searchQuery
        )

        listItems = items
        groupedMeetings = MeetingArchiveIndex.group(items: items)

        if let selectedMeetingID,
           let selected = items.first(where: { $0.id == selectedMeetingID }) {
            selectedListItem = selected
            return
        }

        selectedListItem = items.first
        self.selectedMeetingID = selectedListItem?.id
    }

    private static func mergeMeetings(
        recentMeetings: [MeetingRecord],
        activeMeeting: MeetingRecord?
    ) -> [MeetingRecord] {
        var merged = recentMeetings

        if let activeMeeting {
            if let existingIndex = merged.firstIndex(where: { $0.id == activeMeeting.id }) {
                merged[existingIndex] = activeMeeting
            } else {
                merged.insert(activeMeeting, at: 0)
            }
        }

        return merged
    }
}
