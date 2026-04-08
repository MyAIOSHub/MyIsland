import Combine
import SwiftUI

/// A tiny animated pet view for the notch header bar.
/// Shows a compact ASCII face with breathing, wobble, and bounce animations.
struct MiniPetView: View {
    let pet: Pet
    let size: CGFloat
    let isActive: Bool

    @State private var frameIndex = 0
    @State private var breathScale: CGFloat = 1.0
    @State private var wobble: Double = 0
    @State private var bounce: CGFloat = 0

    private let frameTimer = Timer.publish(every: 0.4, on: .main, in: .common).autoconnect()

    /// Font size for the full-body ASCII art to fit in notch height (~30pt)
    private var bodyFontSize: CGFloat {
        min(size * 0.22, 6)
    }

    var body: some View {
        VStack(spacing: -1) {
            let frames = pet.frames
            let currentFrame = frames.isEmpty ? [] : frames[frameIndex % frames.count]
            ForEach(Array(currentFrame.enumerated()), id: \.offset) { _, line in
                Text(line)
                    .font(.system(size: bodyFontSize, weight: .bold, design: .monospaced))
                    .foregroundColor(petColor)
            }
        }
        .scaleEffect(breathScale)
        .rotationEffect(.degrees(wobble), anchor: .bottom)
        .offset(y: bounce)
        .onAppear { startAnimations() }
        .onReceive(frameTimer) { _ in
            let frames = pet.frames
            frameIndex = (frameIndex + 1) % max(1, frames.count)
            if isActive { triggerBounce() }
        }
    }

    // MARK: - Animations

    private func startAnimations() {
        // Breathing
        withAnimation(.easeInOut(duration: 1.5).repeatForever(autoreverses: true)) {
            breathScale = 1.06
        }
        // Wobble
        let intensity = wobbleForSpecies
        withAnimation(.easeInOut(duration: 1.2).repeatForever(autoreverses: true).delay(0.2)) {
            wobble = intensity
        }
    }

    private func triggerBounce() {
        // Only bounce occasionally
        guard Int.random(in: 0..<5) == 0 else { return }
        withAnimation(.spring(response: 0.2, dampingFraction: 0.3)) {
            bounce = -3
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            withAnimation(.spring(response: 0.25, dampingFraction: 0.5)) {
                bounce = 0
            }
        }
    }

    private var wobbleForSpecies: Double {
        switch pet.species {
        case .rabbit, .blob, .ghost:       return 4.0
        case .duck, .goose, .octopus:      return 3.0
        case .cat, .chonk, .capybara:      return 1.5
        case .turtle, .snail, .cactus:     return 0.5
        default:                           return 2.0
        }
    }

    // MARK: - Colors

    private var petColor: Color {
        if pet.shiny {
            return Color(red: 1.0, green: 0.84, blue: 0.0)
        }
        switch pet.rarity {
        case .legendary: return Color(red: 1.0, green: 0.7, blue: 0.2)  // 金色
        case .epic:      return Color(red: 0.7, green: 0.5, blue: 1.0)  // 紫色
        case .rare:      return Color(red: 0.3, green: 0.7, blue: 1.0)  // 蓝色
        case .uncommon:  return TerminalColors.green                     // 绿色
        case .common:    return .white.opacity(0.7)                      // 白色
        }
    }
}
