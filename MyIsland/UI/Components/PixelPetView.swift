//
//  PixelPetView.swift
//  MyIsland
//
//  Renders a pet in pixel-art style using Canvas.
//  Each ASCII character becomes a colored rectangle block,
//  matching the same Canvas rendering approach as ClaudeCrabIcon.
//

import Combine
import SwiftUI

struct PixelPetView: View {
    let pet: Pet
    var pixelSize: CGFloat = 3  // size per character cell
    var animated: Bool = true

    @State private var frameIndex = 0
    @State private var breathScale: CGFloat = 1.0

    private let timer = Timer.publish(every: 0.5, on: .main, in: .common).autoconnect()

    var body: some View {
        let frames = pet.frames
        let currentFrame: [String] = frames.isEmpty ? [] : frames[frameIndex % frames.count]
        let cols = currentFrame.first?.count ?? 12
        let rows = currentFrame.count

        Canvas { context, _ in
            for (row, line) in currentFrame.enumerated() {
                for (col, char) in line.enumerated() {
                    let color = pixelColor(for: char)
                    guard color != .clear else { continue }
                    let rect = CGRect(
                        x: CGFloat(col) * pixelSize,
                        y: CGFloat(row) * pixelSize,
                        width: pixelSize,
                        height: pixelSize
                    )
                    context.fill(Path(rect), with: .color(color))
                }
            }
        }
        .frame(
            width: CGFloat(cols) * pixelSize,
            height: CGFloat(rows) * pixelSize
        )
        .scaleEffect(breathScale)
        .onAppear {
            if animated {
                withAnimation(.easeInOut(duration: 1.5).repeatForever(autoreverses: true)) {
                    breathScale = 1.04
                }
            }
        }
        .onReceive(timer) { _ in
            guard animated else { return }
            let count = pet.frames.count
            guard count > 0 else { return }
            frameIndex = (frameIndex + 1) % count
        }
    }

    // MARK: - Pixel Color Mapping

    private func pixelColor(for char: Character) -> Color {
        if char == " " { return .clear }

        // Eye characters get special color
        let eyeStr = pet.eye.rawValue
        if String(char) == eyeStr { return eyeColor }

        // Structural characters get body color
        switch char {
        case "/", "\\", "|", "(", ")", "[", "]", "<", ">", "{", "}":
            return bodyColor
        case "-", "_", "=", "~", "^", "`", "'", ".":
            return bodyColor.opacity(0.7)
        case "*", "o", "O", "@", "#", "w":
            return detailColor
        default:
            return bodyColor.opacity(0.85)
        }
    }

    // MARK: - Color Palettes

    private var bodyColor: Color {
        switch pet.species {
        case .duck:
            return .yellow
        case .goose:
            return .white
        case .cat, .chonk, .kitty, .cowsayCat:
            return .orange
        case .dragon, .dragon2:
            return .green
        case .octopus:
            return .pink
        case .owl, .owl2:
            return .brown
        case .penguin, .tuxPenguin:
            return Color(white: 0.2)
        case .turtle:
            return .green
        case .snail:
            return Color(red: 0.6, green: 0.4, blue: 0.2)
        case .ghost:
            return .white.opacity(0.7)
        case .axolotl:
            return .pink
        case .capybara:
            return Color(red: 0.6, green: 0.4, blue: 0.3)
        case .cactus:
            return Color(red: 0.2, green: 0.7, blue: 0.3)
        case .robot:
            return Color(red: 0.5, green: 0.5, blue: 0.6)
        case .rabbit, .bunny2:
            return .white
        case .mushroom:
            return .red
        case .blob:
            return Color(red: 0.3, green: 0.8, blue: 0.5)
        case .fox:
            return Color(red: 0.9, green: 0.5, blue: 0.2)
        case .koala:
            return Color(red: 0.6, green: 0.6, blue: 0.6)
        case .elephant:
            return Color(red: 0.5, green: 0.5, blue: 0.6)
        case .sheep:
            return .white
        case .squirrel:
            return Color(red: 0.6, green: 0.3, blue: 0.1)
        case .bear:
            return Color(red: 0.5, green: 0.3, blue: 0.2)
        case .crab:
            return Color(red: 0.85, green: 0.47, blue: 0.34)
        }
    }

    private var eyeColor: Color {
        if pet.shiny { return Color(red: 1, green: 0.84, blue: 0) }
        return .white
    }

    private var detailColor: Color {
        switch pet.rarity {
        case .legendary:
            return Color(red: 1, green: 0.84, blue: 0)
        case .epic:
            return Color(red: 0.6, green: 0.3, blue: 1)
        case .rare:
            return Color(red: 0.3, green: 0.7, blue: 1)
        default:
            return bodyColor.opacity(0.7)
        }
    }
}
