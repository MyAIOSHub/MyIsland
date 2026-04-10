//
//  NotchMenuView.swift
//  MyIsland
//
//  Minimal menu matching Dynamic Island aesthetic
//

import ApplicationServices
import Combine
import SwiftUI
import ServiceManagement
import Sparkle

// MARK: - NotchMenuView

struct NotchMenuView: View {
    @ObservedObject var viewModel: NotchViewModel
    @ObservedObject private var updateManager = UpdateManager.shared
    @ObservedObject private var screenSelector = ScreenSelector.shared
    @ObservedObject private var soundSelector = SoundSelector.shared
    @State private var claudeHookInstalled: Bool = false
    @State private var codexHookInstalled: Bool = false
    @State private var geminiHookInstalled: Bool = false
    @State private var copilotHookInstalled: Bool = false
    @State private var openclawEnabled: Bool = false
    @State private var openclawGatewayRunning: Bool = false
    @State private var launchAtLogin: Bool = false
    @ObservedObject private var voiceCoordinator = VoiceInputCoordinator.shared

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
        VStack(spacing: 4) {
            // Back button
            MenuRow(
                icon: "chevron.left",
                label: "返回"
            ) {
                viewModel.toggleMenu()
            }

            Divider()
                .background(DesignTokens.Border.subtle)
                .padding(.vertical, DesignTokens.Spacing.xxs)

            // Sound settings (full panel)
            MenuRow(
                icon: "speaker.wave.2",
                label: "声音设置"
            ) {
                withAnimation(.easeInOut(duration: 0.25)) {
                    viewModel.contentType = .soundSettings
                }
            }

            // Display settings
            MenuRow(
                icon: "display",
                label: "显示设置"
            ) {
                withAnimation(.easeInOut(duration: 0.25)) {
                    viewModel.contentType = .displaySettings
                }
            }

            // Pet gacha
            MenuRow(
                icon: "pawprint",
                label: "\u{1F3B4} \u{5BA0}\u{7269}"
            ) {
                withAnimation(.easeInOut(duration: 0.25)) {
                    viewModel.contentType = .petGacha
                }
            }

            // Voice settings
            MenuRow(
                icon: "mic",
                label: "语音设置"
            ) {
                withAnimation(.easeInOut(duration: 0.25)) {
                    viewModel.contentType = .voiceSettings
                }
            }

            // Browser activity
            MenuRow(
                icon: "globe",
                label: "浏览器活动"
            ) {
                withAnimation(.easeInOut(duration: 0.25)) {
                    viewModel.contentType = .browserActivity
                }
            }

            AccessibilityRow(isEnabled: AXIsProcessTrusted())

            // System settings
            MenuToggleRow(
                icon: "power",
                label: "开机启动",
                isOn: launchAtLogin
            ) {
                do {
                    if launchAtLogin {
                        try SMAppService.mainApp.unregister()
                        launchAtLogin = false
                    } else {
                        try SMAppService.mainApp.register()
                        launchAtLogin = true
                    }
                } catch {
                    print("Failed to toggle launch at login: \(error)")
                }
            }

            Divider()
                .background(DesignTokens.Border.subtle)
                .padding(.vertical, DesignTokens.Spacing.xxs)

            MenuToggleRow(
                    icon: "terminal",
                    label: "Claude Code",
                    subtitle: HookTarget.claude.settingsURL.path.replacingOccurrences(of: FileManager.default.homeDirectoryForCurrentUser.path, with: "~"),
                    isOn: claudeHookInstalled
                ) {
                    if claudeHookInstalled {
                        HookInstaller.uninstall(target: .claude)
                        claudeHookInstalled = false
                    } else {
                        HookInstaller.installIfNeeded(target: .claude)
                        claudeHookInstalled = true
                    }
                }

                MenuToggleRow(
                    icon: "chevron.left.forwardslash.chevron.right",
                    label: "Codex",
                    subtitle: HookTarget.codex.settingsURL.path.replacingOccurrences(of: FileManager.default.homeDirectoryForCurrentUser.path, with: "~"),
                    isOn: codexHookInstalled
                ) {
                    if codexHookInstalled {
                        HookInstaller.uninstall(target: .codex)
                        codexHookInstalled = false
                    } else {
                        HookInstaller.installIfNeeded(target: .codex)
                        codexHookInstalled = true
                    }
                }

                MenuToggleRow(
                    icon: "sparkles",
                    label: "Gemini CLI",
                    subtitle: HookTarget.gemini.settingsURL.path.replacingOccurrences(of: FileManager.default.homeDirectoryForCurrentUser.path, with: "~"),
                    isOn: geminiHookInstalled
                ) {
                    if geminiHookInstalled {
                        HookInstaller.uninstall(target: .gemini)
                        geminiHookInstalled = false
                    } else {
                        HookInstaller.installIfNeeded(target: .gemini)
                        geminiHookInstalled = true
                    }
                }

                MenuToggleRow(
                    icon: "cursorarrow.rays",
                    label: "Copilot",
                    subtitle: HookTarget.copilot.settingsURL.path.replacingOccurrences(of: FileManager.default.homeDirectoryForCurrentUser.path, with: "~"),
                    isOn: copilotHookInstalled
                ) {
                    if copilotHookInstalled {
                        HookInstaller.uninstall(target: .copilot)
                        copilotHookInstalled = false
                    } else {
                        HookInstaller.installIfNeeded(target: .copilot)
                        copilotHookInstalled = true
                    }
                }

                OpenClawToggleRow(
                    isOn: $openclawEnabled,
                    isGatewayRunning: openclawGatewayRunning
                )

            // Antigravity (IDE)
            AntigravityHookRow(
                isEnabled: .init(
                    get: { AntigravityWatcher.shared.isEnabled },
                    set: { AntigravityWatcher.shared.isEnabled = $0 }
                ),
                isInstalled: AntigravityWatcher.shared.isInstalled,
                isRunning: AntigravityWatcher.shared.isAppRunning
            )

            Divider()
                .background(DesignTokens.Border.subtle)
                .padding(.vertical, DesignTokens.Spacing.xxs)

            UpdateRow(updateManager: updateManager)

            MenuRow(
                icon: "xmark.circle",
                label: String(localized: "beta.quit"),
                isDestructive: true
            ) {
                NSApplication.shared.terminate(nil)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 8)
        } // ScrollView
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .onAppear {
            refreshStates()
        }
        .onChange(of: viewModel.contentType) { _, newValue in
            if newValue == .menu {
                refreshStates()
            }
        }
    }

    private func refreshStates() {
        claudeHookInstalled = HookInstaller.isInstalled(target: .claude)
        codexHookInstalled = HookInstaller.isInstalled(target: .codex)
        geminiHookInstalled = HookInstaller.isInstalled(target: .gemini)
        copilotHookInstalled = HookInstaller.isInstalled(target: .copilot)
        openclawEnabled = UserDefaults.standard.bool(forKey: "openclawEnabled")
        openclawGatewayRunning = OpenClawGateway.isRunning()
        launchAtLogin = SMAppService.mainApp.status == .enabled
        screenSelector.refreshScreens()
    }
}

