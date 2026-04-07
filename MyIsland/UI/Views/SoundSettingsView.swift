//
//  SoundSettingsView.swift
//  MyIsland
//
//  Full sound settings panel matching the Vibe Island Chinese UI
//

import SwiftUI

struct SoundSettingsView: View {
    @ObservedObject var settings: SoundSettings
    @ObservedObject var viewModel: NotchViewModel

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                // Header
                headerSection

                // Master toggle + volume
                masterSection

                // Notification sound picker
                SoundPickerRow(soundSelector: SoundSelector.shared)

                // Session section
                sectionView(title: "会话", categories: SoundSection.session.categories)

                // Interaction section
                sectionView(title: "交互", categories: SoundSection.interaction.categories)

                // System section
                sectionView(title: "系统", categories: SoundSection.system.categories)

                // Suppression section
                suppressionSection

                // Filter section
                filterSection
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 12)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(Color.black)
    }

    // MARK: - Header

    private var headerSection: some View {
        HStack {
            Button {
                withAnimation(.easeInOut(duration: 0.25)) {
                    viewModel.contentType = .menu
                }
            } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.white.opacity(0.7))
            }
            .buttonStyle(.plain)

            Text("声音")
                .font(.system(size: 15, weight: .bold))
                .foregroundColor(.white)

            Spacer()
        }
        .padding(.horizontal, 4)
    }

    // MARK: - Master Toggle + Volume

    private var masterSection: some View {
        VStack(spacing: 0) {
            // Enable toggle
            HStack {
                Text("启用音效")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(.white)
                Spacer()
                Toggle("", isOn: $settings.isEnabled)
                    .toggleStyle(.switch)
                    .tint(TerminalColors.blue)
                    .labelsHidden()
                    .scaleEffect(0.8)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)

            if settings.isEnabled {
                Divider()
                    .background(Color.white.opacity(0.08))

                // Volume slider
                HStack(spacing: 8) {
                    Text("音量")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(.white)

                    Image(systemName: "speaker.fill")
                        .font(.system(size: 10))
                        .foregroundColor(.white.opacity(0.5))

                    Slider(value: $settings.volume, in: 0...1, step: 0.05)
                        .tint(TerminalColors.blue)

                    Image(systemName: "speaker.wave.3.fill")
                        .font(.system(size: 10))
                        .foregroundColor(.white.opacity(0.5))

                    Text("\(Int(settings.volume * 100))%")
                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                        .foregroundColor(.white.opacity(0.5))
                        .frame(width: 32, alignment: .trailing)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color.white.opacity(0.06))
        )
    }

    // MARK: - Category Section

    private func sectionView(title: String, categories: [SoundCategory]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(.white.opacity(0.4))
                .textCase(.uppercase)
                .padding(.leading, 4)

            VStack(spacing: 0) {
                ForEach(Array(categories.enumerated()), id: \.element) { index, category in
                    if index > 0 {
                        Divider()
                            .background(Color.white.opacity(0.08))
                    }
                    SoundCategoryRow(
                        category: category,
                        isEnabled: Binding(
                            get: { settings.isEnabled(for: category) },
                            set: { settings.setEnabled($0, for: category) }
                        )
                    )
                }
            }
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color.white.opacity(0.06))
            )
        }
    }

    // MARK: - Suppression Section

    private var suppressionSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("抑制")
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(.white.opacity(0.4))
                .textCase(.uppercase)
                .padding(.leading, 4)

            VStack(spacing: 0) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("终端聚焦时静音")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(.white)
                        Text("当终端窗口在前台时不播放通知音")
                            .font(.system(size: 11))
                            .foregroundColor(.white.opacity(0.4))
                    }

                    Spacer()

                    Toggle("", isOn: $settings.suppressWhenTerminalFocused)
                        .toggleStyle(.switch)
                        .tint(TerminalColors.blue)
                        .labelsHidden()
                        .scaleEffect(0.8)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
            }
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color.white.opacity(0.06))
            )
        }
    }

    // MARK: - Filter Section

    private var filterSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("过滤")
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(.white.opacity(0.4))
                .textCase(.uppercase)
                .padding(.leading, 4)

            VStack(spacing: 0) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("自动检测探测会话")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(.white)
                        Text("自动静音健康检查会话")
                            .font(.system(size: 11))
                            .foregroundColor(.white.opacity(0.4))
                        Text("(如 CodexBar ClaudeProbe)")
                            .font(.system(size: 11))
                            .foregroundColor(.white.opacity(0.3))
                    }

                    Spacer()

                    Toggle("", isOn: $settings.autoDetectProbes)
                        .toggleStyle(.switch)
                        .tint(TerminalColors.blue)
                        .labelsHidden()
                        .scaleEffect(0.8)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
            }
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color.white.opacity(0.06))
            )
        }
    }
}

// MARK: - Sound Category Row

private struct SoundCategoryRow: View {
    let category: SoundCategory
    @Binding var isEnabled: Bool
    @State private var isHovered = false

    var body: some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 3) {
                Text(category.displayName)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(.white)
                Text(category.displayDescription)
                    .font(.system(size: 11))
                    .foregroundColor(.white.opacity(0.4))
                    .lineLimit(1)
            }

            Spacer()

            // Preview button
            Button {
                SoundPlayer.shared.preview(category)
            } label: {
                Image(systemName: "play.fill")
                    .font(.system(size: 9))
                    .foregroundColor(.white.opacity(isHovered ? 0.8 : 0.4))
                    .frame(width: 24, height: 24)
                    .background(
                        Circle()
                            .fill(Color.white.opacity(isHovered ? 0.12 : 0.06))
                    )
            }
            .buttonStyle(.plain)
            .onHover { isHovered = $0 }

            Toggle("", isOn: $isEnabled)
                .toggleStyle(.switch)
                .tint(TerminalColors.blue)
                .labelsHidden()
                .scaleEffect(0.8)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }
}
