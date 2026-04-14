import CoreGraphics
import Foundation

struct MeetingLiveInlineRecordingStatusSummary: Equatable {
    let statusText: String
    let sourceText: String
}

enum MeetingLiveLayout {
    static func dualColumnWidth(containerWidth: CGFloat, spacing: CGFloat) -> CGFloat {
        max(0, (containerWidth - spacing) / 2)
    }

    static func inlineRecordingStatusSummary(
        realtimeStatusMessage: String?,
        audioInputMode: MeetingAudioInputMode,
        systemAudioAvailable: Bool
    ) -> MeetingLiveInlineRecordingStatusSummary? {
        guard let realtimeStatusMessage else { return nil }

        let trimmedStatus = realtimeStatusMessage.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedStatus.isEmpty else { return nil }

        return MeetingLiveInlineRecordingStatusSummary(
            statusText: trimmedStatus,
            sourceText: audioInputMode.effectiveDisplayName(systemAudioAvailable: systemAudioAvailable)
        )
    }
}
