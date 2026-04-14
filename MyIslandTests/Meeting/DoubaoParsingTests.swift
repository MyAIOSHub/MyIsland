import Foundation
import XCTest
@testable import My_Island

final class DoubaoParsingTests: XCTestCase {
    func testMemoSubmitBodyEnablesTranscriptionSummaryChapterTodoAndQA() throws {
        let body = MeetingMemoClient.buildSubmitBody(
            audioURL: URL(string: "https://example.com/meeting.wav")!,
            topic: "季度复盘"
        )

        let input = try XCTUnwrap(body["Input"] as? [String: Any])
        let offline = try XCTUnwrap(input["Offline"] as? [String: Any])
        XCTAssertEqual(offline["FileURL"] as? String, "https://example.com/meeting.wav")
        XCTAssertEqual(offline["FileType"] as? String, "audio")

        let params = try XCTUnwrap(body["Params"] as? [String: Any])
        XCTAssertEqual(params["AudioTranscriptionEnable"] as? Bool, true)
        XCTAssertEqual(params["InformationExtractionEnabled"] as? Bool, true)
        XCTAssertEqual(params["SummarizationEnabled"] as? Bool, true)
        XCTAssertEqual(params["ChapterEnabled"] as? Bool, true)
        XCTAssertEqual(params["Topic"] as? String, "季度复盘")

        let transcriptionParams = try XCTUnwrap(params["AudioTranscriptionParams"] as? [String: Any])
        XCTAssertEqual(transcriptionParams["SpeakerIdentification"] as? Bool, true)
        XCTAssertEqual(transcriptionParams["NumberOfSpeaker"] as? Int, 0)

        let extractionParams = try XCTUnwrap(params["InformationExtractionParams"] as? [String: Any])
        let extractionTypes = try XCTUnwrap(extractionParams["Types"] as? [String])
        XCTAssertTrue(extractionTypes.contains("todo_list"))
        XCTAssertTrue(extractionTypes.contains("question_answer"))

        let summaryParams = try XCTUnwrap(params["SummarizationParams"] as? [String: Any])
        let summaryTypes = try XCTUnwrap(summaryParams["Types"] as? [String])
        XCTAssertTrue(summaryTypes.contains("summary"))
    }

    func testStreamingPacketParsingExtractsSpeakerMetadata() throws {
        let payload: [String: Any] = [
            "result": [[
                "text": "我们先定义问题。",
                "start_time": 120,
                "end_time": 920,
                "speaker": "speaker_1",
                "definite": true,
                "additions": [
                    "speech_rate": 1.25,
                    "volume": 0.82,
                    "emotion": "neutral"
                ]
            ]]
        ]
        let packet = try makeStreamingPacket(payload: payload)

        let segments = DoubaoStreamingASRClient.parseSegments(fromPacket: packet)

        XCTAssertEqual(segments.count, 1)
        XCTAssertEqual(segments[0].text, "我们先定义问题。")
        XCTAssertEqual(segments[0].speakerLabel, "speaker_1")
        XCTAssertEqual(segments[0].startTimeMs, 120)
        XCTAssertEqual(segments[0].endTimeMs, 920)
        XCTAssertEqual(segments[0].emotion, "neutral")
        XCTAssertEqual(segments[0].source, "doubao-live")
    }

    func testStreamingPacketParsingUsesStableSegmentIDAcrossPartialUpdates() throws {
        let partialPayload: [String: Any] = [
            "result": [[
                "text": "现在这个",
                "start_time": 5192,
                "end_time": 7002,
                "definite": false
            ]]
        ]
        let finalPayload: [String: Any] = [
            "result": [[
                "text": "现在这个。",
                "start_time": 5192,
                "end_time": 7972,
                "definite": true
            ]]
        ]

        let partial = DoubaoStreamingASRClient.parseSegments(fromPacket: try makeStreamingPacket(payload: partialPayload))
        let final = DoubaoStreamingASRClient.parseSegments(fromPacket: try makeStreamingPacket(payload: finalPayload))

        XCTAssertEqual(partial.count, 1)
        XCTAssertEqual(final.count, 1)
        XCTAssertEqual(partial[0].id, final[0].id)
        XCTAssertEqual(partial[0].startTimeMs, final[0].startTimeMs)
    }

