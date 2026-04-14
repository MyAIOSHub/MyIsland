import Foundation

actor MeetingMemoClient {
    static let shared = MeetingMemoClient()

    struct MemoTaskResponse {
        let taskID: String
    }

    private struct MemoResultFiles {
        let transcriptionURL: URL?
        let chapterURL: URL?
        let informationURL: URL?
        let summaryURL: URL?

        var missingStructuredKinds: [String] {
            var missing: [String] = []
            if chapterURL == nil {
                missing.append("章节")
            }
            if informationURL == nil {
                missing.append("信息提取")
            }
            if summaryURL == nil {
                missing.append("总结")
            }
            return missing
        }
    }

    private struct MemoFetchedPayload {
        let json: [String: Any]
        let data: Data
    }

    enum MemoError: LocalizedError {
        case invalidURL
        case invalidResponse
        case missingTaskID
        case publicAudioURLRequired
        case queryFailed(String)

        var errorDescription: String? {
            switch self {
            case .invalidURL:
                return "豆包妙记地址无效。"
            case .invalidResponse:
                return "豆包妙记返回了无效响应。"
            case .missingTaskID:
                return "豆包妙记没有返回任务 ID。"
            case .publicAudioURLRequired:
                return "豆包妙记官方 API 需要可访问的音频 URL。当前应用只生成本地录音文件，需补充上传链路后才能直连妙记。"
            case .queryFailed(let message):
                return "豆包妙记查询失败：\(message)"
            }
        }
    }

    private let session: URLSession
    private let writeDiagnostic: @Sendable (String, String, Data) async -> Void

    init(
        session: URLSession = .shared,
        writeDiagnostic: @escaping @Sendable (String, String, Data) async -> Void = { meetingID, filename, data in
            guard !meetingID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
            try? await MeetingStorage.shared.writeMeetingDiagnosticData(data, meetingID: meetingID, filename: filename)
        }
    ) {
        self.session = session
        self.writeDiagnostic = writeDiagnostic
    }

    func submit(
        audioURL: URL,
        topic: String,
        config: DoubaoMemoConfig,
        meetingID: String? = nil
    ) async throws -> MemoTaskResponse {
        guard let url = URL(string: config.submitURL) else {
            throw MemoError.invalidURL
        }
        guard !audioURL.isFileURL, let scheme = audioURL.scheme?.lowercased(), scheme == "http" || scheme == "https" else {
            throw MemoError.publicAudioURLRequired
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 30
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        applyHeaders(to: &request, config: config)
        request.httpBody = try JSONSerialization.data(withJSONObject: Self.buildSubmitBody(audioURL: audioURL, topic: topic))

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw MemoError.invalidResponse
        }
        await recordDiagnostic(meetingID, filename: "memo-submit-response.json", data: data)

        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw MemoError.invalidResponse
        }

        if let taskID = Self.extractString(from: json, keys: ["TaskID", "task_id", "taskId", "job_id", "jobId", "id"]),
           !taskID.isEmpty {
            return MemoTaskResponse(taskID: taskID)
        }

        throw MemoError.missingTaskID
    }

    func pollSummary(
        taskID: String,
        config: DoubaoMemoConfig,
        meetingID: String? = nil,
        maxAttempts: Int = 20
    ) async throws -> MeetingMemoArtifact {
        guard let queryURL = URL(string: config.queryURL) else {
            throw MemoError.invalidURL
        }

        var attempt = 0
        while attempt < maxAttempts {
            attempt += 1

            var request = URLRequest(url: queryURL)
            request.httpMethod = "POST"
            request.timeoutInterval = 30
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            applyHeaders(to: &request, config: config)
            request.httpBody = try JSONSerialization.data(withJSONObject: ["TaskID": taskID])

            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
                throw MemoError.invalidResponse
            }
            await recordDiagnostic(meetingID, filename: "memo-query-response.json", data: data)

            guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                throw MemoError.invalidResponse
            }

            let status = Self.extractString(from: json, keys: ["Status", "status", "state", "task_status"])?.lowercased()
            if status == "success" || status == "done" || status == "completed" {
                let resultFiles = Self.parseResultFiles(from: json)
                return try await buildArtifact(from: resultFiles, meetingID: meetingID)
            }

            if status == "failed" || status == "error" {
                let message = Self.extractString(from: json, keys: ["ErrMessage", "error", "message", "reason"]) ?? "unknown error"
                throw MemoError.queryFailed(message)
            }

            try await Task.sleep(for: .seconds(6))
        }

        throw MemoError.queryFailed("timeout")
    }

    static func buildSubmitBody(audioURL: URL, topic: String) -> [String: Any] {
        [
            "Input": [
                "Offline": [
                    "FileURL": audioURL.absoluteString,
                    "FileType": "audio"
                ]
            ],
            "Params": [
                "AllActivate": false,
                "SourceLang": "zh_cn",
                "AudioTranscriptionEnable": true,
                "AudioTranscriptionParams": [
                    "SpeakerIdentification": true,
                    "NumberOfSpeaker": 0
                ],
                "InformationExtractionEnabled": true,
                "InformationExtractionParams": [
                    "Types": ["todo_list", "question_answer"]
                ],
                "SummarizationEnabled": true,
                "SummarizationParams": [
                    "Types": ["summary"]
                ],
                "ChapterEnabled": true,
                "Topic": topic
            ]
        ]
    }

    private func applyHeaders(to request: inout URLRequest, config: DoubaoMemoConfig) {
        request.setValue(config.appID, forHTTPHeaderField: "X-Api-App-Key")
        request.setValue(config.accessToken, forHTTPHeaderField: "X-Api-Access-Key")
        if !config.resourceID.isEmpty {
            request.setValue(config.resourceID, forHTTPHeaderField: "X-Api-Resource-Id")
        }
        request.setValue(UUID().uuidString, forHTTPHeaderField: "X-Api-Request-Id")
        request.setValue("-1", forHTTPHeaderField: "X-Api-Sequence")
    }

    private func buildArtifact(from resultFiles: MemoResultFiles, meetingID: String?) async throws -> MeetingMemoArtifact {
        async let fetchedTranscription = fetchPayload(from: resultFiles.transcriptionURL)
        async let fetchedChapter = fetchPayload(from: resultFiles.chapterURL)
        async let fetchedInformation = fetchPayload(from: resultFiles.informationURL)
        async let fetchedSummary = fetchPayload(from: resultFiles.summaryURL)

        let transcriptionPayload = try await fetchedTranscription
        let chapterPayload = try await fetchedChapter
        let informationPayload = try await fetchedInformation
        let summaryPayload = try await fetchedSummary

        if let transcriptionPayload {
            await recordDiagnostic(meetingID, filename: "memo-transcription-payload.json", data: transcriptionPayload.data)
        }
        if let chapterPayload {
            await recordDiagnostic(meetingID, filename: "memo-chapter-payload.json", data: chapterPayload.data)
        }
        if let informationPayload {
            await recordDiagnostic(meetingID, filename: "memo-information-payload.json", data: informationPayload.data)
        }
        if let summaryPayload {
            await recordDiagnostic(meetingID, filename: "memo-summary-payload.json", data: summaryPayload.data)
        }

        var artifact = Self.buildArtifact(
            transcriptionPayload: transcriptionPayload?.json,
            chapterPayload: chapterPayload?.json,
            informationPayload: informationPayload?.json,
            summarizationPayload: summaryPayload?.json
        )

        if resultFiles.transcriptionURL == nil {
            artifact.diagnosticNotes.append("妙记成功，但未解析到转写结果文件 URL。")
        }
        if !resultFiles.missingStructuredKinds.isEmpty {
            artifact.diagnosticNotes.append("妙记成功，但未解析到结构化结果文件 URL：\(resultFiles.missingStructuredKinds.joined(separator: "、"))。")
        }

        return artifact
    }

    private func fetchPayload(from url: URL?) async throws -> MemoFetchedPayload? {
        guard let url else { return nil }
        let (data, response) = try await session.data(from: url)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw MemoError.invalidResponse
        }

        let object = try JSONSerialization.jsonObject(with: data)
        if let dict = object as? [String: Any] {
            return MemoFetchedPayload(json: dict, data: data)
        }
        if let array = object as? [Any] {
            return MemoFetchedPayload(json: ["items": array], data: data)
        }
        throw MemoError.invalidResponse
    }

    private func recordDiagnostic(_ meetingID: String?, filename: String, data: Data) async {
        guard let meetingID, !meetingID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        await writeDiagnostic(meetingID, filename, data)
    }

    private static func parseResultFiles(from json: [String: Any]) -> MemoResultFiles {
        let result = ((json["Data"] as? [String: Any])?["Result"] as? [String: Any])
            ?? ((json["data"] as? [String: Any])?["result"] as? [String: Any])
            ?? (json["Result"] as? [String: Any])
            ?? json

        return MemoResultFiles(
            transcriptionURL: buildURL(from: result, fallback: json, keys: ["AudioTranscriptionFile", "TranscriptionFile"]),
            chapterURL: buildURL(from: result, fallback: json, keys: ["ChapterFile", "ChapterSummaryFile"]),
            informationURL: buildURL(from: result, fallback: json, keys: ["InformationExtractionFile", "InformationFile"]),
            summaryURL: buildURL(from: result, fallback: json, keys: ["SummarizationFile", "SummaryFile", "AbstractFile"])
        )
    }

    private static func buildURL(from primary: [String: Any], fallback: [String: Any], keys: [String]) -> URL? {
        let normalizedKeys = keys.map(normalizedKey)
        for key in keys {
            if let value = extractString(from: primary, keys: [key]), let url = URL(string: value), !value.isEmpty {
                return url
            }
        }
        for key in normalizedKeys {
            if let value = recursiveStringValue(in: primary, matching: key), let url = URL(string: value), !value.isEmpty {
                return url
            }
        }
        for key in normalizedKeys {
            if let value = recursiveStringValue(in: fallback, matching: key), let url = URL(string: value), !value.isEmpty {
                return url
            }
        }
        return nil
    }

    static func buildArtifact(
        transcriptionPayload: [String: Any]?,
        chapterPayload: [String: Any]?,
        informationPayload: [String: Any]?,
        summarizationPayload: [String: Any]?
    ) -> MeetingMemoArtifact {
        let transcriptSegments = parseTranscriptSegments(from: transcriptionPayload)
        let speakerSpans = transcriptSegments.map {
            SpeakerSpan(
                id: $0.id,
                speakerLabel: $0.speakerLabel ?? "speaker_unknown",
                startTimeMs: $0.startTimeMs,
                endTimeMs: $0.endTimeMs,
                gender: $0.gender,
                speechRate: $0.speechRate,
                volume: $0.volume,
                emotion: $0.emotion
            )
        }

        let summary = extractSummaryText(from: summarizationPayload)
            ?? extractSummaryFromTranscriptionPayload(transcriptionPayload)

        let chapterItems = extractChapterSummaries(from: chapterPayload ?? [:])
        let actionItems = extractActionItems(from: informationPayload ?? [:])
        let qaPairs = extractQAPairs(from: informationPayload ?? [:])
        let processHighlights = extractProcessHighlights(from: informationPayload ?? [:])

        return MeetingMemoArtifact(
            summaryBundle: MeetingSummaryBundle(
                fullSummary: summary,
                chapterSummaries: chapterItems,
                actionItems: actionItems,
                qaPairs: qaPairs,
                processHighlights: processHighlights,
                source: "memo-lark"
            ),
            transcriptSegments: transcriptSegments,
            speakerSpans: speakerSpans
        )
    }

    static func buildSummaryBundle(
        transcriptionPayload: [String: Any]?,
        chapterPayload: [String: Any]?,
        informationPayload: [String: Any]?,
        summarizationPayload: [String: Any]?
    ) -> MeetingSummaryBundle {
        buildArtifact(
            transcriptionPayload: transcriptionPayload,
            chapterPayload: chapterPayload,
            informationPayload: informationPayload,
            summarizationPayload: summarizationPayload
        ).summaryBundle
    }

    static func parseSummaryBundle(from json: [String: Any]) -> MeetingSummaryBundle? {
        let dataObject = (json["data"] as? [String: Any]) ?? json
        return MeetingSummaryBundle(
            fullSummary: extractSummaryText(from: dataObject) ?? "",
            chapterSummaries: extractChapterSummaries(from: dataObject),
            actionItems: extractActionItems(from: dataObject),
            qaPairs: extractQAPairs(from: dataObject),
            processHighlights: extractProcessHighlights(from: dataObject),
            source: "memo"
        )
    }

    private static func extractSummaryText(from payload: [String: Any]?) -> String? {
        guard let payload else { return nil }
        return extractString(
            from: payload,
            keys: [
                "full_summary",
                "summary",
                "abstract",
                "overall_summary",
                "summary_text",
                "overallSummary"
            ]
        )
    }

    private static func extractChapterSummaries(from json: [String: Any]) -> [MeetingChapterSummary] {
        extractArray(
            from: json,
            keys: ["chapter_summary", "chapterSummaries", "chapters", "items"]
        ).compactMap { item -> MeetingChapterSummary? in
            guard let dict = item as? [String: Any] else { return nil }
            let title = extractString(from: dict, keys: ["title", "name", "topic"]) ?? "章节"
            let body = extractString(from: dict, keys: ["summary", "content", "text"]) ?? ""
            guard !body.isEmpty else { return nil }
            return MeetingChapterSummary(title: title, summary: body)
        }
    }

    private static func extractActionItems(from json: [String: Any]) -> [MeetingActionItem] {
        let explicitItems = extractArray(
            from: json,
            keys: ["todo_list", "todos", "todoItems", "action_items"]
        )
        let typedItems = extractTypedItems(from: json, tokens: ["todo", "action", "task"])
        var seen = Set<String>()

        return (explicitItems + typedItems).compactMap { item -> MeetingActionItem? in
            guard let dict = item as? [String: Any] else { return nil }
            let task = extractString(from: dict, keys: ["content", "task", "title", "summary", "text"]) ?? ""
            guard !task.isEmpty else { return nil }
            let owner = extractString(from: dict, keys: ["owner", "owner_name", "assignee"])
            let dueDate = extractString(from: dict, keys: ["due_date", "dueDate", "deadline"])
            let fingerprint = "\(task)|\(owner ?? "")|\(dueDate ?? "")"
            guard seen.insert(fingerprint).inserted else { return nil }
            return MeetingActionItem(task: task, owner: owner, dueDate: dueDate)
        }
    }

    private static func extractQAPairs(from json: [String: Any]) -> [MeetingQAPair] {
        let explicitItems = extractArray(
            from: json,
            keys: ["question_answer", "qa_pairs", "qa", "questions"]
        )
        let typedItems = extractTypedItems(from: json, tokens: ["qa", "question", "answer"])
        var seen = Set<String>()

        return (explicitItems + typedItems).compactMap { item -> MeetingQAPair? in
            guard let dict = item as? [String: Any] else { return nil }
            let question = extractString(from: dict, keys: ["question", "q", "title"]) ?? ""
            let answer = extractString(from: dict, keys: ["answer", "a", "content", "summary", "text"]) ?? ""
            guard !question.isEmpty || !answer.isEmpty else { return nil }
            let fingerprint = "\(question)|\(answer)"
            guard seen.insert(fingerprint).inserted else { return nil }
            return MeetingQAPair(question: question, answer: answer)
        }
    }

    private static func extractProcessHighlights(from json: [String: Any]) -> [String] {
        let explicitHighlights = extractStringArray(
            from: json,
            keys: ["procedure_list", "process_highlights", "processes", "highlights"]
        )
        let typedHighlights = extractTypedItems(from: json, tokens: ["process", "procedure", "highlight"]).compactMap { item -> String? in
            guard let dict = item as? [String: Any] else { return nil }
            return extractString(from: dict, keys: ["content", "summary", "text", "title"])
        }

        var seen = Set<String>()
        return (explicitHighlights + typedHighlights).filter { value in
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return false }
            return seen.insert(trimmed).inserted
        }
    }

    private static func extractTypedItems(from json: [String: Any], tokens: [String]) -> [Any] {
        extractArray(from: json, keys: ["items"]).filter { item in
            guard let dict = item as? [String: Any] else { return false }
            return itemMatchesType(dict, tokens: tokens)
        }
    }

    private static func itemMatchesType(_ dict: [String: Any], tokens: [String]) -> Bool {
        let normalizedTokens = tokens.map(normalizedKey)
        for field in ["type", "category", "kind"] {
            if let value = directString(from: dict, keys: [field]) {
                let normalizedValue = normalizedKey(value)
                if normalizedTokens.contains(where: { normalizedValue.contains($0) }) {
                    return true
                }
            }
        }
        return false
    }

    private static func extractSummaryFromTranscriptionPayload(_ payload: [String: Any]?) -> String {
        let lines = parseTranscriptSegments(from: payload).map(\.text)
        return String(lines.prefix(6).joined(separator: " ").prefix(400))
    }

    private static func parseTranscriptSegments(from payload: [String: Any]?) -> [TranscriptSegment] {
        guard let payload else { return [] }
        return DoubaoStreamingASRClient.parseSegments(fromJSONObject: payload, source: "doubao-memo")
    }

    private static func directString(from json: [String: Any], keys: [String]) -> String? {
        let normalizedKeys = keys.map(normalizedKey)
        for (index, key) in keys.enumerated() {
            if let value = json[key] as? String, !value.isEmpty {
                return value
            }
            let normalizedTarget = normalizedKeys[index]
            for (candidateKey, value) in json {
                guard normalizedKey(candidateKey) == normalizedTarget,
                      let stringValue = value as? String,
                      !stringValue.isEmpty else { continue }
                return stringValue
            }
        }
        return nil
    }

    private static func extractString(from json: [String: Any], keys: [String]) -> String? {
        if let direct = directString(from: json, keys: keys) {
            return direct
        }
        if let nested = json["data"] as? [String: Any], let direct = directString(from: nested, keys: keys) {
            return direct
        }
        if let nested = json["Data"] as? [String: Any], let direct = directString(from: nested, keys: keys) {
            return direct
        }

        for target in keys.map(normalizedKey) {
            if let value = recursiveStringValue(in: json, matching: target) {
                return value
            }
        }
        return nil
    }

    private static func extractArray(from json: [String: Any], keys: [String]) -> [Any] {
        let normalizedKeys = keys.map(normalizedKey)
        for (index, key) in keys.enumerated() {
            if let array = json[key] as? [Any] {
                return array
            }
            let normalizedTarget = normalizedKeys[index]
            for (candidateKey, value) in json {
                guard normalizedKey(candidateKey) == normalizedTarget,
                      let array = value as? [Any] else { continue }
                return array
            }
            if let nested = json["data"] as? [String: Any], let array = extractArray(from: nested, keys: [key]) as [Any]?, !array.isEmpty {
                return array
            }
            if let nested = json["Data"] as? [String: Any], let array = extractArray(from: nested, keys: [key]) as [Any]?, !array.isEmpty {
                return array
            }
        }

        for target in normalizedKeys {
            if let array = recursiveArrayValue(in: json, matching: target) {
                return array
            }
        }
        return []
    }

    private static func extractStringArray(from json: [String: Any], keys: [String]) -> [String] {
        extractArray(from: json, keys: keys).compactMap { item in
            if let text = item as? String, !text.isEmpty {
                return text
            }
            if let dict = item as? [String: Any] {
                return extractString(from: dict, keys: ["content", "summary", "text", "title"])
            }
            return nil
        }
    }

    private static func recursiveStringValue(in object: Any, matching normalizedTarget: String) -> String? {
        if let dict = object as? [String: Any] {
            for (key, value) in dict {
                if normalizedKey(key) == normalizedTarget, let stringValue = value as? String, !stringValue.isEmpty {
                    return stringValue
                }
            }
            for value in dict.values {
                if let stringValue = recursiveStringValue(in: value, matching: normalizedTarget) {
                    return stringValue
                }
            }
        } else if let array = object as? [Any] {
            for value in array {
                if let stringValue = recursiveStringValue(in: value, matching: normalizedTarget) {
                    return stringValue
                }
            }
        }
        return nil
    }

    private static func recursiveArrayValue(in object: Any, matching normalizedTarget: String) -> [Any]? {
        if let dict = object as? [String: Any] {
            for (key, value) in dict {
                if normalizedKey(key) == normalizedTarget, let array = value as? [Any] {
                    return array
                }
            }
            for value in dict.values {
                if let array = recursiveArrayValue(in: value, matching: normalizedTarget) {
                    return array
                }
            }
        } else if let array = object as? [Any] {
            for value in array {
                if let nestedArray = recursiveArrayValue(in: value, matching: normalizedTarget) {
                    return nestedArray
                }
            }
        }
        return nil
    }

    private static func normalizedKey(_ value: String) -> String {
        value.lowercased().unicodeScalars
            .filter(CharacterSet.alphanumerics.contains)
            .map(String.init)
            .joined()
    }
}
