import AVFoundation
import Foundation
import UniformTypeIdentifiers

struct MeetingImportedMediaAsset: Equatable, Sendable {
    let sourceMediaURL: URL
    let preparedAudioURL: URL
    let sourceKind: MeetingImportedMediaKind
    let displayName: String
    let durationSeconds: Double
}

actor MeetingImportedTranscriptPreparationService {
    static let shared = MeetingImportedTranscriptPreparationService()

    enum PreparationError: LocalizedError {
        case nonFileURL
        case unsupportedFileType(String)
        case unreadableMedia(String)
        case missingAudioTrack(String)
        case exportFailed(String)

        var errorDescription: String? {
            switch self {
            case .nonFileURL:
                return "只支持导入本地音频或视频文件。"
            case .unsupportedFileType(let name):
                return "暂不支持导入该文件类型：\(name)。"
            case .unreadableMedia(let name):
                return "无法读取导入媒体：\(name)。"
            case .missingAudioTrack(let name):
                return "导入的视频没有可用音轨：\(name)。"
        case .exportFailed(let message):
                return "准备离线转录音频失败：\(message)"
            }
        }
    }

    func prepareImport(from fileURL: URL, meetingID: String) async throws -> MeetingImportedMediaAsset {
        guard fileURL.isFileURL else {
            throw PreparationError.nonFileURL
        }

        switch try mediaKind(for: fileURL) {
        case .audio:
            return try await importAudio(from: fileURL, meetingID: meetingID)
        case .video:
            return try await importVideo(from: fileURL, meetingID: meetingID)
        }
    }

    func reprepareAudio(for record: MeetingRecord) async throws -> URL? {
        guard let sourceMediaRelativePath = record.sourceMediaRelativePath,
              let sourceKind = record.sourceMediaKind else {
            return nil
        }

        let sourceMediaURL = MeetingStorage.shared.absolutePath(for: sourceMediaRelativePath)
        guard FileManager.default.fileExists(atPath: sourceMediaURL.path) else {
            return nil
        }

        switch sourceKind {
        case .audio:
            return try await prepareAudioSource(from: sourceMediaURL, meetingID: record.id)
        case .video:
            return try await prepareVideoSource(from: sourceMediaURL, meetingID: record.id)
        }
    }

    private func importAudio(from fileURL: URL, meetingID: String) async throws -> MeetingImportedMediaAsset {
        let sourceMediaURL = try await MeetingStorage.shared.sourceMediaURL(
            for: meetingID,
            preferredFilename: fileURL.lastPathComponent
        )
        try copyReplacingItem(at: fileURL, to: sourceMediaURL)

        let preparedAudioURL = try await prepareAudioSource(from: sourceMediaURL, meetingID: meetingID)
        let asset = AVURLAsset(url: sourceMediaURL)
        let durationSeconds = try await resolvedDurationSeconds(for: asset, fallbackName: fileURL.lastPathComponent)

        return MeetingImportedMediaAsset(
            sourceMediaURL: sourceMediaURL,
            preparedAudioURL: preparedAudioURL,
            sourceKind: .audio,
            displayName: fileURL.lastPathComponent,
            durationSeconds: durationSeconds
        )
    }

    private func importVideo(from fileURL: URL, meetingID: String) async throws -> MeetingImportedMediaAsset {
        let sourceMediaURL = try await MeetingStorage.shared.sourceMediaURL(
            for: meetingID,
            preferredFilename: fileURL.lastPathComponent
        )
        try copyReplacingItem(at: fileURL, to: sourceMediaURL)

        let asset = AVURLAsset(url: sourceMediaURL)
        let audioTracks = try await asset.loadTracks(withMediaType: .audio)
        guard !audioTracks.isEmpty else {
            throw PreparationError.missingAudioTrack(fileURL.lastPathComponent)
        }

        let preparedAudioURL = try await prepareVideoSource(from: sourceMediaURL, meetingID: meetingID)

        let durationSeconds = try await resolvedDurationSeconds(for: asset, fallbackName: fileURL.lastPathComponent)

        return MeetingImportedMediaAsset(
            sourceMediaURL: sourceMediaURL,
            preparedAudioURL: preparedAudioURL,
            sourceKind: .video,
            displayName: fileURL.lastPathComponent,
            durationSeconds: durationSeconds
        )
    }

    private func mediaKind(for fileURL: URL) throws -> MeetingImportedMediaKind {
        if let contentType = UTType(filenameExtension: fileURL.pathExtension.lowercased()) {
            if contentType.conforms(to: .audio) {
                return .audio
            }
            if contentType.conforms(to: .movie) || contentType.conforms(to: .video) {
                return .video
            }
        }

        let videoExtensions: Set<String> = ["mov", "mp4", "m4v", "avi", "mkv", "webm"]
        if videoExtensions.contains(fileURL.pathExtension.lowercased()) {
            return .video
        }
        let audioExtensions: Set<String> = ["wav", "mp3", "m4a", "aac", "flac", "aiff", "caf", "ogg"]
        if audioExtensions.contains(fileURL.pathExtension.lowercased()) {
            return .audio
        }

        throw PreparationError.unsupportedFileType(fileURL.lastPathComponent)
    }

    private func prepareAudioSource(from sourceURL: URL, meetingID: String) async throws -> URL {
        let preparedAudioURL = try await MeetingStorage.shared.preparedAudioURL(for: meetingID, fileExtension: "wav")
        try removeItemIfExists(at: preparedAudioURL)
        try transcodeAudioToWAV(from: sourceURL, to: preparedAudioURL)
        return preparedAudioURL
    }

    private func prepareVideoSource(from sourceURL: URL, meetingID: String) async throws -> URL {
        let asset = AVURLAsset(url: sourceURL)
        let audioTracks = try await asset.loadTracks(withMediaType: .audio)
        guard !audioTracks.isEmpty else {
            throw PreparationError.missingAudioTrack(sourceURL.lastPathComponent)
        }

        let intermediateAudioURL = try await MeetingStorage.shared.preparedAudioURL(for: meetingID, fileExtension: "m4a")
        let preparedAudioURL = try await MeetingStorage.shared.preparedAudioURL(for: meetingID, fileExtension: "wav")
        try removeItemIfExists(at: intermediateAudioURL)
        try removeItemIfExists(at: preparedAudioURL)

        guard let exportSession = AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetAppleM4A) else {
            throw PreparationError.unreadableMedia(sourceURL.lastPathComponent)
        }
        exportSession.outputURL = intermediateAudioURL
        exportSession.outputFileType = .m4a
        exportSession.shouldOptimizeForNetworkUse = true

        do {
            try await exportAudio(with: exportSession)
            try transcodeAudioToWAV(from: intermediateAudioURL, to: preparedAudioURL)
        } catch {
            try? FileManager.default.removeItem(at: preparedAudioURL)
            throw error
        }

        try? FileManager.default.removeItem(at: intermediateAudioURL)
        return preparedAudioURL
    }

    private func copyReplacingItem(at sourceURL: URL, to destinationURL: URL) throws {
        if FileManager.default.fileExists(atPath: destinationURL.path) {
            try FileManager.default.removeItem(at: destinationURL)
        }
        try FileManager.default.copyItem(at: sourceURL, to: destinationURL)
    }

    private func removeItemIfExists(at url: URL) throws {
        if FileManager.default.fileExists(atPath: url.path) {
            try FileManager.default.removeItem(at: url)
        }
    }

    private func transcodeAudioToWAV(from sourceURL: URL, to destinationURL: URL) throws {
        let inputFile = try AVAudioFile(forReading: sourceURL, commonFormat: .pcmFormatInt16, interleaved: true)
        let inputFormat = inputFile.processingFormat
        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVSampleRateKey: inputFormat.sampleRate,
            AVNumberOfChannelsKey: Int(inputFormat.channelCount),
            AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsBigEndianKey: false,
            AVLinearPCMIsFloatKey: false,
            AVLinearPCMIsNonInterleaved: false
        ]
        let outputFile = try AVAudioFile(
            forWriting: destinationURL,
            settings: settings,
            commonFormat: .pcmFormatInt16,
            interleaved: true
        )
        let frameCapacity: AVAudioFrameCount = 8_192
        guard let buffer = AVAudioPCMBuffer(pcmFormat: inputFormat, frameCapacity: frameCapacity) else {
            throw PreparationError.exportFailed("无法创建转码缓冲区")
        }

        while true {
            try inputFile.read(into: buffer, frameCount: frameCapacity)
            if buffer.frameLength == 0 {
                break
            }
            try outputFile.write(from: buffer)
        }

        let fileSize = try destinationURL.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
        if fileSize <= 0 {
            throw PreparationError.exportFailed("转码后的 WAV 文件为空")
        }
    }

    private func resolvedDurationSeconds(for asset: AVURLAsset, fallbackName: String) async throws -> Double {
        let duration = try await asset.load(.duration)
        let seconds = CMTimeGetSeconds(duration)
        guard seconds.isFinite else {
            throw PreparationError.unreadableMedia(fallbackName)
        }
        return max(1, seconds)
    }

    private func exportAudio(with exportSession: AVAssetExportSession) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            exportSession.exportAsynchronously {
                switch exportSession.status {
                case .completed:
                    continuation.resume()
                case .failed:
                    continuation.resume(throwing: PreparationError.exportFailed(exportSession.error?.localizedDescription ?? "unknown"))
                case .cancelled:
                    continuation.resume(throwing: PreparationError.exportFailed("cancelled"))
                default:
                    continuation.resume(throwing: PreparationError.exportFailed(exportSession.error?.localizedDescription ?? "unknown"))
                }
            }
        }
    }
}
