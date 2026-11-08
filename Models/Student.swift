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
    
    /// Alias générique pour l'URL du dossier Cloud partagé (Dropbox, Nextcloud, etc.)
    public var urlCloud: String {
        get { urlDropbox }
        set { urlDropbox = newValue }
    }

    /// Nombre de copies actuellement archivées
    public var copiesCount: Int = 0

    /// Nom de famille (en majuscules, ex: "CURIE" ou "DE LA TOUR")
    public var lastName: String {
        let parts = name.components(separatedBy: .whitespacesAndNewlines).filter { !$0.isEmpty }
        guard parts.count > 1 else { return name }
        var nonNumeric = parts
        while let last = nonNumeric.last, Int(last) != nil {
            nonNumeric.removeLast()
        }
        if nonNumeric.count > 1 {
            return nonNumeric.dropLast().joined(separator: " ")
        }
        return nonNumeric.first ?? name
    }

    /// Prénom (capitalisé, ex: "Marie" ou "Jean 2")
    public var firstName: String {
        let parts = name.components(separatedBy: .whitespacesAndNewlines).filter { !$0.isEmpty }
        guard parts.count > 1 else { return "" }
        var nonNumeric = parts
        var trailing: [String] = []
        while let last = nonNumeric.last, Int(last) != nil {
            trailing.insert(last, at: 0)
            nonNumeric.removeLast()
        }
        let fn = nonNumeric.last ?? ""
        return trailing.isEmpty ? fn : "\(fn) \(trailing.joined(separator: " "))"
    }

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

    /// Normalise le nom selon les conventions scolaires : NOM en majuscules, Prénom capitalisé
    /// Exemple : "atton olivier" -> "ATTON Olivier", "ATTON Olivier 2" -> "ATTON Olivier 2"
    public static func sanitizeName(_ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        let parts = trimmed.components(separatedBy: .whitespacesAndNewlines).filter { !$0.isEmpty }
        guard !parts.isEmpty else { return "" }

        // Isoler d'éventuels suffixes numériques (ex: "ATTON Olivier 2")
        var nonNumericParts = parts
        var trailingNumbers: [String] = []
        while let last = nonNumericParts.last, Int(last) != nil {
            trailingNumbers.insert(last, at: 0)
            nonNumericParts.removeLast()
        }

        if nonNumericParts.isEmpty {
            return parts.joined(separator: " ")
        }

        var formattedParts: [String] = []
        if nonNumericParts.count == 1 {
            formattedParts.append(nonNumericParts[0].uppercased())
        } else {
            // Tous les mots sauf le dernier : NOM DE FAMILLE en MAJUSCULES
            for i in 0..<(nonNumericParts.count - 1) {
                formattedParts.append(nonNumericParts[i].uppercased())
            }
            // Dernier mot : Prénom (1ère lettre majuscule, reste minuscule, y compris prénoms composés)
            let prenom = nonNumericParts.last!
            let prenomComponents = prenom.split(separator: "-").map { comp -> String in
                let str = String(comp)
                guard let first = str.first else { return "" }
                return first.uppercased() + str.dropFirst().lowercased()
            }
            formattedParts.append(prenomComponents.joined(separator: "-"))
        }

        formattedParts.append(contentsOf: trailingNumbers)
        return formattedParts.joined(separator: " ")
    }

    /// Transforme un nom en nom de dossier sécurisé sans accents en préservant strictement la casse (NOM Prénom)
    public static func sanitizeFolderName(_ raw: String) -> String {
        // diacriticInsensitive sans caseInsensitive pour préserver les majuscules et minuscules
        let folded = raw.folding(options: [.diacriticInsensitive], locale: .current)
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: " -_"))
        let cleaned = folded.unicodeScalars.filter { allowed.contains($0) }
        let result = String(String.UnicodeScalarView(cleaned)).trimmingCharacters(in: .whitespacesAndNewlines)
        return result.isEmpty ? "Sans_Nom" : result
    }

    /// Génère un identifiant standard à partir du nom complet (ex: "DUPONT Jules" -> "jules.dupont")
    public static func generateLogin(from fullName: String) -> String {
        let clean = sanitizeFolderName(fullName).lowercased()
        let parts = clean.components(separatedBy: " ").filter { !$0.isEmpty }
        guard !parts.isEmpty else { return "eleve" }
        if parts.count >= 2 {
            return "\(parts.last!).\(parts.first!)"
        }
        return parts[0]
    }
}
