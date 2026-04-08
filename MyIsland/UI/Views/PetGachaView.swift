//
//  PetGachaView.swift
//  MyIsland
//
//  Pet gacha (draw) UI with card reveal animation, collection gallery,
//  and active pet selection.
//

import SwiftUI

struct PetGachaView: View {
    @ObservedObject var viewModel: NotchViewModel
    @StateObject private var gacha = PetGachaSystem.shared

    @State private var currentTab: GachaTab = .draw
    @State private var isRolling = false
    @State private var revealedPet: Pet?
    @State private var showCard = false
    @State private var cardFlipped = false

    enum GachaTab {
        case draw, collection
    }

    var body: some View {
        VStack(spacing: 0) {
            // Back button
            backButton

            Divider()
                .background(Color.white.opacity(0.08))
                .padding(.vertical, 4)

            // Tab switcher
            tabSwitcher
                .padding(.horizontal, 8)
                .padding(.bottom, 8)

            // Content
            Group {
                switch currentTab {
                case .draw:
                    drawView
                case .collection:
                    collectionView
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    // MARK: - Back Button

    private var backButton: some View {
        Button {
            withAnimation(.easeInOut(duration: 0.25)) {
                viewModel.contentType = .menu
            }
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 12))
                    .foregroundColor(.white.opacity(0.7))
                    .frame(width: 16)

                Text("返回")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(.white.opacity(0.7))

                Spacer()

                Text("\u{1F3B4} \u{5BA0}\u{7269}\u{62BD}\u{5361}")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(.white.opacity(0.5))
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Tab Switcher

    private var tabSwitcher: some View {
        HStack(spacing: 0) {
            tabButton(
                label: "\u{1F3B4} \u{62BD}\u{5361}",
                tab: .draw
            )
            tabButton(
                label: "\u{1F4CB} \u{6536}\u{85CF}",
                tab: .collection
            )
        }
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.white.opacity(0.05))
        )
    }

    private func tabButton(label: String, tab: GachaTab) -> some View {
        Button {
            withAnimation(.easeInOut(duration: 0.2)) {
                currentTab = tab
            }
        } label: {
            Text(label)
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(currentTab == tab ? .white : .white.opacity(0.4))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(currentTab == tab ? Color.white.opacity(0.1) : Color.clear)
                )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Draw View

    private var drawView: some View {
        VStack(spacing: 12) {
            if let pet = revealedPet, showCard {
                // Revealed card
                revealCard(pet: pet)
                    .transition(.asymmetric(
                        insertion: .scale(scale: 0.3).combined(with: .opacity),
                        removal: .opacity
                    ))
            } else {
                // Placeholder card back
                cardBack
            }

            // Roll button
            Button {
                performRoll()
            } label: {
                HStack(spacing: 8) {
                    Text("\u{1F3B4}")
                    Text("\u{62BD}\u{5361}")
                        .font(.system(size: 14, weight: .bold))
                }
                .foregroundColor(.black)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .background(
                    RoundedRectangle(cornerRadius: 10)
                        .fill(
                            LinearGradient(
                                colors: [
                                    Color(red: 0.3, green: 0.9, blue: 0.4),
                                    Color(red: 0.2, green: 0.8, blue: 0.5),
                                ],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                )
            }
            .buttonStyle(.plain)
            .disabled(isRolling)
            .opacity(isRolling ? 0.5 : 1.0)
            .padding(.horizontal, 16)

            // Roll count
            Text("\u{603B}\u{62BD}\u{5361}: \(gacha.totalRolls) \u{6B21}")
                .font(.system(size: 10))
                .foregroundColor(.white.opacity(0.3))
        }
    }

    // MARK: - Card Back (before roll)

    private var cardBack: some View {
        VStack(spacing: 8) {
            Text("?")
                .font(.system(size: 48, weight: .bold, design: .monospaced))
                .foregroundColor(.white.opacity(0.2))

            Text("\u{70B9}\u{51FB}\u{62BD}\u{5361}\u{83B7}\u{53D6}\u{5BA0}\u{7269}")
                .font(.system(size: 12))
                .foregroundColor(.white.opacity(0.3))
        }
        .frame(maxWidth: .infinity)
        .frame(height: 200)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.white.opacity(0.03))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color.white.opacity(0.08), lineWidth: 1)
                )
        )
        .padding(.horizontal, 16)
    }

    // MARK: - Reveal Card

    private func revealCard(pet: Pet) -> some View {
        VStack(spacing: 8) {
            // Rarity banner
            HStack(spacing: 6) {
                Text(pet.rarity.stars)
                    .font(.system(size: 12))
                Text(pet.rarity.displayName)
                    .font(.system(size: 12, weight: .bold))
            }
            .foregroundColor(rarityColor(pet.rarity))

            // Pet art
            if pet.name == "小蟹OG" {
                ClaudeCrabIcon(size: 56, animateLegs: true)
                    .frame(height: 70)
            } else {
                PixelPetView(pet: pet, pixelSize: 5.0, animated: true)
                    .frame(height: 70)
            }

            // Name + species + OG badge for crab
            HStack(spacing: 4) {
                Text("\"\(pet.name)\"")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundColor(.white)
                Text("- \(pet.species.displayName)")
                    .font(.system(size: 12))
                    .foregroundColor(.white.opacity(0.6))
                if pet.species == .crab {
                    Text("OG")
                        .font(.system(size: 8, weight: .heavy))
                        .foregroundColor(.black)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 1)
                        .background(
                            Capsule().fill(Color(red: 0.85, green: 0.47, blue: 0.34))
                        )
                }
                if pet.shiny {
                    Text("\u{2728}")
                        .font(.system(size: 10))
                }
            }

            // Stats
            statsRow(pet: pet)

            // Set active button
            if gacha.activePet?.id != pet.id {
                Button {
                    gacha.setActive(pet)
                } label: {
                    Text("\u{8BBE}\u{4E3A}\u{5F53}\u{524D}")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.white)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 6)
                        .background(
                            RoundedRectangle(cornerRadius: 6)
                                .fill(Color.white.opacity(0.15))
                        )
                }
                .buttonStyle(.plain)
            } else {
                Text("\u{2705} \u{5F53}\u{524D}\u{5BA0}\u{7269}")
                    .font(.system(size: 11))
                    .foregroundColor(TerminalColors.green)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.white.opacity(0.03))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(rarityColor(pet.rarity).opacity(0.4), lineWidth: 1)
                )
        )
        .shadow(color: rarityColor(pet.rarity).opacity(0.2), radius: 8)
        .padding(.horizontal, 16)
    }

    // MARK: - Stats Row

    private func statsRow(pet: Pet) -> some View {
        let stats = pet.stats.asDictionary
        return HStack(spacing: 8) {
            ForEach(stats.prefix(3), id: \.0) { name, value in
                VStack(spacing: 2) {
                    Text(name)
                        .font(.system(size: 7, weight: .medium, design: .monospaced))
                        .foregroundColor(.white.opacity(0.4))
                    Text("\(value)")
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .foregroundColor(TerminalColors.cyan)
                }
            }
        }
    }

    // MARK: - Collection View

    /// Active pet is always first in the collection
    private var sortedCollection: [Pet] {
        gacha.collection.sorted { a, b in
            let aIsActive = gacha.activePet?.id == a.id
            let bIsActive = gacha.activePet?.id == b.id
            if aIsActive != bIsActive { return aIsActive }
            return false  // preserve original order for the rest
        }
    }

    private var collectionView: some View {
        VStack(spacing: 8) {
            // Collection header
            HStack {
                Text("\u{6536}\u{85CF} (\(gacha.uniqueSpeciesCount)/\(gacha.totalSpeciesCount) \u{79CD})")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.white.opacity(0.6))
                Spacer()
            }
            .padding(.horizontal, 16)

            // Pet grid
            ScrollView {
                LazyVGrid(columns: [
                    GridItem(.flexible(), spacing: 8),
                    GridItem(.flexible(), spacing: 8),
                ], spacing: 8) {
                    ForEach(sortedCollection) { pet in
                        collectionCell(pet: pet)
                    }
                }
                .padding(.horizontal, 16)
            }
        }
    }

    private func collectionCell(pet: Pet) -> some View {
        VStack(spacing: 4) {
            // Pet art
            if pet.name == "小蟹OG" {
                ClaudeCrabIcon(size: 32, animateLegs: false)
                    .frame(height: 36)
            } else {
                PixelPetView(pet: pet, pixelSize: 2.5, animated: false)
                    .frame(height: 36)
            }

            // Name + OG badge for crab
            HStack(spacing: 2) {
                Text(pet.name)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(.white)
                    .lineLimit(1)
                if pet.species == .crab {
                    Text("OG")
                        .font(.system(size: 6, weight: .heavy))
                        .foregroundColor(.black)
                        .padding(.horizontal, 3)
                        .padding(.vertical, 1)
                        .background(
                            Capsule().fill(Color(red: 0.85, green: 0.47, blue: 0.34))
                        )
                }
            }

            // Rarity stars
            Text(pet.rarity.stars)
                .font(.system(size: 8))
                .foregroundColor(rarityColor(pet.rarity))

            // Active indicator
            if gacha.activePet?.id == pet.id {
                Text("\u{5F53}\u{524D}")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundColor(TerminalColors.green)
            }
        }
        .padding(6)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(
                    gacha.activePet?.id == pet.id
                        ? Color.white.opacity(0.08)
                        : Color.white.opacity(0.03)
                )
        )
        .onTapGesture {
            gacha.setActive(pet)
        }
    }

    // MARK: - Actions

    private func performRoll() {
        isRolling = true
        showCard = false
        revealedPet = nil

        // Brief delay for anticipation
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            let pet = gacha.roll()
            revealedPet = pet

            withAnimation(.spring(response: 0.5, dampingFraction: 0.7)) {
                showCard = true
            }

            // Play ceremony sound for epic/legendary draws
            if pet.rarity == .epic || pet.rarity == .legendary {
                SoundPlayer.shared.playCeremony()
            }

            isRolling = false
        }
    }

    // MARK: - Helpers

    private func rarityColor(_ rarity: PetRarity) -> Color {
        switch rarity {
        case .common:    return .gray
        case .uncommon:  return TerminalColors.green
        case .rare:      return TerminalColors.blue
        case .epic:      return Color(red: 0.6, green: 0.3, blue: 0.9)
        case .legendary: return Color(red: 1.0, green: 0.84, blue: 0.0)
        }
    }
}
