//
//  StorageProvider.swift
//  Dropies
//
//  Protocole universel d'accès au stockage.
//  Abstrait les différences entre Dropbox, Nextcloud (Nuage) et le stockage local.
//

import Foundation

public enum StorageError: LocalizedError, Sendable {
    case notConnected
    case notConfigured
    case folderNotFound(path: String)
    case fileNotFound(path: String)
    case unauthorized
    case serverError(statusCode: Int, message: String)
    case networkError(Error)
    case decodingFailed(Error)
    case unknown(String)

    public var errorDescription: String? {
        switch self {
        case .notConnected:
            return "Le service de stockage n'est pas connecté."
        case .notConfigured:
            return "Aucun dossier source n'est configuré."
        case .folderNotFound(let path):
            return "Dossier introuvable : \(path)"
        case .fileNotFound(let path):
            return "Fichier introuvable : \(path)"
        case .unauthorized:
            return "Session expirée ou droits d'accès insuffisants."
        case .serverError(let code, let msg):
            return "Erreur serveur (\(code)) : \(msg)"
        case .networkError(let err):
            return "Erreur réseau : \(err.localizedDescription)"
        case .decodingFailed(let err):
            return "Erreur lors du décodage des données : \(err.localizedDescription)"
        case .unknown(let msg):
            return msg
        }
    }
}

public protocol StorageProvider: AnyObject, Sendable {
    var providerType: AppSettings.StorageProviderType { get }
    var isConnected: Bool { get }
    var accountDisplayName: String? { get }
    var accountEmail: String? { get }

    // MARK: - Connexion
    func disconnect() async throws

    // MARK: - Opérations sur les dossiers et fichiers
    func itemExists(at path: String) async throws -> Bool
    func createDirectory(at path: String) async throws
    func listContents(at path: String) async throws -> [CloudItem]
    func moveItem(from sourcePath: String, to destinationPath: String) async throws
    func deleteItem(at path: String) async throws

    // MARK: - Lecture et Écriture de données brutes
    func readData(at path: String) async throws -> Data
    func writeData(_ data: Data, to path: String) async throws

    // MARK: - Téléversement et Téléchargement de fichiers volumineux (PDF)
    func uploadFile(localURL: URL, remotePath: String, progress: ((Double) -> Void)?) async throws -> CloudFileMetadata
    func downloadFile(remotePath: String, to localURL: URL) async throws

    // MARK: - Partage (liens publics élèves)
    func createSharedLink(for remotePath: String) async throws -> String
}
