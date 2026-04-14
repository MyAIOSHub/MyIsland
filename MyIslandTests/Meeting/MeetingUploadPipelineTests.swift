import Foundation
import XCTest
@testable import My_Island

final class MeetingUploadPipelineTests: XCTestCase {
    func testUploadBuildsYearScopedObjectKeyAndReturnsPresignedMemoURL() async throws {
        let fileURL = makeTempAudioFile()
        let session = makeStubSession()
        UploadStubURLProtocol.requests = []
        UploadStubURLProtocol.handlers = [
            "https://sts.example.com/meeting-tos": .json([
                "accessKeyId": "AKID",
                "secretAccessKey": "SECRET",
                "sessionToken": "SESSION",
                "bucket": "meeting-audio",
                "region": "cn-beijing",
                "endpoint": "https://tos-cn-beijing.volces.com",
                "keyPrefix": "tenant-a"
            ])
        ]

        let client = MeetingObjectStorageClient(session: session)
        let config = MeetingObjectStorageConfig(
            stsURL: "https://sts.example.com/meeting-tos",
            stsBearerToken: "sts-token"
        )

        let asset = try await client.uploadAudio(
            fileURL: fileURL,
            meetingID: "meeting-123",
            meetingDate: Date(timeIntervalSince1970: 1_775_628_800),
            config: config
        )

        XCTAssertEqual(asset.objectKey, "tenant-a/meetings/2026/meeting-123/master.wav")
        XCTAssertTrue(asset.downloadURL.absoluteString.contains("X-Tos-Algorithm=TOS4-HMAC-SHA256"))

        let stsRequest = try XCTUnwrap(UploadStubURLProtocol.requests.first(where: { $0.url?.absoluteString == config.stsURL }))
        XCTAssertEqual(stsRequest.value(forHTTPHeaderField: "Authorization"), "Bearer sts-token")

        let uploadRequest = try XCTUnwrap(UploadStubURLProtocol.requests.first(where: { $0.httpMethod == "PUT" }))
        XCTAssertEqual(uploadRequest.url?.host, "meeting-audio.tos-cn-beijing.volces.com")
        XCTAssertEqual(uploadRequest.value(forHTTPHeaderField: "Content-Type"), "audio/wav")
    }

    func testUploadUsesSourceExtensionAndContentTypeForImportedAudioFormats() async throws {
        let fileURL = makeTempAudioFile(extension: "m4a")
        let session = makeStubSession()
        UploadStubURLProtocol.requests = []
        UploadStubURLProtocol.handlers = [
            "https://sts.example.com/meeting-tos": .json([
                "accessKeyId": "AKID",
                "secretAccessKey": "SECRET",
                "sessionToken": "SESSION",
                "bucket": "meeting-audio",
                "region": "cn-beijing",
                "endpoint": "https://tos-cn-beijing.volces.com",
                "keyPrefix": "tenant-a"
            ])
        ]

        let client = MeetingObjectStorageClient(session: session)
        let config = MeetingObjectStorageConfig(
            stsURL: "https://sts.example.com/meeting-tos",
            stsBearerToken: "sts-token"
        )

        let asset = try await client.uploadAudio(
            fileURL: fileURL,
            meetingID: "meeting-456",
            meetingDate: Date(timeIntervalSince1970: 1_775_628_800),
            config: config
        )

        XCTAssertEqual(asset.objectKey, "tenant-a/meetings/2026/meeting-456/master.m4a")
        let uploadRequest = try XCTUnwrap(UploadStubURLProtocol.requests.first(where: { $0.httpMethod == "PUT" }))
        XCTAssertEqual(uploadRequest.value(forHTTPHeaderField: "Content-Type"), "audio/x-m4a")
    }

    func testUploadSupportsDirectTOSCredentialsWithoutSTS() async throws {
        let fileURL = makeTempAudioFile()
        let session = makeStubSession()
        UploadStubURLProtocol.requests = []
        UploadStubURLProtocol.handlers = [:]

        let client = MeetingObjectStorageClient(session: session)
        let config = MeetingObjectStorageConfig(
            accessKeyID: "AKID",
            secretAccessKey: "SECRET",
            bucket: "meeting-audio",
            region: "cn-beijing",
            endpoint: "https://tos-cn-beijing.volces.com",
            keyPrefix: "tenant-direct"
        )

        let asset = try await client.uploadAudio(
            fileURL: fileURL,
            meetingID: "meeting-direct",
            meetingDate: Date(timeIntervalSince1970: 1_775_628_800),
            config: config
        )

        XCTAssertEqual(asset.objectKey, "tenant-direct/meetings/2026/meeting-direct/master.wav")
        XCTAssertFalse(UploadStubURLProtocol.requests.contains(where: { $0.url?.absoluteString == config.stsURL }))
        let uploadRequest = try XCTUnwrap(UploadStubURLProtocol.requests.first(where: { $0.httpMethod == "PUT" }))
        XCTAssertEqual(uploadRequest.url?.host, "meeting-audio.tos-cn-beijing.volces.com")
        XCTAssertEqual(uploadRequest.value(forHTTPHeaderField: "Content-Type"), "audio/wav")
    }

    private func makeTempAudioFile(extension ext: String = "wav") -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".\(ext)")
        let data = Data(repeating: 0x42, count: 1024)
        try? data.write(to: url)
        addTeardownBlock {
            try? FileManager.default.removeItem(at: url)
        }
        return url
    }

    private func makeStubSession() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [UploadStubURLProtocol.self]
        return URLSession(configuration: configuration)
    }
}

private final class UploadStubURLProtocol: URLProtocol {
    enum StubResponse {
        case json([String: Any], Int = 200)
        case status(Int)
    }

    static var handlers: [String: StubResponse] = [:]
    static var requests: [URLRequest] = []

    override class func canInit(with request: URLRequest) -> Bool {
        true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        Self.requests.append(request)

        guard let url = request.url else {
            client?.urlProtocol(self, didFailWithError: URLError(.badURL))
            return
        }

        let response: StubResponse
        if let matched = Self.handlers[url.absoluteString] {
            response = matched
        } else if request.httpMethod == "PUT" {
            response = .status(200)
        } else {
            response = .status(404)
        }

        let payload: Data
        let statusCode: Int
        switch response {
        case .json(let json, let code):
            payload = (try? JSONSerialization.data(withJSONObject: json, options: [])) ?? Data()
            statusCode = code
        case .status(let code):
            payload = Data()
            statusCode = code
        }

        let http = HTTPURLResponse(url: url, statusCode: statusCode, httpVersion: nil, headerFields: nil)!
        client?.urlProtocol(self, didReceive: http, cacheStoragePolicy: .notAllowed)
        if !payload.isEmpty {
            client?.urlProtocol(self, didLoad: payload)
        }
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}
