//
//  Student.swift
//  Dropies
//
//  Modèle de données représentant un élève.
//  Compatible à 100 % avec le fichier `eleves.json` historique de Droopy.
//

import Foundation
import CryptoKit

public struct Student: Identifiable, Codable, Hashable, Sendable {
    public var id: Int
    public var name: String
    public var classe: String
    public var gender: Gender
    public var login: String
    public var password: String
    public var urlDropbox: String

    public enum Gender: String, Codable, Sendable, CaseIterable {
        case male = "M"
        case female = "F"

        public var label: String {
            switch self {
            case .male: return "Garçon"
            case .female: return "Fille"
            }
        }
    }

    // MARK: - Initializer standard
    public init(
        id: Int,
        name: String,
        classe: String,
        gender: Gender = .male,
        login: String = "",
        password: String = "",
        urlDropbox: String = ""
    ) {
        self.id = id
        self.name = Student.sanitizeName(name)
        self.classe = classe.trimmingCharacters(in: .whitespacesAndNewlines)
        self.gender = gender
        self.login = login.trimmingCharacters(in: .whitespacesAndNewlines)
        self.password = password.trimmingCharacters(in: .whitespacesAndNewlines)
        self.urlDropbox = urlDropbox.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - Décodage JSON personnalisé (compatible eleves.json & variantes)
    enum CodingKeys: String, CodingKey {
        case id
        case name
        case classe
        case gender
        case login
        case password
        case urlDropbox
        case legacyDropboxUrl = "dropbox-url"
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        self.id = try container.decode(Int.self, forKey: .id)
        self.name = try container.decode(String.self, forKey: .name)
        self.classe = (try? container.decode(String.self, forKey: .classe)) ?? ""

        let rawGender = (try? container.decode(String.self, forKey: .gender)) ?? "M"
        self.gender = Gender(rawValue: rawGender.uppercased()) ?? .male

        self.login = (try? container.decode(String.self, forKey: .login)) ?? ""
        self.password = (try? container.decode(String.self, forKey: .password)) ?? ""

        if let url = try? container.decode(String.self, forKey: .urlDropbox) {
            self.urlDropbox = url
        } else if let legacyUrl = try? container.decode(String.self, forKey: .legacyDropboxUrl) {
            self.urlDropbox = legacyUrl
        } else {
            self.urlDropbox = ""
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(name, forKey: .name)
        try container.encode(classe, forKey: .classe)
        try container.encode(gender.rawValue, forKey: .gender)
        try container.encode(login, forKey: .login)
        try container.encode(password, forKey: .password)
        try container.encode(urlDropbox, forKey: .urlDropbox)
    }

    // MARK: - Propriétés calculées utiles

    /// Nom de dossier physique nettoyé de tous les accents et caractères spéciaux
    public var folderName: String {
        Student.sanitizeFolderName(name)
    }

    /// Empreinte SHA-256 du code/mot de passe (pour le portail élève sécurisé)
    public var passwordSha256: String {
        let clean = password.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard !clean.isEmpty else { return "" }
        let digest = SHA256.hash(data: Data(clean.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    // MARK: - Méthodes de nettoyage de texte

    /// Nettoie les espaces multiples et normalise la casse
    public static func sanitizeName(_ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        let components = trimmed.components(separatedBy: .whitespacesAndNewlines).filter { !$0.isEmpty }
        return components.joined(separator: " ")
    }

    /// Transforme un nom en nom de dossier sécurisé sans accents
    public static func sanitizeFolderName(_ raw: String) -> String {
        let folded = raw.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: " -_"))
        let cleaned = folded.unicodeScalars.filter { allowed.contains($0) }
        let result = String(String.UnicodeScalarView(cleaned)).trimmingCharacters(in: .whitespacesAndNewlines)
        return result.isEmpty ? "Sans_Nom" : result
    }
}