// MARK: - Update Row

struct UpdateRow: View {
    @ObservedObject var updateManager: UpdateManager
    @State private var isHovered = false
    @State private var isSpinning = false

    private var appVersion: String {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
        return "v\(version) (\(build))"
    }

    var body: some View {
        Button {
            handleTap()
        } label: {
            HStack(spacing: 10) {
                // Icon
                ZStack {
                    if case .installing = updateManager.state {
                        Image(systemName: "gear")
                            .font(.system(size: 12))
                            .foregroundColor(TerminalColors.blue)
                            .rotationEffect(.degrees(isSpinning ? 360 : 0))
                            .animation(.linear(duration: 1).repeatForever(autoreverses: false), value: isSpinning)
                            .onAppear { isSpinning = true }
                    } else {
                        Image(systemName: icon)
                            .font(.system(size: 12))
                            .foregroundColor(iconColor)
                    }
                }
                .frame(width: 16)

                // Label
                Text(label)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(labelColor)

                Spacer()

                // Right side: progress or status
                rightContent
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(isHovered && isInteractive ? DesignTokens.Surface.hover : Color.clear)
            )
        }
        .buttonStyle(.plain)
        .disabled(!isInteractive)
        .onHover { isHovered = $0 }
        .animation(.easeInOut(duration: 0.2), value: updateManager.state)
    }

