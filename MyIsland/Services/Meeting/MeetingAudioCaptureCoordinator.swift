@preconcurrency import AVFoundation
import Combine
import Foundation
import ScreenCaptureKit
import os.log

@MainActor
final class MeetingAudioCaptureCoordinator: NSObject, ObservableObject {
    private let logger = Logger(subsystem: "com.myisland", category: "MeetingAudio")
    private let idleAudioLevels: [CGFloat] = Array(repeating: 0.05, count: 9)

    @Published private(set) var isRunning = false
    @Published private(set) var audioLevels: [CGFloat] = Array(repeating: 0.05, count: 9)
    @Published private(set) var systemAudioAvailable = false

    private let micRecorder = VoiceAudioRecorder()
    private let systemCapture = MeetingSystemAudioCapture()
    private let writer = MeetingWaveFileWriter()
    private let realtimeMixer = MeetingRealtimeAudioMixer()
    private var currentInputMode: MeetingAudioInputMode = .microphoneAndSystem

    var onMixedPCMChunk: ((Data) -> Void)?

    override init() {
        super.init()
        micRecorder.collectBuffers = false
        systemCapture.onBuffer = { [weak self] buffer in
            Task { [weak self] in
                await self?.handleSystemBuffer(buffer)
            }
        }
    }

    func startCapture(
        rawPCMURL: URL,
        transcriptLogURL: URL,
        inputMode: MeetingAudioInputMode
    ) async throws -> MeetingAudioInputMode {
        guard !isRunning else { return inputMode }

        try await writer.start(rawPCMURL: rawPCMURL)
        let logCreated = FileManager.default.createFile(atPath: transcriptLogURL.path, contents: Data())
        if !logCreated {
            logger.warning("Failed to create transcript log at \(transcriptLogURL.path, privacy: .public)")
        }

        micRecorder.onBuffer = { [weak self] buffer in
            Task { @MainActor [weak self] in
                await self?.handleMicBuffer(buffer)
            }
        }
        isRunning = true
        currentInputMode = inputMode
        return try await applyInputMode(inputMode)
    }

    func stopCapture(finalWAVURL: URL) async throws {
        guard isRunning else { return }
        micRecorder.stopRecording()
        micRecorder.onBuffer = nil
        await systemCapture.stop()

        let trailingFrames = await realtimeMixer.flushRemaining()
        for frame in trailingFrames {
            await writer.appendPCM16(frame)
            onMixedPCMChunk?(frame)
        }

        try await writer.finalize(wavURL: finalWAVURL)
        audioLevels = idleAudioLevels
        systemAudioAvailable = false
        isRunning = false
        currentInputMode = .microphoneAndSystem
        await realtimeMixer.setActiveSources([.microphone, .system])
    }

    func updateInputMode(_ inputMode: MeetingAudioInputMode) async -> MeetingAudioInputMode {
        (try? await applyInputMode(inputMode)) ?? .microphoneOnly
    }

    private func handleMicBuffer(_ buffer: AVAudioPCMBuffer) async {
        audioLevels = micRecorder.audioLevels
        guard let pcmData = MeetingPCMConverter.convertToPCM16MonoData(buffer) else { return }
        let frames = await realtimeMixer.append(pcmData, source: .microphone)
        for frame in frames {
            await writer.appendPCM16(frame)
            onMixedPCMChunk?(frame)
        }
    }

    private func handleSystemBuffer(_ buffer: AVAudioPCMBuffer) async {
        guard let pcmData = MeetingPCMConverter.convertToPCM16MonoData(buffer) else { return }
        let frames = await realtimeMixer.append(pcmData, source: .system)
        for frame in frames {
            await writer.appendPCM16(frame)
            onMixedPCMChunk?(frame)
        }
    }

    private func applyInputMode(_ inputMode: MeetingAudioInputMode) async throws -> MeetingAudioInputMode {
        var effectiveMode = inputMode

        if inputMode.requiresSystemAudio {
            do {
                try await systemCapture.start()
                systemAudioAvailable = true
            } catch {
                logger.warning("System audio capture unavailable: \(error.localizedDescription, privacy: .public)")
                systemAudioAvailable = false
                effectiveMode = .microphoneOnly
            }
        } else {
            await systemCapture.stop()
            systemAudioAvailable = false
        }

        if effectiveMode.requiresMicrophone {
            if !micRecorder.isRecording {
                try micRecorder.startRecording()
            }
            audioLevels = micRecorder.audioLevels
        } else {
            micRecorder.stopRecording()
            audioLevels = idleAudioLevels
        }

        currentInputMode = effectiveMode
        await realtimeMixer.setActiveSources(activeSources(for: effectiveMode))
        return effectiveMode
    }

