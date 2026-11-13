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
    public var isCatchUp: Bool
    public var existingBackupFileName: String?
    public var sourcePDFURL: URL?

    public init(
        id: UUID = UUID(),
        title: String = "",
        date: Date = Date(),
        className: String = "",
        maxScore: Double = 20.0,
        pagesPerCopy: Int = 2,
        copies: [StudentCopy] = [],
        isCatchUp: Bool = false,
        existingBackupFileName: String? = nil,
        sourcePDFURL: URL? = nil
    ) {
        self.id = id
        self.title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        self.date = date
        self.className = className.trimmingCharacters(in: .whitespacesAndNewlines)
        self.maxScore = maxScore
        self.pagesPerCopy = max(1, pagesPerCopy)
        self.copies = copies
        self.isCatchUp = isCatchUp
        self.existingBackupFileName = existingBackupFileName
        self.sourcePDFURL = sourcePDFURL
    }

    // MARK: - Formatage & Parsing de date

    public static let dateFormatter: DateFormatter = {
        let df = DateFormatter()
        df.dateFormat = "yyyy-MM-dd"
        return df
    }()

    public var formattedDate: String {
        Self.dateFormatter.string(from: date)
    }

    /// Nom officiel de l'archive de sauvegarde : "YYYY-MM-DD - Classe - Titre.pdf"
    public var backupFileName: String {
        if let existing = existingBackupFileName, !existing.isEmpty {
            return existing
        }
        let cleanClass = Student.sanitizeFolderName(className)
        let cleanTitle = Student.sanitizeFolderName(title)
        return "\(formattedDate) - \(cleanClass) - \(cleanTitle).pdf"
    }

    /// Analyse le nom d'un fichier de sauvegarde pour en extraire la date, la classe et le titre
    /// Formats supportés : "YYYY-MM-DD - Classe - Titre.pdf", "YYYY-MM-DD_Classe_Titre.pdf", etc.
    public static func parseBackupFileName(_ filename: String) -> (date: Date?, className: String, title: String)? {
        let clean = filename.replacingOccurrences(of: ".pdf", with: "", options: .caseInsensitive)
        
        // 1. Essai avec séparateur standard " - "
        let parts = clean.components(separatedBy: " - ")
        if parts.count >= 3 {
            let dateString = parts[0].trimmingCharacters(in: .whitespaces)
            let parsedDate = dateFormatter.date(from: dateString)
            let className = parts[1].trimmingCharacters(in: .whitespaces)
            let title = parts[2...].joined(separator: " - ").trimmingCharacters(in: .whitespaces)
            return (parsedDate, className, title)
        }
        
        // 2. Essai avec séparateur "_" (ex: 2026-11-08_3e1_Devoir)
        let underscoreParts = clean.components(separatedBy: "_")
        if underscoreParts.count >= 3 {
            let dateString = underscoreParts[0].trimmingCharacters(in: .whitespaces)
            let parsedDate = dateFormatter.date(from: dateString)
            let className = underscoreParts[1].trimmingCharacters(in: .whitespaces)
            let title = underscoreParts[2...].joined(separator: "_").trimmingCharacters(in: .whitespaces)
            return (parsedDate, className, title)
        }
        
        // 3. Extraction intelligente si préfixe de date ISO YYYY-MM-DD
        if clean.count >= 10 {
            let datePrefix = String(clean.prefix(10))
            if let parsedDate = dateFormatter.date(from: datePrefix) {
                let remainder = clean.dropFirst(10).trimmingCharacters(in: CharacterSet(charactersIn: " -_"))
                let remainderParts = remainder.components(separatedBy: " - ")
                if remainderParts.count >= 2 {
                    return (parsedDate, remainderParts[0].trimmingCharacters(in: .whitespaces), remainderParts[1...].joined(separator: " - "))
                } else {
                    return (parsedDate, "", remainder)
                }
            }
        }
        
        return nil
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

// MARK: - Métadonnées de Progression et Reprise d'une Évaluation (Configuration/evaluations.json)

public struct EvaluationMetadata: Codable, Hashable, Sendable {
    public var totalPages: Int
    public var lastViewedPage: Int // 1-based (pour reprise exacte à la réouverture)
    public var maxAnnotatedPage: Int // 1-based (pour calcul de la jauge de progression)
    public var isCompleted: Bool? // Stocké directement dans les métadonnées (sans renommer le fichier sur le Cloud)
    public var lastModified: Date

    public init(
        totalPages: Int = 0,
        lastViewedPage: Int = 1,
        maxAnnotatedPage: Int = 0,
        isCompleted: Bool? = nil,
        lastModified: Date = Date()
    ) {
        self.totalPages = max(0, totalPages)
        self.lastViewedPage = max(1, lastViewedPage)
        self.maxAnnotatedPage = max(0, maxAnnotatedPage)
        self.isCompleted = isCompleted
        self.lastModified = lastModified
    }

    /// Indique si l'évaluation est considérée comme entièrement terminée / corrigée
    public var isEffectivelyCompleted: Bool {
        if isCompleted == true { return true }
        // Règle recto-verso : si le devoir a au moins 2 pages et qu'on a annoté jusqu'à l'avant-dernière page
        // (le verso étant souvent une page blanche non annotée), l'évaluation est bien à 100 %
        if totalPages > 1 && maxAnnotatedPage >= totalPages - 1 {
            return true
        }
        if totalPages > 0 && maxAnnotatedPage >= totalPages {
            return true
        }
        return false
    }

    /// Ratio de progression normalisé de 0.0 à 1.0
    public var progressRatio: Double {
        if isEffectivelyCompleted { return 1.0 }
        guard totalPages > 0 else { return 0.0 }
        return min(1.0, max(0.0, Double(maxAnnotatedPage) / Double(totalPages)))
    }

    /// Pourcentage arrondi de 0 à 100
    public var progressPercent: Int {
        if isEffectivelyCompleted { return 100 }
        return Int((progressRatio * 100).rounded())
    }
}
