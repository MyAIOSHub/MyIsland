//
//  ASCIIPetView.swift
//  MyIsland
//
//  SwiftUI view that renders pet ASCII art with rich idle animations.
//  Terminal aesthetic: green text on dark background, monospaced font.
//  Dynamic effects: breathing scale, wobble, bounce, and idle fidget.
//

import Combine
import SwiftUI

struct ASCIIPetView: View {
    let pet: Pet
    var size: ASCIIPetSize = .large
    var animated: Bool = true

    @State private var frameIndex: Int = 0
    // Dynamic animation states
    @State private var breathScale: CGFloat = 1.0
    @State private var wobbleAngle: Double = 0
    @State private var bounceOffset: CGFloat = 0
    @State private var isBlinking: Bool = false
    @State private var shadowPulse: CGFloat = 0.3

    private let frameTimer = Timer.publish(every: 0.5, on: .main, in: .common).autoconnect()
    private let blinkTimer = Timer.publish(every: 3.0, on: .main, in: .common).autoconnect()

    enum ASCIIPetSize {
        case small   // For collection grid
        case large   // For gacha reveal

        var fontSize: CGFloat {
            switch self {
            case .small: return 8
            case .large: return 14
            }
        }

        var padding: CGFloat {
            switch self {
            case .small: return 4
            case .large: return 12
            }
        }
    }

