//
//  DesignTokens.swift
//  MyIsland
//
//  Unified design token system inspired by Linear & Warp design specs
//

import SwiftUI

struct DesignTokens {

    // MARK: - Text Colors (luminance hierarchy)

    struct Text {
        /// Primary text — warm off-white, not pure white
        static let primary = Color(red: 0.94, green: 0.94, blue: 0.93)       // #f0f0ed
        /// Secondary text — descriptions, subtitles
        static let secondary = Color(red: 0.69, green: 0.70, blue: 0.72)     // #b0b3b8
        /// Tertiary text — timestamps, metadata
        static let tertiary = Color(red: 0.43, green: 0.44, blue: 0.47)      // #6e7177
        /// Quaternary text — placeholders, disabled
        static let quaternary = Color(red: 0.28, green: 0.29, blue: 0.32)    // #484b52
    }

    // MARK: - Surface & Background

    struct Surface {
        /// Base surface — subtle panel differentiation
        static let base = Color.white.opacity(0.03)
        /// Elevated surface — cards, popovers
        static let elevated = Color.white.opacity(0.06)
        /// Hover state
        static let hover = Color.white.opacity(0.08)
        /// Pressed / active state
        static let pressed = Color.white.opacity(0.12)
    }

    // MARK: - Border

    struct Border {
        /// Subtle divider lines
        static let subtle = Color.white.opacity(0.06)
        /// Standard border for cards, inputs
        static let standard = Color.white.opacity(0.10)
        /// Emphasis border for focused elements
        static let emphasis = Color.white.opacity(0.15)
    }

    // MARK: - Spacing (4pt base unit)

    struct Spacing {
        static let xxxs: CGFloat = 2
        static let xxs: CGFloat = 4
        static let xs: CGFloat = 6
        static let sm: CGFloat = 8
        static let md: CGFloat = 12
        static let lg: CGFloat = 16
        static let xl: CGFloat = 20
        static let xxl: CGFloat = 24
    }

    // MARK: - Corner Radius

    struct Radius {
        /// Small: pills, tags, inline badges
        static let sm: CGFloat = 4
        /// Medium: buttons, small cards
        static let md: CGFloat = 6
        /// Large: menu rows, text fields, cards
        static let lg: CGFloat = 8
        /// Extra large: panels, large containers
        static let xl: CGFloat = 12
    }

    // MARK: - Typography

    struct Font {
        /// 10pt — smallest readable text (timestamps, badges)
        static func caption() -> SwiftUI.Font {
            .system(size: 10, weight: .regular)
        }
        /// 11pt — body text, descriptions
        static func body() -> SwiftUI.Font {
            .system(size: 11, weight: .regular)
        }
        /// 12pt medium — labels, menu items
        static func label() -> SwiftUI.Font {
            .system(size: 12, weight: .medium)
        }
        /// 13pt semibold — row titles, section headers
        static func heading() -> SwiftUI.Font {
            .system(size: 13, weight: .semibold)
        }
        /// 15pt bold — page titles
        static func title() -> SwiftUI.Font {
            .system(size: 15, weight: .bold)
        }
        /// Monospaced at specified size
        static func mono(_ size: CGFloat = 11) -> SwiftUI.Font {
            .system(size: size, weight: .regular, design: .monospaced)
        }
    }
}