    func testStreamingPacketParsingExtractsSpeakerIdentifierFromAdditions() throws {
        let payload: [String: Any] = [
            "result": [[
                "text": "我们先定义问题。",
                "start_time": 120,
                "end_time": 920,
                "definite": true,
                "additions": [
                    "speaker_id": "speaker_2",
                    "emotion": "neutral"
                ]
            ]]
        ]

        let segments = DoubaoStreamingASRClient.parseSegments(fromPacket: try makeStreamingPacket(payload: payload))

        XCTAssertEqual(segments.count, 1)
        XCTAssertEqual(segments[0].speakerLabel, "speaker_2")
    }

    func testStreamingPacketParsingNormalizesNumericSpeakerIdentifiers() throws {
        let payload: [String: Any] = [
            "result": [[
                "text": "这是一条说话人结果。",
                "start_time": 300,
                "end_time": 1600,
                "speaker_id": 3,
                "definite": true
            ]]
        ]

        let segments = DoubaoStreamingASRClient.parseSegments(fromPacket: try makeStreamingPacket(payload: payload))

        XCTAssertEqual(segments.count, 1)
        XCTAssertEqual(segments[0].speakerLabel, "speaker_3")
    }

    func testMemoSummaryParsingSupportsNestedKeys() throws {
        let json: [String: Any] = [
            "data": [
                "summary": "会议明确了阶段目标。",
                "chapters": [
                    ["title": "背景", "content": "项目需要重新定位。"]
                ],
                "todos": [
                    ["content": "补齐下周路线图", "owner": "Alice", "due_date": "2026-04-15"]
                ],
                "qa": [
                    ["question": "为什么现在改方向？", "answer": "市场窗口变化。"]
                ],
                "highlights": ["先做问题定义，再做方案收敛"]
            ]
        ]

        let bundle = try XCTUnwrap(MeetingMemoClient.parseSummaryBundle(from: json))

        XCTAssertEqual(bundle.fullSummary, "会议明确了阶段目标。")
        XCTAssertEqual(bundle.chapterSummaries.first?.title, "背景")
        XCTAssertEqual(bundle.actionItems.first?.owner, "Alice")
        XCTAssertEqual(bundle.qaPairs.first?.question, "为什么现在改方向？")
        XCTAssertEqual(bundle.processHighlights, ["先做问题定义，再做方案收敛"])
    }

    func testMemoArtifactParsingBuildsBundleFromOfficialLarkFiles() throws {
        let summaryPayload: [String: Any] = [
            "summary": "会议确定先做问题定义，再输出路线图。"
        ]
        let chapterPayload: [String: Any] = [
            "chapter_summary": [
                ["title": "背景", "summary": "重新定义问题边界。"],
                ["title": "行动", "summary": "确认 owner 和交付节奏。"]
            ]
        ]
        let informationPayload: [String: Any] = [
            "todo_list": [
                ["content": "补齐路线图", "owner": "Alice", "deadline": "2026-04-20"]
            ],
            "question_answer": [
                ["question": "为什么现在调整？", "answer": "因为市场窗口变化。"]
            ],
            "procedure_list": [
                "先定义问题",
                "再确定 owner"
            ]
        ]

        let bundle = MeetingMemoClient.buildSummaryBundle(
            transcriptionPayload: nil,
            chapterPayload: chapterPayload,
            informationPayload: informationPayload,
            summarizationPayload: summaryPayload
        )

        XCTAssertEqual(bundle.fullSummary, "会议确定先做问题定义，再输出路线图。")
        XCTAssertEqual(bundle.chapterSummaries.map(\.title), ["背景", "行动"])
        XCTAssertEqual(bundle.actionItems.first?.task, "补齐路线图")
        XCTAssertEqual(bundle.actionItems.first?.owner, "Alice")
        XCTAssertEqual(bundle.qaPairs.first?.answer, "因为市场窗口变化。")
        XCTAssertEqual(bundle.processHighlights, ["先定义问题", "再确定 owner"])
        XCTAssertEqual(bundle.source, "memo-lark")
    }

