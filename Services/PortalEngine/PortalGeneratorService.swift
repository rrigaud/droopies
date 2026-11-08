//
//  PortalGeneratorService.swift
//  Droopies
//
//  Générateur de portail web autonome Droopy v5.
//  Chiffrement AES-GCM 256 bits côté client avec WebCrypto (PBKDF2 SHA-256 10 000 itérations).
//

import Foundation
import CryptoKit
import CommonCrypto

public enum PortalGeneratorError: LocalizedError, Sendable {
    case noSourceFolder
    case noStudents
    case encryptionFailed
    case invalidIcon
    case writeFailed(String)

    public var errorDescription: String? {
        switch self {
        case .noSourceFolder:
            return "Dossier source non configuré."
        case .noStudents:
            return "Aucun élève à exporter dans le portail."
        case .encryptionFailed:
            return "Échec lors du chiffrement cryptographique des données élèves."
        case .invalidIcon:
            return "Impossible de charger l'icône du portail."
        case .writeFailed(let msg):
            return "Échec de l'écriture sur le Cloud : \(msg)"
        }
    }
}

public struct PortalGenerationResult: Sendable {
    public let path: String
    public let studentCount: Int
    public let portalTitle: String
    public let portalTheme: String
    public let generatedAt: String

    public init(
        path: String,
        studentCount: Int,
        portalTitle: String,
        portalTheme: String,
        generatedAt: String
    ) {
        self.path = path
        self.studentCount = studentCount
        self.portalTitle = portalTitle
        self.portalTheme = portalTheme
        self.generatedAt = generatedAt
    }
}

public final class PortalGeneratorService: Sendable {
    public static let shared = PortalGeneratorService()

    private init() {}

    public struct EncryptedStudentEntry: Codable, Sendable {
        public let h: String
        public let s: String
        public let iv: String
        public let c: String

        public init(h: String, s: String, iv: String, c: String) {
            self.h = h
            self.s = s
            self.iv = iv
            self.c = c
        }
    }

    public struct StudentPayload: Codable, Sendable {
        public let name: String
        public let classe: String
        public let gender: String
        public let dropbox: String

        public init(name: String, classe: String, gender: String, dropbox: String) {
            self.name = name
            self.classe = classe
            self.gender = gender
            self.dropbox = dropbox
        }
    }

    // MARK: - Chiffrement d'un élève (PBKDF2 10 000 itérations + AES-GCM 256)
    public static func encryptStudentData(password: String, payload: StudentPayload) throws -> (s: String, iv: String, c: String) {
        var salt = Data(count: 16)
        let saltRes = salt.withUnsafeMutableBytes { SecRandomCopyBytes(kSecRandomDefault, 16, $0.baseAddress!) }
        guard saltRes == errSecSuccess else { throw PortalGeneratorError.encryptionFailed }

        var iv = Data(count: 12)
        let ivRes = iv.withUnsafeMutableBytes { SecRandomCopyBytes(kSecRandomDefault, 12, $0.baseAddress!) }
        guard ivRes == errSecSuccess else { throw PortalGeneratorError.encryptionFailed }

        var derivedKey = Data(count: 32)
        let pwdData = Data(password.utf8)
        let pbkdfStatus = derivedKey.withUnsafeMutableBytes { keyPtr in
            salt.withUnsafeBytes { saltPtr in
                pwdData.withUnsafeBytes { pwdPtr in
                    CCKeyDerivationPBKDF(
                        CCPBKDFAlgorithm(kCCPBKDF2),
                        pwdPtr.baseAddress?.assumingMemoryBound(to: Int8.self),
                        pwdData.count,
                        saltPtr.baseAddress?.assumingMemoryBound(to: UInt8.self),
                        salt.count,
                        CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA256),
                        10000,
                        keyPtr.baseAddress?.assumingMemoryBound(to: UInt8.self),
                        32
                    )
                }
            }
        }
        guard pbkdfStatus == kCCSuccess else { throw PortalGeneratorError.encryptionFailed }

        let symKey = SymmetricKey(data: derivedKey)
        let nonce = try AES.GCM.Nonce(data: iv)
        let payloadData = try JSONEncoder().encode(payload)
        let sealed = try AES.GCM.seal(payloadData, using: symKey, nonce: nonce)
        let cData = sealed.ciphertext + sealed.tag

        let sHex = salt.map { String(format: "%02x", $0) }.joined()
        let ivHex = iv.map { String(format: "%02x", $0) }.joined()
        let cHex = cData.map { String(format: "%02x", $0) }.joined()