    // MARK: - Right Content

    @ViewBuilder
    private var rightContent: some View {
        switch updateManager.state {
        case .idle:
            Text(appVersion)
                .font(.system(size: 11))
                .foregroundColor(.white.opacity(0.4))

        case .upToDate:
            HStack(spacing: 6) {
                Image(systemName: "checkmark")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundColor(TerminalColors.green)
                Text("已是最新")
                    .font(.system(size: 11))
                    .foregroundColor(TerminalColors.green)
            }

        case .checking, .installing:
            ProgressView()
                .scaleEffect(0.5)
                .frame(width: 12, height: 12)

        case .found(let version, _):
            HStack(spacing: 6) {
                Circle()
                    .fill(TerminalColors.green)
                    .frame(width: 6, height: 6)
                Text("v\(version)")
                    .font(.system(size: 11))
                    .foregroundColor(TerminalColors.green)
            }

        case .downloading(let progress):
            HStack(spacing: 8) {
                ProgressView(value: progress)
                    .frame(width: 60)
                    .tint(TerminalColors.blue)
                Text("\(Int(progress * 100))%")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(TerminalColors.blue)
                    .frame(width: 32, alignment: .trailing)
            }

        case .extracting(let progress):
            HStack(spacing: 8) {
                ProgressView(value: progress)
                    .frame(width: 60)
                    .tint(TerminalColors.amber)
                Text("\(Int(progress * 100))%")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(TerminalColors.amber)
                    .frame(width: 32, alignment: .trailing)
            }

        case .readyToInstall(let version):
            HStack(spacing: 6) {
                Circle()
                    .fill(TerminalColors.green)
                    .frame(width: 6, height: 6)
                Text("v\(version)")
                    .font(.system(size: 11))
                    .foregroundColor(TerminalColors.green)
            }

        case .error:
            Text("重试")
                .font(.system(size: 11))
                .foregroundColor(.white.opacity(0.5))
        }
    }

    // MARK: - Computed Properties

    private var icon: String {
        switch updateManager.state {
        case .idle:
            return "arrow.down.circle"
        case .checking:
            return "arrow.down.circle"
        case .upToDate:
            return "checkmark.circle.fill"
        case .found:
            return "arrow.down.circle.fill"
        case .downloading:
            return "arrow.down.circle"
        case .extracting:
            return "doc.zipper"
        case .readyToInstall:
            return "checkmark.circle.fill"
        case .installing:
            return "gear"
        case .error:
            return "exclamationmark.circle"
        }
    }

    private var iconColor: Color {
        switch updateManager.state {
        case .idle:
            return isHovered ? DesignTokens.Text.primary : DesignTokens.Text.secondary
        case .checking:
            return DesignTokens.Text.secondary
        case .upToDate:
            return TerminalColors.green
        case .found, .readyToInstall:
            return TerminalColors.green
        case .downloading:
            return TerminalColors.blue
        case .extracting:
            return TerminalColors.amber
        case .installing:
            return TerminalColors.blue
        case .error:
            return Color(red: 1.0, green: 0.4, blue: 0.4)
        }
    }

    private var label: String {
        switch updateManager.state {
        case .idle:
            return "检查更新"
        case .checking:
            return "检查中..."
        case .upToDate:
            return "检查更新"
        case .found:
            return "下载更新"
        case .downloading:
            return "下载中..."
        case .extracting:
            return "解压中..."
        case .readyToInstall:
            return "重启并安装"
        case .installing:
            return "安装中..."
        case .error:
            return "更新失败"
        }
    }

