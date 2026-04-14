import Foundation
import XCTest
@testable import My_Island

final class DoubaoStreamingProtocolTests: XCTestCase {
    func testBuildWebSocketRequestUsesOfficialV3Headers() throws {
        let config = DoubaoStreamingConfig(
            endpoint: "wss://openspeech.bytedance.com/api/v3/sauc/bigmodel_async",
            appID: "8281193462",
            accessToken: "token-value",
            resourceID: "volc.bigasr.sauc.concurrent",
            userID: "user-1",
            language: nil
        )

        let request = try DoubaoStreamingProtocol.makeWebSocketRequest(
            config: config,
            connectID: "connect-123"
        )

        XCTAssertEqual(request.value(forHTTPHeaderField: "X-Api-App-Key"), "8281193462")
        XCTAssertEqual(request.value(forHTTPHeaderField: "X-Api-Access-Key"), "token-value")
        XCTAssertEqual(request.value(forHTTPHeaderField: "X-Api-Resource-Id"), "volc.bigasr.sauc.concurrent")
        XCTAssertEqual(request.value(forHTTPHeaderField: "X-Api-Connect-Id"), "connect-123")
    }

    func testBuildFullRequestPacketCompressesPayloadAndIncludesCapabilities() throws {
        let config = DoubaoStreamingConfig(
            endpoint: "wss://openspeech.bytedance.com/api/v3/sauc/bigmodel_async",
            appID: "8281193462",
            accessToken: "token-value",
            resourceID: "volc.bigasr.sauc.concurrent",
            userID: "user-1",
            language: nil
        )

        let packet = try DoubaoStreamingProtocol.buildFullRequestPacket(config: config)
        let envelope = try XCTUnwrap(DoubaoStreamingProtocol.inspectPacket(packet))
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: envelope.payload) as? [String: Any])
        let request = try XCTUnwrap(json["request"] as? [String: Any])

        XCTAssertEqual(envelope.messageType, .fullClientRequest)
        XCTAssertEqual(envelope.compression, .gzip)
        XCTAssertEqual((json["audio"] as? [String: Any])?["format"] as? String, "pcm")
        XCTAssertEqual((json["audio"] as? [String: Any])?["codec"] as? String, "raw")
        XCTAssertEqual((json["audio"] as? [String: Any])?["rate"] as? Int, 16000)
        XCTAssertEqual(request["model_name"] as? String, "bigmodel")
        XCTAssertEqual(request["result_type"] as? String, "single")
        XCTAssertEqual(request["enable_nonstream"] as? Bool, true)
        XCTAssertEqual(request["show_utterances"] as? Bool, true)
        XCTAssertEqual(request["enable_speaker_info"] as? Bool, true)
        XCTAssertEqual(request["show_speech_rate"] as? Bool, true)
        XCTAssertEqual(request["show_volume"] as? Bool, true)
        XCTAssertEqual(request["enable_emotion_detection"] as? Bool, true)
        XCTAssertEqual(request["ssd_version"] as? String, "200")
    }

    func testBuildAudioPacketCompressesPCMWithoutSequenceField() throws {
        let pcm = Data(repeating: 0x7F, count: 6400)

        let packet = try DoubaoStreamingProtocol.buildAudioPacket(payload: pcm, isLast: false)
        let envelope = try XCTUnwrap(DoubaoStreamingProtocol.inspectPacket(packet))

        XCTAssertEqual(envelope.messageType, .audioOnlyRequest)
        XCTAssertEqual(envelope.flags, 0)
        XCTAssertNil(envelope.sequence)
        XCTAssertEqual(envelope.compression, .gzip)
        XCTAssertEqual(envelope.payload, pcm)
    }

    func testParseServerPacketDecompressesFullResponseAndExtractsSegments() throws {
        let payload: [String: Any] = [
            "result": [
                "text": "先定义问题。",
                "utterances": [[
                    "text": "先定义问题。",
                    "start_time": 120,
                    "end_time": 920,
                    "definite": true,
                    "speaker": "speaker_1",
                    "additions": [
                        "speech_rate": 1.5,
                        "volume": 0.4,
                        "emotion": "neutral"
                    ]
                ]]
            ]
        ]
        let packet = try makeFullServerResponsePacket(payload: payload, sequence: 1)

        let segments = DoubaoStreamingASRClient.parseSegments(fromPacket: packet)

        XCTAssertEqual(segments.count, 1)
        XCTAssertEqual(segments[0].speakerLabel, "speaker_1")
        XCTAssertEqual(segments[0].emotion, "neutral")
        XCTAssertEqual(segments[0].startTimeMs, 120)
        XCTAssertEqual(segments[0].endTimeMs, 920)
    }

    func testParseServerPacketReturnsStructuredError() throws {
        let packet = try makeErrorPacket(
            code: 45000001,
            message: "{\"code\":45000001,\"message\":\"bad request\"}"
        )

        let error = try XCTUnwrap(DoubaoStreamingProtocol.extractError(from: packet))

        XCTAssertEqual(error.code, 45_000_001)
        XCTAssertEqual(error.message, "{\"code\":45000001,\"message\":\"bad request\"}")
    }

    private func makeFullServerResponsePacket(payload: [String: Any], sequence: Int32) throws -> Data {
        let json = try JSONSerialization.data(withJSONObject: payload)
        let compressed = try GzipCodec.compress(json)

        var packet = Data([0x11, 0x91, 0x11, 0x00])
        var seq = sequence.bigEndian
        packet.append(Data(bytes: &seq, count: 4))
        var payloadLength = UInt32(compressed.count).bigEndian
        packet.append(Data(bytes: &payloadLength, count: 4))
        packet.append(compressed)
        return packet
    }

    private func makeErrorPacket(code: UInt32, message: String) throws -> Data {
        let payload = Data(message.utf8)

        var packet = Data([0x11, 0xF0, 0x10, 0x00])
        var errorCode = code.bigEndian
        packet.append(Data(bytes: &errorCode, count: 4))
        var payloadLength = UInt32(payload.count).bigEndian
        packet.append(Data(bytes: &payloadLength, count: 4))
        packet.append(payload)
        return packet
    }
}
