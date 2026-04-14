import Foundation

enum MeetingLiveFeedKind: Equatable, Sendable {
    case transcript(TranscriptSegment)
    case advice(MeetingAdviceCard)
    case note(MeetingAnnotation)
}

struct MeetingLiveFeedItem: Identifiable, Equatable, Sendable {
    var id: String
    var sortTimeMs: Int
    var timecode: String
    var kind: MeetingLiveFeedKind
}

enum MeetingLiveTimeline {
    static func resolveLiveAdviceCards(
        activeAdviceCards: [MeetingAdviceCard],
        persistedAdviceCards: [MeetingAdviceCard]
    ) -> [MeetingAdviceCard] {
        let preferred = activeAdviceCards.isEmpty ? persistedAdviceCards : activeAdviceCards
        let fallback = activeAdviceCards.isEmpty ? [] : persistedAdviceCards
        var seen = Set<String>()

        return (preferred + fallback).filter { card in
            seen.insert(card.id).inserted
        }
    }

    static func buildTranscriptItems(meeting: MeetingRecord) -> [MeetingLiveFeedItem] {
        meeting.transcript
            .sorted {
                if $0.startTimeMs == $1.startTimeMs {
                    return $0.endTimeMs < $1.endTimeMs
                }
                return $0.startTimeMs < $1.startTimeMs
            }
            .map { segment in
                MeetingLiveFeedItem(
                    id: segment.id,
                    sortTimeMs: max(0, segment.startTimeMs),
                    timecode: timecode(milliseconds: max(0, segment.startTimeMs)),
                    kind: .transcript(segment)
                )
            }
    }

    static func buildAdviceItemsForLiveColumn(
        meeting: MeetingRecord,
        activeAdviceCards: [MeetingAdviceCard],
        persistedAdviceCards: [MeetingAdviceCard],
        isGeneratingThinking: Bool,
        now: Date = Date()
    ) -> [MeetingLiveFeedItem] {
        let resolvedCards = resolveLiveAdviceCards(
            activeAdviceCards: activeAdviceCards,
            persistedAdviceCards: persistedAdviceCards
        )

        if !resolvedCards.isEmpty {
            return buildAdviceItems(meeting: meeting, adviceCards: resolvedCards)
        }

        guard isGeneratingThinking else {
            return []
        }

        let elapsedMs = max(0, Int(now.timeIntervalSince(meeting.createdAt) * 1_000))
        let placeholder = MeetingAdviceCard(
            id: "thinking-placeholder",
            createdAt: now,
            title: "思考中",
            body: "会议助手正在根据 meeting.md 和最近字幕生成插个嘴...",
            triggerRuleID: "thinking_placeholder",
            source: "ephemeral"
        )

        return [
            MeetingLiveFeedItem(
                id: placeholder.id,
                sortTimeMs: elapsedMs,
                timecode: timecode(milliseconds: elapsedMs),
                kind: .advice(placeholder)
            )
        ]
    }

    static func buildNoteItems(meeting: MeetingRecord) -> [MeetingLiveFeedItem] {
        meeting.noteAnnotations
            .sorted {
                if $0.timecodeMs == $1.timecodeMs {
                    return $0.createdAt < $1.createdAt
                }
                return $0.timecodeMs < $1.timecodeMs
            }
            .map { annotation in
                MeetingLiveFeedItem(
                    id: annotation.id,
                    sortTimeMs: max(0, annotation.timecodeMs),
                    timecode: timecode(milliseconds: max(0, annotation.timecodeMs)),
                    kind: .note(annotation)
                )
            }
    }

    static func buildAdviceItems(meeting: MeetingRecord, adviceCards: [MeetingAdviceCard]) -> [MeetingLiveFeedItem] {
        let transcriptByID = Dictionary(uniqueKeysWithValues: meeting.transcript.map { ($0.id, $0) })

        return adviceCards
            .map { card in
            let anchorTimeMs = anchoredTimeMs(
                for: card,
                transcriptByID: transcriptByID,
                meetingStart: meeting.createdAt
            )

            return MeetingLiveFeedItem(
                id: card.id,
                sortTimeMs: anchorTimeMs,
                    timecode: timecode(milliseconds: anchorTimeMs),
                    kind: .advice(card)
                )
            }
            .sorted { lhs, rhs in
                if lhs.sortTimeMs == rhs.sortTimeMs {
                    return lhs.id < rhs.id
                }
                return lhs.sortTimeMs < rhs.sortTimeMs
            }
    }

    static func buildItems(meeting: MeetingRecord, adviceCards: [MeetingAdviceCard]) -> [MeetingLiveFeedItem] {
        let transcriptItems = buildTranscriptItems(meeting: meeting)
        let adviceItems = buildAdviceItems(meeting: meeting, adviceCards: adviceCards)

        return (transcriptItems + adviceItems).sorted { lhs, rhs in
            if lhs.sortTimeMs == rhs.sortTimeMs {
                switch (lhs.kind, rhs.kind) {
                case (.transcript, .advice):
                    return true
                case (.advice, .transcript):
                    return false
                default:
                    return lhs.id < rhs.id
                }
            }
            return lhs.sortTimeMs < rhs.sortTimeMs
        }
    }

    static func buildSidebarItemsForLiveColumn(
        meeting: MeetingRecord,
        activeAdviceCards: [MeetingAdviceCard],
        persistedAdviceCards: [MeetingAdviceCard],
        isGeneratingThinking: Bool,
        now: Date = Date()
    ) -> [MeetingLiveFeedItem] {
        let adviceItems = buildAdviceItemsForLiveColumn(
            meeting: meeting,
            activeAdviceCards: activeAdviceCards,
            persistedAdviceCards: persistedAdviceCards,
            isGeneratingThinking: isGeneratingThinking,
            now: now
        )
        let noteItems = buildNoteItems(meeting: meeting)

        return (adviceItems + noteItems).sorted { lhs, rhs in
            if lhs.sortTimeMs == rhs.sortTimeMs {
                switch (lhs.kind, rhs.kind) {
                case (.note, .advice):
                    return true
                case (.advice, .note):
                    return false
                default:
                    return lhs.id < rhs.id
                }
            }
            return lhs.sortTimeMs < rhs.sortTimeMs
        }
    }

    static func anchoredTimeMs(
        for card: MeetingAdviceCard,
        transcriptByID: [String: TranscriptSegment],
        meetingStart: Date
    ) -> Int {
        let sourceEndMs = card.sourceSegmentIDs
            .compactMap { transcriptByID[$0]?.endTimeMs }
            .max()

        if let sourceEndMs {
            return max(0, sourceEndMs)
        }

        let elapsed = card.createdAt.timeIntervalSince(meetingStart)
        return max(0, Int(elapsed * 1_000))
    }

    static func timecode(milliseconds: Int) -> String {
        let totalSeconds = max(0, milliseconds / 1_000)
        let hours = totalSeconds / 3_600
        let minutes = (totalSeconds % 3_600) / 60
        let seconds = totalSeconds % 60

        if hours > 0 {
            return String(format: "%02d:%02d:%02d", hours, minutes, seconds)
        }
        return String(format: "%02d:%02d", minutes, seconds)
    }
}
