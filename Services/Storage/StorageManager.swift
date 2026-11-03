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
}
