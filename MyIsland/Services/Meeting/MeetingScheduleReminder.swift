import AppKit
import Foundation
import os.log
import UserNotifications

private let reminderLogger = Logger(subsystem: "com.myisland", category: "ScheduleReminder")
private func reminderDiag(_ message: String) {
    NSLog("[MyIsland.Reminder] %@", message)
    reminderLogger.info("\(message, privacy: .public)")
}

/// In-process scheduler that fires local reminders for upcoming meetings.
///
/// For every meeting whose `state == .scheduled` the reminder enqueues two
/// `Timer` events:
///   • lead-time fire (default 5 minutes before `scheduledAt`)
///   • on-time fire  (at `scheduledAt`)
///
/// Each fire posts a `Notification.Name.meetingReminderFired` so the notch
/// view can expand and surface a "即将开始" card, plays a system sound, and
/// (when authorised) delivers a `UNUserNotification` so the user still sees
/// the prompt when My Island isn't focused or the laptop is locked.
///
/// The scheduler is idempotent: re-registering the same meeting cancels the
/// prior timers first. Past-due reminders (e.g. from a meeting whose time
/// elapsed while the app was closed) are skipped instead of fired immediately
/// — we don't want a flurry of stale alerts on launch.
@MainActor
final class MeetingScheduleReminder {
    static let shared = MeetingScheduleReminder()

    /// Notification posted when a reminder fires. `userInfo`:
    ///   - `meetingID: String`
    ///   - `topic: String`
    ///   - `scheduledAt: Date`
    ///   - `leadTimeSeconds: TimeInterval` (0 means on-time, >0 means
    ///     lead-time)
    static let meetingReminderFiredNotification = Notification.Name(
        "MyIslandMeetingReminderFired"
    )

    /// Lead-time offsets, in seconds. Each meeting fires at every offset that
    /// resolves to a future moment. Tweak in one place if you want to add
    /// "1-minute before" or "15-minute before" reminders later.
    private static let leadTimeOffsetsSeconds: [TimeInterval] = [
        5 * 60,  // 5 minutes before
        0,       // on time
    ]

    /// How long the system notification's body should keep "starts in N min"
    /// language meaningful — anything older than this we treat as "too late
    /// to bother".
    private static let staleReminderToleranceSeconds: TimeInterval = 60

    private struct ScheduledFire {
        let timer: Timer
        let leadTimeSeconds: TimeInterval
    }

    /// Map of meetingID → array of pending `ScheduledFire` for that meeting.
    private var scheduledFires: [String: [ScheduledFire]] = [:]

    private init() {}

    // MARK: - Public API

    /// Request notification authorization at startup. Safe to call repeatedly;
    /// the system caches the answer.
    func requestNotificationAuthorizationIfNeeded() {
        let center = UNUserNotificationCenter.current()
        center.getNotificationSettings { settings in
            switch settings.authorizationStatus {
            case .notDetermined:
                center.requestAuthorization(options: [.alert, .sound, .badge]) { granted, error in
                    if let error {
                        reminderDiag("requestAuthorization error=\(error.localizedDescription)")
                    }
                    reminderDiag("notification authorization granted=\(granted)")
                }
            case .denied:
                reminderDiag("notification authorization denied — system alerts will be skipped")
            case .authorized, .provisional:
                reminderDiag("notification authorization already granted")
            @unknown default:
                break
            }
        }
    }

    /// Cancel any existing reminders for the given meeting and, if it is
    /// still in the `.scheduled` state with a future `scheduledAt`, register
    /// fresh ones at every lead-time offset.
    func register(meeting: MeetingRecord) {
        cancel(meetingID: meeting.id)

        guard meeting.state == .scheduled,
              let scheduledAt = meeting.scheduledAt else {
            return
        }

        let now = Date()
        var fires: [ScheduledFire] = []
        for offset in Self.leadTimeOffsetsSeconds {
            let fireDate = scheduledAt.addingTimeInterval(-offset)
            // Skip past-due fires: don't surprise the user with a reminder
            // for a meeting whose start already elapsed while the app was
            // off, but DO honour reminders that are still within the
            // tolerance window (e.g. "meeting starts in 3 seconds" should
            // still alert).
            if fireDate.timeIntervalSinceNow < -Self.staleReminderToleranceSeconds {
                continue
            }
            let timer = makeTimer(
                fireAt: max(fireDate, now.addingTimeInterval(0.5)),
                meetingID: meeting.id,
                topic: meeting.topic,
                scheduledAt: scheduledAt,
                leadTimeSeconds: offset
            )
            fires.append(ScheduledFire(timer: timer, leadTimeSeconds: offset))
        }

        if !fires.isEmpty {
            scheduledFires[meeting.id] = fires
            reminderDiag("registered meetingID=\(meeting.id) topic=\(meeting.topic) fires=\(fires.count)")
        }
    }

    /// Cancel all pending fires for a single meeting (e.g. user deleted it,
    /// edited the time, or actually started the recording).
    func cancel(meetingID: String) {
        guard let fires = scheduledFires.removeValue(forKey: meetingID) else { return }
        for fire in fires {
            fire.timer.invalidate()
        }
        UNUserNotificationCenter.current().removePendingNotificationRequests(
            withIdentifiers: Self.allNotificationRequestIdentifiers(for: meetingID)
        )
        UNUserNotificationCenter.current().removeDeliveredNotifications(
            withIdentifiers: Self.allNotificationRequestIdentifiers(for: meetingID)
        )
        reminderDiag("cancelled meetingID=\(meetingID)")
    }

