import Foundation

struct MeetingPostProcessingDependencies: Sendable {
    let ensureRemoteAudio: @Sendable (MeetingRecord, URL, MeetingObjectStorageConfig) async throws -> MeetingUploadedAudioAsset
    let buildRemoteAudioURL: @Sendable (String, MeetingObjectStorageConfig) async throws -> URL
    let submitMemo: @Sendable (URL, String, DoubaoMemoConfig, String) async throws -> String
    let pollMemo: @Sendable (String, DoubaoMemoConfig, String) async throws -> MeetingMemoArtifact
    let buildLocalSummary: @Sendable ([TranscriptSegment], String, MeetingAgentModelConfig) async throws -> MeetingSummaryBundle
    let buildPostMeetingAdvice: @Sendable (
        String,
        [TranscriptSegment],
        MeetingSummaryBundle?,
        [MeetingSkillInstall],
        [String],
        MeetingAgentModelConfig
    ) async -> [MeetingAdviceCard]

    static let live = MeetingPostProcessingDependencies(
        ensureRemoteAudio: { record, localAudioURL, config in
            try await MeetingObjectStorageClient.shared.uploadAudio(
                fileURL: localAudioURL,
                meetingID: record.id,
                meetingDate: record.createdAt,
                config: config
            )
        },
        buildRemoteAudioURL: { objectKey, config in
            try await MeetingObjectStorageClient.shared.presignedDownloadURL(
                objectKey: objectKey,
                config: config
            )
        },
        submitMemo: { audioURL, topic, config, meetingID in
            try await MeetingMemoClient.shared.submit(
                audioURL: audioURL,
                topic: topic,
                config: config,
                meetingID: meetingID
            ).taskID
        },
        pollMemo: { taskID, config, meetingID in
            try await MeetingMemoClient.shared.pollSummary(
                taskID: taskID,
                config: config,
                meetingID: meetingID
            )
        },
        buildLocalSummary: { transcript, topic, config in
            try await MeetingSummaryEngine.shared.buildSummary(transcript: transcript, topic: topic, config: config)
        },
        buildPostMeetingAdvice: { topic, transcript, summaryBundle, installedSkills, selectedSkillIDs, config in
            await MeetingAdviceEngine.generatePostMeetingAdviceCards(
                topic: topic,
                transcript: transcript,
                summaryBundle: summaryBundle,
                installedSkills: installedSkills,
                selectedSkillIDs: selectedSkillIDs,
                config: config
            )
        }
    )
}

@MainActor
final class MeetingPostProcessingEngine {
    static let shared = MeetingPostProcessingEngine(dependencies: .live)

    private let dependencies: MeetingPostProcessingDependencies

    init(dependencies: MeetingPostProcessingDependencies) {
        self.dependencies = dependencies
    }

    func process(
        record: MeetingRecord,
        localAudioURL: URL?,
        installedSkills: [MeetingSkillInstall],
        objectStorageConfig: MeetingObjectStorageConfig,
        memoConfig: DoubaoMemoConfig,
        agentConfig: MeetingAgentModelConfig,
        forceSummaryRefresh: Bool = false,
        forceTranscriptRefresh: Bool = false
    ) async -> MeetingRecord {
        var updated = record
        updated.lastError = nil

        if forceSummaryRefresh {
            updated.summaryBundle = nil
            updated.postMeetingAdviceCards = []
        }

        let remoteAudioURL = await ensureRemoteAudioBackup(
            updated: &updated,
            localAudioURL: localAudioURL,
            objectStorageConfig: objectStorageConfig
        )

        if memoConfig.isConfigured, let remoteAudioURL {
            await attemptMemo(
                updated: &updated,
                remoteAudioURL: remoteAudioURL,
                memoConfig: memoConfig,
                forceTranscriptRefresh: forceTranscriptRefresh
            )
        } else if memoConfig.isConfigured && remoteAudioURL == nil {
            if localAudioURL == nil {
                updated.notes.append("没有可用的本地录音文件或远端录音对象，已回退到本地总结。")
            } else {
                updated.notes.append("对象存储不可用，已回退到本地总结。")
            }
        }

        if requiresImportedTranscript(updated), updated.transcript.isEmpty {
            let errorMessage = "离线转录不可用，未能从导入媒体生成逐句转写。"
            updated.lastError = errorMessage
            updated.notes.append(errorMessage)
            updated.state = .failed
            return updated
        }

        if isWeakMemoSummary(updated.summaryBundle, transcript: updated.transcript) {
            updated.notes.append("豆包妙记返回弱总结，已改用本地结构化总结补全。")
            updated.summaryBundle = nil
            await buildFallbackSummary(
                updated: &updated,
                agentConfig: agentConfig,
                preferredSource: "memo-lark+agent-fallback"
            )
        }

        if updated.summaryBundle == nil {
            await buildFallbackSummary(updated: &updated, agentConfig: agentConfig)
        }

        if let summaryBundle = updated.summaryBundle,
           !updated.annotations.isEmpty,
           agentConfig.isConfigured {
            do {
                updated.summaryBundle = try await MeetingSummaryEngine.shared.refineSummary(
                    record: updated,
                    summaryBundle: summaryBundle,
                    installedSkills: installedSkills,
                    selectedSkillIDs: updated.effectiveSkillIDs,
                    config: agentConfig
                )
            } catch {
                updated.notes.append("总结重点加权失败，保留原始总结：\(error.localizedDescription)")
            }
        }

        if !updated.isTopicUserProvided {
            updated.topic = MeetingAutoTitleBuilder.buildTitle(for: updated)
        }

        updated.postMeetingAdviceCards = await dependencies.buildPostMeetingAdvice(
            updated.topic,
            updated.transcript,
            updated.summaryBundle,
            installedSkills,
            updated.effectiveSkillIDs,
            agentConfig
        )
        updated.state = .completed
        return updated
    }

