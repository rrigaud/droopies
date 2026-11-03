//
//  DropboxOAuthManager.swift
//  Dropies
//
//  Gestionnaire officiel de l'authentification native Dropbox via OAuth 2.0 PKCE.
//  Utilise AuthenticationServices (ASWebAuthenticationSession) pour offrir une connexion
//  en 1 clic ("Se connecter avec Dropbox") sans jamais forcer l'enseignant à manipuler
//  ou copier-coller de jeton développeur.
//

import Foundation
import AuthenticationServices
import CryptoKit

#if os(macOS)
import AppKit
#elseif os(iOS)
import UIKit
#endif

/// Résultat d'une authentification réussie
public struct DropboxAuthSession: Sendable {
    public let displayName: String
    public let email: String
    public let accessToken: String
    public let refreshToken: String
    public let appKey: String
}

/// Gestionnaire d'authentification OAuth 2.0 PKCE pour Dropbox
@MainActor
public final class DropboxOAuthManager: NSObject, ASWebAuthenticationPresentationContextProviding {
    public static let shared = DropboxOAuthManager()

    /// Clé d'application Dropbox par défaut pour Dropies.
    /// Peut être surchargée par l'enseignant dans les paramètres avancés s'il a sa propre Scoped App.
    public static let defaultAppKey = "34f1m7xkyj0y8wh"

    public static let callbackScheme = "dropies"
    public static let redirectURI = "dropies://oauth-callback"

    private static let kSavedAppKey = "dropies_dropbox_app_key"

    private var activeAuthSession: ASWebAuthenticationSession?

    public var effectiveAppKey: String {
        get {
            let saved = UserDefaults.standard.string(forKey: Self.kSavedAppKey)?.trimmingCharacters(in: .whitespacesAndNewlines)
            if let saved = saved, !saved.isEmpty {
                return saved
            }
            return Self.defaultAppKey
        }
        set {
            let clean = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
            if clean.isEmpty {
                UserDefaults.standard.removeObject(forKey: Self.kSavedAppKey)
            } else {
                UserDefaults.standard.set(clean, forKey: Self.kSavedAppKey)
            }
        }
    }

    private override init() {
        super.init()
    }

    // MARK: - ASWebAuthenticationPresentationContextProviding

