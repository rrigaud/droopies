//
//  PasswordGenerator.swift
//  Droopies
//
//  Générateur de mots de passe et codes d'accès ergonomiques :
//  - Mots courants simples reliés par des tirets (recommandé pour les enfants)
//  - Suite de caractères aléatoires sans confusion visuelle (pas de O/0, 1/l/I)
//

import Foundation

public struct PasswordGenerator: Sendable {
    // Caractères sans confusion visuelle (évite 0, O, 1, l, I)
    public static let safeCharacters: [Character] = Array("23456789abcdefghjkmnpqrstuvwxyzABCDEFGHJKLMNPQRSTUVWXYZ")

    // Mots simples en français adaptés aux enfants (animaux, couleurs, éléments naturels, objets)
    public static let frenchWords: [String] = [
        "chat", "lion", "loup", "ours", "cerf", "aigle", "tigre", "panda", "koala", "renard",
        "bleu", "vert", "rouge", "jaune", "rose", "blanc", "dore", "argent", "violet",
        "soleil", "lune", "etoile", "nuage", "riviere", "foret", "montagne", "fleur", "arbre",
        "livre", "crayon", "fusee", "ballon", "musique", "chapeau", "bateau", "chateau", "pomme"
    ]

    // Mots simples en anglais
    public static let englishWords: [String] = [
        "cat", "lion", "wolf", "bear", "deer", "eagle", "tiger", "panda", "fox",
        "blue", "green", "red", "yellow", "pink", "white", "gold", "silver", "purple",
        "sun", "moon", "star", "cloud", "river", "forest", "mountain", "flower", "tree",
        "book", "pencil", "rocket", "ball", "music", "boat", "apple"
    ]

    /// Génère une suite aléatoire sécurisée mais sans caractères ambigus (longueur entre 6 et 20)
    public static func generateRandom(length: Int) -> String {
        let count = max(6, min(20, length))
        return String((0..<count).map { _ in safeCharacters.randomElement()! })
    }

    /// Génère une passphrase de 1, 2 ou 3 mots simples reliés par des tirets avec un nombre à la fin
    public static func generatePassphrase(wordCount: Int, language: AppSettings.AppLanguage = .frenchFR) -> String {
        let count = max(1, min(3, wordCount))
        let words = (language == .english) ? englishWords : frenchWords
        var chosen: [String] = []

        var available = words.shuffled()
        for _ in 0..<count {
            if let w = available.popLast() {
                chosen.append(w)
            }
        }

        let num = Int.random(in: 10...99)
        return (chosen + ["\(num)"]).joined(separator: "-")
    }
}
