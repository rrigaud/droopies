//
//  DropboxStorageProvider.swift
//  Droopies
//
//  Implémentation de StorageProvider pour l'API Dropbox v2.
//  Supporte à la fois les jetons d'accès directs (Developer Token)
//  et les Refresh Tokens persistants avec persistance automatique.
//

import Foundation

public final class DropboxStorageProvider: StorageProvider, @unchecked Sendable {
    public let providerType: AppSettings.StorageProviderType = .dropbox

    public private(set) var appKey: String
    public private(set) var refreshToken: String
    public private(set) var accessToken: String?
    public private(set) var rootFolderPath: String

    public private(set) var accountDisplayName: String?
    public private(set) var accountEmail: String?

    private let session = URLSession(configuration: .default)

    private static let kTokenKey = "droopies_dropbox_token"
    private static let kRefreshTokenKey = "droopies_dropbox_refresh_token"
    private static let kAppKey = "droopies_dropbox_app_key"
    private static let kRootPathKey = "droopies_dropbox_root_path"

    public var isConnected: Bool {
        (accessToken != nil && !accessToken!.isEmpty) || (!appKey.isEmpty && !refreshToken.isEmpty)
    }

    public init(
        appKey: String = "",
        refreshToken: String = "",
        accessToken: String? = nil,
        rootFolderPath: String = "/Droopies",
        accountDisplayName: String? = nil,
        accountEmail: String? = nil
    ) {
        // Chargement des valeurs persistées si non fournies
        let savedToken = UserDefaults.standard.string(forKey: Self.kTokenKey)
        let savedRefresh = UserDefaults.standard.string(forKey: Self.kRefreshTokenKey)
        let savedAppKey = UserDefaults.standard.string(forKey: Self.kAppKey)
        let savedRoot = UserDefaults.standard.string(forKey: Self.kRootPathKey) ?? "/Droopies"

        self.accessToken = accessToken ?? savedToken
        self.refreshToken = refreshToken.isEmpty ? (savedRefresh ?? "") : refreshToken
        self.appKey = appKey.isEmpty ? (savedAppKey ?? "") : appKey
        self.rootFolderPath = rootFolderPath.isEmpty ? savedRoot : rootFolderPath
        self.accountDisplayName = accountDisplayName
        self.accountEmail = accountEmail
    }

    public func configure(appKey: String = "", refreshToken: String = "", accessToken: String? = nil, rootFolderPath: String = "/Droopies") {
        self.appKey = appKey
        self.refreshToken = refreshToken
        self.accessToken = accessToken
        self.rootFolderPath = rootFolderPath

        // Sauvegarde persistante
        UserDefaults.standard.set(accessToken, forKey: Self.kTokenKey)
        UserDefaults.standard.set(refreshToken, forKey: Self.kRefreshTokenKey)
        UserDefaults.standard.set(appKey, forKey: Self.kAppKey)
        UserDefaults.standard.set(rootFolderPath, forKey: Self.kRootPathKey)
    }

    public func configure(session: DropboxAuthSession, rootFolderPath: String? = nil) {
        self.appKey = session.appKey
        self.refreshToken = session.refreshToken
        self.accessToken = session.accessToken
        self.accountDisplayName = session.displayName
        self.accountEmail = session.email
        if let root = rootFolderPath, !root.isEmpty {
            self.rootFolderPath = root
        }

        UserDefaults.standard.set(session.accessToken, forKey: Self.kTokenKey)
        UserDefaults.standard.set(session.refreshToken, forKey: Self.kRefreshTokenKey)
        UserDefaults.standard.set(session.appKey, forKey: Self.kAppKey)
        if let root = rootFolderPath, !root.isEmpty {
            UserDefaults.standard.set(root, forKey: Self.kRootPathKey)
        }
    }

