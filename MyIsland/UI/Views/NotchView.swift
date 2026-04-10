//
//  NotchView.swift
//  MyIsland
//
//  The main dynamic island SwiftUI view with accurate notch shape
//

import AppKit
import CoreGraphics
import SwiftUI

// Corner radius constants
private let cornerRadiusInsets = (
    opened: (top: CGFloat(19), bottom: CGFloat(24)),
    closed: (top: CGFloat(6), bottom: CGFloat(14))
)

struct NotchView: View {
    @ObservedObject var viewModel: NotchViewModel
    @StateObject private var sessionMonitor = ClaudeSessionMonitor()
    @StateObject private var activityCoordinator = NotchActivityCoordinator.shared
    @ObservedObject private var updateManager = UpdateManager.shared
    @ObservedObject private var petGacha = PetGachaSystem.shared
    @ObservedObject private var voiceCoordinator = VoiceInputCoordinator.shared
    @State private var previousPendingIds: Set<String> = []
    @State private var previousWaitingForInputIds: Set<String> = []
    @State private var waitingForInputTimestamps: [String: Date] = [:]  // sessionId -> when it entered waitingForInput
    @State private var isVisible: Bool = true  // Always visible - persistent notch
    @State private var isHovering: Bool = false
    @State private var isBouncing: Bool = false

    @Namespace private var activityNamespace

    /// Whether any Claude session is currently processing or compacting
    private var isAnyProcessing: Bool {
        sessionMonitor.instances.contains { $0.phase == .processing || $0.phase == .compacting }
    }

    /// Count of active sessions (processing or waiting for approval)
    private var activeSessionCount: Int {
        sessionMonitor.instances.filter { $0.phase == .processing || $0.phase == .compacting || $0.phase.isWaitingForApproval }.count
    }

    /// Total active tools across all sessions
    private var totalActiveToolCount: Int {
        sessionMonitor.instances.reduce(0) { $0 + $1.activeToolCount }
    }

    /// Whether any Claude session has a pending permission request
    private var hasPendingPermission: Bool {
        sessionMonitor.instances.contains { $0.phase.isWaitingForApproval }
    }

    /// Whether any Claude session is waiting for user input (done/ready state) within the display window
    private var hasWaitingForInput: Bool {
        let now = Date()
        let displayDuration: TimeInterval = 30  // Show checkmark for 30 seconds

        return sessionMonitor.instances.contains { session in
            guard session.phase == .waitingForInput else { return false }
            // Only show if within the 30-second display window
            if let enteredAt = waitingForInputTimestamps[session.stableId] {
                return now.timeIntervalSince(enteredAt) < displayDuration
            }
            return false
        }
    }

    // MARK: - Sizing

    private var closedNotchSize: CGSize {
        let width: CGFloat
        if DisplaySettings.shared.layoutMode == .detailed {
            let fullWidth = DisplaySettings.shared.detailedExtraWidth  // default 320pt
            // Same width for both idle and active states
            width = fullWidth
        } else {
            width = viewModel.deviceNotchRect.width
        }
        return CGSize(
            width: width,
            height: viewModel.deviceNotchRect.height
        )
    }

    /// Extra width for expanding activities (like Dynamic Island)
    private var expansionWidth: CGFloat {
        // Permission indicator adds width on left side only
        let permissionIndicatorWidth: CGFloat = hasPendingPermission ? 18 : 0

        // Expand for processing activity
        if activityCoordinator.expandingActivity.show {
            switch activityCoordinator.expandingActivity.type {
            case .claude:
                let baseWidth = 2 * max(0, closedNotchSize.height - 12) + 20
                return baseWidth + permissionIndicatorWidth
            case .none:
                break
            }
        }

        // Expand for pending permissions (left indicator) or waiting for input (checkmark on right)
        if hasPendingPermission {
            return 2 * max(0, closedNotchSize.height - 12) + 20 + permissionIndicatorWidth
        }

        // Waiting for input just shows checkmark on right, no extra left indicator
        if hasWaitingForInput {
            return 2 * max(0, closedNotchSize.height - 12) + 20
        }

        return 0
    }

    private var notchSize: CGSize {
        switch viewModel.status {
        case .closed, .popping:
            return closedNotchSize
        case .opened:
            return viewModel.openedSize
        }
    }

