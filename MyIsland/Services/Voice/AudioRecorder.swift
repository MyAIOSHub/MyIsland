import AVFoundation
import Combine

@MainActor
final class VoiceAudioRecorder: ObservableObject {
    @Published private(set) var audioLevels: [CGFloat] = Array(repeating: 0.05, count: 9)
    @Published private(set) var isRecording: Bool = false

    private let audioEngine = AVAudioEngine()
    private var recordedBuffers: [AVAudioPCMBuffer] = []
    private var recordingFormat: AVAudioFormat?

    var onBuffer: ((AVAudioPCMBuffer) -> Void)?

    /// Whether to collect audio buffers for later retrieval (non-fast ASR modes)
    var collectBuffers: Bool = false

    func startRecording() throws {
        guard !isRecording else { return }

        recordedBuffers.removeAll()
        let inputNode = audioEngine.inputNode
        let format = inputNode.outputFormat(forBus: 0)
        recordingFormat = format

        inputNode.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buffer, _ in
            self?.onBuffer?(buffer)
            self?.processAudioLevels(buffer: buffer)
            if self?.collectBuffers == true {
                // Deep copy the buffer for later use
                if let copy = AVAudioPCMBuffer(pcmFormat: buffer.format, frameCapacity: buffer.frameLength) {
                    copy.frameLength = buffer.frameLength
                    if let src = buffer.floatChannelData, let dst = copy.floatChannelData {
                        for ch in 0..<Int(buffer.format.channelCount) {
                            memcpy(dst[ch], src[ch], Int(buffer.frameLength) * MemoryLayout<Float>.size)
                        }
                    }
                    self?.recordedBuffers.append(copy)
                }
            }
        }

        audioEngine.prepare()
        try audioEngine.start()
        isRecording = true
    }

    func stopRecording() {
        guard isRecording else { return }
        audioEngine.inputNode.removeTap(onBus: 0)
        audioEngine.stop()
        isRecording = false
        audioLevels = Array(repeating: 0.05, count: 9)
    }

    /// Get the recorded audio as WAV data (for sending to cloud ASR)
    func getRecordedWAVData() -> Data? {
        guard let format = recordingFormat, !recordedBuffers.isEmpty else { return nil }

        // Calculate total frame count
        let totalFrames = recordedBuffers.reduce(0) { $0 + Int($1.frameLength) }
        guard totalFrames > 0 else { return nil }

        // Create a combined buffer
        guard let combined = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(totalFrames)) else { return nil }
        combined.frameLength = AVAudioFrameCount(totalFrames)

        var offset: AVAudioFrameCount = 0
        for buf in recordedBuffers {
            if let src = buf.floatChannelData, let dst = combined.floatChannelData {
                for ch in 0..<Int(format.channelCount) {
                    memcpy(dst[ch].advanced(by: Int(offset)), src[ch], Int(buf.frameLength) * MemoryLayout<Float>.size)
                }
            }
            offset += buf.frameLength
        }

        // Convert to 16-bit PCM WAV
        let sampleRate = format.sampleRate
        let channels = UInt16(format.channelCount)
        let bitsPerSample: UInt16 = 16
        let bytesPerSample = bitsPerSample / 8
        let dataSize = totalFrames * Int(channels) * Int(bytesPerSample)

        var wavData = Data()

        // WAV header
        wavData.append(contentsOf: Array("RIFF".utf8))
        wavData.append(contentsOf: withUnsafeBytes(of: UInt32(36 + dataSize).littleEndian) { Array($0) })
        wavData.append(contentsOf: Array("WAVE".utf8))
        wavData.append(contentsOf: Array("fmt ".utf8))
        wavData.append(contentsOf: withUnsafeBytes(of: UInt32(16).littleEndian) { Array($0) })
        wavData.append(contentsOf: withUnsafeBytes(of: UInt16(1).littleEndian) { Array($0) }) // PCM
        wavData.append(contentsOf: withUnsafeBytes(of: channels.littleEndian) { Array($0) })
        wavData.append(contentsOf: withUnsafeBytes(of: UInt32(sampleRate).littleEndian) { Array($0) })
        let byteRate = UInt32(sampleRate) * UInt32(channels) * UInt32(bytesPerSample)
        wavData.append(contentsOf: withUnsafeBytes(of: byteRate.littleEndian) { Array($0) })
        let blockAlign = channels * bytesPerSample
        wavData.append(contentsOf: withUnsafeBytes(of: blockAlign.littleEndian) { Array($0) })
        wavData.append(contentsOf: withUnsafeBytes(of: bitsPerSample.littleEndian) { Array($0) })
        wavData.append(contentsOf: Array("data".utf8))
        wavData.append(contentsOf: withUnsafeBytes(of: UInt32(dataSize).littleEndian) { Array($0) })

        // Convert float samples to 16-bit PCM
        if let floatData = combined.floatChannelData {
            for frame in 0..<totalFrames {
                for ch in 0..<Int(channels) {
                    let sample = floatData[ch][frame]
                    let clamped = max(-1.0, min(1.0, sample))
                    let int16 = Int16(clamped * Float(Int16.max))
                    wavData.append(contentsOf: withUnsafeBytes(of: int16.littleEndian) { Array($0) })
                }
            }
        }

        return wavData
    }

    /// Clear collected buffers
    func clearBuffers() {
        recordedBuffers.removeAll()
    }

    var inputFormat: AVAudioFormat {
        audioEngine.inputNode.outputFormat(forBus: 0)
    }

    private let noiseGate: Float = 0.02

    private func processAudioLevels(buffer: AVAudioPCMBuffer) {
        guard let channelData = buffer.floatChannelData?[0] else { return }
        let frameLength = Int(buffer.frameLength)
        let barCount = 9

        var levels: [CGFloat] = []
        let segmentSize = max(1, frameLength / barCount)

        for i in 0..<barCount {
            let start = i * segmentSize
            let end = min(start + segmentSize, frameLength)
            var sumOfSquares: Float = 0
            for j in start..<end {
                let sample = channelData[j]
                sumOfSquares += sample * sample
            }
            let rms = sqrt(sumOfSquares / Float(max(1, end - start)))
            // Noise gate: filter out background noise
            let gated = rms > noiseGate ? (rms - noiseGate) / (1.0 - noiseGate) : 0
            // Power curve (0.6 exponent): make low volumes more visible
            let normalized = CGFloat(min(1.0, pow(gated * 8.0, 0.6)))
            levels.append(max(0.05, normalized))
        }

        Task { @MainActor [levels] in
            self.audioLevels = levels
        }
    }
}