    func testMemoArtifactParsingExtractsOfflineTranscriptSegmentsAndSpeakerMetadata() throws {
        let transcriptionPayload: [String: Any] = [
            "items": [
                [
                    "id": "utt-1",
                    "content": "我们先定义问题。",
                    "start_time": 120,
                    "end_time": 920,
                    "speaker_id": "speaker_2",
                    "speaker_gender": "female"
                ],
                [
                    "utterance_id": "utt-2",
                    "text": "然后再确认方案。",
                    "start_time": 1_000,
                    "end_time": 1_900,
                    "additions": [
                        "speaker": 3,
                        "emotion": "neutral"
                    ]
                ]
            ]
        ]

        let artifact = MeetingMemoClient.buildArtifact(
            transcriptionPayload: transcriptionPayload,
            chapterPayload: nil,
            informationPayload: nil,
            summarizationPayload: nil
        )

        XCTAssertEqual(artifact.transcriptSegments.count, 2)
        XCTAssertEqual(artifact.transcriptSegments[0].id, "utt-1")
        XCTAssertEqual(artifact.transcriptSegments[0].speakerLabel, "speaker_2")
        XCTAssertEqual(artifact.transcriptSegments[0].gender, "female")
        XCTAssertEqual(artifact.transcriptSegments[0].source, "doubao-memo")
        XCTAssertEqual(artifact.transcriptSegments[1].id, "utt-2")
        XCTAssertEqual(artifact.transcriptSegments[1].speakerLabel, "speaker_3")
        XCTAssertEqual(artifact.transcriptSegments[1].emotion, "neutral")
        XCTAssertEqual(artifact.speakerSpans.map(\.speakerLabel), ["speaker_2", "speaker_3"])
        XCTAssertEqual(artifact.summaryBundle.fullSummary, "我们先定义问题。 然后再确认方案。")
    }

    func testMemoArtifactParsingSupportsTypedItemsAndSummaryAliasFallbacks() throws {
        let summaryPayload: [String: Any] = [
            "data": [
                "overview": [
                    "abstract": "会议先收敛问题，再拆待办和问答。"
                ]
            ]
        ]
        let chapterPayload: [String: Any] = [
            "items": [
                ["topic": "问题定义", "text": "先把当前问题写成一句话。"],
                ["name": "执行计划", "summary": "再明确 owner 和节奏。"]
            ]
        ]
        let informationPayload: [String: Any] = [
            "items": [
                ["type": "todo", "content": "补齐路线图", "owner_name": "Alice", "deadline": "2026-04-20"],
                ["kind": "question_answer", "question": "为什么现在推进？", "answer": "因为窗口期短。"],
                ["category": "process_highlight", "text": "先定义问题"]
            ]
        ]

        let bundle = MeetingMemoClient.buildSummaryBundle(
            transcriptionPayload: nil,
            chapterPayload: chapterPayload,
            informationPayload: informationPayload,
            summarizationPayload: summaryPayload
        )

        XCTAssertEqual(bundle.fullSummary, "会议先收敛问题，再拆待办和问答。")
        XCTAssertEqual(bundle.chapterSummaries.map(\.title), ["问题定义", "执行计划"])
        XCTAssertEqual(bundle.actionItems.first?.task, "补齐路线图")
        XCTAssertEqual(bundle.actionItems.first?.owner, "Alice")
        XCTAssertEqual(bundle.qaPairs.first?.question, "为什么现在推进？")
        XCTAssertEqual(bundle.processHighlights, ["先定义问题"])
    }

