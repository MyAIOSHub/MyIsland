import Foundation

enum MeetingArchiveFilter: String, CaseIterable, Identifiable, Sendable {
    case all
    case scheduled
    case recording
    case completed
    case failed

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .all:
            return "全部"
        case .scheduled:
            return "预约"
        case .recording:
            return "进行中"
        case .completed:
            return "历史"
        case .failed:
            return "失败"
        }
    }
}

enum MeetingArchiveInspectorTab: String, CaseIterable, Identifiable, Sendable {
    case chapterSummary
    case notesAndFocus
    case advice
    case qaAndActions

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .chapterSummary:
            return "分段总结"
        case .notesAndFocus:
            return "重点笔记"
        case .advice:
            return "插个嘴"
        case .qaAndActions:
            return "问答待办"
        }
    }
}

struct MeetingArchiveSearchDocument: Equatable, Sendable {
    struct Source: Equatable, Sendable {
        let text: String
        let kind: String
    }

    let recordID: String
    let normalizedQuerySources: [Source]

    init(record: MeetingRecord) {
        var sources: [Source] = []

        for segment in record.transcript {
            let text = segment.text.trimmingCharacters(in: .whitespacesAndNewlines)
            if !text.isEmpty {
                sources.append(Source(text: text, kind: "transcript"))
            }
        }

        for annotation in record.annotations {
            let summary = annotation.summaryText(in: record.transcript).trimmingCharacters(in: .whitespacesAndNewlines)
            if !summary.isEmpty {
                sources.append(Source(text: summary, kind: "annotation"))
            }
        }

        for card in record.adviceCards + record.postMeetingAdviceCards {
            let text = [
                card.title,
                card.body,
                card.coreJudgment,
                card.blindSpot,
                card.nextStep
            ]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: "\n")

            if !text.isEmpty {
                sources.append(Source(text: text, kind: "advice"))
            }
        }

        if let summaryBundle = record.summaryBundle {
            let fullSummary = summaryBundle.fullSummary.trimmingCharacters(in: .whitespacesAndNewlines)
            if !fullSummary.isEmpty {
                sources.append(Source(text: fullSummary, kind: "summary"))
            }

            for chapter in summaryBundle.chapterSummaries {
                let text = "\(chapter.title)\n\(chapter.summary)"
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                if !text.isEmpty {
                    sources.append(Source(text: text, kind: "chapter"))
                }
            }
        }

        let topic = record.topic.trimmingCharacters(in: .whitespacesAndNewlines)
        if !topic.isEmpty {
            sources.append(Source(text: topic, kind: "topic"))
        }

        normalizedQuerySources = sources
        recordID = record.id
    }

    func bestMatchingSnippet(for query: String, radius: Int = 28) -> String? {
        let normalizedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !normalizedQuery.isEmpty else { return nil }

        for source in normalizedQuerySources {
            let lowercase = source.text.lowercased()
            guard let range = lowercase.range(of: normalizedQuery) else { continue }

            let startDistance = lowercase.distance(from: lowercase.startIndex, to: range.lowerBound)
            let endDistance = lowercase.distance(from: lowercase.startIndex, to: range.upperBound)
            let snippetStart = max(0, startDistance - radius)
            let snippetEnd = min(source.text.count, endDistance + radius)
            let startIndex = source.text.index(source.text.startIndex, offsetBy: snippetStart)
            let endIndex = source.text.index(source.text.startIndex, offsetBy: snippetEnd)
            let snippet = String(source.text[startIndex..<endIndex]).trimmingCharacters(in: .whitespacesAndNewlines)
            guard !snippet.isEmpty else { continue }

            let prefix = snippetStart > 0 ? "..." : ""
            let suffix = snippetEnd < source.text.count ? "..." : ""
            return prefix + snippet + suffix
        }

        return nil
    }
}

struct MeetingArchiveListItem: Identifiable, Equatable, Sendable {
    let record: MeetingRecord
    let primaryDate: Date
    let displayTime: String
    let previewText: String
    let durationText: String
    let focusCount: Int
    let noteCount: Int
    let adviceCount: Int
    let hasSummary: Bool

    var id: String { record.id }
}

struct MeetingArchiveGroup: Identifiable, Equatable, Sendable {
    let id: String
    let title: String
    let items: [MeetingArchiveListItem]
}