    private var labelColor: Color {
        switch updateManager.state {
        case .idle, .upToDate:
            return isHovered ? DesignTokens.Text.primary : DesignTokens.Text.secondary
        case .checking, .downloading, .extracting, .installing:
            return DesignTokens.Text.primary
        case .found, .readyToInstall:
            return TerminalColors.green
        case .error:
            return Color(red: 1.0, green: 0.4, blue: 0.4)
        }
    }

    private var isInteractive: Bool {
        switch updateManager.state {
        case .idle, .upToDate, .found, .readyToInstall, .error:
            return true
        case .checking, .downloading, .extracting, .installing:
            return false
        }
    }

    // MARK: - Actions

    private func handleTap() {
        switch updateManager.state {
        case .idle, .upToDate, .error:
            updateManager.checkForUpdates()
        case .found:
            updateManager.downloadAndInstall()
        case .readyToInstall:
            updateManager.installAndRelaunch()
        default:
            break
        }
    }
}

// MARK: - ASR Mode Selector Row

struct ASRModeRow: View {
    @ObservedObject private var processor = ASRPostProcessor.shared
    @State private var isHovered = false

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "text.badge.checkmark")
                .font(.system(size: 12))
                .foregroundColor(textColor)
                .frame(width: 16)

            Text("ASR模式")
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(textColor)

            Spacer()

            HStack(spacing: 2) {
                ForEach(ASRMode.allCases, id: \.self) { mode in
                    Button {
                        withAnimation(.easeInOut(duration: 0.15)) {
                            processor.selectedMode = mode
                        }
                    } label: {
                        Text(mode.displayName)
                            .font(.system(size: 10, weight: processor.selectedMode == mode ? .bold : .regular))
                            .foregroundColor(processor.selectedMode == mode ? .black : .white.opacity(0.5))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 3)
                            .background(
                                RoundedRectangle(cornerRadius: 4)
                                    .fill(processor.selectedMode == mode ? Color.white : DesignTokens.Surface.hover)
                            )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(isHovered ? DesignTokens.Surface.hover : Color.clear)
        )
        .onHover { isHovered = $0 }
    }

    private var textColor: Color {
        .white.opacity(isHovered ? 1.0 : 0.7)
    }
}

// MARK: - API Key Input Row

struct APIKeyRow: View {
    @ObservedObject private var processor = ASRPostProcessor.shared
    @State private var isEditing = false
    @State private var isHovered = false

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "key.fill")
                .font(.system(size: 12))
                .foregroundColor(textColor)
                .frame(width: 16)

            Text("LLM API Key")
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(textColor)

            Spacer()

            if isEditing {
                SecureField("sk-...", text: $processor.apiKey)
                    .font(.system(size: 11, design: .monospaced))
                    .textFieldStyle(.plain)
                    .frame(width: 120)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(
                        RoundedRectangle(cornerRadius: 4)
                            .fill(Color.white.opacity(0.1))
                    )
                    .onSubmit { isEditing = false }

                Button {
                    isEditing = false
                } label: {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 14))
                        .foregroundColor(.green)
                }
                .buttonStyle(.plain)
            } else {
                if processor.hasApiKey {
                    Text("sk-...\(String(processor.apiKey.suffix(4)))")
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundColor(.white.opacity(0.4))
                } else {
                    Text("未设置")
                        .font(.system(size: 11))
                        .foregroundColor(.white.opacity(0.3))
                }

                Button {
                    isEditing = true
                } label: {
                    Text(processor.hasApiKey ? "修改" : "设置")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(.black)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(
                            RoundedRectangle(cornerRadius: 4)
                                .fill(Color.white)
                        )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(isHovered ? DesignTokens.Surface.hover : Color.clear)
        )
        .onHover { isHovered = $0 }
    }

    private var textColor: Color {
        .white.opacity(isHovered ? 1.0 : 0.7)
    }
}

