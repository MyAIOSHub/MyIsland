import Foundation
import os.log
#if canImport(EventKit)
import EventKit
#endif

private let calendarLogger = Logger(subsystem: "com.myisland", category: "Calendar")

/// Mirrors NSLog so the message reliably surfaces in Console.app and
/// `log show` (os.Logger info-level is often redacted in field captures).
private func calendarDiag(_ message: String) {
    NSLog("[MyIsland.Calendar] %@", message)
    calendarLogger.info("\(message, privacy: .public)")
}

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
        calendarDiag("sync.begin recordID=\(record.id) topic=\(record.topic) syncEnabled=\(record.calendarSyncEnabled) scheduledAt=\(String(describing: record.scheduledAt))")

        guard record.calendarSyncEnabled else {
            calendarDiag("sync.disabled-by-record")
            return MeetingCalendarSyncResult(
                eventIdentifier: nil,
                state: .disabled,
                errorMessage: nil
            )
        }

        guard let scheduledAt = record.scheduledAt else {
            calendarDiag("sync.no-scheduledAt")
            return MeetingCalendarSyncResult(
                eventIdentifier: record.calendarEventIdentifier,
                state: .failed,
                errorMessage: "预约会议缺少开始时间，无法同步到系统日历。"
            )
        }

        let accessGranted: Bool
        do {
            accessGranted = try await requestEventAccess()
            calendarDiag("requestEventAccess returned granted=\(accessGranted)")
        } catch {
            calendarDiag("requestEventAccess threw error=\(error.localizedDescription)")
            return MeetingCalendarSyncResult(
                eventIdentifier: record.calendarEventIdentifier,
                state: .failed,
                errorMessage: "请求系统日历权限失败：\(error.localizedDescription)"
            )
        }

        guard accessGranted else {
            let statusDesc = Self.describeAuthorizationStatus()
            calendarDiag("sync.access-denied finalStatus=\(statusDesc)")
            return MeetingCalendarSyncResult(
                eventIdentifier: record.calendarEventIdentifier,
                state: .failed,
                errorMessage: "系统日历权限未授予，预约已保存在 My Island。当前授权状态: \(statusDesc)。请到 系统设置 → 隐私与安全 → 日历 中允许 My Island。"
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
        let status = EKEventStore.authorizationStatus(for: .event)
        calendarDiag("requestEventAccess.start authStatus=\(Self.describeAuthorizationStatus())")

        if #available(macOS 14.0, *) {
            switch status {
            case .fullAccess, .writeOnly, .authorized:
                calendarDiag("requestEventAccess.shortcut already-granted")
                return true
            case .denied, .restricted:
                calendarDiag("requestEventAccess.shortcut denied/restricted -> not requesting")
                return false
            case .notDetermined:
                calendarDiag("requestEventAccess.notDetermined -> will request")
            @unknown default:
                calendarDiag("requestEventAccess.unknown-status raw=\(status.rawValue) -> will request")
            }

            do {
                calendarDiag("calling eventStore.requestWriteOnlyAccessToEvents()")
                let granted = try await eventStore.requestWriteOnlyAccessToEvents()
                calendarDiag("requestWriteOnlyAccessToEvents returned granted=\(granted)")
                if granted { return true }
            } catch {
                calendarDiag("requestWriteOnlyAccessToEvents threw \(error.localizedDescription) -> trying full access")
            }
            calendarDiag("calling eventStore.requestFullAccessToEvents()")
            let fullGranted = try await eventStore.requestFullAccessToEvents()
            calendarDiag("requestFullAccessToEvents returned granted=\(fullGranted)")
            return fullGranted
        } else {
            if status == .authorized { return true }
            if status == .denied || status == .restricted { return false }
            return try await withCheckedThrowingContinuation { continuation in
                eventStore.requestAccess(to: .event) { granted, error in
                    if let error {
                        continuation.resume(throwing: error)
                    } else {
                        continuation.resume(returning: granted)
                    }
                }
            }
        }
    }

    nonisolated static func describeAuthorizationStatus() -> String {
        let status = EKEventStore.authorizationStatus(for: .event)
        if #available(macOS 14.0, *) {
            switch status {
            case .notDetermined: return "notDetermined"
            case .restricted:    return "restricted"
            case .denied:        return "denied"
            case .fullAccess:    return "fullAccess"
            case .writeOnly:     return "writeOnly"
            case .authorized:    return "authorized(legacy)"
            @unknown default:    return "unknown(raw=\(status.rawValue))"
            }
        } else {
            switch status {
            case .notDetermined: return "notDetermined"
            case .restricted:    return "restricted"
            case .denied:        return "denied"
            case .authorized:    return "authorized"
            @unknown default:    return "unknown(raw=\(status.rawValue))"
            }
        }
    }
#endif
}
