import Foundation

enum MeetingAutoTitleBuilder {
    private static let genericChapterTitles: Set<String> = [
        "背景",
        "现状",
        "讨论",
        "总结",
        "摘要",
        "行动",
        "行动项",
        "待办",
        "结论",
        "下一步",
        "问题"
    ]

    static func buildTitle(for record: MeetingRecord) -> String {
        "\(buildSubject(for: record)) \(formattedDate(from: record.createdAt))"
    }

    private static func buildSubject(for record: MeetingRecord) -> String {
        if let chapterTitle = record.summaryBundle?.chapterSummaries
            .lazy
            .compactMap({ normalizedChapterTitle($0.title) })
            .first {
            return chapterTitle
        }

        let fallbackSources = [
            record.summaryBundle?.fullSummary,
            record.summaryBundle?.processHighlights.joined(separator: " "),
            record.transcript.first(where: { !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty })?.text
        ]

        for source in fallbackSources {
            if let source, let normalized = normalizedSummarySubject(source) {
                return normalized
            }
        }

        return "会议纪要"
    }

    private static func normalizedChapterTitle(_ rawValue: String) -> String? {
        guard let cleaned = normalizeCandidate(rawValue), !genericChapterTitles.contains(cleaned) else {
            return nil
        }
        return cleaned
    }

    private static func normalizedSummarySubject(_ rawValue: String) -> String? {
        guard var cleaned = normalizeCandidate(rawValue) else { return nil }

        let prefixes = [
            "本次会议围绕",
            "本次会议聚焦",
            "会议围绕",
            "会议聚焦",
            "会议讨论了",
            "会议讨论",
            "会议明确了",
            "主要讨论",
            "重点讨论",
            "围绕",
            "聚焦",
            "关于"
        ]
        for prefix in prefixes where cleaned.hasPrefix(prefix) {
            cleaned.removeFirst(prefix.count)
            cleaned = cleaned.trimmingCharacters(in: .whitespacesAndNewlines)
            break
        }

        let clauseTerminators = ["。", "！", "？", ".", "!", "?", "\n", "；", ";", "：", ":"]
        if let terminatorRange = clauseTerminators
            .compactMap({ cleaned.range(of: $0) })
            .min(by: { $0.lowerBound < $1.lowerBound }) {
            cleaned = String(cleaned[..<terminatorRange.lowerBound])
        }

        let suffixes = [
            "展开讨论",
            "进行了讨论",
            "进行讨论",
            "展开评估",
            "进行评估",
            "展开复盘",
            "进行复盘",
            "达成共识",
            "比较成本",
            "比较了成本",
            "比较了",
            "重点比较",
            "并比较",
            "并评估",
            "并讨论"
        ]
        for suffix in suffixes {
            if let range = cleaned.range(of: suffix) {
                cleaned = String(cleaned[..<range.lowerBound])
                break
            }
        }

        if cleaned.count > 14, let listSeparator = cleaned.firstIndex(of: "、") {
            cleaned = String(cleaned[..<listSeparator])
        }

        cleaned = cleaned.trimmingCharacters(in: CharacterSet(charactersIn: " ，、：:；;"))
        if cleaned.hasSuffix("的讨论") {
            cleaned.removeLast("的讨论".count)
        }
        cleaned = cleaned.trimmingCharacters(in: CharacterSet(charactersIn: " ，、：:；;"))

        if cleaned.count > 18 {
            cleaned = String(cleaned.prefix(18))
                .trimmingCharacters(in: CharacterSet(charactersIn: " ，、：:；;"))
        }

        return cleaned.isEmpty ? nil : cleaned
    }

    private static func normalizeCandidate(_ rawValue: String) -> String? {
        let cleaned = rawValue
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "\t", with: " ")
            .replacingOccurrences(of: "  ", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "-•*#[]()<>"))

        return cleaned.isEmpty ? nil : cleaned
    }

    private static func formattedDate(from date: Date) -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .autoupdatingCurrent
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }
}
