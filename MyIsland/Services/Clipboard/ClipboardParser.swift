//
//  ClipboardParser.swift
//  MyIsland
//
//  Extracts supported clipboard payloads from the system pasteboard.
//

import AppKit
import CryptoKit

enum ClipboardParser {
    nonisolated static func parse(_ pasteboard: NSPasteboard) -> ClipboardPayload? {
        guard !ClipboardPrivacyFilter.shouldIgnore(pasteboard) else { return nil }

        if let files = parseFiles(from: pasteboard), !files.isEmpty {
            return .files(files)
        }

        if let image = parseImage(from: pasteboard) {
            return .image(image)
        }

        if let text = parseText(from: pasteboard) {
            return .text(text)
        }

        return nil
    }

    nonisolated static func canonicalFingerprint(for payload: ClipboardPayload) -> String {
        switch payload {
        case .text(let text):
            return sha256Hex(Data(("text:\(text)").utf8))

        case .image(let asset):
            return sha256Hex(asset.pngData)

        case .files(let files):
            let canonical = files.map { file -> String in
                let modDate = (try? file.url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate)?
                    .timeIntervalSince1970 ?? 0
                return "\(file.url.path)|\(file.byteSize)|\(file.isDirectory)|\(modDate)"
            }
            .joined(separator: "\n")
            return sha256Hex(Data(canonical.utf8))
        }
    }

    nonisolated private static func parseFiles(from pasteboard: NSPasteboard) -> [FileSnapshot]? {
        if let urls = pasteboard.readObjects(
            forClasses: [NSURL.self],
            options: [.urlReadingFileURLsOnly: true]
        ) as? [URL], !urls.isEmpty {
            let files = urls.compactMap(makeFileSnapshot(url:))
            return isMeaningfulFilePayload(files) ? files : nil
        }

        guard let items = pasteboard.pasteboardItems else { return nil }
        let urls = items.compactMap { item -> URL? in
            guard let raw = item.string(forType: .fileURL),
                  let url = URL(string: raw),
                  url.isFileURL else {
                return nil
            }
            return url
        }

        let files = urls.compactMap(makeFileSnapshot(url:))
        return isMeaningfulFilePayload(files) ? files : nil
    }

    nonisolated private static func parseImage(from pasteboard: NSPasteboard) -> ImageAsset? {
        guard let image = NSImage(pasteboard: pasteboard),
              let tiffData = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiffData),
              let pngData = bitmap.representation(using: .png, properties: [:]),
              !pngData.isEmpty else {
            return nil
        }

        let pixelWidth = bitmap.pixelsWide > 0 ? bitmap.pixelsWide : Int(image.size.width)
        let pixelHeight = bitmap.pixelsHigh > 0 ? bitmap.pixelsHigh : Int(image.size.height)
        return ImageAsset(pngData: pngData, pixelWidth: pixelWidth, pixelHeight: pixelHeight)
    }

    nonisolated private static func parseText(from pasteboard: NSPasteboard) -> String? {
        guard let text = pasteboard.string(forType: .string)?
            .trimmingCharacters(in: .whitespacesAndNewlines),
              !text.isEmpty else {
            return nil
        }
        return text
    }

    nonisolated private static func makeFileSnapshot(url: URL) -> FileSnapshot? {
        guard url.isFileURL else { return nil }

        let values = try? url.resourceValues(forKeys: [.isDirectoryKey, .fileSizeKey, .totalFileSizeKey, .nameKey])
        let isDirectory = values?.isDirectory ?? false
        let byteSize = Int64(values?.totalFileSize ?? values?.fileSize ?? recursiveByteSize(at: url))
        let displayName = values?.name ?? url.lastPathComponent

        return FileSnapshot(
            url: url,
            displayName: displayName,
            byteSize: byteSize,
            isDirectory: isDirectory
        )
    }

    nonisolated private static func recursiveByteSize(at url: URL) -> Int {
        if let size = try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? NSNumber {
            return size.intValue
        }

        guard let enumerator = FileManager.default.enumerator(
            at: url,
            includingPropertiesForKeys: [.isRegularFileKey, .totalFileSizeKey, .fileSizeKey]
        ) else {
            return 0
        }

        var total = 0
        for case let childURL as URL in enumerator {
            let values = try? childURL.resourceValues(forKeys: [.isRegularFileKey, .totalFileSizeKey, .fileSizeKey])
            guard values?.isRegularFile == true else { continue }
            total += values?.totalFileSize ?? values?.fileSize ?? 0
        }
        return total
    }

    nonisolated private static func sha256Hex(_ data: Data) -> String {
        let digest = SHA256.hash(data: data)
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    nonisolated private static func isMeaningfulFilePayload(_ files: [FileSnapshot]) -> Bool {
        !files.isEmpty && files.contains { $0.isDirectory || $0.byteSize > 0 }
    }
}
