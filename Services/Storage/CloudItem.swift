//
//  CloudItem.swift
//  Dropies
//
//  Représente un fichier ou un dossier stocké sur le Cloud ou en local.
//

import Foundation

public struct CloudItem: Identifiable, Hashable, Sendable {
    public var id: String { path }
    public var name: String
    public var path: String
    public var isDirectory: Bool
    public var size: Int64?
    public var modifiedAt: Date?

    public init(
        name: String,
        path: String,
        isDirectory: Bool,
        size: Int64? = nil,
        modifiedAt: Date? = nil
    ) {
        self.name = name
        self.path = path
        self.isDirectory = isDirectory
        self.size = size
        self.modifiedAt = modifiedAt
    }
}

public struct CloudFileMetadata: Sendable {
    public let path: String
    public let name: String
    public let size: Int64
    public let sharedUrl: String?

    public init(path: String, name: String, size: Int64, sharedUrl: String? = nil) {
        self.path = path
        self.name = name
        self.size = size
        self.sharedUrl = sharedUrl
    }
}
