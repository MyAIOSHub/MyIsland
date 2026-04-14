import Foundation
import XCTest
@testable import My_Island

final class MeetingAudioPipelineTests: XCTestCase {
    func testMixerOutputsFixedSizeMonoFrames() async throws {
        let mixer = MeetingRealtimeAudioMixer(frameSizeBytes: 6400)
        let micChunk = makePCM16(samples: Array(repeating: 1200, count: 3200))

        let frames = await mixer.append(micChunk, source: .microphone)

        XCTAssertEqual(frames.count, 1)
        XCTAssertEqual(frames[0].count, 6400)
        XCTAssertEqual(frames[0], micChunk)
    }

    func testMixerClampsMixedSourcesToPreventOverflow() async throws {
        let mixer = MeetingRealtimeAudioMixer(frameSizeBytes: 6400)
        let micChunk = makePCM16(samples: Array(repeating: 24_000, count: 3200))
        let systemChunk = makePCM16(samples: Array(repeating: 24_000, count: 3200))

        _ = await mixer.append(micChunk, source: .microphone)
        let frames = await mixer.append(systemChunk, source: .system)
        let samples = decodePCM16(try XCTUnwrap(frames.first))

        XCTAssertEqual(frames.count, 1)
        XCTAssertEqual(samples.max(), Int(Int16.max))
    }

    func testMixerBuffersUntilFrameIsCompleteAndFlushesRemainder() async throws {
        let mixer = MeetingRealtimeAudioMixer(frameSizeBytes: 6400)
        let firstHalf = makePCM16(samples: Array(repeating: 1000, count: 1600))
        let secondHalf = makePCM16(samples: Array(repeating: 1000, count: 1600))

        let partial = await mixer.append(firstHalf, source: .microphone)
        XCTAssertTrue(partial.isEmpty)

        let frames = await mixer.append(secondHalf, source: .microphone)
        XCTAssertEqual(frames.count, 1)

        let trailing = await mixer.flushRemaining()
        XCTAssertTrue(trailing.isEmpty)
    }

    func testMixerDropsDisabledSourceFramesAfterInputModeSwitch() async throws {
        let mixer = MeetingRealtimeAudioMixer(frameSizeBytes: 6400)
        let micChunk = makePCM16(samples: Array(repeating: 1200, count: 3200))
        let systemChunk = makePCM16(samples: Array(repeating: 800, count: 3200))

        await mixer.setActiveSources([.system])
        let ignoredMicFrames = await mixer.append(micChunk, source: .microphone)
        XCTAssertTrue(ignoredMicFrames.isEmpty)

        let frames = await mixer.append(systemChunk, source: .system)
        let samples = decodePCM16(try XCTUnwrap(frames.first))

        XCTAssertEqual(frames.count, 1)
        XCTAssertEqual(samples.first, 800)
    }

    func testMixerHandlesSequentialFramesAfterInternalBufferSliceMovesStartIndex() async throws {
        let mixer = MeetingRealtimeAudioMixer(frameSizeBytes: 6400)
        let doubleFrame = makePCM16(samples: Array(repeating: 1200, count: 6400))

        let frames = await mixer.append(doubleFrame, source: .microphone)

        XCTAssertEqual(frames.count, 2)
        XCTAssertEqual(frames[0].count, 6400)
        XCTAssertEqual(frames[1].count, 6400)
        XCTAssertEqual(frames[0], makePCM16(samples: Array(repeating: 1200, count: 3200)))
        XCTAssertEqual(frames[1], makePCM16(samples: Array(repeating: 1200, count: 3200)))
    }

    private func makePCM16(samples: [Int16]) -> Data {
        var data = Data(capacity: samples.count * MemoryLayout<Int16>.size)
        for sample in samples {
            var little = sample.littleEndian
            data.append(Data(bytes: &little, count: MemoryLayout<Int16>.size))
        }
        return data
    }

    private func decodePCM16(_ data: Data) -> [Int] {
        stride(from: 0, to: data.count, by: 2).map { index in
            let value = data[index..<(index + 2)].withUnsafeBytes { rawBuffer in
                rawBuffer.load(as: Int16.self).littleEndian
            }
            return Int(value)
        }
    }
}
