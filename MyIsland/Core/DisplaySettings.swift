import Foundation
import SwiftUI

/// Display settings for the notch panel, matching original Vibe Island's display preferences.
@Observable
class DisplaySettings {
    static let shared = DisplaySettings()

    // MARK: - Layout Mode

    enum LayoutMode: String, CaseIterable {
        case clean    // Only pet icon + session count number
        case detailed // Pet icon + status text + count + "个会话"

        var displayName: String {
            switch self {
            case .clean: return "简洁"
            case .detailed: return "详细"
            }
        }

        var description: String {
            switch self {
            case .clean: return "给菜单栏图标让路"
            case .detailed: return "会话标题和状态一目了然"
            }
        }
    }

    var layoutMode: LayoutMode = .detailed {
        didSet { save() }
    }

    // MARK: - Panel Dimensions

    /// Content font size (10-13pt, default 11)
    var contentFontSize: CGFloat = 11 {
        didSet { save() }
    }

    /// Completion card height (60-300pt, default 90)
    var completionCardHeight: CGFloat = 90 {
        didSet { save() }
    }

    /// Maximum panel height (300-800pt, default 560)
    var maxPanelHeight: CGFloat = 560 {
        didSet { save() }
    }

    /// Collapsed notch width for detailed mode (200-600pt, default 360)
    var detailedExtraWidth: CGFloat = 360 {
        didSet { save() }
    }

    /// Expanded panel width (300-600pt, default 480)
    var expandedPanelWidth: CGFloat = 480 {
        didSet { save() }
    }

    // MARK: - Agent Detail

    /// Show detailed agent activity (tool name, grep target, etc.)
    /// When off, only show item name + elapsed time/status
    var showAgentDetail: Bool = true {
        didSet { save() }
    }

    // MARK: - Persistence

    private init() { load() }

    func save() {
        let defaults = UserDefaults.standard
        defaults.set(layoutMode.rawValue, forKey: "displayLayoutMode")
        defaults.set(contentFontSize, forKey: "displayContentFontSize")
        defaults.set(completionCardHeight, forKey: "displayCompletionCardHeight")
        defaults.set(maxPanelHeight, forKey: "displayMaxPanelHeight")
        defaults.set(showAgentDetail, forKey: "displayShowAgentDetail")
        defaults.set(detailedExtraWidth, forKey: "displayDetailedExtraWidth")
        defaults.set(expandedPanelWidth, forKey: "displayExpandedPanelWidth")
    }

    func load() {
        let defaults = UserDefaults.standard
        if let mode = defaults.string(forKey: "displayLayoutMode"),
           let parsed = LayoutMode(rawValue: mode) {
            layoutMode = parsed
        }
        let fontSize = defaults.double(forKey: "displayContentFontSize")
        if fontSize > 0 { contentFontSize = CGFloat(fontSize) }
        let cardH = defaults.double(forKey: "displayCompletionCardHeight")
        if cardH > 0 { completionCardHeight = CGFloat(cardH) }
        let panelH = defaults.double(forKey: "displayMaxPanelHeight")
        if panelH > 0 { maxPanelHeight = CGFloat(panelH) }
        if defaults.object(forKey: "displayShowAgentDetail") != nil {
            showAgentDetail = defaults.bool(forKey: "displayShowAgentDetail")
        }
        let extraW = defaults.double(forKey: "displayDetailedExtraWidth")
        if extraW > 0 { detailedExtraWidth = CGFloat(extraW) }
        let panelW = defaults.double(forKey: "displayExpandedPanelWidth")
        if panelW > 0 { expandedPanelWidth = CGFloat(panelW) }
    }

    func resetToDefaults() {
        contentFontSize = 11
        completionCardHeight = 90
        maxPanelHeight = 560
        detailedExtraWidth = 360
        expandedPanelWidth = 480
        showAgentDetail = true
        layoutMode = .detailed
        save()
    }
}