    func testMemoClientWritesSubmitQueryAndPayloadDiagnostics() async throws {
        let session = makeMemoStubSession()
        MemoStubURLProtocol.handlers = [
            "https://memo.example.com/submit": .json(["TaskID": "task-123"]),
            "https://memo.example.com/query": .json([
                "Status": "Success",
                "Data": [
                    "Result": [
                        "Artifacts": [
                            "SummaryFile": "https://memo.example.com/files/summary.json",
                            "InformationFile": "https://memo.example.com/files/info.json"
                        ],
                        "Nested": [
                            "ChapterSummaryFile": "https://memo.example.com/files/chapter.json"
                        ],
                        "OutputList": [
                            ["TranscriptionFile": "https://memo.example.com/files/transcript.json"]
                        ]
                    ]
                ]
            ]),
            "https://memo.example.com/files/transcript.json": .json([
                "items": [
                    ["id": "utt-1", "content": "我们先定义问题。", "start_time": 0, "end_time": 800]
                ]
            ]),
            "https://memo.example.com/files/chapter.json": .json([
                "items": [
                    ["title": "问题定义", "summary": "先锁定问题边界。"]
                ]
            ]),
            "https://memo.example.com/files/info.json": .json([
                "items": [
                    ["type": "todo", "content": "补齐路线图"],
                    ["kind": "question_answer", "question": "为什么现在做？", "answer": "因为窗口期短。"]
                ]
            ]),
            "https://memo.example.com/files/summary.json": .json([
                "data": [
                    "abstract": "会议确认先定义问题，再输出路线图。"
                ]
            ])
        ]

        let diagnosticSpy = MemoDiagnosticSpy()
        let client = MeetingMemoClient(
            session: session,
            writeDiagnostic: { meetingID, filename, data in
                await diagnosticSpy.record(meetingID: meetingID, filename: filename, data: data)
            }
        )

        let config = DoubaoMemoConfig(
            submitURL: "https://memo.example.com/submit",
            queryURL: "https://memo.example.com/query",
            appID: "app",
            accessToken: "token",
            resourceID: "volc.lark.minutes"
        )

        let response = try await client.submit(
            audioURL: URL(string: "https://example.com/audio.wav")!,
            topic: "季度复盘",
            config: config,
            meetingID: "meeting-123"
        )
        let artifact = try await client.pollSummary(
            taskID: response.taskID,
            config: config,
            meetingID: "meeting-123",
            maxAttempts: 1
        )

        XCTAssertEqual(artifact.summaryBundle.fullSummary, "会议确认先定义问题，再输出路线图。")
        XCTAssertEqual(artifact.summaryBundle.chapterSummaries.first?.title, "问题定义")
        XCTAssertEqual(artifact.summaryBundle.actionItems.first?.task, "补齐路线图")
        XCTAssertEqual(artifact.summaryBundle.qaPairs.first?.question, "为什么现在做？")
        let snapshot = await diagnosticSpy.snapshot()
        XCTAssertEqual(snapshot.meetingIDs, ["meeting-123"])
        XCTAssertEqual(
            Set(snapshot.filenames),
            Set([
                "memo-submit-response.json",
                "memo-query-response.json",
                "memo-transcription-payload.json",
                "memo-chapter-payload.json",
                "memo-information-payload.json",
                "memo-summary-payload.json"
            ])
        )
    }

    private func makeStreamingPacket(payload: [String: Any]) throws -> Data {
        let json = try JSONSerialization.data(withJSONObject: payload)
        var packet = Data([0x11, 0x90, 0x00, 0x00])
        var sequence = UInt32(1).bigEndian
        packet.append(Data(bytes: &sequence, count: 4))
        var payloadLength = UInt32(json.count).bigEndian
        packet.append(Data(bytes: &payloadLength, count: 4))
        packet.append(json)
        return packet
    }

    private func makeMemoStubSession() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [MemoStubURLProtocol.self]
        return URLSession(configuration: configuration)
    }
}

private actor MemoDiagnosticSpy {
    private var entries: [(meetingID: String, filename: String, size: Int)] = []

    func record(meetingID: String, filename: String, data: Data) {
        entries.append((meetingID: meetingID, filename: filename, size: data.count))
    }

    func snapshot() -> (meetingIDs: [String], filenames: [String]) {
        var seenMeetingIDs = Set<String>()
        let uniqueMeetingIDs = entries.compactMap { entry -> String? in
            guard seenMeetingIDs.insert(entry.meetingID).inserted else { return nil }
            return entry.meetingID
        }
        return (
            meetingIDs: uniqueMeetingIDs,
            filenames: entries.map(\.filename)
        )
    }
}

private final class MemoStubURLProtocol: URLProtocol {
    enum StubResponse {
        case json([String: Any], Int = 200)
    }

    static var handlers: [String: StubResponse] = [:]

    override class func canInit(with request: URLRequest) -> Bool {
        true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        guard let url = request.url,
              let response = Self.handlers[url.absoluteString] else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
            return
        }

        let statusCode: Int
        let payload: Data
        switch response {
        case .json(let json, let code):
            statusCode = code
            payload = (try? JSONSerialization.data(withJSONObject: json, options: [])) ?? Data()
        }

        let http = HTTPURLResponse(url: url, statusCode: statusCode, httpVersion: nil, headerFields: nil)!
        client?.urlProtocol(self, didReceive: http, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: payload)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}
