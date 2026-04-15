import Combine
import Foundation

@MainActor
final class MeetingSettingsStore: ObservableObject {
    static let shared = MeetingSettingsStore()

    private enum StreamingDefaults {
        // Meeting-oriented long-audio resource: better multi-speaker diarization
        // than the generic `concurrent` tier. The `concurrent` resource often
        // returns the same speaker_id for every utterance in a mono-mixed
        // stream, which is the root cause of "all rows shown as 说话人1".
        static let recommendedResourceID = "volc.bigasr.sauc.duration"
        static let legacyConcurrentResourceID = "volc.bigasr.sauc.concurrent"
        static let unsupportedResourceID = "volc.seedasr.sauc.concurrent"
    }

    private enum Keys {
        static let audioInputMode = "meeting.audio.inputMode"

        static let streamingEndpoint = "meeting.doubao.streaming.endpoint"
        static let streamingAppID = "meeting.doubao.streaming.appID"
        static let streamingAccessToken = "meeting.doubao.streaming.accessToken"
        static let streamingResourceID = "meeting.doubao.streaming.resourceID"
        static let streamingUserID = "meeting.doubao.streaming.userID"
        static let streamingLanguage = "meeting.doubao.streaming.language"

        static let memoSubmitURL = "meeting.doubao.memo.submitURL"
        static let memoQueryURL = "meeting.doubao.memo.queryURL"
        static let memoAppID = "meeting.doubao.memo.appID"
        static let memoAccessToken = "meeting.doubao.memo.accessToken"
        static let memoResourceID = "meeting.doubao.memo.resourceID"

        static let objectStorageSTSURL = "meeting.objectStorage.stsURL"
        static let objectStorageSTSBearerToken = "meeting.objectStorage.stsBearerToken"
        static let objectStorageAccessKeyID = "meeting.objectStorage.accessKeyID"
        static let objectStorageSecretAccessKey = "meeting.objectStorage.secretAccessKey"
        static let objectStorageSessionToken = "meeting.objectStorage.sessionToken"
        static let objectStorageBucket = "meeting.objectStorage.bucket"
        static let objectStorageRegion = "meeting.objectStorage.region"
        static let objectStorageEndpoint = "meeting.objectStorage.endpoint"
        static let objectStorageKeyPrefix = "meeting.objectStorage.keyPrefix"

        static let agentBaseURL = "meeting.agent.baseURL"
        static let agentAPIKey = "meeting.agent.apiKey"
        static let agentModel = "meeting.agent.model"
        static let agentTemperature = "meeting.agent.temperature"
        static let agentSystemPrompt = "meeting.agent.systemPrompt"
        static let agentMaxVisibleViewpoints = "meeting.agent.maxVisibleViewpoints"

        static let legacyStreamingAppKey = "meeting.doubao.streaming.appKey"
        static let legacyStreamingAccessKey = "meeting.doubao.streaming.accessKey"
        static let legacyMemoAppKey = "meeting.doubao.memo.appKey"
        static let legacyMemoAccessKey = "meeting.doubao.memo.accessKey"
    }

    private let defaults = UserDefaults.standard

    @Published var audioInputMode: MeetingAudioInputMode {
        didSet { defaults.set(audioInputMode.rawValue, forKey: Keys.audioInputMode) }
    }

    @Published var streamingEndpoint: String {
        didSet { defaults.set(streamingEndpoint, forKey: Keys.streamingEndpoint) }
    }
    @Published var streamingAppID: String {
        didSet { defaults.set(streamingAppID, forKey: Keys.streamingAppID) }
    }
    @Published var streamingAccessToken: String {
        didSet { defaults.set(streamingAccessToken, forKey: Keys.streamingAccessToken) }
    }
    @Published var streamingResourceID: String {
        didSet { defaults.set(streamingResourceID, forKey: Keys.streamingResourceID) }
    }
    @Published var streamingUserID: String {
        didSet { defaults.set(streamingUserID, forKey: Keys.streamingUserID) }
    }
    @Published var streamingLanguage: String {
        didSet { defaults.set(streamingLanguage, forKey: Keys.streamingLanguage) }
    }

    @Published var memoSubmitURL: String {
        didSet { defaults.set(memoSubmitURL, forKey: Keys.memoSubmitURL) }
    }
    @Published var memoQueryURL: String {
        didSet { defaults.set(memoQueryURL, forKey: Keys.memoQueryURL) }
    }
    @Published var memoAppID: String {
        didSet { defaults.set(memoAppID, forKey: Keys.memoAppID) }
    }
    @Published var memoAccessToken: String {
        didSet { defaults.set(memoAccessToken, forKey: Keys.memoAccessToken) }
    }
    @Published var memoResourceID: String {
        didSet { defaults.set(memoResourceID, forKey: Keys.memoResourceID) }
    }

