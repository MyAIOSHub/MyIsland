import CryptoKit
import Foundation
import UniformTypeIdentifiers

struct MeetingUploadedAudioAsset: Equatable, Sendable {
    let objectKey: String
    let uploadURL: URL
    let downloadURL: URL
}

actor MeetingObjectStorageClient {
    static let shared = MeetingObjectStorageClient()

    struct TemporaryCredentials: Codable, Equatable, Sendable {
        let accessKeyId: String
        let secretAccessKey: String
        let sessionToken: String
        let bucket: String
        let region: String
        let endpoint: String
        let keyPrefix: String

        init(
            accessKeyId: String,
            secretAccessKey: String,
            sessionToken: String,
            bucket: String,
            region: String,
            endpoint: String,
            keyPrefix: String
        ) {
            self.accessKeyId = accessKeyId
            self.secretAccessKey = secretAccessKey
            self.sessionToken = sessionToken
            self.bucket = bucket
            self.region = region
            self.endpoint = endpoint
            self.keyPrefix = keyPrefix
        }
    }

    enum StorageError: LocalizedError {
        case invalidSTSURL
        case invalidSTSPayload
        case invalidEndpoint
        case uploadFailed(Int)

        var errorDescription: String? {
            switch self {
            case .invalidSTSURL:
                return "对象存储 STS 地址无效。"
            case .invalidSTSPayload:
                return "对象存储 STS 返回无效。"
            case .invalidEndpoint:
                return "对象存储 Endpoint 无效。"
            case .uploadFailed(let statusCode):
                return "对象存储上传失败（\(statusCode)）。"
            }
        }
    }

    private let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    func uploadAudio(
        fileURL: URL,
        meetingID: String,
        meetingDate: Date,
        config: MeetingObjectStorageConfig
    ) async throws -> MeetingUploadedAudioAsset {
        let credentials = try await fetchTemporaryCredentials(config: config)
        let objectKey = Self.objectKey(
            meetingID: meetingID,
            meetingDate: meetingDate,
            fileExtension: normalizedAudioFileExtension(for: fileURL),
            keyPrefix: credentials.keyPrefix
        )
        let uploadURL = try presignedURL(
            method: "PUT",
            objectKey: objectKey,
            credentials: credentials
        )
        var request = URLRequest(url: uploadURL)
        request.httpMethod = "PUT"
        request.timeoutInterval = 120
        request.setValue(Self.contentType(for: fileURL), forHTTPHeaderField: "Content-Type")

        let fileData = try Data(contentsOf: fileURL)
        let (_, response) = try await session.upload(for: request, from: fileData)
        guard let http = response as? HTTPURLResponse else {
            throw StorageError.invalidSTSPayload
        }
        guard (200..<300).contains(http.statusCode) else {
            throw StorageError.uploadFailed(http.statusCode)
        }

        let downloadURL = try presignedURL(
            method: "GET",
            objectKey: objectKey,
            credentials: credentials
        )
        return MeetingUploadedAudioAsset(
            objectKey: objectKey,
            uploadURL: uploadURL,
            downloadURL: downloadURL
        )
    }

    func presignedDownloadURL(
        objectKey: String,
        expiresIn: TimeInterval = 3600,
        config: MeetingObjectStorageConfig
    ) async throws -> URL {
        let credentials = try await fetchTemporaryCredentials(config: config)
        return try presignedURL(
            method: "GET",
            objectKey: objectKey,
            credentials: credentials,
            expiresIn: expiresIn
        )
    }

    private func fetchTemporaryCredentials(config: MeetingObjectStorageConfig) async throws -> TemporaryCredentials {
        if config.usesDirectCredentials {
            return TemporaryCredentials(
                accessKeyId: config.accessKeyID,
                secretAccessKey: config.secretAccessKey,
                sessionToken: config.sessionToken,
                bucket: config.bucket,
                region: config.region,
                endpoint: config.endpoint,
                keyPrefix: config.keyPrefix
            )
        }

        guard let url = URL(string: config.stsURL) else {
            throw StorageError.invalidSTSURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 30
        if !config.stsBearerToken.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            request.setValue("Bearer \(config.stsBearerToken)", forHTTPHeaderField: "Authorization")
        }

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw StorageError.invalidSTSPayload
        }
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw StorageError.invalidSTSPayload
        }

        let root = (json["data"] as? [String: Any]) ?? json
        guard let accessKeyId = Self.string(root, keys: ["accessKeyId", "AccessKeyId"]),
              let secretAccessKey = Self.string(root, keys: ["secretAccessKey", "SecretAccessKey"]),
              let bucket = Self.string(root, keys: ["bucket", "Bucket"]),
              let region = Self.string(root, keys: ["region", "Region"]),
              let endpoint = Self.string(root, keys: ["endpoint", "Endpoint"]) else {
            throw StorageError.invalidSTSPayload
        }

        return TemporaryCredentials(
            accessKeyId: accessKeyId,
            secretAccessKey: secretAccessKey,
            sessionToken: Self.string(root, keys: ["sessionToken", "SessionToken"]) ?? "",
            bucket: bucket,
            region: region,
            endpoint: endpoint,
            keyPrefix: Self.string(root, keys: ["keyPrefix", "KeyPrefix"]) ?? ""
        )
    }

    private func presignedURL(
        method: String,
        objectKey: String,
        credentials: TemporaryCredentials,
        expiresIn: TimeInterval = 3600,
        now: Date = Date()
    ) throws -> URL {
        let hostURL = try endpointURL(endpoint: credentials.endpoint, bucket: credentials.bucket)
        guard let host = hostURL.host else {
            throw StorageError.invalidEndpoint
        }

        let requestDate = Self.requestDateString(from: now)
        let shortDate = String(requestDate.prefix(8))
        let credentialScope = "\(shortDate)/\(credentials.region)/tos/request"
        let canonicalURI = "/" + Self.encodePath(objectKey)

        var queryItems: [(String, String)] = [
            ("X-Tos-Algorithm", "TOS4-HMAC-SHA256"),
            ("X-Tos-Credential", "\(credentials.accessKeyId)/\(credentialScope)"),
            ("X-Tos-Date", requestDate),
            ("X-Tos-Expires", String(max(1, Int(expiresIn)))),
            ("X-Tos-SignedHeaders", "host")
        ]
        if !credentials.sessionToken.isEmpty {
            queryItems.append(("X-Tos-Security-Token", credentials.sessionToken))
        }

        let canonicalQuery = queryItems
            .map { (Self.encodeQuery($0.0), Self.encodeQuery($0.1)) }
            .sorted { lhs, rhs in
                if lhs.0 == rhs.0 { return lhs.1 < rhs.1 }
                return lhs.0 < rhs.0
            }
            .map { "\($0.0)=\($0.1)" }
            .joined(separator: "&")

        let canonicalHeaders = "host:\(host)\n"
        let canonicalRequest = [
            method,
            canonicalURI,
            canonicalQuery,
            canonicalHeaders,
            "host",
            "UNSIGNED-PAYLOAD"
        ].joined(separator: "\n")

        let stringToSign = [
            "TOS4-HMAC-SHA256",
            requestDate,
            credentialScope,
            Self.sha256Hex(canonicalRequest)
        ].joined(separator: "\n")

        let signingKey = Self.signingKey(
            secret: credentials.secretAccessKey,
            date: shortDate,
            region: credentials.region,
            service: "tos"
        )
        let signature = HMAC<SHA256>.authenticationCode(
            for: Data(stringToSign.utf8),
            using: signingKey
        ).map { String(format: "%02x", $0) }.joined()

        var components = URLComponents(url: hostURL, resolvingAgainstBaseURL: false)
        components?.percentEncodedPath = canonicalURI
        components?.percentEncodedQuery = canonicalQuery + "&X-Tos-Signature=" + Self.encodeQuery(signature)

        guard let url = components?.url else {
            throw StorageError.invalidEndpoint
        }
        return url
    }

    private func endpointURL(endpoint: String, bucket: String) throws -> URL {
        let trimmed = endpoint.trimmingCharacters(in: .whitespacesAndNewlines)
        let rawURLString = trimmed.contains("://") ? trimmed : "https://\(trimmed)"
        guard let baseURL = URL(string: rawURLString),
              let host = baseURL.host else {
            throw StorageError.invalidEndpoint
        }

        if host.hasPrefix("\(bucket).") {
            return baseURL
        }

        var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false)
        components?.host = "\(bucket).\(host)"
        guard let resolved = components?.url else {
            throw StorageError.invalidEndpoint
        }
        return resolved
    }

    static func objectKey(
        meetingID: String,
        meetingDate: Date,
        fileExtension: String = "wav",
        keyPrefix: String
    ) -> String {
        let calendar = Calendar(identifier: .gregorian)
        let year = calendar.component(.year, from: meetingDate)
        let normalizedExtension = fileExtension.trimmingCharacters(in: CharacterSet(charactersIn: ".")).lowercased()
        let effectiveExtension = normalizedExtension.isEmpty ? "wav" : normalizedExtension
        let scoped = "meetings/\(year)/\(meetingID)/master.\(effectiveExtension)"
        let prefix = keyPrefix.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        return prefix.isEmpty ? scoped : "\(prefix)/\(scoped)"
    }

    private static func requestDateString(from date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyyMMdd'T'HHmmss'Z'"
        return formatter.string(from: date)
    }

    private static func signingKey(secret: String, date: String, region: String, service: String) -> SymmetricKey {
        let dateKey = hmac(data: Data(date.utf8), keyData: Data(secret.utf8))
        let regionKey = hmac(data: Data(region.utf8), keyData: dateKey)
        let serviceKey = hmac(data: Data(service.utf8), keyData: regionKey)
        let signingKey = hmac(data: Data("request".utf8), keyData: serviceKey)
        return SymmetricKey(data: signingKey)
    }

    private static func hmac(data: Data, keyData: Data) -> Data {
        let key = SymmetricKey(data: keyData)
        let signature = HMAC<SHA256>.authenticationCode(for: data, using: key)
        return Data(signature)
    }

    private static func sha256Hex(_ value: String) -> String {
        SHA256.hash(data: Data(value.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    private static func encodePath(_ path: String) -> String {
        path
            .split(separator: "/", omittingEmptySubsequences: false)
            .map { segment in
                String(segment).addingPercentEncoding(withAllowedCharacters: .urlPathAllowed.subtracting(CharacterSet(charactersIn: "+?=&"))) ?? String(segment)
            }
            .joined(separator: "/")
    }

    private static func encodeQuery(_ value: String) -> String {
        let allowed = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_.~")
        return value.addingPercentEncoding(withAllowedCharacters: allowed) ?? value
    }

    private func normalizedAudioFileExtension(for fileURL: URL) -> String {
        let trimmed = fileURL.pathExtension.trimmingCharacters(in: CharacterSet(charactersIn: "."))
        return trimmed.isEmpty ? "wav" : trimmed.lowercased()
    }

    private static func contentType(for fileURL: URL) -> String {
        switch fileURL.pathExtension.lowercased() {
        case "wav":
            return "audio/wav"
        case "m4a":
            return "audio/x-m4a"
        case "mp3":
            return "audio/mpeg"
        default:
            break
        }
        if let contentType = UTType(filenameExtension: fileURL.pathExtension)?.preferredMIMEType {
            return contentType
        }
        return "application/octet-stream"
    }

    private static func string(_ json: [String: Any], keys: [String]) -> String? {
        for key in keys {
            if let value = json[key] as? String, !value.isEmpty {
                return value
            }
        }
        return nil
    }
}
