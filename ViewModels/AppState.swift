//
//  AppState.swift
//  Dropies
//
//  État global réactif de l'application (@Observable).
//  Pilote les données d'élèves, la classe sélectionnée, la configuration Cloud
//  et les évaluations en cours.
//

import Foundation
import Observation

@Observable
public final class AppState: @unchecked Sendable {
    public var storageManager: StorageManager
    public var students: [Student] = []
    public var settings: AppSettings = AppSettings()
    public var selectedClassId: String? = nil

    public var currentEvaluation: Evaluation? = nil
    public var isLoading: Bool = false
    public var errorMessage: String? = nil

    /// Indique si l'appareil est connecté à Internet (piloté par NetworkMonitor)
    public var isOnline: Bool = NetworkMonitor.shared.isOnline

    /// Chemin du dossier racine/source actuellement actif dans le Cloud (observé par l'interface)
    public var currentRootFolderPath: String = ""

    // MARK: - Déclencheurs de Modales Globales
    public var showAddStudentSheet: Bool = false
    public var showCSVImportSheet: Bool = false

    public var currentRootFolderName: String {
        let clean = currentRootFolderPath.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        return clean.isEmpty ? "Racine" : URL(fileURLWithPath: clean).lastPathComponent
    }

    
    // MARK: - Localisation Dynamique Réactive
    public func t(_ key: L10nKey) -> String {
        L10n.t(key, lang: settings.language)
    }

    public init(storageManager: StorageManager = StorageManager()) {
        self.storageManager = storageManager
        self.isOnline = NetworkMonitor.shared.isOnline
        if let dropbox = storageManager.activeProvider as? DropboxStorageProvider {
            self.currentRootFolderPath = dropbox.rootFolderPath
        } else {
            self.currentRootFolderPath = UserDefaults.standard.string(forKey: "droopies_dropbox_root_path")
                ?? UserDefaults.standard.string(forKey: "droopies_selected_folder")
                ?? ""
        }

        // Écoute réactive des transitions réseau (Hors-Ligne <-> En Ligne)
        NetworkMonitor.shared.onStatusChange = { [weak self] online in
            Task { @MainActor in
                guard let self = self else { return }
                let wasOffline = !self.isOnline
                self.isOnline = online
                if online && wasOffline {
                    print("[AppState] 🟢 Retour de la connexion Internet détecté : Synchronisation des devoirs")
                    let sm = self.storageManager
                    Task.detached {
                        await OfflineSyncEngine.shared.performSync(storageManager: sm, isOnline: true)
                    }
                }
            }
        }
    }

    // MARK: - Classes calculées dynamiquement
    public var classes: [ClassGroup] {
        ClassGroup.groupStudents(students)
    }

    public var selectedClass: ClassGroup? {
        guard let id = selectedClassId else { return classes.first }
        return classes.first { $0.id == id }
    }

    public var studentsInSelectedClass: [Student] {
        selectedClass?.students ?? students
    }

    // MARK: - Initialisation des données

    /// Charge `eleves.json` et `settings.json` depuis le stockage actif avec retour de progression
    public func loadInitialData(onProgress: (@Sendable (Double, String) -> Void)? = nil) async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            onProgress?(0.05, "Lecture des réglages (settings.json)...")
            let sets = try await storageManager.loadSettings()
            self.settings = sets

            onProgress?(0.15, "Lecture de la base élèves (eleves.json)...")
            let studs = try await storageManager.loadStudents()
            self.students = studs

            if selectedClassId == nil, let first = classes.first {
                self.selectedClassId = first.id
            }

