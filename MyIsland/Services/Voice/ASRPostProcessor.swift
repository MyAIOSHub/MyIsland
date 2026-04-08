//
//  ASRPostProcessor.swift
//  MyIsland
//
//  ASR + LLM post-processing via Dashscope (百炼) Qwen API.
//  - ASR: qwen3-asr-flash (audio → text)
//  - LLM: qwen-plus (text cleanup per mode prompt)
//

import AppKit
import Combine
import Foundation
import os.log

private let logger = Logger(subsystem: "com.myisland", category: "ASR")

// MARK: - ASR Processing Mode

enum ASRMode: String, CaseIterable, Codable {
    case fast     // 极速 — Apple ASR, no post-processing
    case saving   // 省钱 — saving prompt
    case pua      // PUA  — aggressive correction prompt
    case general  // 通用 — standard cleanup prompt

    var displayName: String {
        switch self {
        case .fast:    return "极速"
        case .saving:  return "省钱"
        case .pua:     return "PUA"
        case .general: return "通用"
        }
    }

    var icon: String {
        switch self {
        case .fast:    return "bolt.fill"
        case .saving:  return "leaf.fill"
        case .pua:     return "flame.fill"
        case .general: return "text.bubble.fill"
        }
    }

    /// Python prompt module name for loading prompts
    var promptModule: String {
        switch self {
        case .fast:    return ""
        case .saving:  return "v4_cn_saving"
        case .pua:     return "v4_cn_pua"
        case .general: return "v4_cn"
        }
    }
}

// MARK: - ASR Post Processor

@MainActor
final class ASRPostProcessor: ObservableObject {
    static let shared = ASRPostProcessor()

    @Published var selectedMode: ASRMode {
        didSet {
            UserDefaults.standard.set(selectedMode.rawValue, forKey: "asrProcessingMode")
        }
    }

    // API config (OpenAI-compatible format)
    @Published var apiKey: String {
        didSet { UserDefaults.standard.set(apiKey, forKey: "dashscopeApiKey") }
    }
    @Published var baseURL: String {
        didSet { UserDefaults.standard.set(baseURL, forKey: "dashscopeBaseURL") }
    }

    private let asrModel = "qwen3-asr-flash"
    private let llmModel = "Qwen3.5-Flash"

    /// Default base URL for Dashscope
    static let defaultBaseURL = "https://dashscope.aliyuncs.com/compatible-mode/v1"

    /// Whether API key is configured
    var hasApiKey: Bool { !apiKey.isEmpty }

    /// Resolved chat completions endpoint
    private var chatEndpoint: String {
        let base = baseURL.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        return "\(base)/chat/completions"
    }

    // Prompt cache
    private var promptCache: [String: String] = [:]
    private let promptDir: String

    private init() {
        let saved = UserDefaults.standard.string(forKey: "asrProcessingMode") ?? ""
        self.selectedMode = ASRMode(rawValue: saved) ?? .general
        self.apiKey = UserDefaults.standard.string(forKey: "dashscopeApiKey") ?? ""
        self.baseURL = UserDefaults.standard.string(forKey: "dashscopeBaseURL") ?? Self.defaultBaseURL
        self.promptDir = NSString(string: "~/Documents/GitHub/AIChatmode").expandingTildeInPath
    }

    // MARK: - Mode Resolution

    func resolveMode(for app: NSRunningApplication?) -> ASRMode {
        return selectedMode
    }

    static func defaultMode(for app: NSRunningApplication?) -> ASRMode {
        guard let bundleId = app?.bundleIdentifier else { return .general }
        if TerminalAppRegistry.isTerminalBundle(bundleId) {
            return .fast
        }
        return .general
    }

    // MARK: - Full Processing Pipeline

    /// Process recorded audio: ASR → LLM post-processing → result text
    func process(audioData: Data, mode: ASRMode) async -> String {
        guard mode != .fast else { return "" }

        logger.info("[ASR] Starting pipeline, mode: \(mode.rawValue, privacy: .public), audio: \(audioData.count) bytes")

        do {
            // Step 1: ASR — audio to text
            let asrText = try await transcribe(audioData: audioData)
            logger.info("[ASR] Transcription: '\(asrText, privacy: .public)'")

            guard !asrText.isEmpty else {
                logger.warning("[ASR] Empty transcription")
                return ""
            }

            // Step 2: LLM post-processing
            let processed = try await postProcess(text: asrText, mode: mode)
            logger.info("[ASR] Post-processed: '\(processed, privacy: .public)'")
            return processed.isEmpty ? asrText : processed

        } catch {
            logger.error("[ASR] Pipeline failed: \(error.localizedDescription, privacy: .public)")
            return ""
        }
    }

