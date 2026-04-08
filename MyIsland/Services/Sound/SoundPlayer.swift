//
//  SoundPlayer.swift
//  MyIsland
//
//  Plays system sounds for session events, respecting per-category settings.
//

import AppKit
import Foundation

@MainActor
class SoundPlayer {
    static let shared = SoundPlayer()

    private let settings = SoundSettings.shared

    private init() {}

    // MARK: - Public API

    /// Play a sound for the given category if globally enabled and category toggle is on
    func play(_ category: SoundCategory) {
        guard settings.isEnabled else { return }
        guard settings.isEnabled(for: category) else { return }
        guard !settings.shouldSuppressSound else { return }
        playSystemSound(category.systemSoundName, volume: settings.volume)
    }

    /// Preview a sound regardless of toggle state (used in settings UI)
    func preview(_ category: SoundCategory) {
        let vol = settings.isEnabled ? settings.volume : 0.3
        playSystemSound(category.systemSoundName, volume: vol)
    }

    /// Play the onboarding ceremony sound for special events (epic/legendary pet draws)
    func playCeremony() {
        guard settings.isEnabled else { return }
        guard let url = Bundle.main.url(forResource: "onboarding-ceremony", withExtension: "wav", subdirectory: "Sounds") else {
            // Try without subdirectory
            guard let url2 = Bundle.main.url(forResource: "onboarding-ceremony", withExtension: "wav") else { return }
            playURL(url2)
            return
        }
        playURL(url)
    }

    // MARK: - Private

    private func playURL(_ url: URL) {
        let sound = NSSound(contentsOf: url, byReference: true)
        sound?.volume = settings.volume
        sound?.play()
    }

    private func playSystemSound(_ name: String, volume: Float) {
        guard let sound = NSSound(named: name) else { return }
        sound.volume = volume
        sound.play()
    }
}
