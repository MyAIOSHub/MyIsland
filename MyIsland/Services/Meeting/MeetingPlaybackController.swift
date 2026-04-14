import AVFoundation
import Combine
import Foundation

struct MeetingPlayableAsset: Equatable, Sendable {
    enum Source: Equatable, Sendable {
        case localFile
        case remoteURL
    }

    let url: URL
    let source: Source

    static func resolve(
        for record: MeetingRecord,
        fileManager: FileManager = .default,
        resolveRelativePath: (String) -> URL = { MeetingStorage.shared.absolutePath(for: $0) }
    ) -> MeetingPlayableAsset? {
        if let audioRelativePath = record.audioRelativePath {
            let localURL = resolveRelativePath(audioRelativePath)
            if fileManager.fileExists(atPath: localURL.path) {
                return MeetingPlayableAsset(url: localURL, source: .localFile)
            }
        }

        if let remoteString = record.uploadedAudioRemoteURL,
           let remoteURL = URL(string: remoteString) {
            return MeetingPlayableAsset(url: remoteURL, source: .remoteURL)
        }

        return nil
    }
}

@MainActor
final class MeetingPlaybackController: ObservableObject {
    @Published private(set) var currentTime: Double = 0
    @Published private(set) var duration: Double = 0
    @Published private(set) var isPlaying = false
    @Published private(set) var errorMessage: String?
    @Published private(set) var asset: MeetingPlayableAsset?

    private var player: AVPlayer?
    private var timeObserverToken: Any?
    private var statusObservation: NSKeyValueObservation?
    private var timeControlObservation: NSKeyValueObservation?

    deinit {
        if let timeObserverToken, let player {
            player.removeTimeObserver(timeObserverToken)
        }
        statusObservation = nil
        timeControlObservation = nil
        player?.pause()
    }

    func load(record: MeetingRecord) {
        tearDownPlayer()

        guard let asset = MeetingPlayableAsset.resolve(for: record) else {
            self.asset = nil
            currentTime = 0
            duration = 0
            isPlaying = false
            errorMessage = "录音文件不可用"
            return
        }

        self.asset = asset
        errorMessage = nil
        currentTime = 0
        duration = 0
        isPlaying = false

        let player = AVPlayer(url: asset.url)
        self.player = player
        observe(player: player)
    }

    func togglePlayback() {
        guard let player else { return }
        if isPlaying {
            player.pause()
        } else {
            player.play()
        }
    }

    func seek(to seconds: Double) {
        guard let player else { return }
        let bounded = max(0, min(seconds, duration > 0 ? duration : seconds))
        let time = CMTime(seconds: bounded, preferredTimescale: 600)
        player.seek(to: time, toleranceBefore: .zero, toleranceAfter: .zero)
        currentTime = bounded
    }

    func skip(by delta: Double) {
        seek(to: currentTime + delta)
    }

    private func observe(player: AVPlayer) {
        let interval = CMTime(seconds: 0.25, preferredTimescale: 600)
        timeObserverToken = player.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak self] time in
            Task { @MainActor [weak self] in
                guard let self else { return }
                currentTime = max(0, time.seconds.isFinite ? time.seconds : 0)
                if let item = player.currentItem {
                    let durationSeconds = item.duration.seconds
                    if durationSeconds.isFinite && durationSeconds > 0 {
                        duration = durationSeconds
                    }
                }
            }
        }

        statusObservation = player.currentItem?.observe(\.status, options: [.initial, .new]) { [weak self] item, _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                switch item.status {
                case .readyToPlay:
                    errorMessage = nil
                    let durationSeconds = item.duration.seconds
                    if durationSeconds.isFinite && durationSeconds > 0 {
                        duration = durationSeconds
                    }
                case .failed:
                    errorMessage = item.error?.localizedDescription ?? "录音文件加载失败"
                case .unknown:
                    break
                @unknown default:
                    break
                }
            }
        }

        timeControlObservation = player.observe(\.timeControlStatus, options: [.initial, .new]) { [weak self] player, _ in
            Task { @MainActor [weak self] in
                self?.isPlaying = player.timeControlStatus == .playing
            }
        }
    }

    private func tearDownPlayer() {
        if let timeObserverToken, let player {
            player.removeTimeObserver(timeObserverToken)
        }
        timeObserverToken = nil
        statusObservation = nil
        timeControlObservation = nil
        player?.pause()
        player = nil
    }
}
