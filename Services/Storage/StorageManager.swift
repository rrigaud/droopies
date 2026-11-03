//
//  StorageManager.swift
//  Dropies
//
//  Gestionnaire centralisé de persistance des données.
//  Orchestre les opérations de haut niveau sur `eleves.json`, `settings.json`
//  et l'arborescence des dossiers élèves.
//

import Foundation
import Observation

@Observable
public final class StorageManager: @unchecked Sendable {
    public var activeProvider: StorageProvider
    public var isLoading: Bool = false
    public var lastErrorMessage: String?

    public init(activeProvider: StorageProvider = LocalStorageProvider()) {
        self.activeProvider = activeProvider
    }

    public func setProvider(_ provider: StorageProvider) {
        self.activeProvider = provider
    }

    // MARK: - Résolution de l'URL du dossier racine (Source)
    public var rootURL: URL {
        get {
            if let local = activeProvider as? LocalStorageProvider, let url = local.rootURL {
                return url
            }
            // Emplacement par défaut : Documents/Source
            let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first ?? URL(fileURLWithPath: NSHomeDirectory())
            return docs.appendingPathComponent("Source")
        }
        set {
            if let local = activeProvider as? LocalStorageProvider {
                local.setRootURL(newValue)
            } else {
                let local = LocalStorageProvider(rootURL: newValue)
                self.activeProvider = local
            }
        }
    }

    /// Résout l'URL locale absolue pour un chemin relatif dans le dossier Source
    public func localURL(for relativePath: String) -> URL {
        let clean = relativePath.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        return clean.isEmpty ? rootURL : rootURL.appendingPathComponent(clean)
    }

    // MARK: - Gestion de `eleves.json`

    /// Charge et décode la liste officielle des élèves depuis `eleves.json`
    public func loadStudents() async throws -> [Student] {
        isLoading = true
        defer { isLoading = false }

        do {
            let data = try await activeProvider.readData(at: "eleves.json")
            let decoder = JSONDecoder()
            let students = try decoder.decode([Student].self, from: data)
            return students
        } catch StorageError.fileNotFound {
            // Si le fichier n'existe pas encore, renvoyer une liste vide
            return []
        } catch {
            throw error
        }
    }

    /// Enregistre la liste des élèves dans `eleves.json` avec indentation propre (2 espaces)
    public func saveStudents(_ students: [Student]) async throws {
        isLoading = true
        defer { isLoading = false }

        // Réattribution d'ID croissants propres
        var maxId = 0
        let cleaned: [Student] = students.map { s in
            var copy = s
            let targetId = (copy.id > 0) ? copy.id : maxId + 1
            maxId = max(maxId, targetId)
            copy.id = targetId
            return copy
        }

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(cleaned)

        try await activeProvider.writeData(data, to: "eleves.json")
    }

    // MARK: - Gestion de `settings.json`

    /// Charge la configuration du portail depuis `settings.json`
    public func loadSettings() async throws -> AppSettings {
        do {
            let data = try await activeProvider.readData(at: "settings.json")
            let settings = try JSONDecoder().decode(AppSettings.self, from: data)
            return settings
        } catch {
            return AppSettings()
        }
    }