    // MARK: - Step 1: ASR via qwen3-asr-flash

    private func transcribe(audioData: Data) async throws -> String {
        let base64Audio = audioData.base64EncodedString()
        let dataURI = "data:audio/wav;base64,\(base64Audio)"

        let payload: [String: Any] = [
            "model": asrModel,
            "messages": [
                [
                    "role": "user",
                    "content": [
                        [
                            "type": "input_audio",
                            "input_audio": ["data": dataURI]
                        ]
                    ]
                ]
            ]
        ]

        let result = try await callAPI(payload: payload)
        return result
    }

    // MARK: - Step 2: LLM Post-Processing via qwen-plus

    private func postProcess(text: String, mode: ASRMode) async throws -> String {
        let systemPrompt = loadPrompt(for: mode, textLength: detectLength(text))

        let payload: [String: Any] = [
            "model": llmModel,
            "enable_thinking": false,
            "messages": [
                ["role": "system", "content": systemPrompt],
                ["role": "user", "content": "<asr_text>\n\(text)\n</asr_text>"]
            ]
        ]

        return try await callAPI(payload: payload)
    }

    // MARK: - API Call

    private func callAPI(payload: [String: Any]) async throws -> String {
        guard let url = URL(string: chatEndpoint) else {
            throw ASRError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 60
        request.httpBody = try JSONSerialization.data(withJSONObject: payload)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw ASRError.invalidResponse
        }

        guard httpResponse.statusCode == 200 else {
            let body = String(data: data, encoding: .utf8) ?? ""
            logger.error("[ASR] API error \(httpResponse.statusCode): \(body, privacy: .public)")
            throw ASRError.apiError(httpResponse.statusCode, body)
        }

        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let choices = json["choices"] as? [[String: Any]],
              let first = choices.first,
              let message = first["message"] as? [String: Any],
              let content = message["content"] as? String else {
            throw ASRError.invalidOutput
        }

        return content.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - Prompt Loading

    private func detectLength(_ text: String) -> String {
        let cjkCount = text.unicodeScalars.filter { $0.value >= 0x4E00 && $0.value <= 0x9FFF }.count
        let total = cjkCount + max(0, text.split(separator: " ").count - cjkCount)
        if total <= 20 { return "short" }
        if total <= 50 { return "medium" }
        return "long"
    }

    private func loadPrompt(for mode: ASRMode, textLength: String) -> String {
        let cacheKey = "\(mode.rawValue)_\(textLength)"
        if let cached = promptCache[cacheKey] {
            return cached
        }

        // Call python to generate prompt
        let moduleName = mode.promptModule
        let script = """
        import sys
        sys.path.insert(0, '\(promptDir)')
        import \(moduleName) as m
        print(m.build_prompt('\(textLength)'))
        """

        let process = Process()
        let pipe = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/python3")
        process.arguments = ["-c", script]
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice

        do {
            try process.run()
            process.waitUntilExit()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            if let prompt = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
               !prompt.isEmpty {
                promptCache[cacheKey] = prompt
                return prompt
            }
        } catch {
            logger.error("[ASR] Failed to load prompt: \(error.localizedDescription, privacy: .public)")
        }

        // Fallback: simple prompt
        return "你是一个ASR后处理助手。请修正以下语音转文字的错误，输出修正后的文本。"
    }
}

// MARK: - Errors

enum ASRError: LocalizedError {
    case invalidURL
    case invalidResponse
    case invalidOutput
    case apiError(Int, String)
    case scriptFailed(Int)

    var errorDescription: String? {
        switch self {
        case .invalidURL: return "Invalid API URL"
        case .invalidResponse: return "Invalid API response"
        case .invalidOutput: return "Invalid output from API"
        case .apiError(let code, let msg): return "API error \(code): \(msg)"
        case .scriptFailed(let code): return "Script failed with exit code \(code)"
        }
    }
}
