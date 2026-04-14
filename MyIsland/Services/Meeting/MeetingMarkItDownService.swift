import Foundation

enum MeetingMarkItDownError: LocalizedError {
    case pythonUnavailable
    case unsupportedPythonVersion(String)
    case missingOutput(URL)
    case unreadableOutput(URL)

    var errorDescription: String? {
        switch self {
        case .pythonUnavailable:
            return "未找到 Python 3.10+，无法安装 MarkItDown。"
        case .unsupportedPythonVersion(let version):
            return "检测到 Python 版本 \(version)，但 MarkItDown 需要 Python 3.10+。"
        case .missingOutput(let url):
            return "MarkItDown 没有生成输出文件：\(url.lastPathComponent)"
        case .unreadableOutput(let url):
            return "无法读取 MarkItDown 输出：\(url.lastPathComponent)"
        }
    }
}

actor MeetingMarkItDownService {
    static let shared = MeetingMarkItDownService()

    private let fileManager: FileManager
    private let processExecutor: ProcessExecuting
    nonisolated let toolsDirectoryURL: URL

    init(
        fileManager: FileManager = .default,
        processExecutor: ProcessExecuting = ProcessExecutor.shared,
        toolsDirectoryURL: URL? = nil
    ) {
        self.fileManager = fileManager
        self.processExecutor = processExecutor
        self.toolsDirectoryURL = toolsDirectoryURL ?? Self.defaultToolsDirectoryURL(fileManager: fileManager)
    }

    nonisolated static func defaultToolsDirectoryURL(fileManager: FileManager = .default) -> URL {
        let bundleIdentifier = Bundle.main.bundleIdentifier ?? "app.myisland.macos"
        let supportURL = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory())
        return supportURL
            .appendingPathComponent(bundleIdentifier, isDirectory: true)
            .appendingPathComponent("Tools", isDirectory: true)
    }

    func convert(fileURL: URL) async throws -> String {
        let executableURL = try await ensureExecutable()
        let outputURL = toolsDirectoryURL.appendingPathComponent("markitdown-\(UUID().uuidString).md")
        defer {
            try? fileManager.removeItem(at: outputURL)
        }

        // Source: https://github.com/microsoft/markitdown#command-line
        // README documents `markitdown input -o output.md` and requires Python 3.10+.
        _ = try await processExecutor.run(
            executableURL.path,
            arguments: [fileURL.path, "-o", outputURL.path]
        )

        guard fileManager.fileExists(atPath: outputURL.path) else {
            throw MeetingMarkItDownError.missingOutput(outputURL)
        }
        let markdown = try String(contentsOf: outputURL, encoding: .utf8)
        return markdown.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func ensureExecutable() async throws -> URL {
        let executableURL = markItDownExecutableURL
        if fileManager.fileExists(atPath: executableURL.path) {
            return executableURL
        }
        return try await bootstrapExecutable()
    }

    private var markItDownExecutableURL: URL {
        toolsDirectoryURL
            .appendingPathComponent("markitdown-venv", isDirectory: true)
            .appendingPathComponent("bin", isDirectory: true)
            .appendingPathComponent("markitdown")
    }

    private var venvDirectoryURL: URL {
        toolsDirectoryURL.appendingPathComponent("markitdown-venv", isDirectory: true)
    }

    private func bootstrapExecutable() async throws -> URL {
        try fileManager.createDirectory(at: toolsDirectoryURL, withIntermediateDirectories: true)
        let pythonExecutable = try await resolvePythonExecutable()

        _ = try await processExecutor.run(
            pythonExecutable.path,
            arguments: ["-m", "venv", venvDirectoryURL.path]
        )

        let pipExecutableURL = venvDirectoryURL
            .appendingPathComponent("bin", isDirectory: true)
            .appendingPathComponent("pip")

        _ = try await processExecutor.run(
            pipExecutableURL.path,
            arguments: ["install", "--upgrade", "pip"]
        )
        _ = try await processExecutor.run(
            pipExecutableURL.path,
            arguments: ["install", "markitdown[pdf,docx,pptx,xlsx,xls]"]
        )

        let executableURL = markItDownExecutableURL
        guard fileManager.fileExists(atPath: executableURL.path) else {
            throw MeetingMarkItDownError.missingOutput(executableURL)
        }
        return executableURL
    }

    private func resolvePythonExecutable() async throws -> URL {
        for candidate in pythonCandidates {
            let result = await processExecutor.runWithResult(candidate.path, arguments: ["--version"])
            guard case .success(let processResult) = result else { continue }

            let versionText = [processResult.output, processResult.stderr]
                .compactMap { $0 }
                .joined(separator: " ")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard let version = parsePythonVersion(versionText) else { continue }
            guard version.major > 3 || (version.major == 3 && version.minor >= 10) else {
                throw MeetingMarkItDownError.unsupportedPythonVersion(versionText)
            }
            return candidate
        }

        throw MeetingMarkItDownError.pythonUnavailable
    }

    private var pythonCandidates: [URL] {
        [
            "/opt/homebrew/bin/python3.12",
            "/opt/homebrew/bin/python3.11",
            "/opt/homebrew/bin/python3.10",
            "/usr/local/bin/python3.12",
            "/usr/local/bin/python3.11",
            "/usr/local/bin/python3.10",
            "/opt/homebrew/bin/python3",
            "/usr/local/bin/python3",
            "/usr/bin/python3"
        ].map { URL(fileURLWithPath: $0) }
    }

    private func parsePythonVersion(_ raw: String) -> (major: Int, minor: Int)? {
        let parts = raw.components(separatedBy: .whitespacesAndNewlines)
        guard let versionToken = parts.first(where: { $0.first?.isNumber == true }) else { return nil }
        let numbers = versionToken.split(separator: ".").compactMap { Int($0) }
        guard numbers.count >= 2 else { return nil }
        return (numbers[0], numbers[1])
    }
}