    /// Cancel everything and re-register every record currently in
    /// `.scheduled` state. Called once at app launch from
    /// `MeetingCoordinator.bootstrap()` and again whenever the recent
    /// meetings list changes en-masse.
    func reconcile(with meetings: [MeetingRecord]) {
        let scheduled = meetings.filter { $0.state == .scheduled }
        let liveIDs = Set(scheduled.map(\.id))

        // Cancel reminders whose meeting no longer exists (or no longer
        // .scheduled).
        for staleID in scheduledFires.keys where !liveIDs.contains(staleID) {
            cancel(meetingID: staleID)
        }

        // Register / refresh every live scheduled meeting.
        for meeting in scheduled {
            register(meeting: meeting)
        }
    }

    // MARK: - Timer construction

    private func makeTimer(
        fireAt: Date,
        meetingID: String,
        topic: String,
        scheduledAt: Date,
        leadTimeSeconds: TimeInterval
    ) -> Timer {
        let timer = Timer(fire: fireAt, interval: 0, repeats: false) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.fireReminder(
                    meetingID: meetingID,
                    topic: topic,
                    scheduledAt: scheduledAt,
                    leadTimeSeconds: leadTimeSeconds
                )
            }
        }
        // .common mode keeps the timer firing even while the user is dragging
        // a window or interacting with the menu bar.
        RunLoop.main.add(timer, forMode: .common)
        return timer
    }

    private func fireReminder(
        meetingID: String,
        topic: String,
        scheduledAt: Date,
        leadTimeSeconds: TimeInterval
    ) {
        reminderDiag("fire meetingID=\(meetingID) topic=\(topic) leadTime=\(Int(leadTimeSeconds))s")

        // 1) In-process broadcast → notch view picks this up.
        NotificationCenter.default.post(
            name: Self.meetingReminderFiredNotification,
            object: nil,
            userInfo: [
                "meetingID": meetingID,
                "topic": topic,
                "scheduledAt": scheduledAt,
                "leadTimeSeconds": leadTimeSeconds,
            ]
        )

        // 2) System notification (works even when the app is in the
        // background or the menu bar is hidden).
        deliverSystemNotification(
            meetingID: meetingID,
            topic: topic,
            scheduledAt: scheduledAt,
            leadTimeSeconds: leadTimeSeconds
        )

        // 3) Audible cue.
        NSSound(named: NSSound.Name("Glass"))?.play()

        // Drop the fired timer from our bookkeeping so `cancel()` doesn't
        // try to invalidate it again.
        if var remaining = scheduledFires[meetingID] {
            remaining.removeAll { $0.leadTimeSeconds == leadTimeSeconds }
            if remaining.isEmpty {
                scheduledFires.removeValue(forKey: meetingID)
            } else {
                scheduledFires[meetingID] = remaining
            }
        }
    }

    private func deliverSystemNotification(
        meetingID: String,
        topic: String,
        scheduledAt: Date,
        leadTimeSeconds: TimeInterval
    ) {
        let center = UNUserNotificationCenter.current()
        center.getNotificationSettings { settings in
            // .ephemeral is iOS-only; macOS only exposes authorized /
            // provisional / denied / notDetermined.
            guard settings.authorizationStatus == .authorized
                || settings.authorizationStatus == .provisional
            else {
                reminderDiag("system notification skipped — auth status \(settings.authorizationStatus.rawValue)")
                return
            }

            let content = UNMutableNotificationContent()
            let displayTopic = topic.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                ? "未命名会议"
                : topic
            if leadTimeSeconds > 0 {
                let minutes = Int(leadTimeSeconds / 60)
                content.title = "会议即将开始"
                content.body = "「\(displayTopic)」将在 \(minutes) 分钟后开始"
            } else {
                content.title = "会议开始时间到"
                content.body = "「\(displayTopic)」预约时间已到，可以开始录制了"
            }
            content.sound = .default
            content.userInfo = [
                "meetingID": meetingID,
                "leadTimeSeconds": leadTimeSeconds,
            ]

            let identifier = Self.notificationRequestIdentifier(
                meetingID: meetingID,
                leadTimeSeconds: leadTimeSeconds
            )
            let request = UNNotificationRequest(
                identifier: identifier,
                content: content,
                trigger: UNTimeIntervalNotificationTrigger(timeInterval: 0.5, repeats: false)
            )
            center.add(request) { error in
                if let error {
                    reminderDiag("UN add error \(error.localizedDescription)")
                }
            }
        }
    }

    // MARK: - Identifier helpers

    private static func notificationRequestIdentifier(
        meetingID: String,
        leadTimeSeconds: TimeInterval
    ) -> String {
        "MyIsland.MeetingReminder.\(meetingID).lead\(Int(leadTimeSeconds))"
    }

    private static func allNotificationRequestIdentifiers(for meetingID: String) -> [String] {
        leadTimeOffsetsSeconds.map { offset in
            notificationRequestIdentifier(meetingID: meetingID, leadTimeSeconds: offset)
        }
    }
}
