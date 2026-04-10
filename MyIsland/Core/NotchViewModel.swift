//
//  NotchViewModel.swift
//  MyIsland
//
//  State management for the dynamic island
//

import AppKit
import Combine
import SwiftUI
import os.log

private let vmLogger = Logger(subsystem: "com.myisland", category: "Pet")

enum NotchStatus: Equatable {
    case closed
    case opened
    case popping
}

enum NotchOpenReason {
    case click
    case hover
    case notification
    case boot
    case unknown
}

enum NotchContentType: Equatable {
    case instances
    case clipboardHistory
    case menu
    case soundSettings
    case displaySettings
    case voiceSettings
    case petGacha
    case browserActivity
    case chat(SessionState)

    var id: String {
        switch self {
        case .instances: return "instances"
        case .clipboardHistory: return "clipboardHistory"
        case .menu: return "menu"
        case .soundSettings: return "soundSettings"
        case .displaySettings: return "displaySettings"
        case .voiceSettings: return "voiceSettings"
        case .petGacha: return "petGacha"
        case .browserActivity: return "browserActivity"
        case .chat(let session): return "chat-\(session.sessionId)"
        }
    }
}

@MainActor
class NotchViewModel: ObservableObject {
    // MARK: - Published State

    @Published var status: NotchStatus = .closed
    @Published var openReason: NotchOpenReason = .unknown
    @Published var contentType: NotchContentType = .instances
    @Published var isHovering: Bool = false
    @Published var sessionCount: Int = 0
    @Published var interactiveContentHeight: CGFloat = 0

    /// Screen-coordinate rect of the pet icon, updated by NotchView via GeometryReader.
    var petIconScreenRect: CGRect = .zero
    /// Screen-coordinate rect of the clipboard icon, updated by NotchView via GeometryReader.
    var clipboardIconScreenRect: CGRect = .zero
    /// Called when pet icon area is tapped (closed state).
    var onPetIconTapped: (() -> Void)?
    /// Called when clipboard icon area is tapped (closed state).
    var onClipboardIconTapped: (() -> Void)?

    // MARK: - Dependencies

    private let screenSelector = ScreenSelector.shared
    private let soundSelector = SoundSelector.shared

    // MARK: - Geometry

    let geometry: NotchGeometry
    let spacing: CGFloat = 12
    let hasPhysicalNotch: Bool

    var deviceNotchRect: CGRect { geometry.deviceNotchRect }
    var screenRect: CGRect { geometry.screenRect }
    var windowHeight: CGFloat { geometry.windowHeight }

    /// Dynamic opened size based on content type
    var openedSize: CGSize {
        let panelW = DisplaySettings.shared.expandedPanelWidth
        let maxH = DisplaySettings.shared.maxPanelHeight
        switch contentType {
        case .chat:
            return CGSize(
                width: min(screenRect.width * 0.5, max(panelW, 500)),
                height: min(maxH, 580)
            )
        case .clipboardHistory:
            return CGSize(
                width: min(screenRect.width * 0.42, max(panelW, 520)),
                height: min(maxH, 560)
            )
        case .menu:
            return CGSize(
                width: min(screenRect.width * 0.4, panelW),
                height: min(maxH, 420 + screenSelector.expandedPickerHeight + soundSelector.expandedPickerHeight)
            )
        case .soundSettings:
            return CGSize(
                width: min(screenRect.width * 0.4, panelW),
                height: min(maxH, 580)
            )
        case .displaySettings:
            return CGSize(
                width: min(screenRect.width * 0.4, panelW),
                height: min(maxH, 620)
            )
        case .voiceSettings:
            return CGSize(
                width: min(screenRect.width * 0.4, panelW),
                height: min(maxH, 400)
            )
        case .petGacha:
            return CGSize(
                width: min(screenRect.width * 0.4, panelW),
                height: min(maxH, 500)
            )
        case .browserActivity:
            return CGSize(
                width: min(screenRect.width * 0.4, panelW),
                height: min(maxH, 420)
            )
        case .instances:
            // Dynamic height: header(40) + per-session row(60) + padding(20) + interactive content
            // When no sessions, use same height as 1 session for consistent appearance
            let rowHeight: CGFloat = 60
            let baseHeight: CGFloat = 60  // header + padding
            let effectiveCount = max(sessionCount, 1)
            let contentHeight = baseHeight + CGFloat(min(effectiveCount, 5)) * rowHeight + interactiveContentHeight
            return CGSize(
                width: min(screenRect.width * 0.4, panelW),
                height: min(maxH, contentHeight)
            )
        }
    }

    // MARK: - Animation

    var animation: Animation {
        .easeOut(duration: 0.25)
    }

    // MARK: - Private

    private var cancellables = Set<AnyCancellable>()
    private let events = EventMonitors.shared
    private var hoverTimer: DispatchWorkItem?

    // MARK: - Initialization

    init(deviceNotchRect: CGRect, screenRect: CGRect, windowHeight: CGFloat, hasPhysicalNotch: Bool) {
        self.geometry = NotchGeometry(
            deviceNotchRect: deviceNotchRect,
            screenRect: screenRect,
            windowHeight: windowHeight
        )
        self.hasPhysicalNotch = hasPhysicalNotch
        setupEventHandlers()
        observeSelectors()
    }

