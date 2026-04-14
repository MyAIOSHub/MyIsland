import Foundation

actor MeetingOpenAIModelClient {
    static let shared = MeetingOpenAIModelClient()

    enum ClientError: LocalizedError {
        case invalidURL
        case invalidResponse
        case apiError(Int, String)
        case missingContent

        var errorDescription: String? {
            switch self {
            case .invalidURL:
                return "会议 Agent 模型地址无效。"
            case .invalidResponse:
                return "会议 Agent 返回无效响应。"
            case .apiError(let status, let message):
                return "会议 Agent 请求失败（\(status)）：\(message)"
            case .missingContent:
                return "会议 Agent 没有返回内容。"
            }
        }
    }

    func complete(
        messages: [[String: Any]],
        config: MeetingAgentModelConfig,
        responseFormat: [String: Any]? = nil
    ) async throws -> String {
        guard let url = URL(string: normalizedChatCompletionsURL(baseURL: config.baseURL)) else {
            throw ClientError.invalidURL
        }

        var payload: [String: Any] = [
            "model": config.model,
            "temperature": config.temperature,
            "messages": messages
        ]
        if let responseFormat {
            payload["response_format"] = responseFormat
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(config.apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 90
        request.httpBody = try JSONSerialization.data(withJSONObject: payload)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw ClientError.invalidResponse
        }
        guard http.statusCode == 200 else {
            let body = String(decoding: data, as: UTF8.self)
            throw ClientError.apiError(http.statusCode, body)
        }

        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let choices = json["choices"] as? [[String: Any]],
              let firstChoice = choices.first,
              let message = firstChoice["message"] as? [String: Any] else {
            throw ClientError.invalidResponse
        }

        if let content = message["content"] as? String, !content.isEmpty {
            return content.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        if let contentParts = message["content"] as? [[String: Any]] {
            let text = contentParts.compactMap { $0["text"] as? String }.joined(separator: "\n")
            if !text.isEmpty {
                return text.trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }

        throw ClientError.missingContent
    }

    private func normalizedChatCompletionsURL(baseURL: String) -> String {
        let trimmed = baseURL.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        if trimmed.hasSuffix("/chat/completions") {
            return trimmed
        }
        return trimmed + "/chat/completions"
    }
}
