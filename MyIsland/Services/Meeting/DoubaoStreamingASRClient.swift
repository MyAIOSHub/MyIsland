import Foundation

actor DoubaoStreamingASRClient {
    static let shared = DoubaoStreamingASRClient()

    enum ClientError: LocalizedError {
        case invalidURL
        case notStarted

        var errorDescription: String? {
            switch self {
            case .invalidURL:
                return "豆包流式 ASR 地址无效。"
            case .notStarted:
                return "豆包流式 ASR 尚未启动。"
            }
        }
    }

    enum Event: Sendable {
        case connecting(connectID: String)
        case requestSent
        case ready
        case audioBuffered(bytes: Int, totalBytes: Int)
        case firstAudioSent(bytes: Int)
        case audioSent(bytes: Int, isLast: Bool)
        case receiving
        case responsePayload(summary: String)
        case segmentsReceived(count: Int)
        case failed(code: Int?, message: String)
        case closed(reason: String)
    }

    private var webSocketTask: URLSessionWebSocketTask?
    private var receivedSegmentFingerprints: [String: String] = [:]
    private var onSegments: (([TranscriptSegment]) -> Void)?
    private var onEvent: ((Event) -> Void)?
    private var isRunning = false
    private var isReady = false
    private var hasSentFirstAudio = false
    private var hasReceivedFirstResponse = false
    private var pendingAudioChunks: [Data] = []
    private var pendingAudioBytes = 0
    private let pendingAudioMaxBytes = 16_000 * 2 * 3

    func start(
        config: DoubaoStreamingConfig,
        onEvent: ((Event) -> Void)? = nil,
        onSegments: @escaping ([TranscriptSegment]) -> Void
    ) async throws {
        await stop()

        let connectID = UUID().uuidString
        let request: URLRequest
        do {
            request = try DoubaoStreamingProtocol.makeWebSocketRequest(config: config, connectID: connectID)
        } catch DoubaoStreamingProtocol.ProtocolError.invalidURL {
            throw ClientError.invalidURL
        } catch {
            throw error
        }

        self.onSegments = onSegments
        self.onEvent = onEvent
        receivedSegmentFingerprints.removeAll()
        pendingAudioChunks.removeAll()
        pendingAudioBytes = 0
        hasSentFirstAudio = false
        hasReceivedFirstResponse = false
        isRunning = true
        isReady = false

        onEvent?(.connecting(connectID: connectID))

        let task = URLSession.shared.webSocketTask(with: request)
        task.resume()
        webSocketTask = task

        let fullRequest = try DoubaoStreamingProtocol.buildFullRequestPacket(config: config)
        try await task.send(.data(fullRequest))
        onEvent?(.requestSent)

        isReady = true
        onEvent?(.ready)

        Task { await self.receiveLoop() }
    }

    func appendAudioChunk(_ pcm16MonoData: Data) async throws {
        guard isRunning else {
            throw ClientError.notStarted
        }

        guard isReady else {
            bufferAudioChunk(pcm16MonoData)
            onEvent?(.audioBuffered(bytes: pcm16MonoData.count, totalBytes: pendingAudioBytes))
            return
        }

        try await sendAudioChunk(pcm16MonoData, isLast: false)
    }

    func stop() async {
        defer {
            webSocketTask = nil
            isRunning = false
            isReady = false
            hasSentFirstAudio = false
            hasReceivedFirstResponse = false
            pendingAudioChunks.removeAll()
            pendingAudioBytes = 0
        }

        guard let task = webSocketTask else { return }

        if isRunning {
            do {
                try await flushPendingAudioIfNeeded()
                try await sendAudioChunk(Data(), isLast: true)
            } catch {
                onEvent?(.failed(code: nil, message: error.localizedDescription))
            }
        }

        task.cancel(with: .goingAway, reason: nil)
        onEvent?(.closed(reason: "client-stop"))
    }

    private func receiveLoop() async {
        guard let task = webSocketTask else { return }

        while isRunning {
            do {
                let message = try await task.receive()
                let data: Data
                switch message {
                case .data(let packet):
                    data = packet
                case .string(let string):
                    data = Data(string.utf8)
                @unknown default:
                    continue
                }

                if let serviceError = DoubaoStreamingProtocol.extractError(from: data) {
                    onEvent?(.failed(code: serviceError.code, message: serviceError.message))
                    task.cancel(with: .goingAway, reason: nil)
                    isRunning = false
                    isReady = false
                    break
                }

                if DoubaoStreamingProtocol.inspectPacket(data) != nil, !hasReceivedFirstResponse {
                    hasReceivedFirstResponse = true
                    onEvent?(.receiving)
                    try? await flushPendingAudioIfNeeded()
                }

                if let summary = Self.makeResponseSummary(fromPacket: data) {
                    onEvent?(.responsePayload(summary: summary))
                }

                let segments = parseServerPacket(data)
                if !segments.isEmpty {
                    onSegments?(segments)
                    onEvent?(.segmentsReceived(count: segments.count))
                }
            } catch {
                guard isRunning else { break }
                onEvent?(.failed(code: nil, message: error.localizedDescription))
                isRunning = false
                isReady = false
                break
            }
        }
    }

    private func sendAudioChunk(_ pcm16MonoData: Data, isLast: Bool) async throws {
        guard let task = webSocketTask else {
            throw ClientError.notStarted
        }

        let packet = try DoubaoStreamingProtocol.buildAudioPacket(payload: pcm16MonoData, isLast: isLast)
        try await task.send(.data(packet))

        if !hasSentFirstAudio && !pcm16MonoData.isEmpty {
            hasSentFirstAudio = true
            onEvent?(.firstAudioSent(bytes: pcm16MonoData.count))
        }

        onEvent?(.audioSent(bytes: pcm16MonoData.count, isLast: isLast))
    }

    private func bufferAudioChunk(_ data: Data) {
        pendingAudioChunks.append(data)
        pendingAudioBytes += data.count

        while pendingAudioBytes > pendingAudioMaxBytes, let removed = pendingAudioChunks.first {
            pendingAudioBytes -= removed.count
            pendingAudioChunks.removeFirst()
        }
    }

    private func flushPendingAudioIfNeeded() async throws {
        guard isReady, !pendingAudioChunks.isEmpty else { return }
        let buffered = pendingAudioChunks
        pendingAudioChunks.removeAll()
        pendingAudioBytes = 0
        for chunk in buffered {
            try await sendAudioChunk(chunk, isLast: false)
        }
    }

    private func parseServerPacket(_ packet: Data) -> [TranscriptSegment] {
        let segments = Self.parseSegments(fromPacket: packet)
        guard !segments.isEmpty else { return [] }

        var unique: [TranscriptSegment] = []
        for segment in segments {
            let fingerprint = "\(segment.text)|\(segment.startTimeMs)|\(segment.endTimeMs)|\(segment.isFinal)"
            if receivedSegmentFingerprints[segment.id] != fingerprint {
                receivedSegmentFingerprints[segment.id] = fingerprint
                unique.append(segment)
            }
        }
        return unique
    }

    nonisolated static func parseSegments(fromPacket packet: Data) -> [TranscriptSegment] {
        if let envelope = DoubaoStreamingProtocol.inspectPacket(packet) {
            return parseSegments(fromPayload: envelope.payload)
        }

        guard let json = try? JSONSerialization.jsonObject(with: packet) else {
            return []
        }
        return parseSegments(fromJSONObject: json, source: "doubao-live")
    }

    nonisolated static func parseSegments(fromPayload payload: Data) -> [TranscriptSegment] {
        guard let json = try? JSONSerialization.jsonObject(with: payload) else {
            return []
        }
        return parseSegments(fromJSONObject: json, source: "doubao-live")
    }

    nonisolated static func parseSegments(fromJSONObject json: Any, source: String) -> [TranscriptSegment] {
        uniqueSegments(extractSegments(from: json, source: source))
    }

    nonisolated static func makeResponseSummary(fromPacket packet: Data) -> String? {
        if let envelope = DoubaoStreamingProtocol.inspectPacket(packet) {
            return makeResponseSummary(fromPayload: envelope.payload)
        }

        guard let json = try? JSONSerialization.jsonObject(with: packet) else {
            return nil
        }
        return summarize(json: json)
    }

    nonisolated static func makeResponseSummary(fromPayload payload: Data) -> String? {
        guard let json = try? JSONSerialization.jsonObject(with: payload) else {
            return nil
        }
        return summarize(json: json)
    }

    private nonisolated static func extractSegments(from json: Any, source: String) -> [TranscriptSegment] {
        var segments: [TranscriptSegment] = []

        if let dict = json as? [String: Any] {
            let containsNestedUtterances =
                (dict["result"] as? [[String: Any]]) != nil
                || ((dict["result"] as? [String: Any])?["utterances"] as? [[String: Any]]) != nil
                || (dict["utterances"] as? [[String: Any]]) != nil

            if !containsNestedUtterances,
               let segment = buildSegment(dict, source: source) {
                segments.append(segment)
            }
            if let utterances = dict["result"] as? [[String: Any]] {
                segments.append(contentsOf: utterances.compactMap { buildSegment($0, source: source) })
            }
            if let resultDict = dict["result"] as? [String: Any],
               let utterances = resultDict["utterances"] as? [[String: Any]] {
                segments.append(contentsOf: utterances.compactMap { buildSegment($0, source: source) })
            }
            if let utterances = dict["utterances"] as? [[String: Any]] {
                segments.append(contentsOf: utterances.compactMap { buildSegment($0, source: source) })
            }
            for value in dict.values {
                segments.append(contentsOf: extractSegments(from: value, source: source))
            }
        } else if let array = json as? [Any] {
            for item in array {
                segments.append(contentsOf: extractSegments(from: item, source: source))
            }
        }

        return segments
    }

    private nonisolated static func uniqueSegments(_ segments: [TranscriptSegment]) -> [TranscriptSegment] {
        var ordered: [TranscriptSegment] = []
        var seen = Set<String>()

        for segment in segments {
            let fingerprint = "\(segment.id)|\(segment.text)|\(segment.startTimeMs)|\(segment.endTimeMs)|\(segment.isFinal)"
            if seen.insert(fingerprint).inserted {
                ordered.append(segment)
            }
        }

        return ordered
    }

    private nonisolated static func buildSegment(_ dict: [String: Any], source: String) -> TranscriptSegment? {
        let text = (
            (dict["text"] as? String)
            ?? (dict["content"] as? String)
            ?? ""
        ).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }

        let start = integerValue(dict["start_time"])
            ?? integerValue(dict["start"])
            ?? integerValue(dict["start_ms"])
            ?? integerValue(dict["begin_time"])
            ?? 0
        let end = integerValue(dict["end_time"])
            ?? integerValue(dict["end"])
            ?? integerValue(dict["end_ms"])
            ?? start
        let definitive = (dict["definite"] as? Bool) ?? true
        let additions = dict["additions"] as? [String: Any]

        let speaker = extractSpeakerLabel(dict: dict, additions: additions)
        let gender = extractGender(dict: dict, additions: additions)
        let speechRate = numericValue(additions?["speech_rate"]) ?? numericValue(dict["speech_rate"])
        let volume = numericValue(additions?["volume"]) ?? numericValue(dict["volume"])
        let emotion = stringValue(additions?["emotion"]) ?? stringValue(dict["emotion"])
        let explicitID = (dict["id"] as? String)
            ?? (dict["utterance_id"] as? String)
            ?? (dict["index"] as? NSNumber).map { "index-\($0.intValue)" }
        let segmentID = explicitID ?? "\(speaker ?? "speaker")-\(start)"

        return TranscriptSegment(
            id: segmentID,
            text: text,
            startTimeMs: start,
            endTimeMs: end,
            speakerLabel: speaker,
            gender: gender,
            isFinal: definitive,
            speechRate: speechRate,
            volume: volume,
            emotion: emotion,
            source: source
        )
    }

    private nonisolated static func summarize(json: Any) -> String? {
        guard let dict = json as? [String: Any] else { return nil }

        var parts: [String] = []
        parts.append("keys=\(dict.keys.sorted().joined(separator: ","))")

        if let resultDict = dict["result"] as? [String: Any] {
            parts.append("result.keys=\(resultDict.keys.sorted().joined(separator: ","))")
        }

        if let utterance = firstUtterance(in: json) {
            parts.append("utterance.keys=\(utterance.keys.sorted().joined(separator: ","))")
            if let additions = utterance["additions"] as? [String: Any], !additions.isEmpty {
                parts.append("additions.keys=\(additions.keys.sorted().joined(separator: ","))")
            }
            if let speaker = extractSpeakerLabel(dict: utterance, additions: utterance["additions"] as? [String: Any]) {
                parts.append("speaker=\(speaker)")
            }
            if let gender = extractGender(dict: utterance, additions: utterance["additions"] as? [String: Any]) {
                parts.append("gender=\(gender)")
            }
        }

        let segments = extractSegments(from: json, source: "doubao-live")
        let speakers = Array(Set(segments.compactMap(\.speakerLabel))).sorted()
        parts.append("segments=\(segments.count)")
        if !speakers.isEmpty {
            parts.append("speakers=\(speakers.joined(separator: ","))")
        }

        return parts.joined(separator: " ")
    }

    private nonisolated static func firstUtterance(in json: Any) -> [String: Any]? {
        if let dict = json as? [String: Any] {
            if let utterances = dict["result"] as? [[String: Any]], let first = utterances.first {
                return first
            }
            if let resultDict = dict["result"] as? [String: Any],
               let utterances = resultDict["utterances"] as? [[String: Any]],
               let first = utterances.first {
                return first
            }
            if let utterances = dict["utterances"] as? [[String: Any]], let first = utterances.first {
                return first
            }
            for value in dict.values {
                if let utterance = firstUtterance(in: value) {
                    return utterance
                }
            }
        } else if let array = json as? [Any] {
            for item in array {
                if let utterance = firstUtterance(in: item) {
                    return utterance
                }
            }
        }

        return nil
    }

    private nonisolated static func extractSpeakerLabel(dict: [String: Any], additions: [String: Any]?) -> String? {
        let candidates: [Any?] = [
            dict["speaker"],
            dict["speaker_id"],
            dict["speaker_label"],
            dict["spk"],
            additions?["speaker"],
            additions?["speaker_id"],
            additions?["speaker_label"],
            additions?["spk"]
        ]

        for candidate in candidates {
            if let normalized = normalizeSpeakerLabel(candidate) {
                return normalized
            }
        }

        return nil
    }

    private nonisolated static func normalizeSpeakerLabel(_ candidate: Any?) -> String? {
        if let string = stringValue(candidate) {
            let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return nil }
            if trimmed.hasPrefix("speaker") {
                return trimmed
            }
            if Int(trimmed) != nil {
                return "speaker_\(trimmed)"
            }
            return trimmed
        }

        if let number = candidate as? NSNumber {
            return "speaker_\(number.intValue)"
        }

        return nil
    }

    private nonisolated static func extractGender(dict: [String: Any], additions: [String: Any]?) -> String? {
        stringValue(dict["gender"])
            ?? stringValue(dict["speaker_gender"])
            ?? stringValue(additions?["gender"])
            ?? stringValue(additions?["speaker_gender"])
    }

    private nonisolated static func stringValue(_ candidate: Any?) -> String? {
        if let string = candidate as? String {
            let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : trimmed
        }
        return nil
    }

    private nonisolated static func numericValue(_ candidate: Any?) -> Double? {
        (candidate as? NSNumber)?.doubleValue
    }

    private nonisolated static func integerValue(_ candidate: Any?) -> Int? {
        if let number = candidate as? NSNumber {
            return number.intValue
        }
        if let string = candidate as? String,
           let value = Int(string.trimmingCharacters(in: .whitespacesAndNewlines)) {
            return value
        }
        return nil
    }
}
