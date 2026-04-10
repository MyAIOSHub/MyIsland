//
//  ClipboardEntry.swift
//  MyIsland
//
//  Models for persisted clipboard history entries.
//

import Foundation

enum ClipboardEntryKind: String, Codable, Equatable, Sendable {
    case text
    case image
    case files
}

struct ClipboardImageMetadata: Codable, Equatable, Sendable {
    let pixelWidth: Int
    let pixelHeight: Int
}

struct ClipboardFileMetadata: Codable, Equatable, Sendable {
    let relativePath: String
    let displayName: String
    let byteSize: Int64
    let isDirectory: Bool
}

struct ClipboardEntry: Codable, Equatable, Identifiable, Sendable {
    let id: String
    let kind: ClipboardEntryKind
    let createdAt: Date
    let sourceAppName: String?
    let fingerprint: String
    let previewText: String
    let byteSize: Int64
    let assetRelativePaths: [String]
    let fileDisplayNames: [String]
    let textContent: String?
    let imageMetadata: ClipboardImageMetadata?
    let files: [ClipboardFileMetadata]
}

struct ImageAsset: Equatable, Sendable {
    let pngData: Data
    let pixelWidth: Int
    let pixelHeight: Int
}

struct FileSnapshot: Equatable, Sendable {
    let url: URL
    let displayName: String
    let byteSize: Int64
    let isDirectory: Bool
}

enum ClipboardPayload: Equatable, Sendable {
    case text(String)
    case image(ImageAsset)
    case files([FileSnapshot])
}