    private func observeSelectors() {
        screenSelector.$isPickerExpanded
            .sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &cancellables)

        soundSelector.$isPickerExpanded
            .sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &cancellables)
    }

    // MARK: - Event Handling

    private func setupEventHandlers() {
        events.mouseLocation
            .throttle(for: .milliseconds(50), scheduler: DispatchQueue.main, latest: true)
            .sink { [weak self] location in
                self?.handleMouseMove(location)
            }
            .store(in: &cancellables)

        events.mouseDown
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.handleMouseDown()
            }
            .store(in: &cancellables)
    }

    /// Whether we're in chat mode (sticky behavior)
    private var isInChatMode: Bool {
        if case .chat = contentType { return true }
        return false
    }

    /// The chat session we're viewing (persists across close/open)
    private var currentChatSession: SessionState?

    private func handleMouseMove(_ location: CGPoint) {
        let inNotch = geometry.isPointInNotch(location)
        let inOpened = status == .opened && geometry.isPointInOpenedPanel(location, size: openedSize)

        let newHovering = inNotch || inOpened

        // Only update if changed to prevent unnecessary re-renders
        guard newHovering != isHovering else { return }

        isHovering = newHovering

        // Cancel any pending hover timer
        hoverTimer?.cancel()
        hoverTimer = nil

        // Start hover timer to auto-expand after 1 second
        if isHovering && (status == .closed || status == .popping) {
            let workItem = DispatchWorkItem { [weak self] in
                guard let self = self, self.isHovering else { return }
                self.notchOpen(reason: .hover)
            }
            hoverTimer = workItem
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0, execute: workItem)
        }
    }

    private func handleMouseDown() {
        let location = NSEvent.mouseLocation

        switch status {
        case .opened:
            // Only close when clicking OUTSIDE the panel — clicking inside never closes
            if geometry.isPointOutsidePanel(location, size: openedSize) {
                notchClose()
                // Re-post the click so it reaches the window/app behind us
                repostClickAt(location)
            }
        case .closed, .popping:
            // Check pet icon tap first (independent of notch hit-test)
            if petIconScreenRect != .zero && petIconScreenRect.contains(location) {
                onPetIconTapped?()
            } else if geometry.isPointInNotch(location) {
                notchOpen(reason: .click)
            }
        }
    }

    /// Re-posts a mouse click at the given screen location so it reaches windows behind us
    private func repostClickAt(_ location: CGPoint) {
        // Small delay to let the window's ignoresMouseEvents update
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            // Convert to CGEvent coordinate system (screen coordinates with Y from top-left)
            guard let screen = NSScreen.main else { return }
            let screenHeight = screen.frame.height
            let cgPoint = CGPoint(x: location.x, y: screenHeight - location.y)

            // Create and post mouse down event
            if let mouseDown = CGEvent(
                mouseEventSource: nil,
                mouseType: .leftMouseDown,
                mouseCursorPosition: cgPoint,
                mouseButton: .left
            ) {
                mouseDown.post(tap: .cghidEventTap)
            }

            // Create and post mouse up event
            if let mouseUp = CGEvent(
                mouseEventSource: nil,
                mouseType: .leftMouseUp,
                mouseCursorPosition: cgPoint,
                mouseButton: .left
            ) {
                mouseUp.post(tap: .cghidEventTap)
            }
        }
    }

    // MARK: - Actions

    func notchOpen(reason: NotchOpenReason = .unknown) {
        openReason = reason
        status = .opened
        logAllWindows()

        // Don't restore chat on notification - show instances list instead
        if reason == .notification {
            currentChatSession = nil
            return
        }

        // Restore chat session if we had one open before
        if let chatSession = currentChatSession {
            // Avoid unnecessary updates if already showing this chat
            if case .chat(let current) = contentType, current.sessionId == chatSession.sessionId {
                return
            }
            contentType = .chat(chatSession)
        }
    }

    func notchClose() {
        // Save chat session before closing if in chat mode
        if case .chat(let session) = contentType {
            currentChatSession = session
        }
        status = .closed
        contentType = .instances
        logAllWindows()
    }

    func notchPop() {
        guard status == .closed else { return }
        status = .popping
    }

    func notchUnpop() {
        guard status == .popping else { return }
        status = .closed
    }

    func toggleMenu() {
        contentType = contentType == .menu ? .instances : .menu
    }

    func showInstances() {
        currentChatSession = nil
        contentType = .instances
        notchOpen(reason: .click)
    }

    func showClipboardHistory() {
        currentChatSession = nil
        contentType = .clipboardHistory
        notchOpen(reason: .click)
    }

    func showChat(for session: SessionState) {
        // Avoid unnecessary updates if already showing this chat
        if case .chat(let current) = contentType, current.sessionId == session.sessionId {
            return
        }
        contentType = .chat(session)
    }

    /// Go back to instances list and clear saved chat state
    func exitChat() {
        currentChatSession = nil
        contentType = .instances
    }

    /// Perform boot animation: expand briefly then collapse
    func performBootAnimation() {
        notchOpen(reason: .boot)
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
            guard let self = self, self.openReason == .boot else { return }
            self.notchClose()
        }
    }
}