    public func disconnect() async throws {
        self.appKey = ""
        self.refreshToken = ""
        self.accessToken = nil
        self.accountDisplayName = nil
        self.accountEmail = nil

        UserDefaults.standard.removeObject(forKey: Self.kTokenKey)
        UserDefaults.standard.removeObject(forKey: Self.kRefreshTokenKey)
        UserDefaults.standard.removeObject(forKey: Self.kAppKey)
    }

    // MARK: - Gestion de l'Access Token
    private func getValidAccessToken() async throws -> String {
        if let token = accessToken, !token.isEmpty {
            return token
        }
        guard isConnected else {
            throw StorageError.notConnected
        }

        var request = URLRequest(url: URL(string: "https://api.dropboxapi.com/oauth2/token")!)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")

        let params = [
            "grant_type": "refresh_token",
            "refresh_token": refreshToken,
            "client_id": appKey
        ]
        request.httpBody = params.map { "\($0.key)=\($0.value)" }.joined(separator: "&").data(using: .utf8)

        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse, (200...299).contains(httpResponse.statusCode) else {
            throw StorageError.unauthorized
        }

        struct TokenResponse: Decodable {
            let access_token: String
        }

        let decoded = try JSONDecoder().decode(TokenResponse.self, from: data)
        self.accessToken = decoded.access_token
        return decoded.access_token
    }

    // MARK: - Normalisation de chemin Dropbox
    private func normalizeRemotePath(_ path: String) -> String {
        let clean = path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let root = rootFolderPath.trimmingCharacters(in: CharacterSet(charactersIn: "/"))

        if root.isEmpty {
            return clean.isEmpty ? "" : "/\(clean)"
        }
        return clean.isEmpty ? "/\(root)" : "/\(root)/\(clean)"
    }

    // MARK: - Opérations API Dropbox

    public func itemExists(at path: String) async throws -> Bool {
        let token = try await getValidAccessToken()
        let remotePath = normalizeRemotePath(path)

        var request = URLRequest(url: URL(string: "https://api.dropboxapi.com/2/files/get_metadata")!)
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: ["path": remotePath])

        let (_, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else { return false }
        return httpResponse.statusCode == 200
    }

    public func createDirectory(at path: String) async throws {
        let token = try await getValidAccessToken()
        let remotePath = normalizeRemotePath(path)

        var request = URLRequest(url: URL(string: "https://api.dropboxapi.com/2/files/create_folder_v2")!)
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: ["path": remotePath, "autorename": false])

        let (_, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse, (200...299).contains(httpResponse.statusCode) || httpResponse.statusCode == 409 else {
            throw StorageError.unknown("Impossible de créer le dossier Dropbox : \(remotePath)")
        }
    }

    public func listContents(at path: String) async throws -> [CloudItem] {
        let token = try await getValidAccessToken()
        let remotePath = normalizeRemotePath(path)

        var request = URLRequest(url: URL(string: "https://api.dropboxapi.com/2/files/list_folder")!)
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let reqPath = remotePath == "/" ? "" : remotePath
        request.httpBody = try JSONSerialization.data(withJSONObject: ["path": reqPath, "recursive": false])

        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse, (200...299).contains(httpResponse.statusCode) else {
            return []
        }

        struct ListFolderResponse: Decodable {
            struct Entry: Decodable {
                let tag: String
                let name: String
                let path_lower: String?
                let size: Int64?

                enum CodingKeys: String, CodingKey {
                    case tag = ".tag"
                    case name
                    case path_lower
                    case size
                }
            }
            let entries: [Entry]
        }

        let decoded = try JSONDecoder().decode(ListFolderResponse.self, from: data)
        return decoded.entries.map { entry in
            CloudItem(
                name: entry.name,
                path: entry.path_lower ?? entry.name,
                isDirectory: entry.tag == "folder",
                size: entry.size
            )
        }
    }

