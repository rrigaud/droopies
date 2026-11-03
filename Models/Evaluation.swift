//
//  Evaluation.swift
//  Dropies
//
//  Modèle représentant une évaluation (un devoir complet),
//  ses métadonnées, son barème et sa collection de copies.
//

import Foundation

public struct Evaluation: Identifiable, Hashable, Sendable {
    public var id: UUID
    public var title: String
    public var date: Date
    public var className: String
    public var maxScore: Double
    public var pagesPerCopy: Int
    public var copies: [StudentCopy]

    public init(
        id: UUID = UUID(),
        title: String = "",
        date: Date = Date(),
        className: String = "",
        maxScore: Double = 20.0,
        pagesPerCopy: Int = 2,
        copies: [StudentCopy] = []
    ) {
        self.id = id
        self.title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        self.date = date
        self.className = className.trimmingCharacters(in: .whitespacesAndNewlines)
        self.maxScore = maxScore
        self.pagesPerCopy = max(1, pagesPerCopy)
        self.copies = copies
    }

    // MARK: - Formatage de date

    private static let dateFormatter: DateFormatter = {
        let df = DateFormatter()
        df.dateFormat = "yyyy-MM-dd"
        return df
    }()

    public var formattedDate: String {
        Self.dateFormatter.string(from: date)
    }

    /// Nom officiel de l'archive de sauvegarde : "YYYY-MM-DD - Classe - Titre.pdf"
    public var backupFileName: String {
        let cleanClass = Student.sanitizeFolderName(className)
        let cleanTitle = Student.sanitizeFolderName(title)
        return "\(formattedDate) - \(cleanClass) - \(cleanTitle).pdf"
    }

    // MARK: - Statistiques calculées

    /// Nombre total de copies découpées
    public var totalCopies: Int {
        copies.count
    }

    /// Nombre de copies identifiées avec succès
    public var identifiedCount: Int {
        copies.filter { $0.isIdentified }.count
    }

    /// Nombre de copies marquées comme absentes
    public var absentCount: Int {
        copies.filter { $0.isAbsent }.count
    }

    /// Indique si toutes les copies ont été traitées
    public var isComplete: Bool {
        totalCopies > 0 && copies.allSatisfy { $0.isIdentified || $0.isAbsent }
    }

    /// Moyenne de la classe (calculée sur les copies notées non absentes)
    public var classAverage: Double? {
        let validGrades = copies.compactMap { copy -> Double? in
            guard !copy.isAbsent, let g = copy.grade else { return nil }
            return g
        }
        guard !validGrades.isEmpty else { return nil }
        let sum = validGrades.reduce(0.0, +)
        return sum / Double(validGrades.count)
    }

    /// Note la plus basse
    public var minGrade: Double? {
        copies.compactMap { !$0.isAbsent ? $0.grade : nil }.min()
    }

    /// Note la plus haute
    public var maxGrade: Double? {
        copies.compactMap { !$0.isAbsent ? $0.grade : nil }.max()
    }

    // MARK: - Algorithme d'estimation automatique du nombre de pages

    /// Déduit le nombre de pages le plus probable pour une copie (entre 1 et 6 pages)
    /// en se basant sur un effectif de classe standard (entre 20 et 36 élèves).
    public static func estimatePagesPerCopy(totalPages: Int, expectedClassSize: Int = 28) -> Int {
        guard totalPages > 0 else { return 2 }

        var bestPageCount = 2
        var minDiff = Int.max

        for candidate in 1...6 {
            let estimatedStudents = totalPages / candidate
            if (20...36).contains(estimatedStudents) {
                let diff = abs(estimatedStudents - expectedClassSize)
                if diff < minDiff {
                    minDiff = diff
                    bestPageCount = candidate
                }
            }
        }

        return bestPageCount
    }
}