    /// Width of the closed content (notch + any expansion)
    private var closedContentWidth: CGFloat {
        closedNotchSize.width + expansionWidth
    }

    // MARK: - Corner Radii

    private var topCornerRadius: CGFloat {
        viewModel.status == .opened
            ? cornerRadiusInsets.opened.top
            : cornerRadiusInsets.closed.top
    }

    private var bottomCornerRadius: CGFloat {
        viewModel.status == .opened
            ? cornerRadiusInsets.opened.bottom
            : cornerRadiusInsets.closed.bottom
    }

    private var currentNotchShape: NotchShape {
        NotchShape(
            topCornerRadius: topCornerRadius,
            bottomCornerRadius: bottomCornerRadius
        )
    }

    // Animation springs
    private let openAnimation = Animation.spring(response: 0.42, dampingFraction: 0.8, blendDuration: 0)
    private let closeAnimation = Animation.spring(response: 0.45, dampingFraction: 1.0, blendDuration: 0)

    // MARK: - Body

    var body: some View {
        ZStack(alignment: .top) {
            // Outer container does NOT receive hits - only the notch content does
            VStack(spacing: 0) {
                notchLayout
                    .frame(
                        maxWidth: viewModel.status == .opened ? notchSize.width : closedContentWidth,
                        alignment: .top
                    )
                    .padding(
                        .horizontal,
                        viewModel.status == .opened
                            ? cornerRadiusInsets.opened.top
                            : cornerRadiusInsets.closed.bottom
                    )
                    .padding([.horizontal, .bottom], viewModel.status == .opened ? 12 : 0)
                    .background(.black)
                    .clipShape(currentNotchShape)
                    .overlay(alignment: .top) {
                        Rectangle()
                            .fill(.black)
                            .frame(height: 1)
                            .padding(.horizontal, topCornerRadius)
                    }
                    .shadow(
                        color: (viewModel.status == .opened || isHovering) ? .black.opacity(0.7) : .clear,
                        radius: 6
                    )
                    .frame(
                        maxWidth: viewModel.status == .opened ? notchSize.width : closedContentWidth,
                        maxHeight: viewModel.status == .opened ? notchSize.height : closedNotchSize.height,
                        alignment: .top
                    )
                    .animation(viewModel.status == .opened ? openAnimation : closeAnimation, value: viewModel.status)
                    .animation(openAnimation, value: notchSize) // Animate container size changes between content types
                    .animation(.smooth, value: activityCoordinator.expandingActivity)
                    .animation(.smooth, value: hasPendingPermission)
                    .animation(.smooth, value: hasWaitingForInput)
                    .animation(.spring(response: 0.3, dampingFraction: 0.5), value: isBouncing)
                    .contentShape(Rectangle())
                    .onHover { hovering in
                        withAnimation(.spring(response: 0.38, dampingFraction: 0.8)) {
                            isHovering = hovering
                        }
                    }
                    .onTapGesture {
                        if viewModel.status != .opened {
                            viewModel.notchOpen(reason: .click)
                        }
                        // Close is handled by headerRow tap gesture
                    }
            }
        }
        .opacity(isVisible ? 1 : 0)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .preferredColorScheme(.dark)
        .onAppear {
            sessionMonitor.startMonitoring()
            viewModel.onPetIconTapped = { [weak petGacha] in
                petGacha?.randomizeActivePet()
            }
            // On non-notched devices, keep visible so users have a target to interact with
            if !viewModel.hasPhysicalNotch {
                isVisible = true
            }
        }
        .onChange(of: viewModel.status) { oldStatus, newStatus in
            handleStatusChange(from: oldStatus, to: newStatus)
        }
        .onChange(of: sessionMonitor.pendingInstances) { _, sessions in
            handlePendingSessionsChange(sessions)
        }
        .onChange(of: sessionMonitor.instances) { _, instances in
            viewModel.sessionCount = instances.count
            // Calculate extra height for interactive content (AskUserQuestion options, etc.)
            var extraHeight: CGFloat = 0
            for session in instances {
                if let questions = session.pendingQuestions, !questions.isEmpty {
                    for q in questions {
                        extraHeight += 30  // question text
                        extraHeight += CGFloat(q.options.count) * 44  // option cards
                        extraHeight += 36  // jump button + spacing
                    }
                }
            }
            viewModel.interactiveContentHeight = extraHeight
            handleProcessingChange()
            handleWaitingForInputChange(instances)
        }
        .onReceive(NotificationCenter.default.publisher(for: .updateAvailableNotification)) { _ in
            if viewModel.status == .closed {
                viewModel.contentType = .menu
                viewModel.notchOpen(reason: .notification)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .updateReadyToInstallNotification)) { _ in
            if viewModel.status == .closed {
                viewModel.contentType = .menu
                viewModel.notchOpen(reason: .notification)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .browserSummaryCompleted)) { _ in
            if viewModel.status == .closed {
                viewModel.contentType = .browserActivity
                viewModel.notchOpen(reason: .notification)
            }
        }
    }