// MARK: - Base URL Input Row

struct BaseURLRow: View {
    @ObservedObject private var processor = ASRPostProcessor.shared
    @State private var isEditing = false
    @State private var isHovered = false

    private var displayURL: String {
        let url = processor.baseURL
        // Show shortened version: remove https:// prefix
        return url.replacingOccurrences(of: "https://", with: "").prefix(30) + (url.count > 38 ? "..." : "")
    }

    private var isDefault: Bool {
        processor.baseURL == ASRPostProcessor.defaultBaseURL
    }

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "link")
                .font(.system(size: 12))
                .foregroundColor(textColor)
                .frame(width: 16)

            Text("Base URL")
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(textColor)

            Spacer()

            if isEditing {
                TextField("https://...", text: $processor.baseURL)
                    .font(.system(size: 10, design: .monospaced))
                    .textFieldStyle(.plain)
                    .frame(width: 160)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(
                        RoundedRectangle(cornerRadius: 4)
                            .fill(Color.white.opacity(0.1))
                    )
                    .onSubmit { isEditing = false }

                Button {
                    isEditing = false
                } label: {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 14))
                        .foregroundColor(.green)
                }
                .buttonStyle(.plain)
            } else {
                Text(isDefault ? "百炼" : String(displayURL))
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundColor(.white.opacity(0.4))
                    .lineLimit(1)

                Button {
                    isEditing = true
                } label: {
                    Text("修改")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(.black)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(
                            RoundedRectangle(cornerRadius: 4)
                                .fill(Color.white)
                        )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(isHovered ? DesignTokens.Surface.hover : Color.clear)
        )
        .onHover { isHovered = $0 }
    }

    private var textColor: Color {
        .white.opacity(isHovered ? 1.0 : 0.7)
    }
}

// MARK: - Accessibility Permission Row

struct AccessibilityRow: View {
    let isEnabled: Bool

    @State private var isHovered = false
    @State private var refreshTrigger = false

    private var currentlyEnabled: Bool {
        // Re-check on each render when refreshTrigger changes
        _ = refreshTrigger
        return isEnabled
    }

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "hand.raised")
                .font(.system(size: 12))
                .foregroundColor(textColor)
                .frame(width: 16)

            Text("辅助功能")
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(textColor)

            Spacer()

            if isEnabled {
                Circle()
                    .fill(TerminalColors.green)
                    .frame(width: 6, height: 6)

                Text("已开启")
                    .font(.system(size: 11))
                    .foregroundColor(.white.opacity(0.4))
            } else {
                Button(action: openAccessibilitySettings) {
                    Text("开启")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(.black)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(
                            RoundedRectangle(cornerRadius: 5)
                                .fill(Color.white)
                        )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(isHovered ? DesignTokens.Surface.hover : Color.clear)
        )
        .onHover { isHovered = $0 }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            refreshTrigger.toggle()
        }
    }

    private var textColor: Color {
        .white.opacity(isHovered ? 1.0 : 0.7)
    }

    private func openAccessibilitySettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }
}

struct MenuRow: View {
    let icon: String
    let label: String
    var isDestructive: Bool = false
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: icon)
                    .font(.system(size: 12))
                    .foregroundColor(textColor)
                    .frame(width: 16)

                Text(label)
                    .font(DesignTokens.Font.heading())
                    .foregroundColor(textColor)

                Spacer()
            }
            .padding(.horizontal, DesignTokens.Spacing.md)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: DesignTokens.Radius.lg)
                    .fill(isHovered ? DesignTokens.Surface.hover : Color.clear)
            )
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
    }

    private var textColor: Color {
        if isDestructive {
            return TerminalColors.red
        }
        return isHovered ? DesignTokens.Text.primary : DesignTokens.Text.secondary
    }
}