    /// Liste les dossiers à la racine ou dans un sous-dossier absolu du compte Dropbox (utilisé pour le sélecteur de dossier racine).
    public func listAccountFolders(at absolutePath: String = "") async throws -> [CloudItem] {
        let token = try await getValidAccessToken()
        let clean = absolutePath.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let reqPath = clean.isEmpty ? "" : "/\(clean)"

        var request = URLRequest(url: URL(string: "https://api.dropboxapi.com/2/files/list_folder")!)
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let body: [String: Any] = [
            "path": reqPath,
            "recursive": false,
            "include_mounted_folders": true,
            "limit": 2000
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw StorageError.unknown("Réponse invalide du serveur Dropbox")
        }
        guard (200...299).contains(httpResponse.statusCode) else {
            let errorText = String(data: data, encoding: .utf8) ?? "Erreur HTTP \(httpResponse.statusCode)"
            throw StorageError.serverError(statusCode: httpResponse.statusCode, message: errorText)
        }

        struct ListFolderResponse: Decodable {
            struct Entry: Decodable {
                let tag: String
                let name: String
                let path_lower: String?
                let path_display: String?

                enum CodingKeys: String, CodingKey {
                    case tag = ".tag"
                    case name
                    case path_lower
                    case path_display
                }
            }
            let entries: [Entry]
        }

        let decoded = try JSONDecoder().decode(ListFolderResponse.self, from: data)
        return decoded.entries.compactMap { entry in
            guard entry.tag == "folder" else { return nil }
            let folderPath = entry.path_display ?? entry.path_lower ?? "/\(entry.name)"
            return CloudItem(
                name: entry.name,
                path: folderPath,
                isDirectory: true
            )
        }
    }

    /// Crée un dossier absolu à la racine du compte Dropbox
    public func createAccountFolder(at absolutePath: String) async throws {
        let token = try await getValidAccessToken()
        let clean = absolutePath.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let reqPath = "/\(clean)"

        var request = URLRequest(url: URL(string: "https://api.dropboxapi.com/2/files/create_folder_v2")!)
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: ["path": reqPath, "autorename": false])

        let (_, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse, (200...299).contains(httpResponse.statusCode) || httpResponse.statusCode == 409 else {
            throw StorageError.unknown("Impossible de créer le dossier : \(reqPath)")
        }
    }

    public func readData(at path: String) async throws -> Data {
        let token = try await getValidAccessToken()
        let remotePath = normalizeRemotePath(path)

        var request = URLRequest(url: URL(string: "https://content.dropboxapi.com/2/files/download")!)
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        let apiArg = ["path": remotePath]
        let apiArgData = try JSONSerialization.data(withJSONObject: apiArg)
        request.setValue(String(data: apiArgData, encoding: .utf8) ?? "{}", forHTTPHeaderField: "Dropbox-API-Arg")

        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse, (200...299).contains(httpResponse.statusCode) else {
            throw StorageError.fileNotFound(path: path)
        }
        return data
    }