    var body: some View {
        let frames = pet.frames
        let currentFrame = frames.isEmpty ? [] : frames[frameIndex % frames.count]

        VStack(spacing: 0) {
            ForEach(Array(currentFrame.enumerated()), id: \.offset) { _, line in
                Text(isBlinking ? blinkLine(line) : line)
                    .font(.system(size: size.fontSize, design: .monospaced))
                    .foregroundColor(textColor)
            }
        }
        .padding(size.padding)
        // Breathing scale animation
        .scaleEffect(animated ? breathScale : 1.0)
        // Wobble rotation
        .rotationEffect(.degrees(animated ? wobbleAngle : 0), anchor: .bottom)
        // Bounce offset
        .offset(y: animated ? bounceOffset : 0)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.black.opacity(0.6))
        )
        .overlay(
            // Shiny golden glow with animated pulse
            pet.shiny ?
                RoundedRectangle(cornerRadius: 8)
                    .stroke(
                        LinearGradient(
                            colors: [
                                Color(red: 1.0, green: 0.84, blue: 0.0).opacity(shadowPulse + 0.3),
                                Color(red: 1.0, green: 0.65, blue: 0.0).opacity(shadowPulse),
                                Color(red: 1.0, green: 0.84, blue: 0.0).opacity(shadowPulse + 0.3),
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 2
                    )
                : nil
        )
        // Rarity-based shadow glow
        .shadow(
            color: rarityGlowColor.opacity(animated ? Double(shadowPulse) : 0.2),
            radius: animated ? 6 : 2
        )
        .onAppear {
            guard animated else { return }
            startAnimations()
        }
        .onReceive(frameTimer) { _ in
            guard animated else { return }
            frameIndex = (frameIndex + 1) % max(1, frames.count)
        }
        .onReceive(blinkTimer) { _ in
            guard animated else { return }
            triggerBlink()
        }
    }

    // MARK: - Animations

    private func startAnimations() {
        // Breathing: gentle scale pulse
        withAnimation(
            .easeInOut(duration: 2.0)
            .repeatForever(autoreverses: true)
        ) {
            breathScale = 1.03
        }

        // Wobble: slight left-right sway (species-dependent intensity)
        let wobbleIntensity = wobbleIntensityForSpecies
        withAnimation(
            .easeInOut(duration: 1.8)
            .repeatForever(autoreverses: true)
            .delay(0.3)
        ) {
            wobbleAngle = wobbleIntensity
        }

        // Bounce: periodic small hop
        startBounceLoop()

        // Shadow pulse for shiny/rare pets
        if pet.shiny || pet.rarity == .epic || pet.rarity == .legendary {
            withAnimation(
                .easeInOut(duration: 1.5)
                .repeatForever(autoreverses: true)
            ) {
                shadowPulse = 0.7
            }
        }
    }

    private func startBounceLoop() {
        // Random bounce interval based on species personality
        let interval = bounceIntervalForSpecies
        DispatchQueue.main.asyncAfter(deadline: .now() + interval) {
            guard animated else { return }
            withAnimation(.spring(response: 0.25, dampingFraction: 0.4)) {
                bounceOffset = -4
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) {
                    bounceOffset = 0
                }
            }
            startBounceLoop()
        }
    }

    private func triggerBlink() {
        isBlinking = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            isBlinking = false
        }
    }

    /// Replace eye characters with blink character
    private func blinkLine(_ line: String) -> String {
        line.replacingOccurrences(of: pet.eye.rawValue, with: "-")
    }

    // MARK: - Per-Species Personality

    /// How much the pet wobbles (based on species energy)
    private var wobbleIntensityForSpecies: Double {
        switch pet.species {
        case .duck, .goose, .penguin:  return 3.0  // Waddle
        case .blob, .ghost:            return 4.0  // Wobbly
        case .cat, .chonk:             return 1.5  // Subtle
        case .dragon:                  return 2.5  // Majestic sway
        case .octopus, .axolotl:       return 3.5  // Fluid
        case .owl:                     return 1.0  // Steady
        case .turtle, .snail:          return 0.8  // Minimal
        case .cactus:                  return 0.5  // Nearly still
        case .robot:                   return 2.0  // Mechanical
        case .rabbit:                  return 4.0  // Energetic
        case .mushroom:                return 1.2  // Gentle
        case .capybara:                return 1.0  // Chill
        case .fox, .squirrel:          return 3.0  // Quick
        case .bunny2:                  return 4.0  // Bouncy
        case .owl2:                    return 1.0  // Steady
        case .koala:                   return 0.8  // Sleepy
        case .tuxPenguin:              return 2.5  // Formal waddle
        case .elephant:                return 1.5  // Heavy sway
        case .sheep:                   return 2.0  // Fluffy wobble
        case .bear:                    return 1.5  // Big sway
        case .dragon2:                 return 2.5  // Majestic
        case .kitty, .cowsayCat:       return 1.5  // Cat-like
        case .crab:                    return 3.0  // Sideways scuttle
        }
    }

    /// How often the pet bounces (seconds between hops)
    private var bounceIntervalForSpecies: TimeInterval {
        switch pet.species {
        case .rabbit:                  return 2.0  // Very bouncy
        case .duck, .goose, .penguin:  return 3.5
        case .blob, .ghost:            return 4.0
        case .cat, .chonk:             return 5.0
        case .dragon:                  return 6.0
        case .octopus, .axolotl:       return 4.5
        case .owl:                     return 7.0  // Rarely
        case .turtle, .snail:          return 8.0  // Very rarely
        case .cactus:                  return 10.0 // Almost never
        case .robot:                   return 3.0
        case .mushroom:                return 6.0
        case .capybara:                return 7.0
        case .fox, .squirrel:          return 2.5
        case .bunny2:                  return 2.0  // Bouncy
        case .owl2:                    return 7.0
        case .koala:                   return 8.0  // Sleepy
        case .tuxPenguin:              return 4.0
        case .elephant:                return 6.0
        case .sheep:                   return 5.0
        case .bear:                    return 5.0
        case .dragon2:                 return 4.0
        case .kitty, .cowsayCat:       return 4.5
        case .crab:                    return 3.0  // Snappy
        }
    }

    // MARK: - Colors

    private var textColor: Color {
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

    private var rarityGlowColor: Color {
        switch pet.rarity {
        case .legendary: return Color(red: 1.0, green: 0.84, blue: 0.0)
        case .epic:      return Color(red: 0.6, green: 0.3, blue: 1.0)
        case .rare:      return Color(red: 0.2, green: 0.6, blue: 1.0)
        case .uncommon:  return TerminalColors.green
        case .common:    return .clear
        }
    }
}
