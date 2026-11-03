//
//  LocalStorageProvider.swift
//  Dropies
//
//  Implémentation locale de StorageProvider utilisant le système de fichiers (FileManager).
//

import Foundation

public final class LocalStorageProvider: StorageProvider, @unchecked Sendable {
    public let providerType: AppSettings.StorageProviderType = .local
    public private(set) var rootURL: URL?
    private let fileManager = FileManager.default

    public var isConnected: Bool {
        rootURL != nil
    }

    public var accountDisplayName: String? {
        rootURL?.lastPathComponent ?? "Dossier Local"
    }

    public var accountEmail: String? {
        rootURL?.path
    }

    public init(rootURL: URL? = nil) {
        self.rootURL = rootURL
    }

    public func setRootURL(_ url: URL) {
        self.rootURL = url
    }

    public func disconnect() async throws {
        self.rootURL = nil
    }

    // MARK: - Résolution de chemin sécurisée
    private func resolveURL(for path: String) throws -> URL {
        guard let root = rootURL else {
            throw StorageError.notConfigured
        }
        let clean = path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        return clean.isEmpty ? root : root.appendingPathComponent(clean)
    }

    // MARK: - Opérations fichiers & dossiers
    public func itemExists(at path: String) async throws -> Bool {
        let url = try resolveURL(for: path)
        return fileManager.fileExists(atPath: url.path)
    }

    public func createDirectory(at path: String) async throws {
        let url = try resolveURL(for: path)
        if !fileManager.fileExists(atPath: url.path) {
            try fileManager.createDirectory(at: url, withIntermediateDirectories: true)
        }
    }

    public func listContents(at path: String) async throws -> [CloudItem] {
        let url = try resolveURL(for: path)
        guard fileManager.fileExists(atPath: url.path) else {
            throw StorageError.folderNotFound(path: path)
        }

        let urls = try fileManager.contentsOfDirectory(
            at: url,
            includingPropertiesForKeys: [.isDirectoryKey, .fileSizeKey, .contentModificationDateKey],
            options: [.skipsHiddenFiles]
        )

        return urls.map { fileURL in
            let resourceValues = try? fileURL.resourceValues(forKeys: [.isDirectoryKey, .fileSizeKey, .contentModificationDateKey])
            let isDir = resourceValues?.isDirectory ?? false
            let size = resourceValues?.fileSize.map { Int64($0) }
            let modDate = resourceValues?.contentModificationDate
            let relativePath = fileURL.path.replacingOccurrences(of: rootURL?.path ?? "", with: "")

            return CloudItem(
                name: fileURL.lastPathComponent,
                path: relativePath,
                isDirectory: isDir,
                size: size,
                modifiedAt: modDate
            )
        }
    }

    public func readData(at path: String) async throws -> Data {
        let url = try resolveURL(for: path)
        guard fileManager.fileExists(atPath: url.path) else {
            throw StorageError.fileNotFound(path: path)
        }
        return try Data(contentsOf: url)
    }

    public func writeData(_ data: Data, to path: String) async throws {
        let url = try resolveURL(for: path)
        let parentDir = url.deletingLastPathComponent()
        if !fileManager.fileExists(atPath: parentDir.path) {
            try fileManager.createDirectory(at: parentDir, withIntermediateDirectories: true)
        }
        try data.write(to: url, options: .atomic)
    }

    public func uploadFile(localURL: URL, remotePath: String, progress: ((Double) -> Void)?) async throws -> CloudFileMetadata {
        let targetURL = try resolveURL(for: remotePath)
        let parentDir = targetURL.deletingLastPathComponent()
        if !fileManager.fileExists(atPath: parentDir.path) {
            try fileManager.createDirectory(at: parentDir, withIntermediateDirectories: true)
        }

        if fileManager.fileExists(atPath: targetURL.path) {
            try fileManager.removeItem(at: targetURL)
        }
        try fileManager.copyItem(at: localURL, to: targetURL)

        progress?(1.0)
        let attrs = try? fileManager.attributesOfItem(atPath: targetURL.path)
        let size = (attrs?[.size] as? NSNumber)?.int64Value ?? 0

        return CloudFileMetadata(path: remotePath, name: targetURL.lastPathComponent, size: size)
    }

    public func downloadFile(remotePath: String, to localURL: URL) async throws {
        let sourceURL = try resolveURL(for: remotePath)
        guard fileManager.fileExists(atPath: sourceURL.path) else {
            throw StorageError.fileNotFound(path: remotePath)
        }

        if fileManager.fileExists(atPath: localURL.path) {
            try fileManager.removeItem(at: localURL)
        }
        try fileManager.copyItem(at: sourceURL, to: localURL)
    }

    public func createSharedLink(for remotePath: String) async throws -> String {
        let url = try resolveURL(for: remotePath)
        return url.absoluteString
    }
}
