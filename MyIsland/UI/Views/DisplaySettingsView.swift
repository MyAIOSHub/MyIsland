import SwiftUI

/// Display settings panel matching original Vibe Island's display preferences.
struct DisplaySettingsView: View {
    @Bindable var displaySettings = DisplaySettings.shared
    var viewModel: NotchViewModel?

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 16) {
                // Header with back button
                HStack {
                    if let viewModel {
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
                    }

                    Text("显示")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundColor(.white)

                    Spacer()
                }

                // Screen selection
                ScreenPickerRow(screenSelector: ScreenSelector.shared)

                Divider().background(Color.white.opacity(0.08))

                // Notch Layout Mode
                notchLayoutSection

                Divider().background(Color.white.opacity(0.08))

                // Panel dimensions
                panelDimensionsSection

                Divider().background(Color.white.opacity(0.08))

                // Agent detail
                agentDetailSection
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    // MARK: - Notch Layout

    @State private var autoExpandNotch: Bool = AppSettings.autoExpandNotch

    private var notchLayoutSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("刘海")
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(.white.opacity(0.7))

            // Preview
            notchPreview
                .padding(.vertical, 4)

            // Layout mode picker
            HStack(spacing: 12) {
                layoutOption(.clean)
                layoutOption(.detailed)
            }

            // Auto-expand toggle
            Toggle(isOn: Binding(
                get: { autoExpandNotch },
                set: { newValue in
                    autoExpandNotch = newValue
                    AppSettings.autoExpandNotch = newValue
                }
            )) {
                Text("自动展开 Notch")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.white.opacity(0.7))
            }
            .toggleStyle(.switch)
            .tint(.blue)
        }
    }

    private var notchPreview: some View {
        ZStack {
            // Background gradient (simulated desktop)
            LinearGradient(
                colors: [Color.purple.opacity(0.6), Color.blue.opacity(0.4)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .clipShape(RoundedRectangle(cornerRadius: 12))

            // Notch pill preview
            VStack {
                HStack(spacing: 6) {
                    // Crab icon
                    Text("🦀")
                        .font(.system(size: 10))

                    if displaySettings.layoutMode == .detailed {
                        Text("读取中")
                            .font(.system(size: 9, weight: .medium, design: .monospaced))
                            .foregroundColor(.white)
                    }

                    Spacer()

                    Text("1")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(.blue)

                    if displaySettings.layoutMode == .detailed {
                        Text("个会话")
                            .font(.system(size: 9))
                            .foregroundColor(.white.opacity(0.6))
                    }
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(
                    Capsule()
                        .fill(.black)
                )
                .frame(width: displaySettings.layoutMode == .detailed ? 180 : 80)

                Spacer()
            }
            .padding(.top, 8)
        }
        .frame(height: 120)
    }

    private func layoutOption(_ mode: DisplaySettings.LayoutMode) -> some View {
        Button {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                displaySettings.layoutMode = mode
            }
        } label: {
            VStack(spacing: 8) {
                // Mini preview
                HStack(spacing: 4) {
                    Circle().fill(.green).frame(width: 5, height: 5)
                    if mode == .detailed {
                        RoundedRectangle(cornerRadius: 2)
                            .fill(.white.opacity(0.3))
                            .frame(width: 30, height: 4)
                    }
                    Spacer()
                    Text("2")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundColor(.white.opacity(0.5))
                    if mode == .detailed {
                        Text("ses")
                            .font(.system(size: 7))
                            .foregroundColor(.white.opacity(0.3))
                    }
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(.black.opacity(0.3))
                )
                .frame(width: mode == .detailed ? 100 : 60)

                Text(mode.displayName)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.white)

                Text(mode.description)
                    .font(.system(size: 10))
                    .foregroundColor(.white.opacity(0.4))
            }
            .frame(maxWidth: .infinity)
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(
                        displaySettings.layoutMode == mode ? Color.blue : Color.white.opacity(0.1),
                        lineWidth: displaySettings.layoutMode == mode ? 2 : 1
                    )
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Panel Dimensions

    private var panelDimensionsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Font size
            settingsSlider(
                label: "内容字体大小",
                value: $displaySettings.contentFontSize,
                range: 10...13,
                defaultValue: 11,
                unit: "pt",
                step: 1
            )

            // Completion card height
            settingsSlider(
                label: "完成卡片高度",
                value: $displaySettings.completionCardHeight,
                range: 60...300,
                defaultValue: 90,
                unit: "pt",
                step: 10
            )

            // Max panel height
            settingsSlider(
                label: "最大面板高度",
                value: $displaySettings.maxPanelHeight,
                range: 300...800,
                defaultValue: 560,
                unit: "pt",
                step: 20
            )

            // Expanded panel width
            settingsSlider(
                label: "展开面板宽度",
                value: $displaySettings.expandedPanelWidth,
                range: 300...600,
                defaultValue: 480,
                unit: "pt",
                step: 20
            )

            // Detailed mode extra width
            if displaySettings.layoutMode == .detailed {
                settingsSlider(
                    label: "详细模式面板宽度",
                    value: $displaySettings.detailedExtraWidth,
                    range: 200...600,
                    defaultValue: 450,
                    unit: "pt",
                    step: 10
                )
            }
        }
    }

    private func settingsSlider(
        label: String,
        value: Binding<CGFloat>,
        range: ClosedRange<CGFloat>,
        defaultValue: CGFloat,
        unit: String,
        step: CGFloat
    ) -> some View {
        VStack(spacing: 6) {
            HStack {
                Text(label)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.white.opacity(0.7))

                Spacer()

                Text("\(Int(value.wrappedValue))\(unit)")
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundColor(.white.opacity(0.5))

                if value.wrappedValue != defaultValue {
                    Text("· 默认")
                        .font(.system(size: 10))
                        .foregroundColor(.white.opacity(0.3))

                    Button {
                        withAnimation { value.wrappedValue = defaultValue }
                    } label: {
                        Image(systemName: "arrow.counterclockwise")
                            .font(.system(size: 9))
                            .foregroundColor(.white.opacity(0.4))
                    }
                    .buttonStyle(.plain)
                } else {
                    Text("（默认）")
                        .font(.system(size: 10))
                        .foregroundColor(.white.opacity(0.3))
                }
            }

            Slider(value: value, in: range, step: step)
                .tint(.blue)
        }
    }

    // MARK: - Agent Detail

    @State private var verboseMode: Bool = AppSettings.verboseMode

    private var agentDetailSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Agents")
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(.white.opacity(0.7))

            Toggle(isOn: Binding(
                get: { displaySettings.showAgentDetail },
                set: { displaySettings.showAgentDetail = $0 }
            )) {
                Text("显示代理活动详情")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.white.opacity(0.7))
            }
            .toggleStyle(.switch)
            .tint(.blue)

            Toggle(isOn: Binding(
                get: { verboseMode },
                set: { newValue in
                    verboseMode = newValue
                    AppSettings.verboseMode = newValue
                }
            )) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("详细模式")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.white.opacity(0.7))
                    Text("显示工具调用参数和输出预览")
                        .font(.system(size: 10))
                        .foregroundColor(.white.opacity(0.4))
                }
            }
            .toggleStyle(.switch)
            .tint(.blue)

            // Agent detail preview
            agentDetailPreview
        }
    }

    private var agentDetailPreview: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 4) {
                Image(systemName: "arrow.triangle.branch")
                    .font(.system(size: 10))
                    .foregroundColor(.white.opacity(0.4))
                Text("Subagents (2)")
                    .font(.system(size: 11))
                    .foregroundColor(.white.opacity(0.5))
            }

            // Example subagent 1
            HStack(spacing: 6) {
                Circle().fill(.blue).frame(width: 6, height: 6)
                Text("Explore (Search API endpoints)")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.white)
                Text("8s")
                    .font(.system(size: 10))
                    .foregroundColor(.white.opacity(0.4))
            }

            if displaySettings.showAgentDetail {
                HStack(spacing: 6) {
                    Text("  └")
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundColor(.white.opacity(0.2))
                    Text("Grep: handleRequest")
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundColor(.white.opacity(0.4))
                }
            }

            // Example subagent 2
            HStack(spacing: 6) {
                Circle().fill(.green).frame(width: 6, height: 6)
                Text("Explore (Read config files)")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.white)
                Text("Done")
                    .font(.system(size: 10))
                    .foregroundColor(.white.opacity(0.4))
            }
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(.black.opacity(0.4))
        )
    }
}
