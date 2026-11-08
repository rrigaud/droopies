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
        rootFolderPath: String = "",
        accountDisplayName: String? = nil,
        accountEmail: String? = nil
    ) {
        // Chargement des valeurs persistées si non fournies
        let savedToken = UserDefaults.standard.string(forKey: Self.kTokenKey)
        let savedRefresh = UserDefaults.standard.string(forKey: Self.kRefreshTokenKey)
        let savedAppKey = UserDefaults.standard.string(forKey: Self.kAppKey)
        let savedRoot = UserDefaults.standard.string(forKey: Self.kRootPathKey) ?? ""

        self.accessToken = accessToken ?? savedToken
        self.refreshToken = refreshToken.isEmpty ? (savedRefresh ?? "") : refreshToken
        self.appKey = appKey.isEmpty ? (savedAppKey ?? "") : appKey
        self.rootFolderPath = rootFolderPath.isEmpty ? savedRoot : rootFolderPath
        self.accountDisplayName = accountDisplayName
        self.accountEmail = accountEmail
    }

    public func configure(appKey: String? = nil, refreshToken: String? = nil, accessToken: String? = nil, rootFolderPath: String? = nil) {
        if let ak = appKey, !ak.isEmpty {
            self.appKey = ak
            UserDefaults.standard.set(ak, forKey: Self.kAppKey)
        }
        if let rt = refreshToken, !rt.isEmpty {
            self.refreshToken = rt
            UserDefaults.standard.set(rt, forKey: Self.kRefreshTokenKey)
        }
        if let at = accessToken {
            self.accessToken = at
            UserDefaults.standard.set(at, forKey: Self.kTokenKey)
        }
        if let rfp = rootFolderPath {
            setRootFolderPath(rfp)
        }
    }

    /// Modifie uniquement le chemin du dossier source sans toucher aux identifiants OAuth
    public func setRootFolderPath(_ path: String) {
        let clean = path.trimmingCharacters(in: .whitespacesAndNewlines)
        self.rootFolderPath = clean
        if clean.isEmpty {
            UserDefaults.standard.removeObject(forKey: Self.kRootPathKey)
        } else {
            UserDefaults.standard.set(clean, forKey: Self.kRootPathKey)
        }
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

    // MARK: - Gestion de l'Access Token avec Rafraîchissement Automatique OAuth 2.0

    /// Rafraîchit le jeton d'accès via le Refresh Token OAuth 2.0
    @discardableResult
    public func refreshAccessToken() async throws -> String {
        let key = appKey.isEmpty ? DropboxOAuthManager.defaultAppKey : appKey
        guard !key.isEmpty && !refreshToken.isEmpty else {
            throw StorageError.notConnected
        }

        var request = URLRequest(url: URL(string: "https://api.dropboxapi.com/oauth2/token")!)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")

        let params = [
            "grant_type": "refresh_token",
            "refresh_token": refreshToken,
            "client_id": key
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
        UserDefaults.standard.set(decoded.access_token, forKey: Self.kTokenKey)
        return decoded.access_token
    }

    private func getValidAccessToken(forceRefresh: Bool = false) async throws -> String {
        if !forceRefresh, let token = accessToken, !token.isEmpty {
            return token
        }
        return try await refreshAccessToken()
    }

    /// Exécute une requête HTTP avec gestion automatique de la réauthentification (refresh token) sur HTTP 401
    private func sendAuthorizedRequest(_ buildRequest: (String) throws -> URLRequest) async throws -> (Data, HTTPURLResponse) {
        var token = try await getValidAccessToken()
        var req = try buildRequest(token)
        let (data, response) = try await session.data(for: req)
        guard let http = response as? HTTPURLResponse else {
            throw StorageError.unknown("Réponse réseau invalide de Dropbox")
        }

        if http.statusCode == 401 {
            // Token expiré : forcer le rafraîchissement et retenter une fois
            token = try await refreshAccessToken()
            req = try buildRequest(token)
            let (retryData, retryResponse) = try await session.data(for: req)
            guard let retryHttp = retryResponse as? HTTPURLResponse else {
                throw StorageError.unknown("Réponse réseau invalide de Dropbox lors du retry")
            }
            if retryHttp.statusCode == 401 {
                throw StorageError.unauthorized
            }
            return (retryData, retryHttp)
        }
        return (data, http)
    }

    // MARK: - Normalisation de chemin Dropbox
    private func normalizeRemotePath(_ path: String) -> String {
        let clean = path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let root = rootFolderPath.trimmingCharacters(in: CharacterSet(charactersIn: "/"))

        // Si path est explicitement "/" -> Racine absolue du compte Dropbox
        if path == "/" {
            return ""
        }

        if root.isEmpty {
            return clean.isEmpty ? "" : "/\(clean)"
        }

        if clean.isEmpty {
            return "/\(root)"
        }

        let cleanLower = clean.lowercased()
        let rootLower = root.lowercased()

        // 1. Si le chemin correspond exactement au dossier root (insensible à la casse)
        if cleanLower == rootLower {
            return "/\(root)"
        }

        // 2. Si le chemin commence déjà par le dossier root (insensible à la casse)
        if cleanLower.hasPrefix("\(rootLower)/") {
            let subPath = clean.dropFirst(root.count).trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            return "/\(root)/\(subPath)"
        }

        // 3. Si le chemin commence explicitement par "/" (chemin absolu hors du dossier root)
        if path.hasPrefix("/") {
            return "/\(clean)"
        }

        // 4. Chemin relatif par rapport au rootFolderPath
        return "/\(root)/\(clean)"
    }

    // MARK: - Opérations API Dropbox

    public func itemExists(at path: String) async throws -> Bool {
        let remotePath = normalizeRemotePath(path)
        guard !remotePath.isEmpty && remotePath != "/" else { return true }
        let payload = try JSONSerialization.data(withJSONObject: ["path": remotePath])

        do {
            let (_, http) = try await sendAuthorizedRequest { token in
                var request = URLRequest(url: URL(string: "https://api.dropboxapi.com/2/files/get_metadata")!)
                request.httpMethod = "POST"
                request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
                request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                request.httpBody = payload
                return request
            }
            return http.statusCode == 200
        } catch {
            return false
        }
    }

    /// Vérifie si un dossier absolu existe sur le compte Dropbox (renvoie false pour un chemin vide ou inexistant)
    public func folderExists(at absolutePath: String) async throws -> Bool {
        let clean = absolutePath.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        // Un chemin vide ou la racine brute "/" ne constituent pas un sous-dossier source dédié valide
        guard !clean.isEmpty else { return false }

        do {
            let payload = try JSONSerialization.data(withJSONObject: ["path": "/\(clean)"])
            let (data, http) = try await sendAuthorizedRequest { token in
                var request = URLRequest(url: URL(string: "https://api.dropboxapi.com/2/files/get_metadata")!)
                request.httpMethod = "POST"
                request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
                request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                request.httpBody = payload
                return request
            }
            guard http.statusCode == 200 else { return false }

            struct MetadataTag: Decodable {
                let tag: String
                enum CodingKeys: String, CodingKey {
                    case tag = ".tag"
                }
            }
            if let decoded = try? JSONDecoder().decode(MetadataTag.self, from: data) {
                return decoded.tag == "folder"
            }
            return false
        } catch {
            return false
        }
    }

    public func createDirectory(at path: String) async throws {
        let remotePath = normalizeRemotePath(path)
        guard !remotePath.isEmpty && remotePath != "/" else { return }

        // S'assurer que chaque niveau parent existe successivement
        let parts = remotePath.split(separator: "/").map(String.init)
        var cumulative = ""
        for part in parts {
            cumulative += "/\(part)"
            let payload = try JSONSerialization.data(withJSONObject: ["path": cumulative, "autorename": false])

            let (data, http) = try await sendAuthorizedRequest { token in
                var request = URLRequest(url: URL(string: "https://api.dropboxapi.com/2/files/create_folder_v2")!)
                request.httpMethod = "POST"
                request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
                request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                request.httpBody = payload
                return request
            }

            if (200...299).contains(http.statusCode) {
                continue
            } else if http.statusCode == 409 {
                let bodyStr = String(data: data, encoding: .utf8) ?? ""
                if bodyStr.contains("conflict") {
                    continue
                }
            }

            let bodyStr = String(data: data, encoding: .utf8) ?? ""
            throw StorageError.serverError(statusCode: http.statusCode, message: "Impossible de créer le dossier \(cumulative) : \(bodyStr)")
        }
    }

    public func listContents(at path: String) async throws -> [CloudItem] {
        let remotePath = normalizeRemotePath(path)
        let reqPath = (remotePath == "/" || remotePath.isEmpty) ? "" : remotePath
        let payload = try JSONSerialization.data(withJSONObject: ["path": reqPath, "recursive": false])

        let (data, http) = try await sendAuthorizedRequest { token in
            var request = URLRequest(url: URL(string: "https://api.dropboxapi.com/2/files/list_folder")!)
            request.httpMethod = "POST"
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = payload
            return request
        }

        guard (200...299).contains(http.statusCode) else {
            return []
        }

        struct ListFolderResponse: Decodable {
            struct Entry: Decodable {
                let tag: String
                let name: String
                let path_lower: String?
                let path_display: String?
                let size: Int64?

                enum CodingKeys: String, CodingKey {
                    case tag = ".tag"
                    case name
                    case path_lower
                    case path_display
                    case size
                }
            }
            let entries: [Entry]
        }

        let decoded = try JSONDecoder().decode(ListFolderResponse.self, from: data)
        return decoded.entries.map { entry in
            let itemPath = entry.path_display ?? entry.path_lower ?? "/\(entry.name)"
            return CloudItem(
                name: entry.name,
                path: itemPath,
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

    /// Crée un dossier absolu à la racine ou dans l'arborescence du compte Dropbox
    public func createAccountFolder(at absolutePath: String) async throws {
        let token = try await getValidAccessToken()
        let clean = absolutePath.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard !clean.isEmpty else { return }

        let parts = clean.split(separator: "/").map(String.init)
        var cumulative = ""
        for part in parts {
            cumulative += "/\(part)"
            var request = URLRequest(url: URL(string: "https://api.dropboxapi.com/2/files/create_folder_v2")!)
            request.httpMethod = "POST"
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONSerialization.data(withJSONObject: ["path": cumulative, "autorename": false])

            let (data, response) = try await session.data(for: request)
            if let http = response as? HTTPURLResponse {
                if (200...299).contains(http.statusCode) {
                    continue
                } else if http.statusCode == 409 {
                    let bodyStr = String(data: data, encoding: .utf8) ?? ""
                    if bodyStr.contains("conflict") {
                        continue
                    }
                }
            }
        }
    }

    public func readData(at path: String) async throws -> Data {
        let remotePath = normalizeRemotePath(path)
        let apiArg = ["path": remotePath]
        let apiArgData = try JSONSerialization.data(withJSONObject: apiArg)
        let argString = String(data: apiArgData, encoding: .utf8) ?? "{}"

        let (data, http) = try await sendAuthorizedRequest { token in
            var request = URLRequest(url: URL(string: "https://content.dropboxapi.com/2/files/download")!)
            request.httpMethod = "POST"
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            request.setValue(argString, forHTTPHeaderField: "Dropbox-API-Arg")
            return request
        }

        guard (200...299).contains(http.statusCode) else {
            throw StorageError.fileNotFound(path: path)
        }
        return data
    }

    public func writeData(_ data: Data, to path: String) async throws {
        let remotePath = normalizeRemotePath(path)
        let apiArg = [
            "path": remotePath,
            "mode": "overwrite",
            "autorename": false,
            "mute": true
        ] as [String : Any]
        let apiArgData = try JSONSerialization.data(withJSONObject: apiArg)
        let argString = String(data: apiArgData, encoding: .utf8) ?? "{}"

        let (respData, http) = try await sendAuthorizedRequest { token in
            var request = URLRequest(url: URL(string: "https://content.dropboxapi.com/2/files/upload")!)
            request.httpMethod = "POST"
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            request.setValue("application/octet-stream", forHTTPHeaderField: "Content-Type")
            request.setValue(argString, forHTTPHeaderField: "Dropbox-API-Arg")
            request.httpBody = data
            return request
        }

        guard (200...299).contains(http.statusCode) else {
            let errorText = String(data: respData, encoding: .utf8) ?? "Erreur HTTP \(http.statusCode)"
            throw StorageError.serverError(statusCode: http.statusCode, message: "Échec d'écriture Dropbox : \(errorText)")
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
        let remotePath = normalizeRemotePath(path)
        let payload = try JSONSerialization.data(withJSONObject: ["path": remotePath])

        let (respData, http) = try await sendAuthorizedRequest { token in
            var request = URLRequest(url: URL(string: "https://api.dropboxapi.com/2/files/delete_v2")!)
            request.httpMethod = "POST"
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = payload
            return request
        }

        guard (200...299).contains(http.statusCode) else {
            let errorText = String(data: respData, encoding: .utf8) ?? ""
            throw StorageError.unknown("Échec suppression Dropbox (\(remotePath)) : \(errorText)")
        }
    }

    public func moveItem(from sourcePath: String, to destinationPath: String) async throws {
        let fromRemote = normalizeRemotePath(sourcePath)
        let toRemote = normalizeRemotePath(destinationPath)
        let payload = try JSONSerialization.data(withJSONObject: [
            "from_path": fromRemote,
            "to_path": toRemote,
            "autorename": false
        ])

        let (respData, http) = try await sendAuthorizedRequest { token in
            var request = URLRequest(url: URL(string: "https://api.dropboxapi.com/2/files/move_v2")!)
            request.httpMethod = "POST"
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = payload
            return request
        }

        guard (200...299).contains(http.statusCode) else {
            let errorText = String(data: respData, encoding: .utf8) ?? ""
            throw StorageError.unknown("Échec déplacement Dropbox : \(errorText)")
        }
    }

    public func createSharedLink(for remotePath: String) async throws -> String {
        let fullPath = normalizeRemotePath(remotePath)
        let payload = try JSONSerialization.data(withJSONObject: ["path": fullPath])

        let (data, http) = try await sendAuthorizedRequest { token in
            var request = URLRequest(url: URL(string: "https://api.dropboxapi.com/2/sharing/create_shared_link_with_settings")!)
            request.httpMethod = "POST"
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = payload
            return request
        }

        struct SharedLinkResponse: Decodable {
            let url: String
        }

        if (200...299).contains(http.statusCode) {
            let decoded = try JSONDecoder().decode(SharedLinkResponse.self, from: data)
            return decoded.url
        }

        // Si le lien existe déjà (409 conflict), interroger `list_shared_links`
        let listPayload = try JSONSerialization.data(withJSONObject: ["path": fullPath, "direct_only": true])
        let (listData, listHttp) = try await sendAuthorizedRequest { token in
            var listReq = URLRequest(url: URL(string: "https://api.dropboxapi.com/2/sharing/list_shared_links")!)
            listReq.httpMethod = "POST"
            listReq.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            listReq.setValue("application/json", forHTTPHeaderField: "Content-Type")
            listReq.httpBody = listPayload
            return listReq
        }

        guard (200...299).contains(listHttp.statusCode) else {
            let msg = String(data: listData, encoding: .utf8) ?? ""
            throw StorageError.unknown("Impossible d'obtenir le lien de partage : \(msg)")
        }

        struct ListLinksResponse: Decodable {
            struct Link: Decodable { let url: String }
            let links: [Link]
        }
        let listDecoded = try JSONDecoder().decode(ListLinksResponse.self, from: listData)
        if let first = listDecoded.links.first {
            return first.url
        }

        throw StorageError.unknown("Lien partagé introuvable pour \(remotePath)")
    }

    // MARK: - Informations du compte connecté
    public func fetchAccountInfo() async throws {
        do {
            try await requestAccountInfo(token: try await getValidAccessToken())
        } catch StorageError.unauthorized {
            let freshToken = try await refreshAccessToken()
            try await requestAccountInfo(token: freshToken)
        }
    }

    private func requestAccountInfo(token: String) async throws {
        var request = URLRequest(url: URL(string: "https://api.dropboxapi.com/2/users/get_current_account")!)
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw StorageError.unknown("Réponse serveur invalide")
        }
        if http.statusCode == 401 {
            throw StorageError.unauthorized
        }
        guard http.statusCode == 200 else { return }

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
