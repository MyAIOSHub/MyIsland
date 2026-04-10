//
//  ClipboardStore.swift
//  MyIsland
//
//  Persistent clipboard history store.
//

import Combine
import Foundation
import os.log

actor ClipboardStore {
    static let shared = ClipboardStore()
    nonisolated static let logger = Logger(subsystem: "com.myisland", category: "Clipboard")

    nonisolated static func baseDirectoryURL(fileManager: FileManager = .default) -> URL {
        let bundleIdentifier = Bundle.main.bundleIdentifier ?? "app.myisland.macos"
        let supportURL = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory())
        return supportURL
            .appendingPathComponent(bundleIdentifier, isDirectory: true)
            .appendingPathComponent("ClipboardHistory", isDirectory: true)
    }

    private nonisolated(unsafe) let entriesSubject = CurrentValueSubject<[ClipboardEntry], Never>([])

    nonisolated var entriesPublisher: AnyPublisher<[ClipboardEntry], Never> {
        entriesSubject.eraseToAnyPublisher()
    }

    private let fileManager = FileManager.default
    private let maxEntries = 200
    private var entries: [ClipboardEntry] = []
    private var hasStarted = false

    private let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }()

    private let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()

    private init() {}

    func start() async {
        guard !hasStarted else { return }
        hasStarted = true

        do {
            try ensureDirectories()
            try loadIndex()
        } catch {
            Self.logger.error("Failed to start clipboard store: \(error.localizedDescription, privacy: .public)")
            entries = []
        }

        publish()
    }

    func recentEntries(limit: Int) -> [ClipboardEntry] {
        Array(entries.prefix(limit))
    }

    func capture(_ payload: ClipboardPayload, sourceAppName: String?) async {
        await start()

        let fingerprint = ClipboardParser.canonicalFingerprint(for: payload)
        if let firstEntry = entries.first, firstEntry.fingerprint == fingerprint {
            return
        }

        do {
            let entry = try makeEntry(for: payload, sourceAppName: sourceAppName, fingerprint: fingerprint)
            entries.insert(entry, at: 0)
            try evictIfNeeded()
            try persist()
        } catch {
            Self.logger.error("Failed to capture clipboard entry: \(error.localizedDescription, privacy: .public)")
        }
    }

    func payload(for entryId: String) -> ClipboardPayload? {
        guard let entry = entries.first(where: { $0.id == entryId }) else { return nil }

        switch entry.kind {
        case .text:
            guard let text = entry.textContent, !text.isEmpty else { return nil }
            return .text(text)

        case .image:
            guard let relativePath = entry.assetRelativePaths.first else { return nil }
            let fileURL = absoluteURL(relativePath: relativePath)
            guard let data = try? Data(contentsOf: fileURL), !data.isEmpty else { return nil }
            let imageMeta = entry.imageMetadata ?? ClipboardImageMetadata(pixelWidth: 0, pixelHeight: 0)
            return .image(ImageAsset(
                pngData: data,
                pixelWidth: imageMeta.pixelWidth,
                pixelHeight: imageMeta.pixelHeight
            ))

        case .files:
            let files = entry.files.compactMap { file -> FileSnapshot? in
                let url = absoluteURL(relativePath: file.relativePath)
                guard fileManager.fileExists(atPath: url.path) else { return nil }
                return FileSnapshot(
                    url: url,
                    displayName: file.displayName,
                    byteSize: file.byteSize,
                    isDirectory: file.isDirectory
                )
            }
            return files.isEmpty ? nil : .files(files)
        }
    }

    func promote(entryId: String) throws {
        guard let index = entries.firstIndex(where: { $0.id == entryId }), index > 0 else { return }
        let entry = entries.remove(at: index)
        entries.insert(entry, at: 0)
        try persist()
    }

    func delete(entryId: String) throws {
        guard let index = entries.firstIndex(where: { $0.id == entryId }) else { return }
        let entry = entries.remove(at: index)
        try deleteAssets(for: entry)
        try persist()
    }

    func clearAll() throws {
        let removedEntries = entries
        entries.removeAll()
        for entry in removedEntries {
            try deleteAssets(for: entry)
        }
        try persist()
    }

    // MARK: - Persistence

    private func persist() throws {
        let data = try encoder.encode(entries)
        try data.write(to: indexURL, options: [.atomic])
        publish()
    }

    private func loadIndex() throws {
        guard fileManager.fileExists(atPath: indexURL.path) else {
            entries = []
            return
        }

        let data = try Data(contentsOf: indexURL)
        entries = try decoder.decode([ClipboardEntry].self, from: data)
    }

    private func publish() {
        entriesSubject.send(entries)
    }

    // MARK: - Entry Construction

    private func makeEntry(
        for payload: ClipboardPayload,
        sourceAppName: String?,
        fingerprint: String
    ) throws -> ClipboardEntry {
        let id = UUID().uuidString
        let createdAt = Date()
        let entryDirectory = entryDirectoryURL(entryId: id)
        try fileManager.createDirectory(at: entryDirectory, withIntermediateDirectories: true, attributes: nil)

        switch payload {
        case .text(let text):
            let previewText = normalizedPreviewText(text)
            return ClipboardEntry(
                id: id,
                kind: .text,
                createdAt: createdAt,
                sourceAppName: sourceAppName,
                fingerprint: fingerprint,
                previewText: previewText,
                byteSize: Int64(text.lengthOfBytes(using: .utf8)),
                assetRelativePaths: [],
                fileDisplayNames: [],
                textContent: text,
                imageMetadata: nil,
                files: []
            )

        case .image(let asset):
            let imageURL = entryDirectory.appendingPathComponent("image.png")
            try asset.pngData.write(to: imageURL, options: [.atomic])
            let relativePath = relativePath(for: imageURL)
            return ClipboardEntry(
                id: id,
                kind: .image,
                createdAt: createdAt,
                sourceAppName: sourceAppName,
                fingerprint: fingerprint,
                previewText: "\(asset.pixelWidth)×\(asset.pixelHeight)",
                byteSize: Int64(asset.pngData.count),
                assetRelativePaths: [relativePath],
                fileDisplayNames: [],
                textContent: nil,
                imageMetadata: ClipboardImageMetadata(pixelWidth: asset.pixelWidth, pixelHeight: asset.pixelHeight),
                files: []
            )

        case .files(let files):
            var relativePaths: [String] = []
            var fileDisplayNames: [String] = []
            var fileMetadata: [ClipboardFileMetadata] = []

            for file in files {
                let destinationURL = uniqueDestinationURL(for: file.displayName, in: entryDirectory)
                try fileManager.copyItem(at: file.url, to: destinationURL)
                let relativePath = relativePath(for: destinationURL)
                relativePaths.append(relativePath)
                fileDisplayNames.append(file.displayName)
                fileMetadata.append(ClipboardFileMetadata(
                    relativePath: relativePath,
                    displayName: file.displayName,
                    byteSize: file.byteSize,
                    isDirectory: file.isDirectory
                ))
            }

            return ClipboardEntry(
                id: id,
                kind: .files,
                createdAt: createdAt,
                sourceAppName: sourceAppName,
                fingerprint: fingerprint,
                previewText: fileDisplayNames.joined(separator: ", "),
                byteSize: fileMetadata.reduce(0) { $0 + $1.byteSize },
                assetRelativePaths: relativePaths,
                fileDisplayNames: fileDisplayNames,
                textContent: nil,
                imageMetadata: nil,
                files: fileMetadata
            )
        }
    }

    // MARK: - Eviction / Cleanup

    private func evictIfNeeded() throws {
        while entries.count > maxEntries {
            let removed = entries.removeLast()
            try deleteAssets(for: removed)
        }
    }

    private func deleteAssets(for entry: ClipboardEntry) throws {
        let directoryURL = entryDirectoryURL(entryId: entry.id)
        if fileManager.fileExists(atPath: directoryURL.path) {
            try fileManager.removeItem(at: directoryURL)
        }
    }

    private func uniqueDestinationURL(for fileName: String, in directory: URL) -> URL {
        let sanitizedName = fileName.isEmpty ? "file" : fileName
        let candidate = directory.appendingPathComponent(sanitizedName)
        guard fileManager.fileExists(atPath: candidate.path) else { return candidate }

        let baseName = candidate.deletingPathExtension().lastPathComponent
        let ext = candidate.pathExtension
        var index = 1
        while true {
            let suffix = "\(baseName)-\(index)"
            let candidateName = ext.isEmpty ? suffix : "\(suffix).\(ext)"
            let nextURL = directory.appendingPathComponent(candidateName)
            if !fileManager.fileExists(atPath: nextURL.path) {
                return nextURL
            }
            index += 1
        }
    }

    // MARK: - Paths

    private var baseDirectoryURL: URL {
        Self.baseDirectoryURL(fileManager: fileManager)
    }

    private var entriesDirectoryURL: URL {
        baseDirectoryURL.appendingPathComponent("Entries", isDirectory: true)
    }

    private var indexURL: URL {
        baseDirectoryURL.appendingPathComponent("index.json")
    }

    private func entryDirectoryURL(entryId: String) -> URL {
        entriesDirectoryURL.appendingPathComponent(entryId, isDirectory: true)
    }

    private func ensureDirectories() throws {
        try fileManager.createDirectory(at: baseDirectoryURL, withIntermediateDirectories: true, attributes: nil)
        try fileManager.createDirectory(at: entriesDirectoryURL, withIntermediateDirectories: true, attributes: nil)
    }

    private func relativePath(for url: URL) -> String {
        let prefix = baseDirectoryURL.path + "/"
        return url.path.replacingOccurrences(of: prefix, with: "")
    }

    private func absoluteURL(relativePath: String) -> URL {
        baseDirectoryURL.appendingPathComponent(relativePath)
    }

    private func normalizedPreviewText(_ text: String) -> String {
        text
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "\n", with: " ")
    }
}
