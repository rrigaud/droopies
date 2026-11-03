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

    public init(storageManager: StorageManager = StorageManager()) {
        self.storageManager = storageManager
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

    /// Charge `eleves.json` et `settings.json` depuis le stockage actif
    public func loadInitialData() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            async let loadedStudents = storageManager.loadStudents()
            async let loadedSettings = storageManager.loadSettings()

            let (studs, sets) = try await (loadedStudents, loadedSettings)
            self.students = studs
            self.settings = sets

            if selectedClassId == nil, let first = classes.first {
                self.selectedClassId = first.id
            }
        } catch {
            self.errorMessage = "Impossible de charger les données : \(error.localizedDescription)"
        }
    }

    // MARK: - Opérations Élèves

    public func addStudent(_ student: Student) async throws {
        var updated = students
        updated.append(student)
        try await storageManager.saveStudents(updated)
        self.students = updated
    }

    public func updateStudent(_ student: Student) async throws {
        guard let index = students.firstIndex(where: { $0.id == student.id }) else { return }
        var updated = students
        updated[index] = student
        try await storageManager.saveStudents(updated)
        self.students = updated
    }

    public func deleteStudent(_ student: Student) async throws {
        var updated = students
        updated.removeAll { $0.id == student.id }
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