    #if os(macOS)
    public func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        return NSApplication.shared.keyWindow ?? NSApplication.shared.windows.first ?? NSWindow()
    }
    #elseif os(iOS)
    public func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        if let keyWindow = scenes.flatMap({ $0.windows }).first(where: { $0.isKeyWindow }) {
            return keyWindow
        }
        if let firstWindow = scenes.flatMap({ $0.windows }).first {
            return firstWindow
        }
        return UIWindow()
    }
    #endif

    // MARK: - PKCE Utilities

    /// Génère un Code Verifier cryptographique aléatoire de 64 caractères (RFC 7636)
    private func generateCodeVerifier() -> String {
        var bytes = [UInt8](repeating: 0, count: 48)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        return Data(bytes)
            .base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    /// Calcule le Code Challenge SHA-256 encodé en Base64-URL
    private func generateCodeChallenge(from verifier: String) -> String {
        guard let data = verifier.data(using: .utf8) else { return "" }
        let hash = SHA256.hash(data: data)
        return Data(hash)
            .base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    // MARK: - Flux de Connexion 1-Clic

    /// Déclenche le flux OAuth 2.0 PKCE natif avec `ASWebAuthenticationSession`.
    /// Ouvre la boîte de dialogue système sécurisée Safari, capture le code et l'échange
    /// directement contre un Refresh Token persistant et les infos de profil utilisateur.
    public func signInWithDropbox(customAppKey: String? = nil) async throws -> DropboxAuthSession {
        let appKeyToUse = (customAppKey?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false)
            ? customAppKey!.trimmingCharacters(in: .whitespacesAndNewlines)
            : effectiveAppKey

        guard !appKeyToUse.isEmpty else {
            throw StorageError.unknown("Clé d'application Dropbox manquante.")
        }

        let verifier = generateCodeVerifier()
        let challenge = generateCodeChallenge(from: verifier)

        var components = URLComponents(string: "https://www.dropbox.com/oauth2/authorize")!
        components.queryItems = [
            URLQueryItem(name: "client_id", value: appKeyToUse),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "token_access_type", value: "offline"),
            URLQueryItem(name: "code_challenge", value: challenge),
            URLQueryItem(name: "code_challenge_method", value: "S256"),
            URLQueryItem(name: "redirect_uri", value: Self.redirectURI)
        ]

        guard let authURL = components.url else {
            throw StorageError.unknown("Impossible de générer l'URL d'autorisation Dropbox.")
        }

        // 1. Lancement de la session ASWebAuthenticationSession
        let callbackURL = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<URL, Error>) in
            let session = ASWebAuthenticationSession(
                url: authURL,
                callbackURLScheme: Self.callbackScheme
            ) { url, error in
                if let error = error {
                    continuation.resume(throwing: error)
                    return
                }
                guard let url = url else {
                    continuation.resume(throwing: StorageError.unknown("Aucune URL de retour reçue."))
                    return
                }
                continuation.resume(returning: url)
            }

            session.presentationContextProvider = self
            session.prefersEphemeralWebBrowserSession = false
            self.activeAuthSession = session

            guard session.start() else {
                continuation.resume(throwing: StorageError.unknown("Impossible de lancer la session d'authentification Safari."))
                return
            }
        }

        // 2. Extraction du code d'autorisation
        guard let urlComponents = URLComponents(url: callbackURL, resolvingAgainstBaseURL: false),
              let code = urlComponents.queryItems?.first(where: { $0.name == "code" })?.value else {
            throw StorageError.unknown("Code d'autorisation Dropbox introuvable dans le retour.")
        }

        // 3. Échange du code d'autorisation contre les tokens (Access & Refresh)
        var tokenRequest = URLRequest(url: URL(string: "https://api.dropboxapi.com/oauth2/token")!)
        tokenRequest.httpMethod = "POST"
        tokenRequest.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")

        let params: [String: String] = [
            "code": code,
            "grant_type": "authorization_code",
            "client_id": appKeyToUse,
            "code_verifier": verifier,
            "redirect_uri": Self.redirectURI
        ]
        tokenRequest.httpBody = params.map { "\($0.key)=\($0.value)" }.joined(separator: "&").data(using: .utf8)

        let (data, response) = try await URLSession.shared.data(for: tokenRequest)
        guard let httpResponse = response as? HTTPURLResponse, (200...299).contains(httpResponse.statusCode) else {
            let errString = String(data: data, encoding: .utf8) ?? "Erreur HTTP inconnue"
            throw StorageError.unknown("Échec d'échange du token : \(errString)")
        }

        struct TokenExchangeResponse: Decodable {
            let access_token: String
            let refresh_token: String?
            let account_id: String?
        }

        let tokenResult = try JSONDecoder().decode(TokenExchangeResponse.self, from: data)
        guard let refreshToken = tokenResult.refresh_token else {
            throw StorageError.unknown("Aucun Refresh Token reçu de Dropbox. Vérifiez les droits de l'application.")
        }

        // 4. Récupération des informations de profil
        let profile = try await fetchAccountProfile(accessToken: tokenResult.access_token)

        // 5. Mémorisation des réglages
        effectiveAppKey = appKeyToUse
        UserDefaults.standard.set(tokenResult.access_token, forKey: "dropies_dropbox_token")
        UserDefaults.standard.set(refreshToken, forKey: "dropies_dropbox_refresh_token")

        return DropboxAuthSession(
            displayName: profile.name,
            email: profile.email,
            accessToken: tokenResult.access_token,
            refreshToken: refreshToken,
            appKey: appKeyToUse
        )
    }

    /// Récupère le nom et l'adresse e-mail de l'utilisateur connecté via l'API Dropbox
    private func fetchAccountProfile(accessToken: String) async throws -> (name: String, email: String) {
        var request = URLRequest(url: URL(string: "https://api.dropboxapi.com/2/users/get_current_account")!)
        request.httpMethod = "POST"
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            return ("Enseignant Dropbox", "Compte actif")
        }

        struct AccountResponse: Decodable {
            struct Name: Decodable { let display_name: String }
            let name: Name
            let email: String
        }

        if let decoded = try? JSONDecoder().decode(AccountResponse.self, from: data) {
            return (decoded.name.display_name, decoded.email)
        }
        return ("Enseignant Dropbox", "Compte actif")
    }
}