            if !isOnline || studs.isEmpty {
                onProgress?(1.0, isOnline ? "Base de données initialisée" : "Mode Hors-Ligne activé • Données locales prêtes")
            } else {
                // Synchronisation et vérification fine élève par élève
                let updated = try await storageManager.autoSyncAllStudents(students: studs) { current, total, student, stepText in
                    let fraction = 0.15 + (0.85 * (Double(current) / Double(total)))
                    onProgress?(fraction, "Élève \(current)/\(total) : \(stepText)")
                }
                self.students = updated

                // Synchronisation déterministe des devoirs en arrière-plan
                let sm = self.storageManager
                Task.detached {
                    await OfflineSyncEngine.shared.performSync(storageManager: sm, isOnline: true)
                }
            }
        } catch {
            self.errorMessage = "Impossible de charger les données : \(error.localizedDescription)"
        }
    }

    /// Bascule de dossier source avec rafraîchissement réactif instantané de l'interface et des données
    @MainActor
    public func switchSourceFolder(to newPath: String) async {
        let clean = newPath.trimmingCharacters(in: .whitespacesAndNewlines)
        self.currentRootFolderPath = clean
        UserDefaults.standard.set(clean, forKey: "droopies_selected_folder")
        UserDefaults.standard.set(clean, forKey: "droopies_dropbox_root_path")

        if let dropbox = storageManager.activeProvider as? DropboxStorageProvider {
            dropbox.setRootFolderPath(clean)
        }

        // Réinitialiser la classe pour forcer la mise à jour des vues
        self.selectedClassId = nil

        // Créer l'arborescence des 4 dossiers si elle n'existe pas encore
        try? await storageManager.ensureSourceFolderStructure()

        // Recharger immédiatement les élèves et réglages du nouveau dossier
        await loadInitialData()
    }

    // MARK: - Opérations Élèves

    @MainActor
    public func addStudent(_ student: Student) async throws {
        var newStudent = student
        let nextId = (students.map { $0.id }.max() ?? 0) + 1
        newStudent.id = nextId

        // 1. Ajout optimiste immédiat dans la liste pour un affichage instantané dans le tableau
        var updated = students
        updated.append(newStudent)
        self.students = updated
        try await storageManager.saveStudents(updated)

        // 2. Création asynchrone du dossier et du partage Cloud en tâche de fond (sans figer l'interface)
        Task { [weak self, newStudent] in
            guard let self = self else { return }
            let synced = (try? await self.storageManager.ensureSingleStudentFolder(newStudent)) ?? newStudent
            await MainActor.run {
                if let idx = self.students.firstIndex(where: { $0.id == newStudent.id }) {
                    self.students[idx] = synced
                }
            }
            try? await self.storageManager.saveStudents(self.students)
        }
    }

    @MainActor
    public func updateStudent(_ student: Student, oldStudent: Student? = nil) async throws {
        guard let index = students.firstIndex(where: { $0.id == student.id }) else { return }
        let previous = oldStudent ?? students[index]

        let hasNameOrClassChanged = !previous.classe.isEmpty && !previous.name.isEmpty &&
            (previous.classe != student.classe || previous.name != student.name)

        if hasNameOrClassChanged {
            let oldClassFolder = "Evaluations/Eleves/\(Student.sanitizeFolderName(previous.classe))"
            let oldPath = "\(oldClassFolder)/\(previous.folderName)"

            let newClassFolder = "Evaluations/Eleves/\(Student.sanitizeFolderName(student.classe))"
            let newPath = "\(newClassFolder)/\(student.folderName)"

            try? await storageManager.ensureSourceFolderStructure()
            try? await storageManager.activeProvider.createDirectory(at: newClassFolder)

            let oldExists = (try? await storageManager.activeProvider.itemExists(at: oldPath)) ?? false
            if oldExists {
                // Si la destination existe déjà (résidu vide d'un test ou conflit), la nettoyer
                let newExists = (try? await storageManager.activeProvider.itemExists(at: newPath)) ?? false
                if newExists {
                    let contents = (try? await storageManager.activeProvider.listContents(at: newPath)) ?? []
                    if contents.isEmpty {
                        try? await storageManager.activeProvider.deleteItem(at: newPath)
                    }
                }

                do {
                    try await storageManager.activeProvider.moveItem(from: oldPath, to: newPath)
                } catch {
                    print("Erreur déplacement de \(oldPath) vers \(newPath): \(error)")
                }
            } else {
                // Si l'ancien dossier n'existait pas physiquement, créer le nouveau
                try? await storageManager.activeProvider.createDirectory(at: newPath)
            }
        }

        // S'assurer que le dossier Cloud et son partage existent pour la nouvelle configuration
        let synced = (try? await storageManager.ensureSingleStudentFolder(student)) ?? student

        // Mise à jour de la liste réactive et persistance
        var updated = students
        if let idx = updated.firstIndex(where: { $0.id == student.id }) {
            updated[idx] = synced
        }
        self.students = updated
        try await storageManager.saveStudents(updated)
    }

    public func ensureStudentFolder(for student: Student) async throws -> Student {
        let synced = try await storageManager.ensureSingleStudentFolder(student)
        if let idx = students.firstIndex(where: { $0.id == student.id }) {
            var updated = students
            updated[idx] = synced
            try await storageManager.saveStudents(updated)
            self.students = updated
        }
        return synced
    }

    /// Synchronisation automatique continue en tâche de fond
    public func autoSyncMissingFoldersAndShares() async {
        guard !students.isEmpty else { return }
        let hasMissingShares = students.contains { $0.urlDropbox.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        if hasMissingShares {
            do {
                let updated = try await storageManager.autoSyncAllStudents(students: students)
                await MainActor.run {
                    self.students = updated
                }
            } catch {
                print("Erreur autoSyncMissingFoldersAndShares : \(error)")
            }
        }
    }

    public func deleteStudent(_ student: Student) async throws {
        isLoading = true
        defer { isLoading = false }

        var updated = students
        updated.removeAll { $0.id == student.id }
        try await storageManager.saveStudents(updated)
        self.students = updated

        // Supprimer également le dossier Cloud correspondant
        try? await storageManager.deleteStudentFolder(student)
    }

    public func deleteStudents(ids: Set<Int>) async throws {
        isLoading = true
        defer { isLoading = false }

        let toDelete = students.filter { ids.contains($0.id) }
        var updated = students
        updated.removeAll { ids.contains($0.id) }
        try await storageManager.saveStudents(updated)
        self.students = updated

        for s in toDelete {
            try? await storageManager.deleteStudentFolder(s)
        }
    }

    public func applyPasswords(_ newPasswords: [Int: String]) async throws {
        isLoading = true
        defer { isLoading = false }

        var updated = students
        for i in 0..<updated.count {
            if let p = newPasswords[updated[i].id] {
                updated[i].password = p
            }
        }
        try await storageManager.saveStudents(updated)
        self.students = updated
    }

    // MARK: - Génération des dossiers physiques manquants

    public func generateMissingFolders() async throws {
        isLoading = true
        defer { isLoading = false }
        let updated = try await storageManager.ensureStudentFolders(students: students)
        self.students = updated
    }

    // MARK: - Génération de mots de passe aléatoires

    public func generateRandomPasswords(for targetStudents: [Student]? = nil) async throws {
        isLoading = true
        defer { isLoading = false }

        let wordList = [
            "pomme", "cerise", "nuage", "soleil", "étoile", "bateau", "fusée",
            "plage", "forêt", "rivière", "fleur", "oiseau", "tigre", "panda",
            "koala", "dauphin", "arbre", "jardin", "musique", "livre", "stylo"
        ]

        var updated = students
        let targetIds = Set((targetStudents ?? students).map { $0.id })

        for i in 0..<updated.count {
            if targetIds.contains(updated[i].id) {
                let word = wordList.randomElement() ?? "classe"
                let number = Int.random(in: 10...99)
                updated[i].password = "\(word)\(number)"
            }
        }

        try await storageManager.saveStudents(updated)
        self.students = updated
    }
}