    private func ensureRemoteAudioBackup(
        updated: inout MeetingRecord,
        localAudioURL: URL,
        objectStorageConfig: MeetingObjectStorageConfig
    ) async -> URL? {
        guard objectStorageConfig.isConfigured else {
            return nil
        }

        do {
            if let objectKey = updated.uploadedAudioObjectKey, !objectKey.isEmpty {
                let remoteAudioURL = try await dependencies.buildRemoteAudioURL(objectKey, objectStorageConfig)
                updated.uploadedAudioRemoteURL = remoteAudioURL.absoluteString
                return remoteAudioURL
            }

            let asset = try await dependencies.ensureRemoteAudio(updated, localAudioURL, objectStorageConfig)
            updated.uploadedAudioObjectKey = asset.objectKey
            updated.uploadedAudioRemoteURL = asset.downloadURL.absoluteString
            return asset.downloadURL
        } catch {
            updated.notes.append("对象存储上传失败，保留本地录音：\(error.localizedDescription)")
            return nil
        }
    }

    private func ensureRemoteAudioBackup(
        updated: inout MeetingRecord,
        localAudioURL: URL?,
        objectStorageConfig: MeetingObjectStorageConfig,
    ) async -> URL? {
        guard objectStorageConfig.isConfigured else {
            return nil
        }

        if let localAudioURL {
            return await ensureRemoteAudioBackup(
                updated: &updated,
                localAudioURL: localAudioURL,
                objectStorageConfig: objectStorageConfig
            )
        }

        if let objectKey = updated.uploadedAudioObjectKey, !objectKey.isEmpty {
            do {
                let remoteAudioURL = try await dependencies.buildRemoteAudioURL(objectKey, objectStorageConfig)
                updated.uploadedAudioRemoteURL = remoteAudioURL.absoluteString
                return remoteAudioURL
            } catch {
                updated.notes.append("对象存储音频链接恢复失败：\(error.localizedDescription)")
            }
        }

        return nil
    }

    private func attemptMemo(
        updated: inout MeetingRecord,
        remoteAudioURL: URL,
        memoConfig: DoubaoMemoConfig,
        forceTranscriptRefresh: Bool
    ) async {
        do {
            let taskID = try await dependencies.submitMemo(remoteAudioURL, updated.topic, memoConfig, updated.id)
            let artifact = try await dependencies.pollMemo(taskID, memoConfig, updated.id)
            if !artifact.diagnosticNotes.isEmpty {
                updated.notes.append(contentsOf: artifact.diagnosticNotes)
            }
            if !artifact.transcriptSegments.isEmpty && (updated.transcript.isEmpty || forceTranscriptRefresh) {
                updated.transcript = MeetingMarkdownRenderer.canonicalTranscript(from: artifact.transcriptSegments)
            }
            if !artifact.speakerSpans.isEmpty && (updated.speakerSpans.isEmpty || forceTranscriptRefresh) {
                updated.speakerSpans = artifact.speakerSpans.sorted { lhs, rhs in
                    if lhs.startTimeMs == rhs.startTimeMs {
                        return lhs.endTimeMs < rhs.endTimeMs
                    }
                    return lhs.startTimeMs < rhs.startTimeMs
                }
            }
            if !artifact.summaryBundle.fullSummary.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                || !artifact.summaryBundle.chapterSummaries.isEmpty
                || !artifact.summaryBundle.actionItems.isEmpty
                || !artifact.summaryBundle.qaPairs.isEmpty
                || !artifact.summaryBundle.processHighlights.isEmpty {
                updated.summaryBundle = artifact.summaryBundle
            }
        } catch {
            updated.notes.append("豆包妙记失败，已回退到本地总结：\(error.localizedDescription)")
        }
    }

    private func requiresImportedTranscript(_ record: MeetingRecord) -> Bool {
        record.sourceMediaRelativePath?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
    }

    private func buildFallbackSummary(
        updated: inout MeetingRecord,
        agentConfig: MeetingAgentModelConfig,
        preferredSource: String? = nil
    ) async {
        if agentConfig.isConfigured, !updated.transcript.isEmpty {
            do {
                var summaryBundle = try await dependencies.buildLocalSummary(updated.transcript, updated.topic, agentConfig)
                if let preferredSource {
                    summaryBundle.source = preferredSource
                }
                updated.summaryBundle = summaryBundle
                return
            } catch {
                updated.notes.append("本地总结失败，已回退到 transcript 拼接：\(error.localizedDescription)")
            }
        }

        updated.summaryBundle = MeetingSummaryBundle(
            fullSummary: updated.transcript.map(\.text).joined(separator: " "),
            source: "local-transcript"
        )
    }

    private func isWeakMemoSummary(
        _ summaryBundle: MeetingSummaryBundle?,
        transcript: [TranscriptSegment]
    ) -> Bool {
        guard let summaryBundle, summaryBundle.source == "memo-lark" else {
            return false
        }
        guard summaryBundle.chapterSummaries.isEmpty,
              summaryBundle.actionItems.isEmpty,
              summaryBundle.qaPairs.isEmpty,
              summaryBundle.processHighlights.isEmpty else {
            return false
        }

        let normalizedSummary = normalizedWeakSummary(summaryBundle.fullSummary)
        if normalizedSummary.isEmpty {
            return true
        }

        let transcriptFallback = normalizedWeakSummary(
            String(transcript.map(\.text).prefix(6).joined(separator: " ").prefix(400))
        )
        return !transcriptFallback.isEmpty && normalizedSummary == transcriptFallback
    }

    private func normalizedWeakSummary(_ text: String) -> String {
        text
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }
}
