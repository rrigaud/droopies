//
//  ClassGroup.swift
//  Dropies
//
//  Représente un regroupement d'élèves par classe.
//

import Foundation

public struct ClassGroup: Identifiable, Hashable, Sendable {
    public var id: String { name }
    public var name: String
    public var students: [Student]

    public init(name: String, students: [Student] = []) {
        self.name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        self.students = students.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    /// Nom de dossier sécurisé pour la classe sur le disque/Cloud
    public var folderName: String {
        Student.sanitizeFolderName(name)
    }

    /// Nombre total d'élèves dans la classe
    public var studentCount: Int {
        students.count
    }

    public var count: Int {
        studentCount
    }

    /// Nombre de garçons
    public var maleCount: Int {
        students.filter { $0.gender == .male }.count
    }

    /// Nombre de filles
    public var femaleCount: Int {
        students.filter { $0.gender == .female }.count
    }

    /// Regroupe une liste plate d'élèves en un tableau de ClassGroup ordonnées
    public static func groupStudents(_ students: [Student]) -> [ClassGroup] {
        let grouped = Dictionary(grouping: students) { $0.classe.isEmpty ? "Sans Classe" : $0.classe }
        return grouped.map { ClassGroup(name: $0.key, students: $0.value) }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }
}