    private func activeSources(for inputMode: MeetingAudioInputMode) -> Set<MeetingRealtimeAudioSource> {
        var sources: Set<MeetingRealtimeAudioSource> = []
        if inputMode.requiresMicrophone {
            sources.insert(.microphone)
        }
        if inputMode.requiresSystemAudio {
            sources.insert(.system)
        }
        return sources
    }
}

final class MeetingSystemAudioCapture: NSObject, SCStreamOutput, SCStreamDelegate {
    nonisolated(unsafe) var onBuffer: ((AVAudioPCMBuffer) -> Void)?

    private let sampleQueue = DispatchQueue(label: "com.myisland.meeting.systemaudio", qos: .userInitiated)
    private var stream: SCStream?

    func start() async throws {
        guard stream == nil else { return }
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        guard let display = content.displays.first else {
            throw NSError(domain: "MeetingSystemAudioCapture", code: 1, userInfo: [NSLocalizedDescriptionKey: "No display available for system audio capture"])
        }

        let filter = SCContentFilter(display: display, excludingWindows: [])
        let configuration = SCStreamConfiguration()
        configuration.capturesAudio = true
        configuration.excludesCurrentProcessAudio = true
        configuration.sampleRate = 16000
        configuration.channelCount = 2

        let stream = SCStream(filter: filter, configuration: configuration, delegate: self)
        try stream.addStreamOutput(self, type: .audio, sampleHandlerQueue: sampleQueue)
        try await stream.startCapture()
        self.stream = stream
    }

    func stop() async {
        guard let stream else { return }
        try? await stream.stopCapture()
        self.stream = nil
    }

    nonisolated func stream(_ stream: SCStream, didStopWithError error: any Error) {
        // Best-effort capture; failures are handled by the coordinator.
    }

    nonisolated func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of outputType: SCStreamOutputType) {
        guard outputType == .audio,
              let pcmBuffer = sampleBuffer.makePCMBuffer() else {
            return
        }
        onBuffer?(pcmBuffer)
    }
}

actor MeetingWaveFileWriter {
    private var rawPCMURL: URL?
    private var handle: FileHandle?
    private var totalBytesWritten: Int = 0

    func start(rawPCMURL: URL) async throws {
        self.rawPCMURL = rawPCMURL
        FileManager.default.createFile(atPath: rawPCMURL.path, contents: Data())
        handle = try FileHandle(forWritingTo: rawPCMURL)
        totalBytesWritten = 0
    }

    func appendPCM16(_ data: Data) {
        guard let handle else { return }
        try? handle.write(contentsOf: data)
        totalBytesWritten += data.count
    }

    func finalize(wavURL: URL) async throws {
        try handle?.close()
        handle = nil

        guard let rawPCMURL else { return }
        let pcmData = try Data(contentsOf: rawPCMURL)
        let wavData = MeetingPCMConverter.wrapPCM16AsWAV(pcmData, sampleRate: 16000, channels: 1)
        try wavData.write(to: wavURL, options: [.atomic])
        try? FileManager.default.removeItem(at: rawPCMURL)
        self.rawPCMURL = nil
        totalBytesWritten = 0
    }
}

