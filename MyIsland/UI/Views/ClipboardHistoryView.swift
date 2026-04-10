//
//  ClipboardHistoryView.swift
//  MyIsland
//
//  Clipboard history views for the full panel and recent preview card.
//

import AppKit
import SwiftUI

struct ClipboardHistoryView: View {
    @ObservedObject var viewModel: NotchViewModel
    @ObservedObject private var historyManager = ClipboardHistoryManager.shared

    var body: some View {
        if historyManager.entries.isEmpty {
            emptyState
        } else {
            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: DesignTokens.Spacing.sm) {
                    header

                    LazyVStack(spacing: DesignTokens.Spacing.xs) {
                        ForEach(historyManager.entries) { entry in
                            ClipboardEntryRow(
                                entry: entry,
                                onRestore: { historyManager.restore(entryId: entry.id) },
                                onPasteNow: { historyManager.pasteNow(entryId: entry.id) },
                                onDelete: { historyManager.delete(entryId: entry.id) }
                            )
                        }
                    }
                }
                .padding(.vertical, DesignTokens.Spacing.xs)
            }
            .scrollBounceBehavior(.basedOnSize)
        }
    }

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: DesignTokens.Spacing.xxs) {
                Text(String(localized: "clipboard.title"))
                    .font(DesignTokens.Font.title())
                    .foregroundColor(DesignTokens.Text.primary)

                Text(String(localized: "clipboard.subtitle"))
                    .font(DesignTokens.Font.body())
                    .foregroundColor(DesignTokens.Text.tertiary)
                    .lineLimit(2)
            }

            Spacer()

            Button(role: .destructive) {
                historyManager.clearAll()
            } label: {
                Text(String(localized: "clipboard.clearAll"))
                    .font(DesignTokens.Font.body())
                    .foregroundColor(TerminalColors.red)
                    .padding(.horizontal, DesignTokens.Spacing.sm)
                    .padding(.vertical, DesignTokens.Spacing.xs)
                    .background(
                        Capsule()
                            .fill(DesignTokens.Surface.elevated)
                    )
            }
            .buttonStyle(.plain)
            .help(NSLocalizedString("clipboard.clearAll", comment: ""))
        }
        .padding(.horizontal, DesignTokens.Spacing.sm)
    }

    private var emptyState: some View {
        VStack(spacing: DesignTokens.Spacing.sm) {
            Image(systemName: "doc.on.clipboard")
                .font(.system(size: 22, weight: .medium))
                .foregroundColor(DesignTokens.Text.quaternary)
            Text(String(localized: "clipboard.emptyTitle"))
                .font(DesignTokens.Font.heading())
                .foregroundColor(DesignTokens.Text.tertiary)
            Text(String(localized: "clipboard.emptyHint"))
                .font(DesignTokens.Font.caption())
                .foregroundColor(DesignTokens.Text.quaternary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct RecentClipboardCard: View {
    let entries: [ClipboardEntry]
    let onOpenHistory: () -> Void
    let onRestore: (ClipboardEntry) -> Void
    let onPasteNow: (ClipboardEntry) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.xs) {
            HStack {
                Label {
                    Text(String(localized: "clipboard.recentTitle"))
                        .font(DesignTokens.Font.heading())
                        .foregroundColor(DesignTokens.Text.primary)
                } icon: {
                    Image(systemName: "doc.on.clipboard")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(DesignTokens.Text.secondary)
                }

                Spacer()

                Button(action: onOpenHistory) {
                    Text(String(localized: "clipboard.viewAll"))
                        .font(DesignTokens.Font.caption())
                        .foregroundColor(DesignTokens.Text.secondary)
                }
                .buttonStyle(.plain)
                .help(NSLocalizedString("clipboard.viewAll", comment: ""))
            }

            ForEach(entries) { entry in
                HStack(spacing: DesignTokens.Spacing.sm) {
                    ClipboardEntryLeadingPreview(entry: entry, compact: true)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(compactTitle(for: entry))
                            .font(DesignTokens.Font.body())
                            .foregroundColor(DesignTokens.Text.primary)
                            .lineLimit(1)

                        Text(compactSubtitle(for: entry))
                            .font(DesignTokens.Font.caption())
                            .foregroundColor(DesignTokens.Text.tertiary)
                            .lineLimit(1)
                    }

                    Spacer(minLength: 0)

                    HStack(spacing: DesignTokens.Spacing.xs) {
                        CompactClipboardActionButton(
                            icon: "arrow.uturn.backward",
                            tooltipKey: "clipboard.action.restore"
                        ) {
                            onRestore(entry)
                        }
                        CompactClipboardActionButton(
                            icon: "paperplane",
                            tooltipKey: "clipboard.action.pasteNow"
                        ) {
                            onPasteNow(entry)
                        }
                    }
                }
                .padding(.vertical, 2)
            }
        }
        .padding(DesignTokens.Spacing.md)
        .background(
            RoundedRectangle(cornerRadius: DesignTokens.Radius.xl)
                .fill(DesignTokens.Surface.elevated)
                .overlay(
                    RoundedRectangle(cornerRadius: DesignTokens.Radius.xl)
                        .strokeBorder(DesignTokens.Border.subtle, lineWidth: 1)
                )
        )
    }

    private func compactTitle(for entry: ClipboardEntry) -> String {
        switch entry.kind {
        case .text:
            return entry.previewText
        case .image:
            return String(localized: "clipboard.kind.image")
        case .files:
            return entry.fileDisplayNames.first ?? String(localized: "clipboard.kind.files")
        }
    }

    private func compactSubtitle(for entry: ClipboardEntry) -> String {
        let details = ClipboardEntryFormatters.metadata(for: entry)
        if let sourceAppName = entry.sourceAppName, !sourceAppName.isEmpty {
            return "\(sourceAppName) · \(details)"
        }
        return details
    }
}

