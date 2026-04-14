import Foundation

enum MeetingMarkdownRenderer {
    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        formatter.locale = Locale(identifier: "zh_CN")
        return formatter
    }()

    static func render(record: MeetingRecord, installedSkills: [MeetingSkillInstall]) -> String {
        let skillNameMap = Dictionary(uniqueKeysWithValues: installedSkills.map { ($0.id, $0.displayName) })
        let selectedSkillNames = displayNames(for: record.selectedSkillIDs, skillNameMap: skillNameMap)
        let recommendedSkillNames = displayNames(for: record.autoRecommendedSkillIDs, skillNameMap: skillNameMap)
        let transcript = canonicalTranscript(from: record.transcript)
        let speakerDisplayMap = MeetingSpeakerLabelResolver.displayMap(
            transcript: transcript,
            speakerSpans: record.speakerSpans
        )

        var lines: [String] = []
        lines.append("# \(record.topic)")
        lines.append("")
        lines.append("- Meeting ID: \(record.id)")
        lines.append("- 开始时间: \(dateFormatter.string(from: record.createdAt))")
        lines.append("- 结束时间: \(record.endedAt.map { dateFormatter.string(from: $0) } ?? "进行中")")
        if let scheduledAt = record.scheduledAt {
            lines.append("- 预约时间: \(dateFormatter.string(from: scheduledAt))")
            lines.append("- 预约时长: \(record.durationMinutes) 分钟")
            lines.append("- 日历同步: \(record.calendarSyncState.displayName)")
        }
        lines.append("- 已选 Skills: \(selectedSkillNames.isEmpty ? "无" : selectedSkillNames.joined(separator: ", "))")
        lines.append("- 自动推荐 Skills: \(recommendedSkillNames.isEmpty ? "无" : recommendedSkillNames.joined(separator: ", "))")
        lines.append("")
        if let sourceMediaRelativePath = record.sourceMediaRelativePath,
           let sourceMediaKind = record.sourceMediaKind {
            lines.append("## 导入媒体")
            lines.append("- 类型: \(sourceMediaKind.displayName)")
            lines.append("- 文件: \(record.sourceMediaDisplayName ?? URL(fileURLWithPath: sourceMediaRelativePath).lastPathComponent)")
            if let audioRelativePath = record.audioRelativePath,
               audioRelativePath != sourceMediaRelativePath {
                lines.append("- 转录音频: \(URL(fileURLWithPath: audioRelativePath).lastPathComponent)")
            }
            lines.append("")
        }
        lines.append("## 重点关注")
        appendAnnotations(
            record.focusAnnotations.sorted { $0.timecodeMs < $1.timecodeMs },
            transcript: record.transcript,
            emptyText: "暂无重点关注",
            lines: &lines
        )

        lines.append("")
        lines.append("## 会议笔记")
        appendAnnotations(
            record.noteAnnotations.sorted { $0.timecodeMs < $1.timecodeMs },
            transcript: record.transcript,
            emptyText: "暂无会议笔记",
            lines: &lines
        )

        lines.append("")
        lines.append("## 实时转写")
        if transcript.isEmpty {
            lines.append("暂无实时转写")
        } else {
            for segment in transcript {
                let speaker = MeetingSpeakerLabelResolver.displayName(
                    for: segment.speakerLabel,
                    mapping: speakerDisplayMap
                )
                lines.append("[\(timestamp(segment.startTimeMs))][\(speaker)] \(segment.text)")
            }
        }

        lines.append("")
        lines.append("## 思考记录")
        if record.adviceCards.isEmpty {
            lines.append("暂无思考记录")
        } else {
            for card in record.adviceCards.sorted(by: { $0.createdAt < $1.createdAt }) {
                lines.append("### \(dateFormatter.string(from: card.createdAt)) · \(card.title)")
                lines.append(card.body)
                appendStructuredAdvice(card, into: &lines)
                appendSkillLine(card.skillIDs, skillNameMap: skillNameMap, into: &lines)
                lines.append("")
            }
            if lines.last == "" {
                lines.removeLast()
            }
        }

        lines.append("")
        lines.append("## 会后总结")
        if let summary = record.summaryBundle {
            if summary.fullSummary.isEmpty {
                lines.append("暂无会后总结")
            } else {
                lines.append(summary.fullSummary)
            }

            if !summary.chapterSummaries.isEmpty {
                lines.append("")
                lines.append("### 章节总结")
                for chapter in summary.chapterSummaries {
                    lines.append("- \(chapter.title)：\(chapter.summary)")
                }
            }

            if !summary.actionItems.isEmpty {
                lines.append("")
                lines.append("### 待办提取")
                for item in summary.actionItems {
                    let meta = [item.owner, item.dueDate].compactMap { $0 }.joined(separator: " · ")
                    lines.append(meta.isEmpty ? "- \(item.task)" : "- \(item.task)（\(meta)）")
                }
            }

            if !summary.qaPairs.isEmpty {
                lines.append("")
                lines.append("### 问答提取")
                for pair in summary.qaPairs {
                    lines.append("- Q: \(pair.question)")
                    lines.append("  A: \(pair.answer)")
                }
            }

            if !summary.processHighlights.isEmpty {
                lines.append("")
                lines.append("### 流程提取")
                for highlight in summary.processHighlights {
                    lines.append("- \(highlight)")
                }
            }
        } else {
            lines.append("暂无会后总结")
        }

        if !record.postMeetingAdviceCards.isEmpty {
            lines.append("")
            lines.append("### 会后讨论建议")
            for card in record.postMeetingAdviceCards.sorted(by: { $0.createdAt < $1.createdAt }) {
                lines.append("#### \(card.title)")
                lines.append(card.body)
                appendStructuredAdvice(card, into: &lines)
                appendSkillLine(card.skillIDs, skillNameMap: skillNameMap, into: &lines)
                lines.append("")
            }
            if lines.last == "" {
                lines.removeLast()
            }
        }

        return lines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines) + "\n"
    }

    static func canonicalTranscript(from transcript: [TranscriptSegment]) -> [TranscriptSegment] {
        var byID: [String: TranscriptSegment] = [:]
        for segment in transcript {
            guard !segment.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { continue }
            if let existing = byID[segment.id] {
                byID[segment.id] = prefer(segment, over: existing)
            } else {
                byID[segment.id] = segment
            }
        }

        return byID.values.sorted {
            if $0.startTimeMs == $1.startTimeMs {
                return $0.id < $1.id
            }
            return $0.startTimeMs < $1.startTimeMs
        }
    }

    private static func prefer(_ candidate: TranscriptSegment, over existing: TranscriptSegment) -> TranscriptSegment {
        if candidate.isFinal != existing.isFinal {
            return candidate.isFinal ? candidate : existing
        }
        if candidate.endTimeMs != existing.endTimeMs {
            return candidate.endTimeMs > existing.endTimeMs ? candidate : existing
        }
        return candidate.text.count >= existing.text.count ? candidate : existing
    }

    private static func appendStructuredAdvice(_ card: MeetingAdviceCard, into lines: inout [String]) {
        if let meetingTheme = card.meetingTheme {
            lines.append("- topic_taxonomy: \(meetingTheme.rawValue)")
        }
        if let currentSubtask = card.currentSubtask {
            lines.append("- current_subtask: \(currentSubtask.rawValue)")
        }
        if let agoraRoom = card.agoraRoom {
            lines.append("- agora_room: \(agoraRoom.rawValue)")
        }
        if let routingWhy = card.routingWhy, !routingWhy.isEmpty {
            lines.append("- route_why: \(routingWhy)")
        }
        if !card.viewpoints.isEmpty {
            lines.append("- viewpoints:")
            for viewpoint in card.viewpoints {
                lines.append("#### \(viewpoint.stance) · \(viewpoint.subagentName.rawValue)")
                lines.append("- 核心观点：\(viewpoint.corePoint)")
                lines.append("- 质疑点：\(viewpoint.challenge)")
                lines.append("- 缺失证据：\(viewpoint.evidenceNeeded)")
                lines.append("- 建议追问：\(viewpoint.followUpLine)")
                if !viewpoint.skillIDs.isEmpty {
                    lines.append("- subagent_skills: \(viewpoint.skillIDs.joined(separator: ", "))")
                }
            }
        }
        if let supervisorSummary = card.supervisorSummary {
            lines.append("- 关键缺口：\(supervisorSummary.keyGap)")
            lines.append("- 被忽略的问题：\(supervisorSummary.ignoredQuestion)")
            lines.append("- 最值得追问：\(supervisorSummary.bestFollowUpLine)")
            lines.append("- 下一步动作：\(supervisorSummary.nextAction)")
        }
        if let coreJudgment = card.coreJudgment, !coreJudgment.isEmpty {
            lines.append("- 核心判断：\(coreJudgment)")
        }
        if let blindSpot = card.blindSpot, !blindSpot.isEmpty {
            lines.append("- 被忽略的问题：\(blindSpot)")
        }
        if let nextStep = card.nextStep, !nextStep.isEmpty {
            lines.append("- 下一步建议：\(nextStep)")
        }
    }

    private static func appendSkillLine(_ skillIDs: [String], skillNameMap: [String: String], into lines: inout [String]) {
        let names = displayNames(for: skillIDs, skillNameMap: skillNameMap)
        if !names.isEmpty {
            lines.append("- 采用视角：\(names.joined(separator: ", "))")
        }
    }

    private static func appendAnnotations(
        _ annotations: [MeetingAnnotation],
        transcript: [TranscriptSegment],
        emptyText: String,
        lines: inout [String]
    ) {
        guard !annotations.isEmpty else {
            lines.append(emptyText)
            return
        }

        for annotation in annotations {
            let titleText = annotation.effectiveText.replacingOccurrences(of: "\n", with: " / ")
            if annotation.isTranscriptComment {
                lines.append("- [\(timestamp(annotation.timecodeMs))][\(annotation.source.displayName)] \(titleText)")
                if let quoteContext = annotation.quoteContext(in: transcript, maxCharacters: 220) {
                    lines.append("  > \(quoteContext.inlineText)")
                }
            } else {
                lines.append("- [\(timestamp(annotation.timecodeMs))][\(annotation.source.displayName)] \(titleText)")
            }

            for attachment in annotation.attachments {
                lines.append("")
                lines.append("### 附件 · \(timestamp(annotation.timecodeMs)) · \(attachment.displayName)")
                lines.append("- 类型：\(attachment.kind.displayName)")
                lines.append("- 原文件：\(attachment.relativePath)")
                lines.append("")

                let markdown = attachment.extractedMarkdown.trimmingCharacters(in: .whitespacesAndNewlines)
                if markdown.isEmpty {
                    lines.append("> 附件暂无可用 Markdown 内容")
                } else {
                    lines.append(markdown)
                }
                lines.append("")
            }
        }
    }

    private static func displayNames(for ids: [String], skillNameMap: [String: String]) -> [String] {
        ids.map { skillNameMap[$0] ?? $0 }
    }

    private static func timestamp(_ milliseconds: Int) -> String {
        let totalSeconds = max(0, milliseconds / 1000)
        return String(format: "%02d:%02d", totalSeconds / 60, totalSeconds % 60)
    }
}