    public func writeData(_ data: Data, to path: String) async throws {
        let token = try await getValidAccessToken()
        let remotePath = normalizeRemotePath(path)

        var request = URLRequest(url: URL(string: "https://content.dropboxapi.com/2/files/upload")!)
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/octet-stream", forHTTPHeaderField: "Content-Type")

        let apiArg = [
            "path": remotePath,
            "mode": "overwrite",
            "autorename": false,
            "mute": true
        ] as [String : Any]
        let apiArgData = try JSONSerialization.data(withJSONObject: apiArg)
        request.setValue(String(data: apiArgData, encoding: .utf8) ?? "{}", forHTTPHeaderField: "Dropbox-API-Arg")
        request.httpBody = data

        let (_, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse, (200...299).contains(httpResponse.statusCode) else {
            throw StorageError.unknown("Échec d'écriture Dropbox")
        }
    }

    public func uploadFile(localURL: URL, remotePath: String, progress: ((Double) -> Void)?) async throws -> CloudFileMetadata {
        let data = try Data(contentsOf: localURL)
        try await writeData(data, to: remotePath)
        progress?(1.0)
        return CloudFileMetadata(path: remotePath, name: localURL.lastPathComponent, size: Int64(data.count))
    }

    public func downloadFile(remotePath: String, to localURL: URL) async throws {
        let data = try await readData(at: remotePath)
        try data.write(to: localURL)
    }

    public func deleteItem(at path: String) async throws {
        let token = try await getValidAccessToken()
        let remotePath = normalizeRemotePath(path)

        var request = URLRequest(url: URL(string: "https://api.dropboxapi.com/2/files/delete_v2")!)
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: ["path": remotePath])

        let (_, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse, (200...299).contains(httpResponse.statusCode) else {
            throw StorageError.unknown("Échec suppression Dropbox : \(remotePath)")
        }
    }

    public func moveItem(from sourcePath: String, to destinationPath: String) async throws {
        let token = try await getValidAccessToken()
        let fromRemote = normalizeRemotePath(sourcePath)
        let toRemote = normalizeRemotePath(destinationPath)

        var request = URLRequest(url: URL(string: "https://api.dropboxapi.com/2/files/move_v2")!)
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "from_path": fromRemote,
            "to_path": toRemote,
            "autorename": false
        ])

        let (_, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse, (200...299).contains(httpResponse.statusCode) else {
            throw StorageError.unknown("Échec déplacement Dropbox")
        }
    }

    public func createSharedLink(for remotePath: String) async throws -> String {
        let token = try await getValidAccessToken()
        let fullPath = normalizeRemotePath(remotePath)

        var request = URLRequest(url: URL(string: "https://api.dropboxapi.com/2/sharing/create_shared_link_with_settings")!)
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: ["path": fullPath])

        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw StorageError.unknown("Erreur lien de partage")
        }

        struct SharedLinkResponse: Decodable {
            let url: String
        }

        if (200...299).contains(httpResponse.statusCode) {
            let decoded = try JSONDecoder().decode(SharedLinkResponse.self, from: data)
            return decoded.url
        }

        // Si le lien existe déjà, interroger `list_shared_links`
        var listReq = URLRequest(url: URL(string: "https://api.dropboxapi.com/2/sharing/list_shared_links")!)
        listReq.httpMethod = "POST"
        listReq.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        listReq.setValue("application/json", forHTTPHeaderField: "Content-Type")
        listReq.httpBody = try JSONSerialization.data(withJSONObject: ["path": fullPath, "direct_only": true])

        let (listData, listResp) = try await session.data(for: listReq)
        guard let listHttp = listResp as? HTTPURLResponse, listHttp.statusCode == 200 else {
            throw StorageError.unknown("Impossible d'obtenir le lien de partage")
        }

        struct ListLinksResponse: Decodable {
            struct Link: Decodable { let url: String }
            let links: [Link]
        }
        let listDecoded = try JSONDecoder().decode(ListLinksResponse.self, from: listData)
        if let first = listDecoded.links.first {
            return first.url
        }

        throw StorageError.unknown("Lien introuvable")
    }

    // MARK: - Informations du compte connecté
    public func fetchAccountInfo() async throws {
        let token = try await getValidAccessToken()
        var request = URLRequest(url: URL(string: "https://api.dropboxapi.com/2/users/get_current_account")!)
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else { return }

        struct AccountInfo: Decodable {
            struct Name: Decodable { let display_name: String }
            let name: Name
            let email: String
        }

        if let info = try? JSONDecoder().decode(AccountInfo.self, from: data) {
            self.accountDisplayName = info.name.display_name
            self.accountEmail = info.email
        }
    }

    public func testConnection() async throws -> (name: String, email: String) {
        try await fetchAccountInfo()
        let name = accountDisplayName ?? "Utilisateur Dropbox"
        let email = accountEmail ?? "Connecté"
        return (name, email)
    }
}