    /// Sauvegarde les préférences dans `settings.json`
    public func saveSettings(_ settings: AppSettings) async throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(settings)
        try await activeProvider.writeData(data, to: "settings.json")
    }

    // MARK: - Création et vérification de l'arborescence

    /// S'assure que les dossiers racines standards existent dans le dossier Source
    public func ensureSourceFolderStructure() async throws {
        let directories = [
            "Documents",
            "Evaluations",
            "Evaluations/A corriger",
            "Evaluations/Backup",
            "Evaluations/Eleves"
        ]

        for dir in directories {
            try await activeProvider.createDirectory(at: dir)
        }
    }

    /// Vérifie et crée les dossiers physiques de tous les élèves manquants
    public func ensureStudentFolders(students: [Student]) async throws -> [Student] {
        try await ensureSourceFolderStructure()

        var updatedStudents = students
        var hasChanges = false

        for (index, student) in students.enumerated() {
            guard !student.classe.isEmpty && !student.name.isEmpty else { continue }

            let classFolder = "Evaluations/Eleves/\(Student.sanitizeFolderName(student.classe))"
            let studentFolder = "\(classFolder)/\(student.folderName)"

            // Créer le dossier s'il n'existe pas
            try await activeProvider.createDirectory(at: studentFolder)

            // Si c'est Dropbox et que le lien partagé est manquant, le générer
            if activeProvider.providerType == .dropbox && student.urlDropbox.isEmpty {
                if let link = try? await activeProvider.createSharedLink(for: studentFolder) {
                    updatedStudents[index].urlDropbox = link
                    hasChanges = true
                }
            }
        }

        // Si des liens Dropbox ont été générés, réécrire `eleves.json`
        if hasChanges {
            try await saveStudents(updatedStudents)
        }

        return updatedStudents
    }

    /// Vérifie si le dossier d'un élève existe physiquement
    public func checkStudentFolderExists(for student: Student) async -> Bool {
        guard !student.classe.isEmpty && !student.name.isEmpty else { return false }
        let path = "Evaluations/Eleves/\(Student.sanitizeFolderName(student.classe))/\(student.folderName)"
        return (try? await activeProvider.itemExists(at: path)) ?? false
    }

    // MARK: - Gestion des Scans dans `Evaluations/A corriger`

    public struct ScanItem: Identifiable, Hashable, Sendable {
        public var id: String { path }
        public var name: String
        public var path: String
        public var isCorrected: Bool
        public var cleanTitle: String {
            if name.hasPrefix("CORRIGE_") {
                return String(name.dropFirst("CORRIGE_".count))
            } else if name.hasPrefix("Finished_") {
                return String(name.dropFirst("Finished_".count))
            }
            return name
        }
    }

    /// Liste tous les fichiers PDF en attente ou corrigés dans `Evaluations/A corriger`
    public func listScans() async throws -> [ScanItem] {
        try await ensureSourceFolderStructure()
        let items = try await activeProvider.listContents(at: "Evaluations/A corriger")
        return items
            .filter { !$0.isDirectory && $0.name.lowercased().hasSuffix(".pdf") }
            .map { item in
                let isCorr = item.name.hasPrefix("CORRIGE_") || item.name.hasPrefix("Finished_")
                return ScanItem(name: item.name, path: item.path, isCorrected: isCorr)
            }
            .sorted { $0.name < $1.name }
    }

    /// Marque un scan comme "CORRIGÉ" en préfixant son nom par `CORRIGE_`
    public func markScan(scan: ScanItem, asCorrected: Bool) async throws {
        let currentDir = "Evaluations/A corriger"
        let newName: String
        if asCorrected {
            newName = scan.name.hasPrefix("CORRIGE_") ? scan.name : "CORRIGE_\(scan.name)"
        } else {
            newName = scan.cleanTitle
        }
        guard newName != scan.name else { return }
        try await activeProvider.moveItem(from: "\(currentDir)/\(scan.name)", to: "\(currentDir)/\(newName)")
    }

    // MARK: - Gestion des Évaluations passées (`Evaluations/Backup`)

    public struct ExistingBackup: Identifiable, Hashable, Sendable {
        public var id: String { fileName }
        public var fileName: String
        public var path: String
        public var date: Date?
        public var className: String
        public var evaluationTitle: String
    }

    /// Liste les évaluations déjà distribuées archivées dans `Evaluations/Backup`
    public func listExistingBackups() async throws -> [ExistingBackup] {
        try await ensureSourceFolderStructure()
        let items = try await activeProvider.listContents(at: "Evaluations/Backup")
        return items
            .filter { !$0.isDirectory && $0.name.lowercased().hasSuffix(".pdf") }
            .compactMap { item in
                guard let parsed = Evaluation.parseBackupFileName(item.name) else { return nil }
                return ExistingBackup(
                    fileName: item.name,
                    path: item.path,
                    date: parsed.date,
                    className: parsed.className,
                    evaluationTitle: parsed.title
                )
            }
            .sorted { ($0.date ?? Date.distantPast) > ($1.date ?? Date.distantPast) }
    }

    // MARK: - Détection des élèves ayant déjà une évaluation

    /// Vérifie si un élève a déjà un PDF d'évaluation dans son dossier
    public func studentHasEvaluation(student: Student, evaluationTitle: String) async -> Bool {
        let classDir = Student.sanitizeFolderName(student.classe)
        let studentDir = student.folderName
        let path = "Evaluations/Eleves/\(classDir)/\(studentDir)"
        guard let files = try? await activeProvider.listContents(at: path) else { return false }
        let cleanTitle = Student.sanitizeFolderName(evaluationTitle).lowercased()
        return files.contains { file in
            let cleanFileName = file.name.lowercased()
            return cleanFileName.contains(cleanTitle) && cleanFileName.hasSuffix(".pdf")
        }
    }
}
