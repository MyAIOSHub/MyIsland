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
                .background(Color.white.opacity(0.08))
                .padding(.vertical, 4)

            // Appearance settings
            ScreenPickerRow(screenSelector: screenSelector)
            SoundPickerRow(soundSelector: soundSelector)

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

            // Voice input toggle
            MenuToggleRow(
                icon: "mic",
                label: "语音输入 (Fn)",
                isOn: voiceCoordinator.isEnabled
            ) {
                voiceCoordinator.isEnabled.toggle()
            }

            Divider()
                .background(Color.white.opacity(0.08))
                .padding(.vertical, 4)

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

            // CLI Hooks section
            Text("CLI Hooks")
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(.white.opacity(0.4))
                .padding(.horizontal, 12)
                .padding(.top, 4)

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

            AccessibilityRow(isEnabled: AXIsProcessTrusted())

            Divider()
                .background(Color.white.opacity(0.08))
                .padding(.vertical, 4)

            // IDE Extensions section
            IDEExtensionsSection()

            Divider()
                .background(Color.white.opacity(0.08))
                .padding(.vertical, 4)

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
                    .fill(isHovered && isInteractive ? Color.white.opacity(0.08) : Color.clear)
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
                Text("Up to date")
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
            Text("Retry")
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
            return .white.opacity(isHovered ? 1.0 : 0.7)
        case .checking:
            return .white.opacity(0.7)
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
            return "Check for Updates"
        case .checking:
            return "Checking..."
        case .upToDate:
            return "Check for Updates"
        case .found:
            return "Download Update"
        case .downloading:
            return "Downloading..."
        case .extracting:
            return "Extracting..."
        case .readyToInstall:
            return "Install & Relaunch"
        case .installing:
            return "Installing..."
        case .error:
            return "Update failed"
        }
    }

    private var labelColor: Color {
        switch updateManager.state {
        case .idle, .upToDate:
            return .white.opacity(isHovered ? 1.0 : 0.7)
        case .checking, .downloading, .extracting, .installing:
            return .white.opacity(0.9)
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
                .fill(isHovered ? Color.white.opacity(0.08) : Color.clear)
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
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(textColor)

                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(isHovered ? Color.white.opacity(0.08) : Color.clear)
            )
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
    }

    private var textColor: Color {
        if isDestructive {
            return Color(red: 1.0, green: 0.4, blue: 0.4)
        }
        return .white.opacity(isHovered ? 1.0 : 0.7)
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
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(textColor)

                    if let subtitle {
                        Text(subtitle)
                            .font(.system(size: 9))
                            .foregroundColor(.white.opacity(0.3))
                            .lineLimit(1)
                    }
                }

                Spacer()

                Circle()
                    .fill(isOn ? TerminalColors.green : Color.white.opacity(0.3))
                    .frame(width: 6, height: 6)

                Text(isOn ? "已开启" : "关闭")
                    .font(.system(size: 11))
                    .foregroundColor(.white.opacity(0.4))
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(isHovered ? Color.white.opacity(0.08) : Color.clear)
            )
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
    }

    private var textColor: Color {
        .white.opacity(isHovered ? 1.0 : 0.7)
    }
}

// MARK: - IDE Extensions Section

struct IDEExtensionsSection: View {
    @State private var antigravityEnabled = AntigravityWatcher.shared.isEnabled
    private let antigravityInstalled = AntigravityWatcher.shared.isInstalled
    private let antigravityRunning = AntigravityWatcher.shared.isAppRunning

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("IDE 扩展")
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(.white.opacity(0.4))
                .padding(.horizontal, 12)
                .padding(.top, 4)

            // Antigravity built-in agent hook
            AntigravityHookRow(
                isEnabled: $antigravityEnabled,
                isInstalled: antigravityInstalled,
                isRunning: antigravityRunning
            )
        }
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
                    .fill(isHovered && isInstalled ? Color.white.opacity(0.08) : Color.clear)
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
                .fill(isHovered ? Color.white.opacity(0.08) : Color.clear)
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