struct MenuToggleRow: View {
    let icon: String
    let label: String
    var subtitle: String? = nil
    let isOn: Bool
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: icon)
                    .font(.system(size: 12))
                    .foregroundColor(textColor)
                    .frame(width: 16)

                VStack(alignment: .leading, spacing: 1) {
                    Text(label)
                        .font(DesignTokens.Font.heading())
                        .foregroundColor(textColor)

                    if let subtitle {
                        Text(subtitle)
                            .font(.system(size: 9))
                            .foregroundColor(DesignTokens.Text.tertiary)
                            .lineLimit(1)
                    }
                }

                Spacer()

                Circle()
                    .fill(isOn ? TerminalColors.green : DesignTokens.Text.tertiary)
                    .frame(width: 6, height: 6)

                Text(isOn ? "已开启" : "关闭")
                    .font(DesignTokens.Font.body())
                    .foregroundColor(DesignTokens.Text.tertiary)
            }
            .padding(.horizontal, DesignTokens.Spacing.md)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(isHovered ? DesignTokens.Surface.hover : Color.clear)
            )
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
    }

    private var textColor: Color {
        isHovered ? DesignTokens.Text.primary : DesignTokens.Text.secondary
    }
}


// MARK: - Antigravity Hook Row

struct AntigravityHookRow: View {
    @Binding var isEnabled: Bool
    let isInstalled: Bool
    let isRunning: Bool

    @State private var isHovered = false

    var body: some View {
        Button {
            guard isInstalled else { return }
            isEnabled.toggle()
            AntigravityWatcher.shared.isEnabled = isEnabled
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "atom")
                    .font(.system(size: 12))
                    .foregroundColor(textColor)
                    .frame(width: 16)

                VStack(alignment: .leading, spacing: 1) {
                    Text("Antigravity")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(textColor)

                    Text("内置 Gemini Agent · state.vscdb")
                        .font(.system(size: 9))
                        .foregroundColor(.white.opacity(0.3))
                        .lineLimit(1)
                }

                Spacer()

                if !isInstalled {
                    Text("未安装")
                        .font(.system(size: 11))
                        .foregroundColor(.white.opacity(0.3))
                } else if isEnabled {
                    Circle()
                        .fill(isRunning ? TerminalColors.green : Color.orange)
                        .frame(width: 6, height: 6)
                    Text(isRunning ? "监听中" : "待启动")
                        .font(.system(size: 11))
                        .foregroundColor(.white.opacity(0.4))
                } else {
                    Circle()
                        .fill(Color.white.opacity(0.3))
                        .frame(width: 6, height: 6)
                    Text("关闭")
                        .font(.system(size: 11))
                        .foregroundColor(.white.opacity(0.4))
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(isHovered && isInstalled ? DesignTokens.Surface.hover : Color.clear)
            )
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .disabled(!isInstalled)
    }

    private var textColor: Color {
        guard isInstalled else { return .white.opacity(0.3) }
        return .white.opacity(isHovered ? 1.0 : 0.7)
    }
}

struct IDEExtInfo: Identifiable {
    let id = UUID()
    let name: String
    let subtitle: String?
    let icon: String
    let installURL: String?
    let bundleId: String

    var isInstalled: Bool {
        NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleId) != nil
    }
}

struct IDEExtRow: View {
    let ext: IDEExtInfo
    @State private var isHovered = false

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: ext.icon)
                .font(.system(size: 12))
                .foregroundColor(.white.opacity(0.7))
                .frame(width: 16)

            VStack(alignment: .leading, spacing: 1) {
                Text(ext.name)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(.white.opacity(isHovered ? 1.0 : 0.7))

                if let sub = ext.subtitle {
                    Text(sub)
                        .font(.system(size: 9))
                        .foregroundColor(.white.opacity(0.35))
                }
            }

            Spacer()

            if ext.isInstalled {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 12))
                    .foregroundColor(TerminalColors.green)
                Text("已安装")
                    .font(.system(size: 10))
                    .foregroundColor(.white.opacity(0.4))
            } else if ext.installURL != nil {
                Button {
                    if let urlStr = ext.installURL, let url = URL(string: urlStr) {
                        NSWorkspace.shared.open(url)
                    }
                } label: {
                    Text("安装")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Color.orange)
                        .clipShape(RoundedRectangle(cornerRadius: 4))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(isHovered ? Color.white.opacity(0.06) : Color.clear)
        )
        .onHover { isHovered = $0 }
    }
}