enum MeetingPCMConverter {
    nonisolated static let targetFormat = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 16000, channels: 1, interleaved: false)!

    nonisolated static func convertToPCM16MonoData(_ buffer: AVAudioPCMBuffer) -> Data? {
        let sourceFormat = buffer.format
        guard let converter = AVAudioConverter(from: sourceFormat, to: targetFormat) else {
            return nil
        }

        let ratio = targetFormat.sampleRate / sourceFormat.sampleRate
        let expectedFrames = AVAudioFrameCount((Double(buffer.frameLength) * ratio).rounded(.up)) + 32
        guard let converted = AVAudioPCMBuffer(pcmFormat: targetFormat, frameCapacity: max(expectedFrames, 64)) else {
            return nil
        }

        var error: NSError?
        let status = converter.convert(to: converted, error: &error) { _, outStatus in
            outStatus.pointee = .haveData
            return buffer
        }
        guard status != .error, error == nil, converted.frameLength > 0 else {
            return nil
        }

        guard let channelData = converted.floatChannelData?[0] else {
            return nil
        }

        var pcmData = Data(capacity: Int(converted.frameLength) * MemoryLayout<Int16>.size)
        for index in 0..<Int(converted.frameLength) {
            let sample = max(-1.0, min(1.0, channelData[index]))
            var int16 = Int16(sample * Float(Int16.max)).littleEndian
            pcmData.append(Data(bytes: &int16, count: MemoryLayout<Int16>.size))
        }
        return pcmData
    }

    nonisolated static func wrapPCM16AsWAV(_ pcmData: Data, sampleRate: Int, channels: Int) -> Data {
        let bitsPerSample: UInt16 = 16
        let bytesPerSample = Int(bitsPerSample / 8)
        let dataSize = pcmData.count
        let byteRate = UInt32(sampleRate * channels * bytesPerSample)
        let blockAlign = UInt16(channels * bytesPerSample)

        var wavData = Data()
        wavData.append("RIFF".data(using: .utf8)!)
        var riffChunkSize = UInt32(36 + dataSize).littleEndian
        wavData.append(Data(bytes: &riffChunkSize, count: 4))
        wavData.append("WAVE".data(using: .utf8)!)
        wavData.append("fmt ".data(using: .utf8)!)
        var fmtChunkSize = UInt32(16).littleEndian
        wavData.append(Data(bytes: &fmtChunkSize, count: 4))
        var audioFormat = UInt16(1).littleEndian
        wavData.append(Data(bytes: &audioFormat, count: 2))
        var numChannels = UInt16(channels).littleEndian
        wavData.append(Data(bytes: &numChannels, count: 2))
        var sampleRateLE = UInt32(sampleRate).littleEndian
        wavData.append(Data(bytes: &sampleRateLE, count: 4))
        var byteRateLE = byteRate.littleEndian
        wavData.append(Data(bytes: &byteRateLE, count: 4))
        var blockAlignLE = blockAlign.littleEndian
        wavData.append(Data(bytes: &blockAlignLE, count: 2))
        var bitsPerSampleLE = bitsPerSample.littleEndian
        wavData.append(Data(bytes: &bitsPerSampleLE, count: 2))
        wavData.append("data".data(using: .utf8)!)
        var dataSizeLE = UInt32(dataSize).littleEndian
        wavData.append(Data(bytes: &dataSizeLE, count: 4))
        wavData.append(pcmData)
        return wavData
    }
}

private extension CMSampleBuffer {
    nonisolated func makePCMBuffer() -> AVAudioPCMBuffer? {
        guard let formatDescription = CMSampleBufferGetFormatDescription(self),
              let streamBasicDescription = CMAudioFormatDescriptionGetStreamBasicDescription(formatDescription) else {
            return nil
        }

        let asbd = streamBasicDescription.pointee
        guard let format = AVAudioFormat(streamDescription: streamBasicDescription) else {
            return nil
        }

        let frameLength = CMSampleBufferGetNumSamples(self)
        guard let pcmBuffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(frameLength)) else {
            return nil
        }
        pcmBuffer.frameLength = pcmBuffer.frameCapacity

        let bufferListSize = MemoryLayout<AudioBufferList>.size + MemoryLayout<AudioBuffer>.size * Int(asbd.mChannelsPerFrame)
        let audioBufferListPointer = UnsafeMutablePointer<AudioBufferList>.allocate(capacity: 1)
        defer { audioBufferListPointer.deallocate() }

        var blockBuffer: CMBlockBuffer?
        let status = CMSampleBufferGetAudioBufferListWithRetainedBlockBuffer(
            self,
            bufferListSizeNeededOut: nil,
            bufferListOut: audioBufferListPointer,
            bufferListSize: bufferListSize,
            blockBufferAllocator: kCFAllocatorDefault,
            blockBufferMemoryAllocator: kCFAllocatorDefault,
            flags: kCMSampleBufferFlag_AudioBufferList_Assure16ByteAlignment,
            blockBufferOut: &blockBuffer
        )

        guard status == noErr else { return nil }

        let sourceBuffers = UnsafeMutableAudioBufferListPointer(audioBufferListPointer)

        if let floatChannelData = pcmBuffer.floatChannelData {
            for channel in 0..<Int(format.channelCount) {
                let source = sourceBuffers[min(channel, sourceBuffers.count - 1)]
                let sampleCount = min(Int(frameLength), Int(source.mDataByteSize) / MemoryLayout<Float>.size)
                memcpy(floatChannelData[channel], source.mData, sampleCount * MemoryLayout<Float>.size)
            }
            return pcmBuffer
        }

        if let int16ChannelData = pcmBuffer.int16ChannelData {
            for channel in 0..<Int(format.channelCount) {
                let source = sourceBuffers[min(channel, sourceBuffers.count - 1)]
                let sampleCount = min(Int(frameLength), Int(source.mDataByteSize) / MemoryLayout<Int16>.size)
                memcpy(int16ChannelData[channel], source.mData, sampleCount * MemoryLayout<Int16>.size)
            }
            return pcmBuffer
        }

        return nil
    }
}