private struct ClipboardEntryRow: View {
    let entry: ClipboardEntry
    let onRestore: () -> Void
    let onPasteNow: () -> Void
    let onDelete: () -> Void

    @State private var isHovered = false

    var body: some View {
        HStack(alignment: .top, spacing: DesignTokens.Spacing.md) {
            ClipboardEntryLeadingPreview(entry: entry, compact: false)

            VStack(alignment: .leading, spacing: DesignTokens.Spacing.xxs) {
                HStack(spacing: DesignTokens.Spacing.xs) {
                    Text(ClipboardEntryFormatters.title(for: entry))
                        .font(DesignTokens.Font.heading())
                        .foregroundColor(DesignTokens.Text.primary)
                        .lineLimit(1)

                    Text(ClipboardEntryFormatters.kindLabel(for: entry))
                        .font(.system(size: 8, weight: .medium))
                        .foregroundColor(DesignTokens.Text.tertiary)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(Capsule().fill(DesignTokens.Surface.base))
                }

                Text(ClipboardEntryFormatters.body(for: entry))
                    .font(DesignTokens.Font.body())
                    .foregroundColor(DesignTokens.Text.secondary)
                    .lineLimit(entry.kind == .text ? 2 : 1)

                HStack(spacing: DesignTokens.Spacing.xs) {
                    Text(ClipboardEntryFormatters.metadata(for: entry))
                        .font(DesignTokens.Font.caption())
                        .foregroundColor(DesignTokens.Text.tertiary)
                        .lineLimit(1)

                    if let sourceAppName = entry.sourceAppName, !sourceAppName.isEmpty {
                        Text("· \(sourceAppName)")
                            .font(DesignTokens.Font.caption())
                            .foregroundColor(DesignTokens.Text.quaternary)
                            .lineLimit(1)
                    }
                }
            }

            Spacer(minLength: 0)

            VStack(alignment: .trailing, spacing: DesignTokens.Spacing.xs) {
                Text(ClipboardEntryFormatters.relativeTime(entry.createdAt))
                    .font(DesignTokens.Font.caption())
                    .foregroundColor(DesignTokens.Text.quaternary)

                if isHovered {
                    HStack(spacing: DesignTokens.Spacing.xs) {
                        CompactClipboardActionButton(
                            icon: "arrow.uturn.backward",
                            tooltipKey: "clipboard.action.restore",
                            action: onRestore
                        )
                        CompactClipboardActionButton(
                            icon: "paperplane",
                            tooltipKey: "clipboard.action.pasteNow",
                            action: onPasteNow
                        )
                        CompactClipboardActionButton(
                            icon: "trash",
                            tooltipKey: "clipboard.action.delete",
                            tint: TerminalColors.red,
                            action: onDelete
                        )
                    }
                    .transition(.opacity)
                }
            }
        }
        .padding(.horizontal, DesignTokens.Spacing.md)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: DesignTokens.Radius.lg)
                .fill(isHovered ? DesignTokens.Surface.hover : Color.clear)
        )
        .onHover { isHovered = $0 }
        .animation(.easeInOut(duration: 0.15), value: isHovered)
    }
}

