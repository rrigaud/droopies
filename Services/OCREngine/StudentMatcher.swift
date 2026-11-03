//
//  StudentMatcher.swift
//  Dropies
//
//  Algorithme de réconciliation floue (Fuzzy Matching Levenshtein)
//  pour attribuer automatiquement les copies aux élèves de la classe
//  et extraire les notes manuscrites.
//

import Foundation

public struct StudentMatchCandidate: Sendable {
    public let student: Student
    public let confidence: Double // Entre 0.0 et 1.0
    public let matchedText: String

    public var isHighlyConfident: Bool {
        confidence >= 0.80
    }
}

public final class StudentMatcher: Sendable {

    // MARK: - Réconciliation d'Élève

    /// Compare les lignes de texte lues par l'OCR avec la liste des élèves de la classe
    /// et renvoie les meilleurs candidats classés par score de similarité.
    public static func findMatches(
        recognizedLines: [String],
        students: [Student]
    ) -> [StudentMatchCandidate] {
        var candidates: [StudentMatchCandidate] = []

        // Concaténation de tout le texte de l'en-tête nettoyé
        let fullHeaderText = recognizedLines.joined(separator: " ").lowercased()

        for student in students {
            let studentName = student.name.lowercased()
            let components = studentName.components(separatedBy: .whitespaces).filter { $0.count >= 2 }

            var bestScore: Double = 0.0
            var bestMatchedText = ""

            // 1. Comparaison avec chaque ligne reconnue
            for line in recognizedLines {
                let cleanLine = line.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                guard cleanLine.count >= 2 else { continue }

                // Distance globale avec le nom complet
                let fullSim = similarity(s1: cleanLine, s2: studentName)
                if fullSim > bestScore {
                    bestScore = fullSim
                    bestMatchedText = line
                }

                // Vérification présence de chaque composant (Nom ou Prénom)
                for part in components {
                    if cleanLine.contains(part) {
                        bestScore = max(bestScore, 0.85)
                        bestMatchedText = line
                    } else {
                        let partSim = similarity(s1: cleanLine, s2: part)
                        if partSim >= 0.80 {
                            bestScore = max(bestScore, partSim)
                            bestMatchedText = line
                        }
                    }
                }
            }

            // 2. Recherche directe de sous-chaîne dans tout l'en-tête
            if fullHeaderText.contains(studentName) {
                bestScore = 1.0
                bestMatchedText = student.name
            }

            if bestScore >= 0.50 {
                candidates.append(StudentMatchCandidate(
                    student: student,
                    confidence: bestScore,
                    matchedText: bestMatchedText
                ))
            }
        }

        // Tri du meilleur au moins bon
        return candidates.sorted { $0.confidence > $1.confidence }
    }

    // MARK: - Extraction de la Note Manuscrite

    /// Recherche une note dans les textes reconnus (ex: "14.5/20", "15 / 20", "18/20", "12,5")
    public static func extractGrade(from recognizedLines: [String], maxScore: Double = 20.0) -> Double? {
        let pattern = #"(?:\b|^)(\d{1,2}(?:[.,]\d{1,2})?)\s*(?:\/|\s*sur\s*)\s*(\d{1,2})\b"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
            return nil
        }

        for line in recognizedLines {
            let range = NSRange(line.startIndex..<line.endIndex, in: line)
            if let match = regex.firstMatch(in: line, options: [], range: range) {
                if let scoreRange = Range(match.range(at: 1), in: line) {
                    let scoreStr = String(line[scoreRange]).replacingOccurrences(of: ",", with: ".")
                    if let val = Double(scoreStr), val <= maxScore {
                        return val
                    }
                }
            }
        }

        return nil
    }

    // MARK: - Algorithme de Levenshtein Normalisé

    /// Calcule un ratio de similarité entre 0.0 (totalement différent) et 1.0 (identique)
    public static func similarity(s1: String, s2: String) -> Double {
        let clean1 = s1.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let clean2 = s2.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        if clean1 == clean2 { return 1.0 }
        let maxLen = max(clean1.count, clean2.count)
        guard maxLen > 0 else { return 1.0 }

        let dist = levenshteinDistance(s1: clean1, s2: clean2)
        return max(0.0, 1.0 - (Double(dist) / Double(maxLen)))
    }

    private static func levenshteinDistance(s1: String, s2: String) -> Int {
        let a = Array(s1)
        let b = Array(s2)
        let m = a.count
        let n = b.count

        var d = Array(repeating: Array(repeating: 0, count: n + 1), count: m + 1)

        for i in 0...m { d[i][0] = i }
        for j in 0...n { d[0][j] = j }

        for i in 1...m {
            for j in 1...n {
                if a[i - 1] == b[j - 1] {
                    d[i][j] = d[i - 1][j - 1]
                } else {
                    d[i][j] = min(
                        d[i - 1][j] + 1,     // suppression
                        d[i][j - 1] + 1,     // insertion
                        d[i - 1][j - 1] + 1  // substitution
                    )
                }
            }
        }
        return d[m][n]
    }
}