// MARK: - OpenClaw Gateway

/// Lightweight check for the OpenClaw WebSocket gateway.
enum OpenClawGateway {
    static var port: Int {
        let saved = UserDefaults.standard.integer(forKey: "openClawPort")
        return saved > 0 ? saved : 18789
    }

    /// Quick TCP probe to see if anything is listening on the port.
    static func isRunning() -> Bool {
        let fd = socket(AF_INET, SOCK_STREAM, 0)
        guard fd >= 0 else { return false }
        defer { close(fd) }

        var addr = sockaddr_in()
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_port = in_port_t(port).bigEndian
        addr.sin_addr.s_addr = inet_addr("127.0.0.1")

        let result = withUnsafePointer(to: &addr) { ptr in
            ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockPtr in
                Darwin.connect(fd, sockPtr, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        return result == 0
    }
}

// MARK: - OpenClaw Toggle Row

struct OpenClawToggleRow: View {
    @Binding var isOn: Bool
    let isGatewayRunning: Bool

    @State private var isHovered = false
    @State private var isEditingPort = false
    @State private var portText: String = ""

    var body: some View {
        VStack(spacing: 0) {
            Button {
                isOn.toggle()
                UserDefaults.standard.set(isOn, forKey: "openclawEnabled")
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: "network")
                        .font(.system(size: 12))
                        .foregroundColor(textColor)
                        .frame(width: 16)

                    VStack(alignment: .leading, spacing: 1) {
                        Text("OpenClaw")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(textColor)

                        HStack(spacing: 4) {
                            Text("ws://localhost:\(OpenClawGateway.port)")
                                .font(.system(size: 9))
                                .foregroundColor(.white.opacity(0.3))
                                .lineLimit(1)

                            Button {
                                portText = "\(OpenClawGateway.port)"
                                isEditingPort.toggle()
                            } label: {
                                Image(systemName: "pencil")
                                    .font(.system(size: 8))
                                    .foregroundColor(.white.opacity(0.3))
                            }
                            .buttonStyle(.plain)
                        }
                    }

                    Spacer()

                    if isOn {
                        Circle()
                            .fill(isGatewayRunning ? TerminalColors.green : Color.orange)
                            .frame(width: 6, height: 6)

                        Text(isGatewayRunning ? "已连接" : "未就绪")
                            .font(.system(size: 11))
                            .foregroundColor(.white.opacity(0.4))
                    } else {
                        Circle()
                            .fill(Color.white.opacity(0.3))
                            .frame(width: 6, height: 6)

                        Text("关闭")
                            .font(.system(size: 11))
                            .foregroundColor(.white.opacity(0.4))
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
            }
            .buttonStyle(.plain)

            if isEditingPort {
                HStack(spacing: 6) {
                    Text("端口")
                        .font(.system(size: 11))
                        .foregroundColor(.white.opacity(0.5))

                    TextField("18789", text: $portText)
                        .font(.system(size: 11, design: .monospaced))
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 70)
                        .onSubmit { savePort() }

                    Button("确定") { savePort() }
                        .font(.system(size: 10, weight: .medium))
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                }
                .padding(.horizontal, 40)
                .padding(.bottom, 8)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(isHovered ? DesignTokens.Surface.hover : Color.clear)
        )
        .onHover { isHovered = $0 }
        .animation(.easeInOut(duration: 0.2), value: isEditingPort)
    }

    private var textColor: Color {
        .white.opacity(isHovered ? 1.0 : 0.7)
    }

    private func savePort() {
        if let port = Int(portText), port > 0, port <= 65535 {
            UserDefaults.standard.set(port, forKey: "openClawPort")
        }
        isEditingPort = false
    }
}
