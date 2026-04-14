import Foundation
import zlib

enum GzipCodec {
    enum Error: LocalizedError {
        case compressionFailed(Int32)
        case decompressionFailed(Int32)

        var errorDescription: String? {
            switch self {
            case .compressionFailed(let status):
                return "Gzip 压缩失败：\(status)"
            case .decompressionFailed(let status):
                return "Gzip 解压失败：\(status)"
            }
        }
    }

    nonisolated static func compress(_ data: Data) throws -> Data {
        try process(data, operation: .compress)
    }

    nonisolated static func decompress(_ data: Data) throws -> Data {
        try process(data, operation: .decompress)
    }

    private enum Operation {
        case compress
        case decompress
    }

    private nonisolated static func process(_ data: Data, operation: Operation) throws -> Data {
        guard !data.isEmpty else { return Data() }

        var stream = z_stream()
        let chunkSize = 16_384
        let windowBits = MAX_WBITS + 16

        let initStatus: Int32 = {
            switch operation {
            case .compress:
                return deflateInit2_(
                    &stream,
                    Z_DEFAULT_COMPRESSION,
                    Z_DEFLATED,
                    windowBits,
                    MAX_MEM_LEVEL,
                    Z_DEFAULT_STRATEGY,
                    ZLIB_VERSION,
                    Int32(MemoryLayout<z_stream>.size)
                )
            case .decompress:
                return inflateInit2_(
                    &stream,
                    windowBits,
                    ZLIB_VERSION,
                    Int32(MemoryLayout<z_stream>.size)
                )
            }
        }()

        guard initStatus == Z_OK else {
            switch operation {
            case .compress:
                throw Error.compressionFailed(initStatus)
            case .decompress:
                throw Error.decompressionFailed(initStatus)
            }
        }

        defer {
            switch operation {
            case .compress:
                deflateEnd(&stream)
            case .decompress:
                inflateEnd(&stream)
            }
        }

        var output = Data()
        try data.withUnsafeBytes { rawBuffer in
            stream.next_in = UnsafeMutablePointer<Bytef>(mutating: rawBuffer.bindMemory(to: Bytef.self).baseAddress)
            stream.avail_in = uInt(data.count)

            repeat {
                var buffer = [UInt8](repeating: 0, count: chunkSize)
                let status: Int32 = try buffer.withUnsafeMutableBytes { outputBytes in
                    guard let baseAddress = outputBytes.bindMemory(to: Bytef.self).baseAddress else {
                        switch operation {
                        case .compress:
                            throw Error.compressionFailed(Z_STREAM_ERROR)
                        case .decompress:
                            throw Error.decompressionFailed(Z_STREAM_ERROR)
                        }
                    }

                    stream.next_out = baseAddress
                    stream.avail_out = uInt(chunkSize)

                    let flush: Int32
                    switch operation {
                    case .compress:
                        flush = stream.avail_in == 0 ? Z_FINISH : Z_NO_FLUSH
                    case .decompress:
                        flush = Z_NO_FLUSH
                    }
                    switch operation {
                    case .compress:
                        return deflate(&stream, flush)
                    case .decompress:
                        return inflate(&stream, Z_NO_FLUSH)
                    }
                }

                let produced = chunkSize - Int(stream.avail_out)
                if produced > 0 {
                    output.append(contentsOf: buffer.prefix(produced))
                }

                switch operation {
                case .compress:
                    guard status == Z_OK || status == Z_STREAM_END else {
                        throw Error.compressionFailed(status)
                    }
                    if status == Z_STREAM_END { return }
                case .decompress:
                    guard status == Z_OK || status == Z_STREAM_END else {
                        throw Error.decompressionFailed(status)
                    }
                    if status == Z_STREAM_END { return }
                }
            } while true
        }

        return output
    }
}

enum DoubaoStreamingProtocol {
    enum MessageType: Int, Equatable {
        case fullClientRequest = 0x1
        case audioOnlyRequest = 0x2
        case fullServerResponse = 0x9
        case error = 0xF
    }

    enum Serialization: Int, Equatable {
        case raw = 0x0
        case json = 0x1
    }

    enum Compression: Int, Equatable {
        case none = 0x0
        case gzip = 0x1
    }

    struct PacketEnvelope: Equatable {
        let messageType: MessageType
        let flags: Int
        let serialization: Serialization
        let compression: Compression
        let sequence: Int32?
        let payload: Data
    }

    struct ServiceError: Equatable {
        let code: Int
        let message: String
    }

    enum ProtocolError: LocalizedError {
        case invalidURL
        case invalidPayload
        case unsupportedPacket

        var errorDescription: String? {
            switch self {
            case .invalidURL:
                return "豆包流式 ASR 地址无效。"
            case .invalidPayload:
                return "豆包流式 ASR 数据包无效。"
            case .unsupportedPacket:
                return "暂不支持的豆包流式 ASR 数据包。"
            }
        }
    }

    nonisolated static func makeWebSocketRequest(config: DoubaoStreamingConfig, connectID: String) throws -> URLRequest {
        guard let url = URL(string: config.endpoint) else {
            throw ProtocolError.invalidURL
        }

        var request = URLRequest(url: url)
        request.setValue(config.appID, forHTTPHeaderField: "X-Api-App-Key")
        request.setValue(config.accessToken, forHTTPHeaderField: "X-Api-Access-Key")
        request.setValue(config.resourceID, forHTTPHeaderField: "X-Api-Resource-Id")
        request.setValue(connectID, forHTTPHeaderField: "X-Api-Connect-Id")
        return request
    }

