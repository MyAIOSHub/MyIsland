import Foundation
#if canImport(EventKit)
import EventKit
#endif

struct MeetingCalendarSyncResult: Sendable {
    let eventIdentifier: String?
    let state: MeetingCalendarSyncState
    let errorMessage: String?
}

actor MeetingCalendarService {
    static let shared = MeetingCalendarService()

#if canImport(EventKit)
    private let eventStore = EKEventStore()
#endif

    func sync(record: MeetingRecord) async -> MeetingCalendarSyncResult {
#if canImport(EventKit)
        guard record.calendarSyncEnabled else {
            return MeetingCalendarSyncResult(
                eventIdentifier: nil,
                state: .disabled,
                errorMessage: nil
            )
        }

        guard let scheduledAt = record.scheduledAt else {
            return MeetingCalendarSyncResult(
                eventIdentifier: record.calendarEventIdentifier,
                state: .failed,
                errorMessage: "预约会议缺少开始时间，无法同步到系统日历。"
            )
        }

        let accessGranted: Bool
        do {
            accessGranted = try await requestEventAccess()
        } catch {
            return MeetingCalendarSyncResult(
                eventIdentifier: record.calendarEventIdentifier,
                state: .failed,
                errorMessage: "请求系统日历权限失败：\(error.localizedDescription)"
            )
        }

        guard accessGranted else {
            return MeetingCalendarSyncResult(
                eventIdentifier: record.calendarEventIdentifier,
                state: .failed,
                errorMessage: "系统日历权限未授予，预约已保存在 My Island。"
            )
        }

        guard let calendar = eventStore.defaultCalendarForNewEvents else {
            return MeetingCalendarSyncResult(
                eventIdentifier: record.calendarEventIdentifier,
                state: .failed,
                errorMessage: "没有可用的默认日历，预约已保存在 My Island。"
            )
        }

        let event = record.calendarEventIdentifier
            .flatMap { eventStore.event(withIdentifier: $0) }
            ?? EKEvent(eventStore: eventStore)
        event.calendar = calendar
        event.title = record.topic.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? MeetingRecord.untitledTopicPlaceholder
            : record.topic
        event.startDate = scheduledAt
        event.endDate = scheduledAt.addingTimeInterval(TimeInterval(max(record.durationMinutes, 1) * 60))
        event.notes = "由 My Island 创建的预约会议"

        do {
            try eventStore.save(event, span: .thisEvent, commit: true)
            return MeetingCalendarSyncResult(
                eventIdentifier: event.eventIdentifier,
                state: .synced,
                errorMessage: nil
            )
        } catch {
            return MeetingCalendarSyncResult(
                eventIdentifier: record.calendarEventIdentifier,
                state: .failed,
                errorMessage: "同步系统日历失败：\(error.localizedDescription)"
            )
        }
#else
        return MeetingCalendarSyncResult(
            eventIdentifier: record.calendarEventIdentifier,
            state: .failed,
            errorMessage: "当前环境不支持系统日历同步。"
        )
#endif
    }

    func remove(eventIdentifier: String?) async {
#if canImport(EventKit)
        guard let eventIdentifier else { return }
        let accessGranted = (try? await requestEventAccess()) ?? false
        guard accessGranted, let event = eventStore.event(withIdentifier: eventIdentifier) else { return }
        try? eventStore.remove(event, span: .thisEvent, commit: true)
#else
        _ = eventIdentifier
#endif
    }

#if canImport(EventKit)
    private func requestEventAccess() async throws -> Bool {
        try await withCheckedThrowingContinuation { continuation in
            eventStore.requestAccess(to: .event) { granted, error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: granted)
                }
            }
        }
    }
#endif
}
