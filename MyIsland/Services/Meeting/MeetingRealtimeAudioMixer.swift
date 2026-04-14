import Foundation

nonisolated enum MeetingRealtimeAudioSource: Hashable, Sendable {
    case microphone
    case system
}

actor MeetingRealtimeAudioMixer {
    private let frameSizeBytes: Int
    private var microphoneBuffer = Data()
    private var systemBuffer = Data()
    private var microphoneBridgeFrame: Data?
    private var systemBridgeFrame: Data?
    private var activeSources: Set<MeetingRealtimeAudioSource> = [.microphone, .system]

    init(frameSizeBytes: Int = 6_400) {
        self.frameSizeBytes = max(frameSizeBytes, 2)
    }

    func append(_ data: Data, source: MeetingRealtimeAudioSource) -> [Data] {
        guard activeSources.contains(source) else { return [] }
        switch source {
        case .microphone:
            microphoneBuffer.append(data)
        case .system:
            systemBuffer.append(data)
        }
        return drainFrames(flushRemainder: false)
    }

    func setActiveSources(_ sources: Set<MeetingRealtimeAudioSource>) {
        activeSources = sources
        if !sources.contains(.microphone) {
            microphoneBuffer.removeAll(keepingCapacity: false)
            microphoneBridgeFrame = nil
        }
        if !sources.contains(.system) {
            systemBuffer.removeAll(keepingCapacity: false)
            systemBridgeFrame = nil
        }
    }

    func flushRemaining() -> [Data] {
        drainFrames(flushRemainder: true)
    }

    private func drainFrames(flushRemainder: Bool) -> [Data] {
        var frames: [Data] = []

        while max(microphoneBuffer.count, systemBuffer.count) >= frameSizeBytes {
            frames.append(makeMixedFrame(size: frameSizeBytes))
        }

        if flushRemainder, max(microphoneBuffer.count, systemBuffer.count) > 0 {
            frames.append(makeMixedFrame(size: max(microphoneBuffer.count, systemBuffer.count)))
        }

        return frames
    }

    private func makeMixedFrame(size: Int) -> Data {
        let paddedSize = ((max(size, 1) + 1) / 2) * 2
        let micChunk = dequeueChunk(from: &microphoneBuffer, bridge: &microphoneBridgeFrame, size: paddedSize)
        let systemChunk = dequeueChunk(from: &systemBuffer, bridge: &systemBridgeFrame, size: paddedSize)
        return mix(microphone: micChunk, system: systemChunk)
    }

    private func dequeueChunk(from buffer: inout Data, bridge: inout Data?, size: Int) -> Data {
        let available = min(size, buffer.count)
        var chunk = Data()
        if available > 0 {
            chunk = Data(buffer.prefix(available))
            buffer.removeFirst(available)
            if chunk.count < size {
                chunk.append(Data(repeating: 0, count: size - chunk.count))
            }
            bridge = chunk
            return chunk
        }

        if let bridged = bridge {
            if bridged.count >= size {
                chunk = Data(bridged.prefix(size))
            } else {
                chunk = bridged
                chunk.append(Data(repeating: 0, count: size - bridged.count))
            }
            bridge = nil
            return chunk
        }

        return Data(repeating: 0, count: size)
    }

    private func mix(microphone: Data, system: Data) -> Data {
        let frameSize = max(microphone.count, system.count)
        var mixed = Data(capacity: frameSize)

        for index in stride(from: 0, to: frameSize, by: 2) {
            let micSample = sample(at: index, in: microphone)
            let systemSample = sample(at: index, in: system)
            let clamped = max(Int32(Int16.min), min(Int32(Int16.max), micSample + systemSample))
            let sample = Int16(clamped).littleEndian
            mixed.append(UInt8(truncatingIfNeeded: sample & 0x00FF))
            mixed.append(UInt8(truncatingIfNeeded: (sample >> 8) & 0x00FF))
        }

        return mixed
    }

    private func sample(at index: Int, in data: Data) -> Int32 {
        guard index + 1 < data.count else { return 0 }
        let low = UInt16(data[index])
        let high = UInt16(data[index + 1]) << 8
        return Int32(Int16(bitPattern: low | high))
    }
}