    // MARK: - Notch Layout

    private var isProcessing: Bool {
        activityCoordinator.expandingActivity.show && activityCoordinator.expandingActivity.type == .claude
    }

    /// Whether to show the expanded closed state (processing, pending permission, or waiting for input)
    private var showClosedActivity: Bool {
        isProcessing || hasPendingPermission || hasWaitingForInput
    }

    @ViewBuilder
    private var notchLayout: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header row - always present, contains crab and spinner that persist across states
            headerRow
                .frame(height: max(24, closedNotchSize.height))

            // Main content only when opened
            if viewModel.status == .opened {
                contentView
                    .frame(width: notchSize.width - 24) // Fixed width to prevent reflow
                    .transition(
                        .asymmetric(
                            insertion: .scale(scale: 0.8, anchor: .top)
                                .combined(with: .opacity)
                                .animation(.smooth(duration: 0.35)),
                            removal: .opacity.animation(.easeOut(duration: 0.15))
                        )
                    )
            }
        }
    }

    // MARK: - Voice Recording Header

    @ViewBuilder
    private var voiceRecordingHeader: some View {
        HStack(spacing: 6) {
            // Left: captured app icon
            if let icon = voiceCoordinator.capturedAppIcon {
                Image(nsImage: icon)
                    .resizable()
                    .frame(width: 16, height: 16)
                    .clipShape(RoundedRectangle(cornerRadius: 3))
            } else {
                Image(systemName: "mic.fill")
                    .font(.system(size: 12))
                    .foregroundColor(.white.opacity(0.8))
            }

            Spacer()

            // Right: waveform or result indicator
            switch voiceCoordinator.voiceState {
            case .recording:
                WaveformView(
                    levels: voiceCoordinator.audioRecorder.audioLevels,
                    mode: voiceCoordinator.audioRecorder.audioLevels.reduce(0, +) / 9.0 > 0.15 ? .speaking : .quiet,
                    barCount: 5, barWidth: 3, spacing: 3,
                    maxHeight: 14, minHeight: 3
                )
                .colorMultiply(.white.opacity(0.9))

            case .processing, .sending:
                WaveformView(
                    levels: Array(repeating: CGFloat(0.1), count: 5),
                    mode: .processing,
                    barCount: 5, barWidth: 3, spacing: 3,
                    maxHeight: 14, minHeight: 3
                )
                .colorMultiply(.white.opacity(0.5))

            case .success:
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(TerminalColors.green)
                    .transition(.scale.combined(with: .opacity))

            case .error:
                Image(systemName: "exclamationmark.circle.fill")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.yellow)
                    .transition(.scale.combined(with: .opacity))

            case .idle:
                EmptyView()
            }
        }
        .padding(.horizontal, 10)
        .animation(.easeInOut(duration: 0.25), value: voiceCoordinator.voiceState)
        .frame(height: closedNotchSize.height)
    }

    // MARK: - Header Row (persists across states)

    @ViewBuilder
    private var headerRow: some View {
        if voiceCoordinator.voiceState != .idle {
            voiceRecordingHeader
        } else {
        HStack(spacing: 0) {
            // Left side - always show pet/crab icon
            HStack(spacing: 4) {
                notchIcon(size: 14, animateLegs: isProcessing)
                    .id(petGacha.activePet?.id)
                    .background(
                        GeometryReader { geo in
                            Color.clear
                                .onAppear {
                                    updatePetIconRect(geo)
                                }
                                .onChange(of: geo.frame(in: .global)) { _ in
                                    updatePetIconRect(geo)
                                }
                        }
                    )
                    .matchedGeometryEffect(id: "crab", in: activityNamespace, isSource: true)

                // Permission indicator only (amber)
                if hasPendingPermission {
                    PermissionIndicatorIcon(size: 14, color: Color(red: 0.85, green: 0.47, blue: 0.34))
                        .matchedGeometryEffect(id: "status-indicator", in: activityNamespace, isSource: showClosedActivity)
                }
            }
            .frame(width: viewModel.status == .opened ? nil : sideWidth + (hasPendingPermission ? 18 : 0))
            .padding(.leading, viewModel.status == .opened ? 8 : 10)

            // Center content
            if viewModel.status == .opened {
                openedHeaderContent
            } else if !showClosedActivity {
                // Idle: show session status dots + count
                let isDetailed = DisplaySettings.shared.layoutMode == .detailed
                if isDetailed {
                    HStack {
                        Text("待机")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundColor(.white.opacity(0.4))
                        Spacer()
                        sessionStatusDots
                        let count = sessionMonitor.instances.count
                        Text("\(count)")
                            .font(.system(size: 11, weight: .bold, design: .monospaced))
                            .foregroundColor(.white.opacity(0.4))
                        Text("个会话")
                            .font(.system(size: 9))
                            .foregroundColor(.white.opacity(0.3))
                    }
                    .padding(.horizontal, 4)
                } else {
                    sessionStatusDots
                    Spacer()
                }
            } else {
                // Closed with activity: show status based on layout mode
                let isDetailed = DisplaySettings.shared.layoutMode == .detailed
                if isDetailed {
                    HStack(spacing: 4) {
                        if let firstActive = sessionMonitor.instances.first(where: { $0.phase == .processing || $0.phase == .compacting }) {
                            Text(firstActive.lastToolName ?? "工作中")
                                .font(.system(size: 10, weight: .medium, design: .monospaced))
                                .foregroundColor(.white.opacity(0.7))
                                .lineLimit(1)
                        } else if hasPendingPermission {
                            Text("审批中")
                                .font(.system(size: 10, weight: .medium))
                                .foregroundColor(Color(red: 0.85, green: 0.47, blue: 0.34))
                        } else if hasWaitingForInput {
                            Text("等待输入")
                                .font(.system(size: 10, weight: .medium))
                                .foregroundColor(TerminalColors.green)
                        }
                        Spacer()
                        Text("\(sessionMonitor.instances.count)")
                            .font(.system(size: 11, weight: .bold, design: .monospaced))
                            .foregroundColor(.blue)
                        Text("个会话")
                            .font(.system(size: 9))
                            .foregroundColor(.white.opacity(0.5))
                    }
                    .padding(.horizontal, 2)
                } else {
                    if activeSessionCount > 1 || totalActiveToolCount > 1 {
                        let displayCount = activeSessionCount > 1 ? activeSessionCount : totalActiveToolCount
                        Text("\(displayCount)")
                            .font(.system(size: 9, weight: .bold, design: .monospaced))
                            .foregroundColor(.white.opacity(0.6))
                    } else {
                        Spacer()
                    }
                }
            }

            // Right side - spinner when processing/pending, checkmark when waiting for input
            Group {
                if showClosedActivity {
                    if isProcessing || hasPendingPermission {
                        ProcessingSpinner()
                            .matchedGeometryEffect(id: "spinner", in: activityNamespace, isSource: showClosedActivity)
                            .frame(width: viewModel.status == .opened ? 20 : sideWidth)
                    } else if hasWaitingForInput {
                        ReadyForInputIndicatorIcon(size: 14, color: TerminalColors.green)
                            .matchedGeometryEffect(id: "spinner", in: activityNamespace, isSource: showClosedActivity)
                            .frame(width: viewModel.status == .opened ? 20 : sideWidth)
                    }
                }
            }
            .padding(.trailing, viewModel.status == .opened ? 0 : 10)
            // Prevent spinner/checkmark clipping on collapsed notch
            if viewModel.status != .opened && showClosedActivity {
                Spacer().frame(width: 4)
            }
        }
        .frame(height: closedNotchSize.height)
        } // else (non-voice header)
    }

    private var sideWidth: CGFloat {
        max(0, closedNotchSize.height - 12) + 10
    }

    /// Session status dots for minimized notch — up to 8 colored dots sorted by priority
    private var sessionStatusDots: some View {
        let sortedSessions = sessionMonitor.instances
            .filter { $0.phase != .ended }
            .sorted { $0.phase.dotPriority > $1.phase.dotPriority }
            .prefix(8)

        return HStack(spacing: 3) {
            ForEach(Array(sortedSessions.enumerated()), id: \.element.sessionId) { _, session in
                Circle()
                    .fill(session.phase.dotColor)
                    .frame(width: 5, height: 5)
            }
        }
    }

    // MARK: - Opened Header Content

    @ViewBuilder
    private var openedHeaderContent: some View {
        HStack(spacing: 12) {
            // Show static crab only if not showing activity in headerRow
            // (headerRow handles crab + indicator when showClosedActivity is true)
            if !showClosedActivity {
                notchIcon(size: 14, animateLegs: false)
                    .matchedGeometryEffect(id: "crab", in: activityNamespace, isSource: !showClosedActivity)
                    .padding(.leading, 8)
            }

            Spacer()

            // Menu toggle
            Button {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                    viewModel.toggleMenu()
                    if viewModel.contentType == .menu {
                        updateManager.markUpdateSeen()
                    }
                }
            } label: {
                ZStack(alignment: .topTrailing) {
                    Image(systemName: viewModel.contentType == .menu ? "xmark" : "line.3.horizontal")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.white.opacity(0.4))
                        .frame(width: 22, height: 22)
                        .contentShape(Rectangle())

                    // Green dot for unseen update
                    if updateManager.hasUnseenUpdate && viewModel.contentType != .menu {
                        Circle()
                            .fill(TerminalColors.green)
                            .frame(width: 6, height: 6)
                            .offset(x: -2, y: 2)
                    }
                }
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - Content View (Opened State)

    @ViewBuilder
    private var contentView: some View {
        Group {
            switch viewModel.contentType {
            case .instances:
                ClaudeInstancesView(
                    sessionMonitor: sessionMonitor,
                    viewModel: viewModel
                )
            case .menu:
                NotchMenuView(viewModel: viewModel)
            case .soundSettings:
                SoundSettingsView(settings: SoundSettings.shared, viewModel: viewModel)
            case .displaySettings:
                DisplaySettingsView(viewModel: viewModel)
            case .voiceSettings:
                VoiceSettingsView(viewModel: viewModel, voiceCoordinator: VoiceInputCoordinator.shared, processor: ASRPostProcessor.shared)
            case .petGacha:
                PetGachaView(viewModel: viewModel)
            case .browserActivity:
                BrowserActivityView(viewModel: viewModel)
            case .chat(let session):
                ChatView(
                    sessionId: session.sessionId,
                    initialSession: session,
                    sessionMonitor: sessionMonitor,
                    viewModel: viewModel
                )
            }
        }
        .frame(width: notchSize.width - 24) // Fixed width to prevent text reflow
        // Removed .id() - was causing view recreation and performance issues
    }

    // MARK: - Notch Icon (pet or crab)

    @ViewBuilder
    private func notchIcon(size: CGFloat, animateLegs: Bool) -> some View {
        if let pet = petGacha.activePet {
            if pet.name == "小蟹OG" {
                ClaudeCrabIcon(size: size, animateLegs: animateLegs)
            } else {
                PixelPetView(pet: pet, pixelSize: 2.0, animated: animateLegs)
                    .frame(width: 18, height: 18)
                    .clipped()
            }
        } else {
            ClaudeCrabIcon(size: size, animateLegs: animateLegs)
        }
    }

    // MARK: - Pet Icon Rect

    /// Convert SwiftUI global frame to NSScreen coordinates and sync to ViewModel
    private func updatePetIconRect(_ geo: GeometryProxy) {
        let frame = geo.frame(in: .global)
        // SwiftUI global coords: origin top-left, Y down
        // NSScreen coords: origin bottom-left, Y up
        guard let screen = NSScreen.main else { return }
        let screenHeight = screen.frame.height
        let converted = CGRect(
            x: frame.origin.x,
            y: screenHeight - frame.origin.y - frame.height,
            width: frame.width,
            height: frame.height
        )
        // Add generous tap padding (the icon is tiny ~14pt)
        let padded = converted.insetBy(dx: -8, dy: -8)
        viewModel.petIconScreenRect = padded
    }

    // MARK: - Event Handlers

    private func handleProcessingChange() {
        if isAnyProcessing || hasPendingPermission {
            // Show claude activity when processing or waiting for permission
            activityCoordinator.showActivity(type: .claude)
            isVisible = true
        } else if hasWaitingForInput {
            // Keep visible for waiting-for-input but hide the processing spinner
            activityCoordinator.hideActivity()
            isVisible = true
        } else {
            // Hide activity when done
            activityCoordinator.hideActivity()

            // Keep notch always visible (persistent mode)
            // isVisible stays true so the notch is always on screen
        }
    }

    private func handleStatusChange(from oldStatus: NotchStatus, to newStatus: NotchStatus) {
        switch newStatus {
        case .opened, .popping:
            isVisible = true
            // Clear waiting-for-input timestamps only when manually opened (user acknowledged)
            if viewModel.openReason == .click || viewModel.openReason == .hover {
                waitingForInputTimestamps.removeAll()
            }
        case .closed:
            // Keep visible always (persistent notch)
            break
        }
    }

    private func handlePendingSessionsChange(_ sessions: [SessionState]) {
        let currentIds = Set(sessions.map { $0.stableId })
        let newPendingIds = currentIds.subtracting(previousPendingIds)

        if !newPendingIds.isEmpty &&
           viewModel.status == .closed &&
           AppSettings.autoExpandNotch &&
           !TerminalVisibilityDetector.isTerminalVisibleOnCurrentSpace() {
            viewModel.notchOpen(reason: .notification)
        }

        previousPendingIds = currentIds
    }

    private func handleWaitingForInputChange(_ instances: [SessionState]) {
        // Get sessions that are now waiting for input
        let waitingForInputSessions = instances.filter { $0.phase == .waitingForInput }
        let currentIds = Set(waitingForInputSessions.map { $0.stableId })
        let newWaitingIds = currentIds.subtracting(previousWaitingForInputIds)

        // Track timestamps for newly waiting sessions
        let now = Date()
        for session in waitingForInputSessions where newWaitingIds.contains(session.stableId) {
            waitingForInputTimestamps[session.stableId] = now
        }

        // Clean up timestamps for sessions no longer waiting
        let staleIds = Set(waitingForInputTimestamps.keys).subtracting(currentIds)
        for staleId in staleIds {
            waitingForInputTimestamps.removeValue(forKey: staleId)
        }

        // Bounce the notch when a session newly enters waitingForInput state
        if !newWaitingIds.isEmpty {
            // Get the sessions that just entered waitingForInput
            let newlyWaitingSessions = waitingForInputSessions.filter { newWaitingIds.contains($0.stableId) }

            // Play notification sound if the session is not actively focused
            if !WindowManager.isSuppressingNotificationSound,
               let soundName = AppSettings.notificationSound.soundName {
                // Check if we should play sound (async check for tmux pane focus)
                Task {
                    let shouldPlaySound = await shouldPlayNotificationSound(for: newlyWaitingSessions)
                    if shouldPlaySound {
                        await MainActor.run {
                            NSSound(named: soundName)?.play()
                        }
                    }
                }
            }

            // Trigger bounce animation to get user's attention
            DispatchQueue.main.async {
                isBouncing = true
                // Bounce back after a short delay
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                    isBouncing = false
                }
            }

            // Schedule hiding the checkmark after 30 seconds
            DispatchQueue.main.asyncAfter(deadline: .now() + 30) { [self] in
                // Trigger a UI update to re-evaluate hasWaitingForInput
                handleProcessingChange()
            }
        }

        previousWaitingForInputIds = currentIds
    }

    /// Determine if notification sound should play for the given sessions
    /// Returns true if ANY session is not actively focused
    private func shouldPlayNotificationSound(for sessions: [SessionState]) async -> Bool {
        for session in sessions {
            guard let pid = session.pid else {
                // No PID means we can't check focus, assume not focused
                return true
            }

            let isFocused = await TerminalVisibilityDetector.isSessionFocused(sessionPid: pid)
            if !isFocused {
                return true
            }
        }

        return false
    }
}