    @Published var objectStorageSTSURL: String {
        didSet { defaults.set(objectStorageSTSURL, forKey: Keys.objectStorageSTSURL) }
    }
    @Published var objectStorageSTSBearerToken: String {
        didSet { defaults.set(objectStorageSTSBearerToken, forKey: Keys.objectStorageSTSBearerToken) }
    }
    @Published var objectStorageAccessKeyID: String {
        didSet { defaults.set(objectStorageAccessKeyID, forKey: Keys.objectStorageAccessKeyID) }
    }
    @Published var objectStorageSecretAccessKey: String {
        didSet { defaults.set(objectStorageSecretAccessKey, forKey: Keys.objectStorageSecretAccessKey) }
    }
    @Published var objectStorageSessionToken: String {
        didSet { defaults.set(objectStorageSessionToken, forKey: Keys.objectStorageSessionToken) }
    }
    @Published var objectStorageBucket: String {
        didSet { defaults.set(objectStorageBucket, forKey: Keys.objectStorageBucket) }
    }
    @Published var objectStorageRegion: String {
        didSet { defaults.set(objectStorageRegion, forKey: Keys.objectStorageRegion) }
    }
    @Published var objectStorageEndpoint: String {
        didSet { defaults.set(objectStorageEndpoint, forKey: Keys.objectStorageEndpoint) }
    }
    @Published var objectStorageKeyPrefix: String {
        didSet { defaults.set(objectStorageKeyPrefix, forKey: Keys.objectStorageKeyPrefix) }
    }

    @Published var agentBaseURL: String {
        didSet { defaults.set(agentBaseURL, forKey: Keys.agentBaseURL) }
    }
    @Published var agentAPIKey: String {
        didSet { defaults.set(agentAPIKey, forKey: Keys.agentAPIKey) }
    }
    @Published var agentModel: String {
        didSet { defaults.set(agentModel, forKey: Keys.agentModel) }
    }
    @Published var agentTemperature: Double {
        didSet { defaults.set(agentTemperature, forKey: Keys.agentTemperature) }
    }
    @Published var agentSystemPrompt: String {
        didSet { defaults.set(agentSystemPrompt, forKey: Keys.agentSystemPrompt) }
    }
    @Published var agentMaxVisibleViewpoints: Int {
        didSet { defaults.set(agentMaxVisibleViewpoints, forKey: Keys.agentMaxVisibleViewpoints) }
    }

    private init() {
        audioInputMode = MeetingAudioInputMode(
            rawValue: defaults.string(forKey: Keys.audioInputMode) ?? ""
        ) ?? .microphoneAndSystem

        streamingEndpoint = defaults.string(forKey: Keys.streamingEndpoint)
            ?? "wss://openspeech.bytedance.com/api/v3/sauc/bigmodel_async"
        streamingAppID = defaults.string(forKey: Keys.streamingAppID)
            ?? defaults.string(forKey: Keys.legacyStreamingAppKey)
            ?? ""
        streamingAccessToken = defaults.string(forKey: Keys.streamingAccessToken)
            ?? defaults.string(forKey: Keys.legacyStreamingAccessKey)
            ?? ""
        let storedStreamingResourceID = defaults.string(forKey: Keys.streamingResourceID)
        let migratedStreamingResourceID = Self.normalizedStreamingResourceID(storedStreamingResourceID)
        streamingResourceID = migratedStreamingResourceID
        if storedStreamingResourceID != migratedStreamingResourceID {
            defaults.set(migratedStreamingResourceID, forKey: Keys.streamingResourceID)
        }
        streamingUserID = defaults.string(forKey: Keys.streamingUserID) ?? UUID().uuidString
        streamingLanguage = defaults.string(forKey: Keys.streamingLanguage) ?? ""

        memoSubmitURL = defaults.string(forKey: Keys.memoSubmitURL)
            ?? "https://openspeech.bytedance.com/api/v3/auc/lark/submit"
        memoQueryURL = defaults.string(forKey: Keys.memoQueryURL)
            ?? "https://openspeech.bytedance.com/api/v3/auc/lark/query"
        memoAppID = defaults.string(forKey: Keys.memoAppID)
            ?? defaults.string(forKey: Keys.legacyMemoAppKey)
            ?? ""
        memoAccessToken = defaults.string(forKey: Keys.memoAccessToken)
            ?? defaults.string(forKey: Keys.legacyMemoAccessKey)
            ?? ""
        memoResourceID = defaults.string(forKey: Keys.memoResourceID) ?? "volc.lark.minutes"

        objectStorageSTSURL = defaults.string(forKey: Keys.objectStorageSTSURL) ?? ""
        objectStorageSTSBearerToken = defaults.string(forKey: Keys.objectStorageSTSBearerToken) ?? ""
        objectStorageAccessKeyID = defaults.string(forKey: Keys.objectStorageAccessKeyID) ?? ""
        objectStorageSecretAccessKey = defaults.string(forKey: Keys.objectStorageSecretAccessKey) ?? ""
        objectStorageSessionToken = defaults.string(forKey: Keys.objectStorageSessionToken) ?? ""
        objectStorageBucket = defaults.string(forKey: Keys.objectStorageBucket) ?? ""
        objectStorageRegion = defaults.string(forKey: Keys.objectStorageRegion) ?? ""
        objectStorageEndpoint = defaults.string(forKey: Keys.objectStorageEndpoint) ?? ""
        objectStorageKeyPrefix = defaults.string(forKey: Keys.objectStorageKeyPrefix) ?? ""

        agentBaseURL = defaults.string(forKey: Keys.agentBaseURL) ?? "https://dashscope.aliyuncs.com/compatible-mode/v1"
        agentAPIKey = defaults.string(forKey: Keys.agentAPIKey) ?? ""
        agentModel = defaults.string(forKey: Keys.agentModel) ?? "qwen-plus"
        let storedTemperature = defaults.object(forKey: Keys.agentTemperature) as? Double
        agentTemperature = storedTemperature ?? 0.2
        agentSystemPrompt = defaults.string(forKey: Keys.agentSystemPrompt)
            ?? "你是会议讨论助手。请基于提供的会议技能和最近讨论内容，给出简洁、批判性、可执行的建议，优先指出前提假设、被忽略的问题和下一步动作。"
        let storedMaxVisibleViewpoints = defaults.object(forKey: Keys.agentMaxVisibleViewpoints) as? Int
        agentMaxVisibleViewpoints = storedMaxVisibleViewpoints ?? 3
    }

