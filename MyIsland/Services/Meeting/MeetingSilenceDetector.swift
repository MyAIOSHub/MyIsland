import Foundation

struct MeetingSilenceDetector: Sendable {
    let silenceDuration: TimeInterval
    let cooldownDuration: TimeInterval
    let energyThreshold: Double

    private var monitoringStartedAt: Date?
    private var lastAudibleAt: Date?
    private var lastTriggerAt: Date?

    init(
        silenceDuration: TimeInterval = 10,
        cooldownDuration: TimeInterval = 120,
        energyThreshold: Double = 0.02
    ) {
        self.silenceDuration = silenceDuration
        self.cooldownDuration = cooldownDuration
        self.energyThreshold = energyThreshold
    }

    mutating func begin(at date: Date) {
        monitoringStartedAt = date
        lastAudibleAt = nil
        lastTriggerAt = nil
    }

    mutating func reset() {
        monitoringStartedAt = nil
        lastAudibleAt = nil
        lastTriggerAt = nil
    }

    mutating func processPCM16(_ data: Data, at date: Date = Date()) -> Bool {
        processEnergyLevel(Self.energyLevel(fromPCM16: data), at: date)
    }

    mutating func processEnergyLevel(_ level: Double, at date: Date) -> Bool {
        if monitoringStartedAt == nil {
            monitoringStartedAt = date
        }

        if level >= energyThreshold {
            lastAudibleAt = date
            return false
        }

        let silenceReference = lastAudibleAt ?? monitoringStartedAt ?? date
        guard date.timeIntervalSince(silenceReference) >= silenceDuration else { return false }

        if let lastTriggerAt, date.timeIntervalSince(lastTriggerAt) < cooldownDuration {
            return false
        }

        lastTriggerAt = date
        return true
    }

    static func energyLevel(fromPCM16 data: Data) -> Double {
        guard data.count >= 2 else { return 0 }
        let sampleCount = data.count / 2
        guard sampleCount > 0 else { return 0 }

        var sumSquares: Double = 0
        data.withUnsafeBytes { rawBuffer in
            let samples = rawBuffer.bindMemory(to: Int16.self)
            for sample in samples {
                let normalized = Double(Int16(littleEndian: sample)) / Double(Int16.max)
                sumSquares += normalized * normalized
            }
        }
        return sqrt(sumSquares / Double(sampleCount))
    }
}