enum MeetingArchiveIndex {
    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "HH:mm"
        return formatter
    }()

    private static let dayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()

    static func buildListItems(
        meetings: [MeetingRecord],
        filter: MeetingArchiveFilter,
        searchQuery: String
    ) -> [MeetingArchiveListItem] {
        let normalizedQuery = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)

        return meetings
            .filter { matchesFilter($0, filter: filter) }
            .filter { record in
                guard !normalizedQuery.isEmpty else { return true }
                let document = MeetingArchiveSearchDocument(record: record)
                return document.bestMatchingSnippet(for: normalizedQuery) != nil
            }
            .map { record in
                let primaryDate = primaryDate(for: record)
                let searchDocument = MeetingArchiveSearchDocument(record: record)
                let previewText = previewText(for: record, searchQuery: normalizedQuery, searchDocument: searchDocument)

                return MeetingArchiveListItem(
                    record: record,
                    primaryDate: primaryDate,
                    displayTime: timeFormatter.string(from: primaryDate),
                    previewText: previewText,
                    durationText: durationText(for: record),
                    focusCount: record.focusAnnotations.count,
                    noteCount: record.noteAnnotations.count,
                    adviceCount: record.adviceCards.count + record.postMeetingAdviceCards.count,
                    hasSummary: record.summaryBundle?.fullSummary.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
                )
            }
            .sorted { lhs, rhs in
                if lhs.primaryDate == rhs.primaryDate {
                    return lhs.id > rhs.id
                }
                return lhs.primaryDate > rhs.primaryDate
            }
    }

    static func group(
        items: [MeetingArchiveListItem],
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> [MeetingArchiveGroup] {
        let grouped = Dictionary(grouping: items) { item in
            calendar.startOfDay(for: item.primaryDate)
        }

        return grouped.keys.sorted(by: >).map { day in
            MeetingArchiveGroup(
                id: dayFormatter.string(from: day),
                title: groupTitle(for: day, now: now, calendar: calendar),
                items: grouped[day]?.sorted(by: { $0.primaryDate > $1.primaryDate }) ?? []
            )
        }
    }

    static func matchesFilter(_ record: MeetingRecord, filter: MeetingArchiveFilter) -> Bool {
        switch filter {
        case .all:
            return true
        case .scheduled:
            return record.state == .scheduled
        case .recording:
            return record.state == .recording
        case .completed:
            return record.state == .completed || record.state == .processing || record.state == .draft
        case .failed:
            return record.state == .failed
        }
    }

    static func primaryDate(for record: MeetingRecord) -> Date {
        switch record.state {
        case .scheduled:
            return record.scheduledAt ?? record.createdAt
        case .completed, .failed, .processing:
            return record.endedAt ?? record.createdAt
        case .recording, .draft:
            return record.createdAt
        }
    }

    static func durationText(for record: MeetingRecord) -> String {
        if record.state == .scheduled {
            return "\(max(record.durationMinutes, 1)) 分钟"
        }

        if let endedAt = record.endedAt {
            let seconds = max(1, Int(endedAt.timeIntervalSince(record.createdAt)))
            return minutesAndSecondsText(totalSeconds: seconds)
        }

        let transcriptEndMs = record.transcript.map(\.endTimeMs).max() ?? 0
        if transcriptEndMs > 0 {
            return minutesAndSecondsText(totalSeconds: transcriptEndMs / 1_000)
        }

        return "\(max(record.durationMinutes, 1)) 分钟"
    }

    private static func previewText(
        for record: MeetingRecord,
        searchQuery: String,
        searchDocument: MeetingArchiveSearchDocument
    ) -> String {
        if let snippet = searchDocument.bestMatchingSnippet(for: searchQuery) {
            return snippet
        }

        if let summaryBundle = record.summaryBundle {
            let summary = summaryBundle.fullSummary.trimmingCharacters(in: .whitespacesAndNewlines)
            if !summary.isEmpty {
                return summary
            }

            if let chapter = summaryBundle.chapterSummaries.first {
                let text = chapter.summary.trimmingCharacters(in: .whitespacesAndNewlines)
                if !text.isEmpty {
                    return text
                }
            }
        }

        if let finalTranscript = record.transcript.last(where: { $0.isFinal && !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) {
            return finalTranscript.text
        }

        if let transcript = record.transcript.last(where: { !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) {
            return transcript.text
        }

        return "暂无摘要"
    }

    private static func groupTitle(for day: Date, now: Date, calendar: Calendar) -> String {
        if calendar.isDate(day, inSameDayAs: now) {
            return "今天"
        }

        if let yesterday = calendar.date(byAdding: .day, value: -1, to: now),
           calendar.isDate(day, inSameDayAs: yesterday) {
            return "昨天"
        }

        return dayFormatter.string(from: day)
    }

    private static func minutesAndSecondsText(totalSeconds: Int) -> String {
        let seconds = max(0, totalSeconds)
        let hours = seconds / 3_600
        let minutes = (seconds % 3_600) / 60
        let remainder = seconds % 60

        if hours > 0 {
            return "\(hours)小时\(minutes)分"
        }
        if minutes > 0 {
            return remainder == 0 ? "\(minutes) 分钟" : String(format: "%d:%02d", minutes, remainder)
        }
        return "\(remainder) 秒"
    }
}