    private static func normalizedStreamingResourceID(_ value: String?) -> String {
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !trimmed.isEmpty else { return StreamingDefaults.recommendedResourceID }
        if trimmed == StreamingDefaults.unsupportedResourceID {
            return StreamingDefaults.recommendedResourceID
        }
        // One-time migration: users previously on the `concurrent` tier get
        // upgraded to `duration` for better speaker diarization. Users who
        // explicitly need `concurrent` can set it again from the settings UI.
        if trimmed == StreamingDefaults.legacyConcurrentResourceID {
            return StreamingDefaults.recommendedResourceID
        }
        return trimmed
    }

    var streamingConfig: DoubaoStreamingConfig {
        DoubaoStreamingConfig(
            endpoint: streamingEndpoint.trimmingCharacters(in: .whitespacesAndNewlines),
            appID: streamingAppID.trimmingCharacters(in: .whitespacesAndNewlines),
            accessToken: streamingAccessToken.trimmingCharacters(in: .whitespacesAndNewlines),
            resourceID: streamingResourceID.trimmingCharacters(in: .whitespacesAndNewlines),
            userID: streamingUserID.trimmingCharacters(in: .whitespacesAndNewlines),
            language: streamingLanguage.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                ? nil
                : streamingLanguage.trimmingCharacters(in: .whitespacesAndNewlines)
        )
    }

    var memoConfig: DoubaoMemoConfig {
        DoubaoMemoConfig(
            submitURL: memoSubmitURL.trimmingCharacters(in: .whitespacesAndNewlines),
            queryURL: memoQueryURL.trimmingCharacters(in: .whitespacesAndNewlines),
            appID: memoAppID.trimmingCharacters(in: .whitespacesAndNewlines),
            accessToken: memoAccessToken.trimmingCharacters(in: .whitespacesAndNewlines),
            resourceID: memoResourceID.trimmingCharacters(in: .whitespacesAndNewlines)
        )
    }

    var objectStorageConfig: MeetingObjectStorageConfig {
        MeetingObjectStorageConfig(
            stsURL: objectStorageSTSURL.trimmingCharacters(in: .whitespacesAndNewlines),
            stsBearerToken: objectStorageSTSBearerToken.trimmingCharacters(in: .whitespacesAndNewlines),
            accessKeyID: objectStorageAccessKeyID.trimmingCharacters(in: .whitespacesAndNewlines),
            secretAccessKey: objectStorageSecretAccessKey.trimmingCharacters(in: .whitespacesAndNewlines),
            sessionToken: objectStorageSessionToken.trimmingCharacters(in: .whitespacesAndNewlines),
            bucket: objectStorageBucket.trimmingCharacters(in: .whitespacesAndNewlines),
            region: objectStorageRegion.trimmingCharacters(in: .whitespacesAndNewlines),
            endpoint: objectStorageEndpoint.trimmingCharacters(in: .whitespacesAndNewlines),
            keyPrefix: objectStorageKeyPrefix.trimmingCharacters(in: CharacterSet(charactersIn: "/ \n\t"))
        )
    }

    var agentModelConfig: MeetingAgentModelConfig {
        MeetingAgentModelConfig(
            baseURL: agentBaseURL.trimmingCharacters(in: .whitespacesAndNewlines),
            apiKey: agentAPIKey.trimmingCharacters(in: .whitespacesAndNewlines),
            model: agentModel.trimmingCharacters(in: .whitespacesAndNewlines),
            temperature: agentTemperature,
            systemPrompt: agentSystemPrompt
        )
    }

    var maxVisibleViewpoints: Int {
        min(max(agentMaxVisibleViewpoints, 2), 5)
    }
}
