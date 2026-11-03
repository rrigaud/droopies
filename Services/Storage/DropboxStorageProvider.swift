//
//  DropboxStorageProvider.swift
//  Dropies
//
//  Implémentation de StorageProvider pour l'API Dropbox v2.
//  Gère l'authentification OAuth2 PKCE, le refresh token persistant et les échanges réseau.
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

    public var isConnected: Bool {
        !appKey.isEmpty && !refreshToken.isEmpty
    }

    public init(
        appKey: String = "",
        refreshToken: String = "",
        rootFolderPath: String = "",
        accountDisplayName: String? = nil,
        accountEmail: String? = nil
    ) {
        self.appKey = appKey
        self.refreshToken = refreshToken
        self.rootFolderPath = rootFolderPath
        self.accountDisplayName = accountDisplayName
        self.accountEmail = accountEmail
    }

    public func configure(appKey: String, refreshToken: String, rootFolderPath: String) {
        self.appKey = appKey
        self.refreshToken = refreshToken
        self.rootFolderPath = rootFolderPath
    }

    public func disconnect() async throws {
        self.appKey = ""
        self.refreshToken = ""
        self.accessToken = nil
        self.accountDisplayName = nil
        self.accountEmail = nil
    }

    // MARK: - Gestion de l'Access Token (OAuth2 Refresh)
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

        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw StorageError.unknown("Réponse invalide")
        }
        // 200 = créé, 409 = dossier existe déjà (acceptable)
        if httpResponse.statusCode != 200 && httpResponse.statusCode != 409 {
            let msg = String(data: data, encoding: .utf8) ?? ""
            throw StorageError.serverError(statusCode: httpResponse.statusCode, message: msg)
        }
    }

    public func listContents(at path: String) async throws -> [CloudItem] {
        let token = try await getValidAccessToken()
        let remotePath = normalizeRemotePath(path)

        var request = URLRequest(url: URL(string: "https://api.dropboxapi.com/2/files/list_folder")!)
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: ["path": remotePath])

        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            throw StorageError.folderNotFound(path: path)
        }

        struct ListFolderResponse: Decodable {
            struct Entry: Decodable {
                let tag: String
                let name: String
                let path_display: String?
                let size: Int64?

                enum CodingKeys: String, CodingKey {
                    case tag = ".tag"
                    case name
                    case path_display
                    case size
                }
            }
            let entries: [Entry]
        }

        let decoded = try JSONDecoder().decode(ListFolderResponse.self, from: data)
        return decoded.entries.map { entry in
            CloudItem(
                name: entry.name,
                path: entry.path_display ?? entry.name,
                isDirectory: entry.tag == "folder",
                size: entry.size
            )
        }
    }

    public func moveItem(from sourcePath: String, to destinationPath: String) async throws {
        let token = try await getValidAccessToken()
        let fromPath = normalizeRemotePath(sourcePath)
        let toPath = normalizeRemotePath(destinationPath)

        var request = URLRequest(url: URL(string: "https://api.dropboxapi.com/2/files/move_v2")!)
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "from_path": fromPath,
            "to_path": toPath,
            "autorename": false
        ])

        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            let msg = String(data: data, encoding: .utf8) ?? ""
            throw StorageError.serverError(statusCode: (response as? HTTPURLResponse)?.statusCode ?? 500, message: msg)
        }
    }

    public func deleteItem(at path: String) async throws {
        let token = try await getValidAccessToken()
        let remotePath = normalizeRemotePath(path)

        var request = URLRequest(url: URL(string: "https://api.dropboxapi.com/2/files/delete_v2")!)
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: ["path": remotePath])

        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse, (httpResponse.statusCode == 200 || httpResponse.statusCode == 409) else {
            let msg = String(data: data, encoding: .utf8) ?? ""
            throw StorageError.serverError(statusCode: (response as? HTTPURLResponse)?.statusCode ?? 500, message: msg)
        }
    }

    public func readData(at path: String) async throws -> Data {
        let token = try await getValidAccessToken()
        let remotePath = normalizeRemotePath(path)

        var request = URLRequest(url: URL(string: "https://content.dropboxapi.com/2/files/download")!)
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        let apiArg = try JSONSerialization.data(withJSONObject: ["path": remotePath])
        let apiArgHeader = String(data: apiArg, encoding: .utf8) ?? "{}"
        request.setValue(apiArgHeader, forHTTPHeaderField: "Dropbox-API-Arg")

        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
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
}
