//
//  AppSettings.swift
//  Dropies
//
//  Modèle de configuration de l'application et du portail élèves,
//  compatible à 100 % avec le fichier `settings.json` de Droopy.
//

import Foundation

public struct AppSettings: Codable, Hashable, Sendable {
    public var portalUrl: String
    public var portalTitle: String
    public var portalSubtitle: String
    public var portalTheme: String
    public var portalIcon: String
    public var portalLastGeneratedAt: String?
    public var studentsLastSyncedAt: String?
    public var studentsLastModifiedAt: String?

    // Préférences locales d'application (non stockées dans settings.json partagé)
    public var preferredTheme: ThemeMode
    public var activeStorageProvider: StorageProviderType

    public enum ThemeMode: String, Codable, Sendable, CaseIterable {
        case dark = "dark"
        case light = "light"
        case system = "system"

        public var label: String {
            switch self {
            case .dark: return "Sombre"
            case .light: return "Clair"
            case .system: return "Automatique (Système)"
            }
        }
    }

    public enum StorageProviderType: String, Codable, Sendable, CaseIterable, Identifiable {
        case dropbox = "dropbox"
        case nextcloud = "nextcloud"
        case oneDrive = "oneDrive"
        case googleDrive = "googleDrive"
        case local = "local"

        public var id: String { rawValue }

        public var displayName: String {
            switch self {
            case .dropbox: return "Dropbox"
            case .nextcloud: return "Nextcloud (Nuage Éducation)"
            case .oneDrive: return "Microsoft OneDrive"
            case .googleDrive: return "Google Drive"
            case .local: return "Fichiers Apple / Finder (Natif)"
            }
        }

        public var iconName: String {
            switch self {
            case .dropbox: return "shippingbox.fill"
            case .nextcloud: return "cloud.fill"
            case .oneDrive: return "server.rack"
            case .googleDrive: return "triangle.fill"
            case .local: return "folder.fill"
            }
        }
    }

    /// Année scolaire en cours (ex: "2026-2027" du 1er septembre au 31 août)
    public static var currentSchoolYear: String {
        let calendar = Calendar.current
        let now = Date()
        let year = calendar.component(.year, from: now)
        let month = calendar.component(.month, from: now)
        if month >= 8 {
            return "\(year)-\(year + 1)"
        } else {
            return "\(year - 1)-\(year)"
        }
    }

    public init(
        portalUrl: String = "",
        portalTitle: String = "Portail Élèves",
        portalSubtitle: String = "Évaluations & Documents de la classe",
        portalTheme: String = "emeraude",
        portalIcon: String = "Icon-portail.png",
        portalLastGeneratedAt: String? = nil,
        studentsLastSyncedAt: String? = nil,
        studentsLastModifiedAt: String? = nil,
        preferredTheme: ThemeMode = .dark,
        activeStorageProvider: StorageProviderType = .dropbox
    ) {
        self.portalUrl = portalUrl
        self.portalTitle = portalTitle
        self.portalSubtitle = portalSubtitle
        self.portalTheme = portalTheme
        self.portalIcon = portalIcon
        self.portalLastGeneratedAt = portalLastGeneratedAt
        self.studentsLastSyncedAt = studentsLastSyncedAt
        self.studentsLastModifiedAt = studentsLastModifiedAt
        self.preferredTheme = preferredTheme
        self.activeStorageProvider = activeStorageProvider
    }

    // MARK: - Décodage JSON personnalisé (compatible avec settings.json)
    enum CodingKeys: String, CodingKey {
        case portalUrl
        case portalTitle
        case portalSubtitle
        case portalTheme
        case portalIcon
        case portalLastGeneratedAt
        case studentsLastSyncedAt
        case studentsLastModifiedAt
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        self.portalUrl = (try? container.decode(String.self, forKey: .portalUrl)) ?? ""
        self.portalTitle = (try? container.decode(String.self, forKey: .portalTitle)) ?? "Portail Élèves"
        self.portalSubtitle = (try? container.decode(String.self, forKey: .portalSubtitle)) ?? "Évaluations & Documents de la classe"
        self.portalTheme = (try? container.decode(String.self, forKey: .portalTheme)) ?? "emeraude"
        self.portalIcon = (try? container.decode(String.self, forKey: .portalIcon)) ?? "Icon-portail.png"
        self.portalLastGeneratedAt = try? container.decode(String.self, forKey: .portalLastGeneratedAt)
        self.studentsLastSyncedAt = try? container.decode(String.self, forKey: .studentsLastSyncedAt)
        self.studentsLastModifiedAt = try? container.decode(String.self, forKey: .studentsLastModifiedAt)

        self.preferredTheme = .dark
        self.activeStorageProvider = .dropbox
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(portalUrl, forKey: .portalUrl)
        try container.encode(portalTitle, forKey: .portalTitle)
        try container.encode(portalSubtitle, forKey: .portalSubtitle)
        try container.encode(portalTheme, forKey: .portalTheme)
        try container.encode(portalIcon, forKey: .portalIcon)
        try container.encodeIfPresent(portalLastGeneratedAt, forKey: .portalLastGeneratedAt)
        try container.encodeIfPresent(studentsLastSyncedAt, forKey: .studentsLastSyncedAt)
        try container.encodeIfPresent(studentsLastModifiedAt, forKey: .studentsLastModifiedAt)
    }

    // MARK: - Mises à jour d'horodatage ISO 8601
    private static let isoFormatter = ISO8601DateFormatter()

    public mutating func touchModification() {
        self.studentsLastModifiedAt = Self.isoFormatter.string(from: Date())
    }

    public mutating func touchPortalGeneration() {
        self.portalLastGeneratedAt = Self.isoFormatter.string(from: Date())
    }
}
