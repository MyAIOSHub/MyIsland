//
//  ActionButton.swift
//  MyIsland
//
//  Reusable action button component with variants
//

import SwiftUI

enum ButtonVariant {
    /// Filled background with border — primary actions
    case primary
    /// No background, text only — secondary/ghost actions
    case ghost
    /// Low-contrast background — subtle/tertiary actions
    case subtle
}

struct ActionButton: View {
    let title: String
    let icon: String
    let color: Color
    var variant: ButtonVariant = .primary
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Image(systemName: icon)
                    .font(.system(size: 9, weight: .bold))
                Text(title)
                    .font(.system(size: 10, weight: .semibold, design: .rounded))
            }
            .foregroundColor(foregroundColor)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: DesignTokens.Radius.md)
                    .fill(backgroundColor)
            )
            .overlay(
                RoundedRectangle(cornerRadius: DesignTokens.Radius.md)
                    .strokeBorder(borderColor, lineWidth: variant == .ghost ? 0 : 1)
            )
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
    }

    private var foregroundColor: Color {
        switch variant {
        case .primary:
            return isHovered ? .black : color
        case .ghost:
            return isHovered ? color : DesignTokens.Text.secondary
        case .subtle:
            return isHovered ? color : DesignTokens.Text.primary
        }
    }

    private var backgroundColor: Color {
        switch variant {
        case .primary:
            return isHovered ? color : color.opacity(0.15)
        case .ghost:
            return isHovered ? DesignTokens.Surface.hover : .clear
        case .subtle:
            return isHovered ? DesignTokens.Surface.pressed : DesignTokens.Surface.elevated
        }
    }

    private var borderColor: Color {
        switch variant {
        case .primary:
            return color.opacity(0.3)
        case .ghost:
            return .clear
        case .subtle:
            return DesignTokens.Border.subtle
        }
    }
}