    nonisolated static func buildFullRequestPacket(config: DoubaoStreamingConfig) throws -> Data {
        var payload: [String: Any] = [
            "user": [
                "uid": config.userID
            ],
            "audio": [
                "format": "pcm",
                "codec": "raw",
                "rate": 16000,
                "bits": 16,
                "channel": 1
            ],
            "request": [
                "model_name": "bigmodel",
                "result_type": "single",
                "enable_itn": true,
                "enable_punc": true,
                "enable_ddc": true,
                "show_utterances": true,
                "enable_nonstream": true,
                "show_speech_rate": true,
                "show_volume": true,
                "enable_emotion_detection": true,
                "enable_speaker_info": true,
                "ssd_version": "200"
            ]
        ]

        if let language = config.language?.trimmingCharacters(in: .whitespacesAndNewlines), !language.isEmpty {
            var audio = payload["audio"] as? [String: Any] ?? [:]
            audio["language"] = language
            payload["audio"] = audio
        }

        let json = try JSONSerialization.data(withJSONObject: payload)
        let compressed = try GzipCodec.compress(json)

        var packet = Data([0x11, 0x10, 0x11, 0x00])
        packet.append(uint32Data(UInt32(compressed.count)))
        packet.append(compressed)
        return packet
    }

    nonisolated static func buildAudioPacket(payload: Data, isLast: Bool) throws -> Data {
        let compressed = try GzipCodec.compress(payload)

        var packet = Data([0x11, isLast ? 0x22 : 0x20, 0x01, 0x00])
        packet.append(uint32Data(UInt32(compressed.count)))
        packet.append(compressed)
        return packet
    }

    nonisolated static func inspectPacket(_ packet: Data) -> PacketEnvelope? {
        guard packet.count >= 8 else { return nil }
        let headerSize = Int(packet[0] & 0x0F) * 4
        guard packet.count >= headerSize + 4 else { return nil }

        guard let messageType = MessageType(rawValue: Int((packet[1] & 0xF0) >> 4)),
              let serialization = Serialization(rawValue: Int((packet[2] & 0xF0) >> 4)),
              let compression = Compression(rawValue: Int(packet[2] & 0x0F)) else {
            return nil
        }

        var cursor = headerSize
        var sequence: Int32?

        if messageType == .fullServerResponse, packet.count >= cursor + 8 {
            sequence = int32(from: packet, at: cursor)
            cursor += 4
        }

        guard packet.count >= cursor + 4 else { return nil }
        let payloadLength = Int(uint32(from: packet, at: cursor))
        cursor += 4
        guard packet.count >= cursor + payloadLength else { return nil }

        let rawPayload = packet.subdata(in: cursor..<(cursor + payloadLength))
        let payload = try? decodePayload(rawPayload, compression: compression)

        guard let payload else { return nil }
        return PacketEnvelope(
            messageType: messageType,
            flags: Int(packet[1] & 0x0F),
            serialization: serialization,
            compression: compression,
            sequence: sequence,
            payload: payload
        )
    }

    nonisolated static func extractError(from packet: Data) -> ServiceError? {
        guard packet.count >= 12 else { return nil }
        let headerSize = Int(packet[0] & 0x0F) * 4
        guard packet.count >= headerSize + 8 else { return nil }
        guard MessageType(rawValue: Int((packet[1] & 0xF0) >> 4)) == .error else {
            return nil
        }
        guard let compression = Compression(rawValue: Int(packet[2] & 0x0F)) else {
            return nil
        }

        let code = Int(uint32(from: packet, at: headerSize))
        let payloadLength = Int(uint32(from: packet, at: headerSize + 4))
        let payloadStart = headerSize + 8
        guard packet.count >= payloadStart + payloadLength else { return nil }

        let rawPayload = packet.subdata(in: payloadStart..<(payloadStart + payloadLength))
        let payloadData = try? decodePayload(rawPayload, compression: compression)
        let message = payloadData.flatMap { String(data: $0, encoding: .utf8) } ?? ""
        return ServiceError(code: code, message: message)
    }

    private nonisolated static func decodePayload(_ data: Data, compression: Compression) throws -> Data {
        switch compression {
        case .none:
            return data
        case .gzip:
            return try GzipCodec.decompress(data)
        }
    }

    private nonisolated static func uint32Data(_ value: UInt32) -> Data {
        let bytes: [UInt8] = [
            UInt8((value >> 24) & 0xFF),
            UInt8((value >> 16) & 0xFF),
            UInt8((value >> 8) & 0xFF),
            UInt8(value & 0xFF)
        ]
        return Data(bytes)
    }

    nonisolated static func uint32(from data: Data, at offset: Int) -> UInt32 {
        guard data.count >= offset + 4 else { return 0 }
        return (UInt32(data[offset]) << 24)
        | (UInt32(data[offset + 1]) << 16)
        | (UInt32(data[offset + 2]) << 8)
        | UInt32(data[offset + 3])
    }

    nonisolated static func int32(from data: Data, at offset: Int) -> Int32 {
        Int32(bitPattern: uint32(from: data, at: offset))
    }
}