        return (s: sHex, iv: ivHex, c: cHex)
    }

    // MARK: - Génération complète du portail
    public func generatePortal(
        provider: any StorageProvider,
        students: [Student],
        title: String,
        subtitle: String,
        theme: String,
        useCustomIcon: Bool = true,
        onProgress: (@Sendable (Double, String) -> Void)? = nil
    ) async throws -> PortalGenerationResult {
        guard !students.isEmpty else {
            throw PortalGeneratorError.noStudents
        }

        let cleanTitle = title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Portail Élèves" : title.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanSubtitle = subtitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Évaluations & Documents de la classe" : subtitle.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanTheme = (theme == "azur") ? "azur" : "emeraude"

        let themeColors: (theme: String, bg: String) = (cleanTheme == "azur")
            ? ("#38bdf8", "#020617")
            : ("#10b981", "#020617")

        onProgress?(0.05, "Préparation de l'arborescence Exports/Portail-Web...")

        let outDir = "Exports/Portail-Web"
        try await provider.createDirectory(at: outDir)
        try await provider.createDirectory(at: "\(outDir)/images")
        try await provider.createDirectory(at: "\(outDir)/images/icons")
        try await provider.createDirectory(at: "\(outDir)/scripts")
        try await provider.createDirectory(at: "\(outDir)/css")

        onProgress?(0.15, "Vérification du dossier Documents partagé...")
        var documentsUrl = ""
        do {
            documentsUrl = try await provider.createSharedLink(for: "Documents")
        } catch {
            print("[PortalGenerator] Note: impossible de récupérer le lien Documents : \(error)")
        }

        onProgress?(0.25, "Préparation des icônes de l'application (PWA)...")
        var iconData: Data = PortalDefaultIcon.pngData ?? Data()
        if useCustomIcon {
            if let customIcon = try? await provider.readData(at: "Configuration/Icone Portail.png"), !customIcon.isEmpty {
                iconData = customIcon
            } else if let legacyIcon0 = try? await provider.readData(at: "Configuration/Portal-Icone.png"), !legacyIcon0.isEmpty {
                iconData = legacyIcon0
                try? await provider.writeData(legacyIcon0, to: "Configuration/Icone Portail.png")
                try? await provider.deleteItem(at: "Configuration/Portal-Icone.png")
            } else if let legacyIcon1 = try? await provider.readData(at: "Configuration/Icon-portail.png"), !legacyIcon1.isEmpty {
                iconData = legacyIcon1
                try? await provider.writeData(legacyIcon1, to: "Configuration/Icone Portail.png")
                try? await provider.deleteItem(at: "Configuration/Icon-portail.png")
            } else if let legacyIcon2 = try? await provider.readData(at: "Icon-portail.png"), !legacyIcon2.isEmpty {
                iconData = legacyIcon2
                try? await provider.writeData(legacyIcon2, to: "Configuration/Icone Portail.png")
                try? await provider.deleteItem(at: "Icon-portail.png")
            }
        }

        try await provider.writeData(iconData, to: "\(outDir)/images/icons/icon-192x192.png")
        try await provider.writeData(iconData, to: "\(outDir)/images/icons/icon-512x512.png")

        onProgress?(0.35, "Chiffrement AES-GCM de la base élèves...")
        var encryptedStudents: [EncryptedStudentEntry] = []
        let total = Double(students.count)

        for (idx, s) in students.enumerated() {
            let normLogin = s.login.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            guard !normLogin.isEmpty else { continue }
            let normPwd = s.password.trimmingCharacters(in: .whitespacesAndNewlines)

            let digest = SHA256.hash(data: Data(normLogin.utf8))
            let loginHash = digest.map { String(format: "%02x", $0) }.joined()

            let payload = StudentPayload(
                name: s.name,
                classe: s.classe,
                gender: s.gender.rawValue,
                dropbox: s.urlDropbox
            )

            let enc = try Self.encryptStudentData(password: normPwd, payload: payload)
            encryptedStudents.append(EncryptedStudentEntry(
                h: loginHash,
                s: enc.s,
                iv: enc.iv,
                c: enc.c
            ))

            let prog = 0.35 + (0.35 * (Double(idx + 1) / total))
            onProgress?(prog, "Chiffrement AES-GCM (\(idx + 1)/\(students.count))...")
        }

        onProgress?(0.72, "Génération des fichiers web autonomes...")

        // 1. scripts/data.js
        let dataJs = Self.generateDataJs(
            portalTitle: cleanTitle,
            portalSubtitle: cleanSubtitle,
            documentsUrl: documentsUrl,
            students: encryptedStudents
        )
        try await provider.writeData(Data(dataJs.utf8), to: "\(outDir)/scripts/data.js")

        // 2. manifest.json
        let manifest = Self.generateManifest(
            portalTitle: cleanTitle,
            portalSubtitle: cleanSubtitle,
            colors: themeColors
        )
        try await provider.writeData(Data(manifest.utf8), to: "\(outDir)/manifest.json")

        // 3. sw.js
        let sw = Self.generateSw()
        try await provider.writeData(Data(sw.utf8), to: "\(outDir)/sw.js")

        // 4. css/style.css
        let css = Self.generateCss(theme: cleanTheme)
        try await provider.writeData(Data(css.utf8), to: "\(outDir)/css/style.css")

        // 5. scripts/app.js
        let appJs = Self.generateAppJs()
        try await provider.writeData(Data(appJs.utf8), to: "\(outDir)/scripts/app.js")

        // 6. index.html
        let html = Self.generateHtml(
            title: cleanTitle,
            subtitle: cleanSubtitle,
            colors: themeColors
        )
        try await provider.writeData(Data(html.utf8), to: "\(outDir)/index.html")

        // 7. README.txt
        let readme = Self.generateReadme()
        try await provider.writeData(Data(readme.utf8), to: "\(outDir)/README.txt")

        // 8. version.json
        let isoFormatter = ISO8601DateFormatter()
        let nowIso = isoFormatter.string(from: Date())

        let studentHashString = students
            .sorted(by: { $0.id < $1.id })
            .map { "\($0.login.lowercased()):\($0.password):\($0.name):\($0.classe)" }
            .joined(separator: "|")
        let studentsDigest = SHA256.hash(data: Data(studentHashString.utf8)).map { String(format: "%02x", $0) }.joined()

        let versionPayload: [String: Any] = [
            "updatedAt": nowIso,
            "studentCount": encryptedStudents.count,
            "generator": "Droopy v5",
            "theme": cleanTheme,
            "title": cleanTitle,
            "subtitle": cleanSubtitle,
            "iconMode": useCustomIcon ? "custom" : "default",
            "studentsDigest": studentsDigest
        ]
        let versionData = try JSONSerialization.data(withJSONObject: versionPayload, options: [.prettyPrinted, .sortedKeys])
        try await provider.writeData(versionData, to: "\(outDir)/version.json")

        onProgress?(1.0, "Portail Web généré avec succès !")

        return PortalGenerationResult(
            path: outDir,
            studentCount: encryptedStudents.count,
            portalTitle: cleanTitle,
            portalTheme: cleanTheme,
            generatedAt: nowIso
        )
    }

    // MARK: - Générateur scripts/data.js
    public static func generateDataJs(
        portalTitle: String,
        portalSubtitle: String,
        documentsUrl: String,
        students: [EncryptedStudentEntry]
    ) -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let studentsJson = (try? String(data: encoder.encode(students), encoding: .utf8)) ?? "[]"

        let titleJson = (try? String(data: JSONEncoder().encode(portalTitle), encoding: .utf8)) ?? "\"\""
        let subtitleJson = (try? String(data: JSONEncoder().encode(portalSubtitle), encoding: .utf8)) ?? "\"\""
        let docUrlJson = (try? String(data: JSONEncoder().encode(documentsUrl), encoding: .utf8)) ?? "\"\""

        return """
// Base élèves chiffrée de Droopy v5 - Chiffrement AES-GCM 256 bits
// Aucun nom ni lien Dropbox n'est visible en clair sans le mot de passe de l'élève.
const PortalData = {
  portalTitle: \(titleJson),
  portalSubtitle: \(subtitleJson),
  documentsUrl: \(docUrlJson),
  students: \(studentsJson)
};
"""
    }

    // MARK: - Générateur manifest.json
    public static func generateManifest(
        portalTitle: String,
        portalSubtitle: String,
        colors: (theme: String, bg: String)
    ) -> String {
        let manifestObj: [String: Any] = [
            "name": portalTitle,
            "short_name": portalTitle,
            "description": portalSubtitle,
            "icons": [
                [
                    "src": "images/icons/icon-192x192.png",
                    "sizes": "192x192",
                    "type": "image/png"
                ],
                [
                    "src": "images/icons/icon-512x512.png",
                    "sizes": "512x512",
                    "type": "image/png"
                ]
            ],
            "start_url": "./index.html",
            "display": "standalone",
            "background_color": colors.bg,
            "theme_color": colors.theme
        ]
        if let data = try? JSONSerialization.data(withJSONObject: manifestObj, options: [.prettyPrinted, .sortedKeys]),
           let str = String(data: data, encoding: .utf8) {
            return str
        }
        return "{}"
    }

    // MARK: - Générateur sw.js
    public static func generateSw() -> String {
        return ##"""
// Service Worker minimal PWA
const CACHE_NAME = 'droopy-portal-v5';
self.addEventListener('install', (e) => {
  self.skipWaiting();
});
self.addEventListener('activate', (e) => {
  e.waitUntil(clients.claim());
});
self.addEventListener('fetch', (e) => {
  e.respondWith(
    fetch(e.request).catch(() => caches.match(e.request))
  );
});

"""##
    }

    // MARK: - Générateur README.txt
    public static func generateReadme() -> String {
        return ##"""
=======================================================
PORTAIL ÉLÈVES AUTONOME - DROOPY v5
=======================================================

Ce dossier contient votre portail web de connexion complet, sécurisé et prêt à l'emploi.
Il s'agit d'un site web statique qui peut être hébergé sur n'importe quel serveur ou service web :

OPTIONS D'HÉBERGEMENT POSSIBLES :

1. HÉBERGEURS STATIQUES GRATUITS (EN 1 GLISSER-DÉPOSER) :
   - Netlify Drop : Rendez-vous sur https://app.netlify.com/drop et glissez-déposez TOUT ce dossier "Portail-Web".
   - Vercel : Importez le dossier via le tableau de bord Vercel.
   - Cloudflare Pages : Glissez-déposez l'archive ou connectez votre dépôt.

2. VOTRE PROPRE NOM DE DOMAINE / SERVEUR WEB (OVH, Infomaniak, Hostinger...) :
   - Transférez simplement par FTP le contenu de ce dossier "Portail-Web" dans le répertoire public de votre serveur (ex: /public_html ou /www).
   - Vos élèves accèderont directement à votre domaine (ex: https://espace-eleves.fr).

SÉCURITÉ ET CONFIDENTIALITÉ :
- Les données des élèves (noms, classes, URLs Dropbox) sont stockées dans scripts/data.js de manière 100% chiffrée (AES-GCM 256 bits).
- Aucun élève ne peut voir ou deviner les liens de ses camarades en inspectant le code source.

APPLICATION SMARTPHONE (PWA) :
- Les élèves et parents peuvent installer ce portail directement sur leur écran d'accueil Android ou iPhone via le bouton dédié sur la page.

"""##
    }

    // MARK: - Générateur css/style.css
    public static func generateCss(theme: String) -> String {
        let isAzur = (theme == "azur")
        let vars = isAzur ? ##"""
  --theme-body-bg: radial-gradient(ellipse at 50% 20%, #0c4a6e 0%, #172554 45%, #020617 100%);
  --theme-glow: rgba(56, 189, 248, 0.30);
  --theme-card-bg: rgba(255, 255, 255, 0.08);
  --theme-card-border: rgba(255, 255, 255, 0.16);
  --theme-card-shadow: 0 25px 60px -10px rgba(0, 0, 0, 0.65), 0 0 40px rgba(56, 189, 248, 0.15);
  --theme-primary: #38bdf8;
  --theme-primary-hover: #7dd3fc;
  --theme-btn-text: #082f49;
  --theme-btn-shadow: 0 8px 24px rgba(56, 189, 248, 0.35);
  --theme-input-bg: rgba(255, 255, 255, 0.07);
  --theme-input-border: rgba(255, 255, 255, 0.16);
  --theme-input-focus: #38bdf8;
  --theme-particle-color: #bae6fd;
  --theme-avatar-bg: rgba(56, 189, 248, 0.2);
  --theme-avatar-border: rgba(125, 211, 252, 0.4);
  --theme-badge-bg: rgba(56, 189, 248, 0.2);
  --theme-badge-text: #7dd3fc;
  --theme-badge-border: rgba(56, 189, 248, 0.35);
"""## : ##"""
  --theme-body-bg: radial-gradient(ellipse at 50% 20%, #064e3b 0%, #022c22 45%, #020617 100%);
  --theme-glow: rgba(16, 185, 129, 0.28);
  --theme-card-bg: rgba(255, 255, 255, 0.08);
  --theme-card-border: rgba(255, 255, 255, 0.16);
  --theme-card-shadow: 0 25px 60px -10px rgba(0, 0, 0, 0.65), 0 0 40px rgba(16, 185, 129, 0.12);
  --theme-primary: #10b981;
  --theme-primary-hover: #34d399;
  --theme-btn-text: #022c22;
  --theme-btn-shadow: 0 8px 24px rgba(16, 185, 129, 0.35);
  --theme-input-bg: rgba(255, 255, 255, 0.07);
  --theme-input-border: rgba(255, 255, 255, 0.16);
  --theme-input-focus: #10b981;
  --theme-particle-color: #6ee7b7;
  --theme-avatar-bg: rgba(16, 185, 129, 0.2);
  --theme-avatar-border: rgba(52, 211, 153, 0.35);
  --theme-badge-bg: rgba(16, 185, 129, 0.2);
  --theme-badge-text: #6ee7b7;
  --theme-badge-border: rgba(16, 185, 129, 0.35);
"""##
        let body = ##"""
* {
  box-sizing: border-box;
  margin: 0;
  padding: 0;
  font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, Helvetica, Arial, sans-serif;
}
:root {
  ${vars}
}
html, body {
  min-height: 100%;
  width: 100%;
}
body {
  background: var(--theme-body-bg);
  color: #f8fafc;
  display: flex;
  flex-direction: column;
  align-items: center;
  justify-content: center;
  padding: 24px 16px;
  position: relative;
  overflow-x: hidden;
  -webkit-font-smoothing: antialiased;
}
.ambient-glow {
  position: absolute;
  width: 480px;
  height: 480px;
  border-radius: 50%;
  background: var(--theme-glow);
  filter: blur(80px);
  pointer-events: none;
  z-index: 1;
}
.particles-layer {
  position: fixed;
  inset: 0;
  pointer-events: none;
  overflow: hidden;
  z-index: 2;
}
.school-particle {
  position: absolute;
  bottom: -50px;
  animation: floatUpward linear infinite;
  will-change: transform, opacity;
  color: var(--theme-particle-color);
}
@keyframes floatUpward {
  0% { transform: translateY(110vh) rotate(0deg); opacity: 0; }
  12% { opacity: var(--particle-opacity, 0.2); }
  88% { opacity: var(--particle-opacity, 0.2); }
  100% { transform: translateY(-20vh) rotate(360deg); opacity: 0; }
}
.portal-container {
  width: 100%;
  max-width: 410px;
  margin: auto;
  position: relative;
  z-index: 10;
  text-align: center;
}
.avatar-wrapper {
  margin-bottom: 14px;
  display: inline-block;
  position: relative;
}
.avatar-squircle {
  width: 98px;
  height: 98px;
  border-radius: 26px;
  background: var(--theme-avatar-bg);
  backdrop-filter: blur(16px);
  -webkit-backdrop-filter: blur(16px);
  border: 1.5px solid var(--theme-avatar-border);
  box-shadow: 0 12px 30px rgba(0, 0, 0, 0.35);
  display: flex;
  align-items: center;
  justify-content: center;
  padding: 8px;
  animation: gentleFloat 4s ease-in-out infinite;
  margin: 0 auto;
}
.avatar-img {
  width: 100%;
  height: 100%;
  object-fit: contain;
  border-radius: 18px;
  display: block;
}
.avatar-shadow {
  width: 76px;
  height: 10px;
  background: rgba(0, 0, 0, 0.35);
  border-radius: 50%;
  margin: 8px auto 0;
  filter: blur(4px);
  animation: shadowPulse 4s ease-in-out infinite;
}
@keyframes gentleFloat {
  0%, 100% { transform: translateY(0px); }
  50% { transform: translateY(-8px); }
}
@keyframes shadowPulse {
  0%, 100% { transform: scale(1); opacity: 0.35; }
  50% { transform: scale(0.85); opacity: 0.16; }
}
.portal-title {
  font-size: 26px;
  font-weight: 800;
  letter-spacing: -0.5px;
  margin-bottom: 3px;
  text-shadow: 0 2px 10px rgba(0, 0, 0, 0.4);
}
.portal-subtitle {
  font-size: 13px;
  color: rgba(255, 255, 255, 0.82);
  margin-bottom: 22px;
  font-weight: 500;
  text-shadow: 0 1px 4px rgba(0, 0, 0, 0.3);
}
.card {
  background: var(--theme-card-bg);
  backdrop-filter: blur(20px);
  -webkit-backdrop-filter: blur(20px);
  border: 1px solid var(--theme-card-border);
  border-radius: 26px;
  padding: 28px 24px;
  box-shadow: var(--theme-card-shadow);
  color: #ffffff;
  text-align: left;
}
.card-header {
  display: flex;
  align-items: center;
  justify-content: space-between;
  margin-bottom: 20px;
  padding-bottom: 14px;
  border-bottom: 1px solid rgba(255, 255, 255, 0.1);
}
.card-header-badge {
  font-size: 10px;
  font-weight: 800;
  text-transform: uppercase;
  letter-spacing: 0.5px;
  color: var(--theme-badge-text);
  display: block;
  margin-bottom: 2px;
}
.card-header h3 {
  font-size: 17px;
  font-weight: 800;
  color: #ffffff;
}
.card-lock-tag {
  background: var(--theme-badge-bg);
  color: var(--theme-badge-text);
  border: 1px solid var(--theme-badge-border);
  font-size: 11px;
  font-weight: 700;
  padding: 3px 9px;
  border-radius: 20px;
  display: inline-flex;
  align-items: center;
  gap: 5px;
}
.form-group {
  margin-bottom: 16px;
}
.form-label {
  display: flex;
  align-items: center;
  gap: 6px;
  font-size: 11px;
  font-weight: 700;
  color: rgba(255, 255, 255, 0.85);
  text-transform: uppercase;
  letter-spacing: 0.5px;
  margin-bottom: 6px;
}
.form-label svg {
  width: 14px;
  height: 14px;
  color: var(--theme-primary);
}
.input-wrapper {
  position: relative;
  display: flex;
  align-items: center;
}
.form-input {
  width: 100%;
  padding: 12px 14px;
  border-radius: 13px;
  border: 1px solid var(--theme-input-border);
  background: var(--theme-input-bg);
  color: #ffffff;
  font-size: 14px;
  font-weight: 500;
  outline: none;
  transition: all 0.2s ease;
}
.form-input::placeholder {
  color: rgba(255, 255, 255, 0.35);
  font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, Helvetica, Arial, sans-serif;
  letter-spacing: normal;
  font-size: 14px;
}
.form-input.pwd-field {
  padding-right: 44px;
  font-family: monospace;
  font-size: 15px;
  letter-spacing: 1px;
}
.form-input.pwd-field::placeholder {
  font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, Helvetica, Arial, sans-serif;
  letter-spacing: normal;
  font-size: 14px;
}
.form-input:focus {
  border-color: var(--theme-input-focus);
  background: rgba(255, 255, 255, 0.12);
  box-shadow: 0 0 0 3px rgba(255, 255, 255, 0.1);
}
.input-hint {
  font-size: 11px;
  color: rgba(255, 255, 255, 0.5);
  margin-top: 5px;
  padding-left: 2px;
}
.btn-eye-toggle {
  position: absolute;
  right: 6px;
  top: 50%;
  transform: translateY(-50%);
  width: 34px;
  height: 34px;
  border-radius: 8px;
  border: none;
  background: transparent;
  color: rgba(255, 255, 255, 0.6);
  cursor: pointer;
  display: flex;
  align-items: center;
  justify-content: center;
  transition: all 0.15s ease;
}
.btn-eye-toggle:hover {
  background: rgba(255, 255, 255, 0.15);
  color: #ffffff;
}
.btn-eye-toggle svg {
  width: 18px;
  height: 18px;
  stroke: currentColor;
}
.btn-submit {
  width: 100%;
  padding: 14px;
  border-radius: 14px;
  border: none;
  background: var(--theme-primary);
  color: var(--theme-btn-text);
  font-size: 13px;
  font-weight: 800;
  text-transform: uppercase;
  letter-spacing: 0.5px;
  cursor: pointer;
  display: flex;
  align-items: center;
  justify-content: center;
  gap: 8px;
  box-shadow: var(--theme-btn-shadow);
  transition: all 0.15s ease;
  margin-top: 8px;
}
.btn-submit:hover {
  background: var(--theme-primary-hover);
  transform: translateY(-1px);
  box-shadow: 0 10px 28px rgba(0, 0, 0, 0.4);
}
.btn-submit:active {
  transform: translateY(0);
}
.btn-submit svg {
  width: 16px;
  height: 16px;
}
.error-box {
  display: none;
  margin-top: 14px;
  padding: 10px;
  border-radius: 12px;
  background: rgba(239, 68, 68, 0.15);
  border: 1px solid rgba(239, 68, 68, 0.35);
  color: #fca5a5;
  font-size: 12px;
  text-align: center;
  font-weight: 600;
}
.dash-header {
  display: flex;
  align-items: center;
  justify-content: space-between;
  margin-bottom: 20px;
  padding-bottom: 14px;
  border-bottom: 1px solid rgba(255, 255, 255, 0.1);
}
.dash-status-pill {
  display: inline-flex;
  align-items: center;
  gap: 6px;
  background: var(--theme-badge-bg);
  color: var(--theme-badge-text);
  font-size: 10px;
  font-weight: 800;
  text-transform: uppercase;
  padding: 3px 9px;
  border-radius: 12px;
  margin-bottom: 4px;
  border: 1px solid var(--theme-badge-border);
}
.dash-pulse-dot {
  width: 6px;
  height: 6px;
  background: var(--theme-primary);
  border-radius: 50%;
  box-shadow: 0 0 0 2px rgba(255, 255, 255, 0.3);
}
.dash-student-name {
  font-size: 20px;
  font-weight: 800;
  color: #ffffff;
  line-height: 1.2;
}
.dash-student-class {
  font-size: 12px;
  color: rgba(255, 255, 255, 0.7);
  margin-top: 3px;
}
.dash-avatar-badge {
  width: 46px;
  height: 46px;
  border-radius: 15px;
  background: var(--theme-primary);
  color: var(--theme-btn-text);
  font-size: 16px;
  font-weight: 900;
  display: flex;
  align-items: center;
  justify-content: center;
  box-shadow: 0 6px 16px rgba(0, 0, 0, 0.3);
}
.dash-actions {
  display: flex;
  flex-direction: column;
  gap: 12px;
  margin-bottom: 20px;
}
.btn-dash-dropbox {
  display: flex;
  align-items: center;
  justify-content: space-between;
  padding: 16px;
  border-radius: 18px;
  background: var(--theme-primary);
  color: var(--theme-btn-text);
  text-decoration: none;
  box-shadow: var(--theme-btn-shadow);
  transition: all 0.2s ease;
}
.btn-dash-dropbox:hover {
  background: var(--theme-primary-hover);
  transform: translateY(-2px);
  box-shadow: 0 10px 24px rgba(0, 0, 0, 0.4);
}
.btn-dash-docs {
  display: flex;
  align-items: center;
  justify-content: space-between;
  padding: 16px;
  border-radius: 18px;
  background: rgba(255, 255, 255, 0.08);
  border: 1px solid rgba(255, 255, 255, 0.18);
  color: #ffffff;
  text-decoration: none;
  transition: all 0.2s ease;
}
.btn-dash-docs:hover {
  background: rgba(255, 255, 255, 0.14);
  border-color: var(--theme-primary);
  transform: translateY(-2px);
}
.action-left {
  display: flex;
  align-items: center;
  gap: 12px;
}
.action-icon-box {
  width: 42px;
  height: 42px;
  border-radius: 13px;
  display: flex;
  align-items: center;
  justify-content: center;
  font-size: 22px;
}
.action-icon-box.green {
  background: rgba(0, 0, 0, 0.12);
}
.action-icon-box.white {
  background: rgba(255, 255, 255, 0.12);
  border: 1px solid rgba(255, 255, 255, 0.2);
}
.action-texts h4 {
  font-size: 14px;
  font-weight: 800;
  line-height: 1.2;
}
.action-texts p {
  font-size: 11px;
  opacity: 0.85;
  margin-top: 2px;
}
.cloud-info-box {
  background: rgba(255, 255, 255, 0.05);
  border: 1px solid rgba(255, 255, 255, 0.12);
  border-radius: 16px;
  padding: 14px;
  margin-bottom: 20px;
  display: flex;
  align-items: flex-start;
  gap: 10px;
}
.cloud-info-box svg {
  width: 18px;
  height: 18px;
  color: var(--theme-primary);
  flex-shrink: 0;
  margin-top: 1px;
}
.cloud-info-box p {
  font-size: 11px;
  color: rgba(255, 255, 255, 0.75);
  line-height: 1.45;
}
.dash-footer {
  display: flex;
  align-items: center;
  justify-content: space-between;
  padding-top: 14px;
  border-top: 1px solid rgba(255, 255, 255, 0.1);
  font-size: 11px;
  color: rgba(255, 255, 255, 0.5);
}
.btn-logout {
  background: transparent;
  border: none;
  color: #f87171;
  font-size: 12px;
  font-weight: 700;
  cursor: pointer;
  display: inline-flex;
  align-items: center;
  gap: 4px;
  padding: 4px 8px;
  border-radius: 6px;
  transition: background 0.15s;
}
.btn-logout:hover {
  background: rgba(239, 68, 68, 0.15);
}
.card-footer-pwa {
  margin-top: 18px;
  padding-top: 14px;
  border-top: 1px solid rgba(255, 255, 255, 0.1);
  display: flex;
  align-items: center;
  justify-content: space-between;
  font-size: 11px;
  color: rgba(255, 255, 255, 0.6);
}
.pwa-badge {
  display: inline-flex;
  align-items: center;
  gap: 6px;
}
.pwa-dot {
  width: 7px;
  height: 7px;
  border-radius: 50%;
  background: var(--theme-primary);
}
.btn-pwa-install {
  background: transparent;
  border: none;
  color: var(--theme-primary);
  font-weight: 700;
  cursor: pointer;
  display: inline-flex;
  align-items: center;
  gap: 4px;
}
.btn-pwa-install:hover {
  text-decoration: underline;
}
.modal-overlay {
  display: none;
  position: fixed;
  inset: 0;
  background: rgba(0, 0, 0, 0.75);
  backdrop-filter: blur(8px);
  z-index: 100;
  align-items: center;
  justify-content: center;
  padding: 16px;
}
.modal-box {
  background: #0f172a;
  color: #f8fafc;
  border: 1px solid rgba(255, 255, 255, 0.15);
  border-radius: 24px;
  padding: 24px;
  max-width: 380px;
  width: 100%;
  box-shadow: 0 25px 50px rgba(0, 0, 0, 0.5);
  text-align: left;
}
.modal-title {
  font-size: 16px;
  font-weight: 800;
  margin-bottom: 12px;
  display: flex;
  align-items: center;
  justify-content: space-between;
}
.modal-step {
  padding: 12px;
  background: rgba(255, 255, 255, 0.06);
  border: 1px solid rgba(255, 255, 255, 0.1);
  border-radius: 12px;
  margin-bottom: 10px;
  font-size: 12px;
  line-height: 1.45;
}

"""##
        return body.replacingOccurrences(of: "${vars}", with: vars)
    }

    // MARK: - Générateur scripts/app.js
    public static func generateAppJs() -> String {
        return ##"""
// Logique d'authentification et d'installation PWA - Droopy v5
(function() {
  'use strict';

  // Sélecteurs
  const formLogin = document.getElementById('formLogin');
  const dashStudent = document.getElementById('dashStudent');
  const inputLogin = document.getElementById('inputLogin');
  const inputPassword = document.getElementById('inputPassword');
  const btnLogin = document.getElementById('btnLogin');
  const btnTogglePwd = document.getElementById('btnTogglePwd');
  const eyeSvgOpen = document.getElementById('eyeSvgOpen');
  const eyeSvgOff = document.getElementById('eyeSvgOff');
  const errorBox = document.getElementById('errorBox');
  const studentNameEl = document.getElementById('studentName');
  const studentClassEl = document.getElementById('studentClass');
  const studentInitialsEl = document.getElementById('studentInitials');
  const linkDropbox = document.getElementById('linkDropbox');
  const linkDocs = document.getElementById('linkDocs');
  const btnLogout = document.getElementById('btnLogout');
  const btnPwa = document.getElementById('btnPwa');
  const modalPwa = document.getElementById('modalPwa');
  const btnCloseModal = document.getElementById('btnCloseModal');

  // Afficher / Masquer mot de passe avec l'icône oeil vectoriel classique
  if (btnTogglePwd) {
    btnTogglePwd.addEventListener('click', () => {
      const isPwd = inputPassword.type === 'password';
      inputPassword.type = isPwd ? 'text' : 'password';
      if (eyeSvgOpen && eyeSvgOff) {
        eyeSvgOpen.style.display = isPwd ? 'none' : 'block';
        eyeSvgOff.style.display = isPwd ? 'block' : 'none';
      }
    });
  }

  // Déchiffrement AES-GCM avec Web Crypto API
  async function decryptPayload(password, saltHex, ivHex, ciphertextHex) {
    const enc = new TextEncoder();
    const dec = new TextDecoder();
    const fromHex = (hex) => new Uint8Array(hex.match(/.{1,2}/g).map((b) => parseInt(b, 16)));

    const salt = fromHex(saltHex);
    const iv = fromHex(ivHex);
    const ciphertext = fromHex(ciphertextHex);

    const keyMaterial = await window.crypto.subtle.importKey(
      'raw',
      enc.encode(password),
      { name: 'PBKDF2' },
      false,
      ['deriveKey']
    );

    const derivedKey = await window.crypto.subtle.deriveKey(
      {
        name: 'PBKDF2',
        salt,
        iterations: 10000,
        hash: 'SHA-256',
      },
      keyMaterial,
      { name: 'AES-GCM', length: 256 },
      false,
      ['decrypt']
    );

    const decrypted = await window.crypto.subtle.decrypt(
      { name: 'AES-GCM', iv },
      derivedKey,
      ciphertext
    );

    return JSON.parse(dec.decode(decrypted));
  }

  // SHA256 avec Web Crypto API
  async function sha256(text) {
    const enc = new TextEncoder();
    const data = enc.encode(text);
    const hashBuf = await window.crypto.subtle.digest('SHA-256', data);
    return Array.from(new Uint8Array(hashBuf)).map((b) => b.toString(16).padStart(2, '0')).join('');
  }

  // Connexion de l'élève
  async function handleLogin() {
    errorBox.style.display = 'none';
    const login = inputLogin.value.trim().toLowerCase();
    const password = inputPassword.value.trim();

    if (!login || !password) {
      errorBox.innerText = 'Veuillez renseigner votre identifiant et votre mot de passe.';
      errorBox.style.display = 'block';
      return;
    }

    try {
      btnLogin.disabled = true;
      btnLogin.innerHTML = '<span>Déchiffrement AES...</span>';

      const hashedLogin = await sha256(login);
      const studentEntry = (PortalData.students || []).find((s) => s.h === hashedLogin);

      if (!studentEntry) {
        throw new Error('Identifiant ou mot de passe incorrect.');
      }

      // Tentative de déchiffrement avec le mot de passe fourni
      const student = await decryptPayload(password, studentEntry.s, studentEntry.iv, studentEntry.c);

      // Succès : affichage de l'espace élève
      studentNameEl.innerText = student.name;
      studentClassEl.innerText = student.classe ? 'Classe : ' + student.classe : '';

      // Initiales élève
      if (studentInitialsEl && student.name) {
        const parts = student.name.trim().split(/\s+/);
        studentInitialsEl.innerText = parts.length >= 2 
          ? (parts[0][0] + parts[parts.length - 1][0]).toUpperCase()
          : student.name.substring(0, 2).toUpperCase();
      }

      if (student.dropbox) {
        linkDropbox.href = student.dropbox;
        linkDropbox.style.display = 'flex';
      } else {
        linkDropbox.style.display = 'none';
      }

      if (PortalData.documentsUrl) {
        linkDocs.href = PortalData.documentsUrl;
        linkDocs.style.display = 'flex';
      } else {
        linkDocs.style.display = 'none';
      }

      formLogin.style.display = 'none';
      dashStudent.style.display = 'block';
      if (btnPwa) btnPwa.style.display = 'none';
    } catch (err) {
      errorBox.innerText = 'Identifiant ou mot de passe incorrect.';
      errorBox.style.display = 'block';
    } finally {
      btnLogin.disabled = false;
      btnLogin.innerHTML = '<span>Ouvrir mon dossier</span> <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.5"><path d="M5 12h14M12 5l7 7-7 7"/></svg>';
    }
  }

  btnLogin.addEventListener('click', handleLogin);
  inputPassword.addEventListener('keyup', (e) => {
    if (e.key === 'Enter') handleLogin();
  });
  inputLogin.addEventListener('keyup', (e) => {
    if (e.key === 'Enter') inputPassword.focus();
  });

  btnLogout.addEventListener('click', () => {
    dashStudent.style.display = 'none';
    formLogin.style.display = 'block';
    inputPassword.value = '';
    if (btnPwa && !isStandalone) btnPwa.style.display = 'inline-flex';
  });

  // ==========================================
  // Gestion PWA (Android 1-clic & Guide iOS)
  // ==========================================
  let deferredPrompt = null;
  const isStandalone = window.matchMedia('(display-mode: standalone)').matches || window.navigator.standalone === true;

  if (isStandalone && btnPwa) {
    btnPwa.style.display = 'none';
  }

  window.addEventListener('beforeinstallprompt', (e) => {
    e.preventDefault();
    deferredPrompt = e;
    if (btnPwa && !isStandalone) {
      btnPwa.style.display = 'inline-flex';
    }
  });

  if (btnPwa) {
    btnPwa.addEventListener('click', () => {
      if (deferredPrompt) {
        deferredPrompt.prompt();
        deferredPrompt.userChoice.then((choice) => {
          if (choice.outcome === 'accepted') {
            btnPwa.style.display = 'none';
          }
          deferredPrompt = null;
        });
      } else {
        openPwaModal();
      }
    });
  }

  function openPwaModal() {
    const isIos = /iPhone|iPad|iPod/.test(navigator.userAgent);
    const isSafari = isIos && /Safari/.test(navigator.userAgent) && !/CriOS|FxiOS|OPiOS|Instagram|WhatsApp|FB/.test(navigator.userAgent);

    const iosContent = document.getElementById('modalIosContent');
    const genericContent = document.getElementById('modalGenericContent');

    if (isIos) {
      iosContent.style.display = 'block';
      genericContent.style.display = 'none';
      const webviewNotice = document.getElementById('iosWebviewNotice');
      if (webviewNotice) {
        webviewNotice.style.display = isSafari ? 'none' : 'block';
      }
    } else {
      iosContent.style.display = 'none';
      genericContent.style.display = 'block';
    }

    modalPwa.style.display = 'flex';
  }

  if (btnCloseModal) {
    btnCloseModal.addEventListener('click', () => {
      modalPwa.style.display = 'none';
    });
  }

  modalPwa.addEventListener('click', (e) => {
    if (e.target === modalPwa) modalPwa.style.display = 'none';
  });

  if ('serviceWorker' in navigator) {
    navigator.serviceWorker.register('./sw.js').catch(() => {});
  }
})();

"""##
    }

    // MARK: - Générateur index.html
    public static func generateHtml(
        title: String,
        subtitle: String,
        colors: (theme: String, bg: String)
    ) -> String {
        var html = ##"""
<!DOCTYPE html>
<html lang="fr">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0, maximum-scale=1.0, user-scalable=no">
  <title>${title}</title>

  <link rel="manifest" href="manifest.json">
  <meta name="theme-color" content="${colors.theme}">

  <!-- Support iOS Safari PWA -->
  <meta name="apple-mobile-web-app-capable" content="yes">
  <meta name="apple-mobile-web-app-status-bar-style" content="black-translucent">
  <meta name="apple-mobile-web-app-title" content="${title}">
  <link rel="apple-touch-icon" href="images/icons/icon-192x192.png">

  <link rel="stylesheet" href="css/style.css">
</head>
<body>

  <!-- Halo lumineux en arrière-plan -->
  <div class="ambient-glow"></div>

  <!-- Particules scolaires ascendantes (maths, chimie, géo, français, langues) -->
  
    <div class="particles-layer">
      <div class="school-particle" style="left: 6%; animation-duration: 22s; animation-delay: -2s; --particle-opacity: 0.22; transform: scale(1.1);"><svg width="24" height="24" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8"><polygon points="3,21 21,21 3,3"/><rect x="3" y="17" width="4" height="4" stroke-width="1.2"/></svg></div>
      <div class="school-particle" style="left: 18%; animation-duration: 28s; animation-delay: -11s; --particle-opacity: 0.18; transform: scale(0.9);"><svg width="24" height="24" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8"><path d="M4.5 3h15M6 3v16a2 2 0 0 0 2 2h8a2 2 0 0 0 2-2V3M6 14h12M9 8h2M9 11h3"/></svg></div>
      <div class="school-particle" style="left: 28%; animation-duration: 20s; animation-delay: -5s; --particle-opacity: 0.25; transform: scale(1.2);"><svg width="24" height="24" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8"><circle cx="12" cy="12" r="10"/><path d="M12 2a14.5 14.5 0 0 0 0 20M12 2a14.5 14.5 0 0 1 0 20M2 12h20"/></svg></div>
      <div class="school-particle" style="left: 42%; animation-duration: 25s; animation-delay: -17s; --particle-opacity: 0.20; transform: scale(1.0);"><svg width="24" height="24" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8"><path d="M2 3h6a4 4 0 0 1 4 4v14a3 3 0 0 0-3-3H2z"/><path d="M22 3h-6a4 4 0 0 0-4 4v14a3 3 0 0 1 3-3h7z"/></svg></div>
      <div class="school-particle" style="left: 55%; animation-duration: 21s; animation-delay: -8s; --particle-opacity: 0.24; transform: scale(1.15);"><svg width="24" height="24" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8"><circle cx="12" cy="12" r="2.5"/><ellipse cx="12" cy="12" rx="10" ry="4" transform="rotate(30 12 12)"/><ellipse cx="12" cy="12" rx="10" ry="4" transform="rotate(-30 12 12)"/></svg></div>
      <div class="school-particle" style="left: 68%; animation-duration: 30s; animation-delay: -14s; --particle-opacity: 0.16; transform: scale(0.85);"><svg width="22" height="22" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8"><path d="M4 15s1-1 4-1 5 2 8 2 4-1 4-1V3s-1 1-4 1-5-2-8-2-4 1-4 1z"/><line x1="4" y1="22" x2="4" y2="15"/></svg></div>
      <div class="school-particle" style="left: 80%; animation-duration: 24s; animation-delay: -3s; --particle-opacity: 0.22; transform: scale(1.05);"><svg width="22" height="22" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><path d="M4 7h16M8 7v12M16 7v10a2 2 0 0 0 2 2"/></svg></div>
      <div class="school-particle" style="left: 92%; animation-duration: 27s; animation-delay: -19s; --particle-opacity: 0.19; transform: scale(0.95);"><svg width="24" height="24" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8"><polygon points="3,21 21,21 3,3"/><rect x="3" y="17" width="4" height="4" stroke-width="1.2"/></svg></div>
      <div class="school-particle" style="left: 12%; animation-duration: 23s; animation-delay: -15s; --particle-opacity: 0.21; transform: scale(1.1);"><svg width="24" height="24" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8"><path d="M4.5 3h15M6 3v16a2 2 0 0 0 2 2h8a2 2 0 0 0 2-2V3M6 14h12M9 8h2M9 11h3"/></svg></div>
      <div class="school-particle" style="left: 35%; animation-duration: 29s; animation-delay: -7s; --particle-opacity: 0.17; transform: scale(0.9);"><svg width="24" height="24" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8"><circle cx="12" cy="12" r="10"/><path d="M12 2a14.5 14.5 0 0 0 0 20M12 2a14.5 14.5 0 0 1 0 20M2 12h20"/></svg></div>
      <div class="school-particle" style="left: 50%; animation-duration: 19s; animation-delay: -1s; --particle-opacity: 0.26; transform: scale(1.25);"><svg width="24" height="24" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8"><path d="M2 3h6a4 4 0 0 1 4 4v14a3 3 0 0 0-3-3H2z"/><path d="M22 3h-6a4 4 0 0 0-4 4v14a3 3 0 0 1 3-3h7z"/></svg></div>
      <div class="school-particle" style="left: 62%; animation-duration: 26s; animation-delay: -21s; --particle-opacity: 0.20; transform: scale(1.0);"><svg width="24" height="24" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8"><circle cx="12" cy="12" r="2.5"/><ellipse cx="12" cy="12" rx="10" ry="4" transform="rotate(30 12 12)"/><ellipse cx="12" cy="12" rx="10" ry="4" transform="rotate(-30 12 12)"/></svg></div>
      <div class="school-particle" style="left: 75%; animation-duration: 22s; animation-delay: -9s; --particle-opacity: 0.23; transform: scale(1.1);"><svg width="22" height="22" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8"><path d="M4 15s1-1 4-1 5 2 8 2 4-1 4-1V3s-1 1-4 1-5-2-8-2-4 1-4 1z"/><line x1="4" y1="22" x2="4" y2="15"/></svg></div>
      <div class="school-particle" style="left: 88%; animation-duration: 31s; animation-delay: -12s; --particle-opacity: 0.15; transform: scale(0.85);"><svg width="22" height="22" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><path d="M4 7h16M8 7v12M16 7v10a2 2 0 0 0 2 2"/></svg></div>
    </div>

  <div class="portal-container">
    <div class="avatar-wrapper">
      <div class="avatar-squircle">
        <img src="images/icons/icon-192x192.png" alt="Avatar" class="avatar-img">
      </div>
      <div class="avatar-shadow"></div>
    </div>

    <h1 class="portal-title">${title}</h1>
    <p class="portal-subtitle">${subtitle}</p>

    <!-- FORMULAIRE DE CONNEXION -->
    <div id="formLogin" class="card">
      <div class="card-header">
        <div>
          <span class="card-header-badge">Espace Réservé</span>
          <h3>Connexion à votre dossier</h3>
        </div>
        <span class="card-lock-tag">
          <svg width="12" height="12" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.5"><rect width="18" height="11" x="3" y="11" rx="2" ry="2"/><path d="M7 11V7a5 5 0 0 1 10 0v4"/></svg>
          AES 256
        </span>
      </div>

      <div class="form-group">
        <label class="form-label" for="inputLogin">
          <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.2"><path d="M19 21v-2a4 4 0 0 0-4-4H9a4 4 0 0 0-4 4v2"/><circle cx="12" cy="7" r="4"/></svg>
          Identifiant élève
        </label>
        <div class="input-wrapper">
          <input
            type="text"
            id="inputLogin"
            class="form-input"
            placeholder="Votre identifiant"
            autocapitalize="none"
            autocorrect="off"
            spellcheck="false"
          >
        </div>
        <div class="input-hint">Transmis par votre enseignant</div>
      </div>

      <div class="form-group">
        <label class="form-label" for="inputPassword">
          <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.2"><rect width="18" height="11" x="3" y="11" rx="2" ry="2"/><path d="M7 11V7a5 5 0 0 1 10 0v4"/></svg>
          Mot de passe
        </label>
        <div class="input-wrapper">
          <input
            type="password"
            id="inputPassword"
            class="form-input pwd-field"
            placeholder="Votre mot de passe"
            autocapitalize="none"
          >
          <button type="button" id="btnTogglePwd" class="btn-eye-toggle" title="Afficher / Masquer le mot de passe">
            <svg id="eyeSvgOpen" viewBox="0 0 24 24" fill="none" stroke-width="2" stroke-linecap="round" stroke-linejoin="round">
              <path d="M2.062 12.348a1 1 0 0 1 0-.696 10.75 10.75 0 0 1 19.876 0 1 1 0 .696 10.75 10.75 0 0 1-19.876 0Z"/>
              <circle cx="12" cy="12" r="3"/>
            </svg>
            <svg id="eyeSvgOff" style="display: none;" viewBox="0 0 24 24" fill="none" stroke-width="2" stroke-linecap="round" stroke-linejoin="round">
              <path d="M9.88 9.88a3 3 0 1 0 4.24 4.24"/>
              <path d="M10.73 5.08A10.43 10.43 0 0 1 12 5c7 0 10 7 10 7a13.16 13.16 0 0 1-1.67 2.68"/>
              <path d="M6.61 6.61A13.526 13.526 0 0 0 2 12s3 7 10 7a9.74 9.74 0 0 0 5.39-1.61"/>
              <line x1="2" y1="2" x2="22" y2="22"/>
            </svg>
          </button>
        </div>
        <div class="input-hint">Cliquez sur l'icône de l'œil pour vérifier votre saisie</div>
      </div>

      <button type="button" id="btnLogin" class="btn-submit">
        <span>Ouvrir mon dossier</span>
        <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.5"><path d="M5 12h14M12 5l7 7-7 7"/></svg>
      </button>

      <div id="errorBox" class="error-box"></div>

      <div class="card-footer-pwa">
        <span class="pwa-badge">
          <span class="pwa-dot"></span>
          Connexion directe & hors-ligne
        </span>
        <button type="button" id="btnPwa" class="btn-pwa-install">
          📲 Installer l'application
        </button>
      </div>
    </div>

    <!-- ESPACE ÉLÈVE (DÉVERROUILLÉ) -->
    <div id="dashStudent" class="card" style="display: none;">
      <div class="dash-header">
        <div>
          <div class="dash-status-pill">
            <span class="dash-pulse-dot"></span>
            Dossier sécurisé ouvert
          </div>
          <h2 id="studentName" class="dash-student-name"></h2>
          <p id="studentClass" class="dash-student-class"></p>
        </div>
        <div id="studentInitials" class="dash-avatar-badge"></div>
      </div>

      <div class="dash-actions">
        <a id="linkDropbox" href="#" target="_blank" class="btn-dash-dropbox">
          <div class="action-left">
            <div class="action-icon-box green">📂</div>
            <div class="action-texts">
              <h4>Mes copies & évaluations</h4>
              <p>Consulter toutes mes copies corrigées</p>
            </div>
          </div>
          <svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.5"><path d="M5 12h14M12 5l7 7-7 7"/></svg>
        </a>

        <a id="linkDocs" href="#" target="_blank" class="btn-dash-docs">
          <div class="action-left">
            <div class="action-icon-box white">📚</div>
            <div class="action-texts">
              <h4>Documents du cours</h4>
              <p>Polycopiés, fiches méthode & devoirs</p>
            </div>
          </div>
          <svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.5"><path d="M7 17L17 7M17 7H7M17 7V17"/></svg>
        </a>
      </div>

      <div class="cloud-info-box">
        <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><circle cx="12" cy="12" r="10"/><line x1="12" y1="16" x2="12" y2="12"/><line x1="12" y1="8" x2="12.01" y2="8"/></svg>
        <p>Toutes vos évaluations corrigées et annotées par votre professeur sont stockées dans votre dossier cloud personnel. Cliquez ci-dessus pour les ouvrir ou les télécharger.</p>
      </div>

      <div class="dash-footer">
        <span>Session chiffrée de bout en bout</span>
        <button type="button" id="btnLogout" class="btn-logout">
          <svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><path d="M9 21H5a2 2 0 0 1-2-2V5a2 2 0 0 1 2-2h4"/><polyline points="16 17 21 12 16 7"/><line x1="21" y1="12" x2="9" y2="12"/></svg>
          Se déconnecter
        </button>
      </div>
    </div>
  </div>

  <!-- MODAL D'AIDE INSTALLATION SMARTPHONE PWA -->
  <div id="modalPwa" class="modal-overlay">
    <div class="modal-box">
      <div class="modal-title">
        <span>📲 Installer sur mon smartphone</span>
        <button type="button" id="btnCloseModal" style="background: none; border: none; font-size: 16px; cursor: pointer; color: inherit;">✕</button>
      </div>

      <!-- Guide iOS (iPhone / iPad) -->
      <div id="modalIosContent">
        <div id="iosWebviewNotice" style="display: none; padding: 10px; border-radius: 10px; background: rgba(245, 158, 11, 0.15); border: 1px solid rgba(245, 158, 11, 0.35); color: #fde68a; font-size: 11px; margin-bottom: 12px;">
          ⚠️ Vous êtes dans un navigateur interne : touchez l'icône 🧭 ou <strong>Safari</strong> en bas à droite pour ouvrir la page dans Safari.
        </div>
        <p style="font-size: 12px; opacity: 0.8; margin-bottom: 12px;">Pour créer l'icône sur votre écran d'accueil iPhone :</p>
        <div class="modal-step">
          1. Touchez le bouton <strong>Partager</strong> <kbd style="background: rgba(255, 255, 255, 0.15); padding: 2px 6px; border-radius: 4px; font-family: monospace;">⎋ / [ ↑ ]</kbd> en bas de Safari.
        </div>
        <div class="modal-step">
          2. Faites défiler vers le bas et touchez <strong>« Sur l'écran d'accueil »</strong> <kbd style="background: rgba(255, 255, 255, 0.15); padding: 2px 6px; border-radius: 4px; font-family: monospace;">➕</kbd>.
        </div>
      </div>

      <!-- Guide Générique / Android -->
      <div id="modalGenericContent" style="display: none;">
        <p style="font-size: 12px; opacity: 0.8; margin-bottom: 12px;">Pour ajouter ce portail à votre écran d'accueil :</p>
        <div class="modal-step">
          1. Touchez le menu <kbd style="background: rgba(255, 255, 255, 0.15); padding: 2px 6px; border-radius: 4px; font-family: monospace;">⋮</kbd> en haut à droite de votre navigateur.
        </div>
        <div class="modal-step">
          2. Choisissez <strong>« Installer l'application »</strong> ou <strong>« Ajouter à l'écran d'accueil »</strong>.
        </div>
      </div>
    </div>
  </div>

  <script src="scripts/data.js"></script>
  <script src="scripts/app.js"></script>
</body>
</html>

"""##
        html = html.replacingOccurrences(of: "${title}", with: title)
        html = html.replacingOccurrences(of: "${subtitle}", with: subtitle)
        html = html.replacingOccurrences(of: "${colors.theme}", with: colors.theme)
        return html
    }
}