private struct ClipboardEntryLeadingPreview: View {
    let entry: ClipboardEntry
    let compact: Bool

    var body: some View {
        Group {
            switch entry.kind {
            case .text:
                ZStack {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(DesignTokens.Surface.base)
                    Image(systemName: "text.alignleft")
                        .font(.system(size: compact ? 10 : 12, weight: .semibold))
                        .foregroundColor(DesignTokens.Text.secondary)
                }

            case .image:
                if let image = loadImage() {
                    Image(nsImage: image)
                        .resizable()
                        .scaledToFill()
                } else {
                    ZStack {
                        RoundedRectangle(cornerRadius: 8)
                            .fill(DesignTokens.Surface.base)
                        Image(systemName: "photo")
                            .font(.system(size: compact ? 10 : 12, weight: .semibold))
                            .foregroundColor(DesignTokens.Text.secondary)
                    }
                }

            case .files:
                ZStack {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(DesignTokens.Surface.base)
                    Image(systemName: entry.files.first?.isDirectory == true ? "folder" : "doc")
                        .font(.system(size: compact ? 10 : 12, weight: .semibold))
                        .foregroundColor(DesignTokens.Text.secondary)
                }
            }
        }
        .frame(width: compact ? 28 : 42, height: compact ? 28 : 42)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(DesignTokens.Border.subtle, lineWidth: 1)
        )
    }

    private func loadImage() -> NSImage? {
        guard entry.kind == .image,
              let relativePath = entry.assetRelativePaths.first else {
            return nil
        }
        let url = ClipboardStore.baseDirectoryURL().appendingPathComponent(relativePath)
        return NSImage(contentsOf: url)
    }
}

private struct CompactClipboardActionButton: View {
    let icon: String
    let tooltipKey: String
    var tint: Color = DesignTokens.Text.secondary
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 10, weight: .medium))
                .foregroundColor(isHovered ? DesignTokens.Text.primary : tint)
                .frame(width: 22, height: 22)
                .background(
                    Circle()
                        .fill(isHovered ? DesignTokens.Surface.hover : Color.clear)
                )
        }
        .buttonStyle(.plain)
        .help(NSLocalizedString(tooltipKey, comment: ""))
        .onHover { isHovered = $0 }
    }
}

private enum ClipboardEntryFormatters {
    static func title(for entry: ClipboardEntry) -> String {
        switch entry.kind {
        case .text:
            return entry.previewText
        case .image:
            return String(localized: "clipboard.kind.image")
        case .files:
            if entry.fileDisplayNames.count == 1 {
                return entry.fileDisplayNames[0]
            }
            return String(format: String(localized: "clipboard.files.count"), locale: Locale.current, Int64(entry.fileDisplayNames.count))
        }
    }

    static func body(for entry: ClipboardEntry) -> String {
        switch entry.kind {
        case .text:
            return entry.textContent ?? entry.previewText
        case .image:
            return String(localized: "clipboard.image.body")
        case .files:
            return entry.fileDisplayNames.joined(separator: ", ")
        }
    }

    static func kindLabel(for entry: ClipboardEntry) -> String {
        switch entry.kind {
        case .text:
            return String(localized: "clipboard.kind.text")
        case .image:
            return String(localized: "clipboard.kind.image")
        case .files:
            return String(localized: "clipboard.kind.files")
        }
    }

    static func metadata(for entry: ClipboardEntry) -> String {
        let sizeString = ByteCountFormatter.string(fromByteCount: entry.byteSize, countStyle: .file)

        switch entry.kind {
        case .text:
            return sizeString
        case .image:
            if let imageMetadata = entry.imageMetadata {
                return "\(imageMetadata.pixelWidth)×\(imageMetadata.pixelHeight) · \(sizeString)"
            }
            return sizeString
        case .files:
            return "\(entry.fileDisplayNames.count) · \(sizeString)"
        }
    }

    static func relativeTime(_ date: Date) -> String {
        RelativeDateTimeFormatter().localizedString(for: date, relativeTo: Date())
    }
}
