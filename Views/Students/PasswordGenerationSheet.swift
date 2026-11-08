//
//  PasswordGenerationSheet.swift
//  Droopies
//
//  Feuille modale de génération de mots de passe pour les élèves :
//  - Mots courants simples reliés par des tirets (1, 2 ou 3 mots)
//  - Suite de caractères aléatoires sans confusion visuelle (slider de 6 à 20 caractères)
//  - Aperçu en direct et application immédiate à la sélection.
//

import SwiftUI

public struct PasswordGenerationSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Bindable public var appState: AppState
    public let targetStudentIds: Set<Int>

    public enum GenerationMode: String, CaseIterable, Identifiable {
        case words = "Mots simples (Recommandé)"
        case random = "Suite aléatoire"

        public var id: String { rawValue }
    }

    @State private var mode: GenerationMode = .words
    @State private var wordCount: Int = 2
    @State private var randomLength: Double = 8
    @State private var livePreview: String = ""

    public init(appState: AppState, targetStudentIds: Set<Int>) {
        self.appState = appState
        self.targetStudentIds = targetStudentIds
    }

    private var targetCount: Int {
        if targetStudentIds.isEmpty {
            return appState.students.count
        }
        return targetStudentIds.count
    }

    public var body: some View {
        NavigationStack {
            Form {
                // Section 1 : Cible
                Section {
                    HStack {
                        Image(systemName: "person.2.fill")
                            .foregroundColor(.blue)
                        Text("Élèves concernés")
                            .fontWeight(.medium)
                        Spacer()
                        Text("\(targetCount) élève(s)")
                            .font(.subheadline.bold())
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(Color.blue.opacity(0.12))
                            .clipShape(Capsule())
                    }
                }

                // Section 2 : Type de mot de passe
                Section("Type de mot de passe") {
                    Picker("Méthode", selection: $mode) {
                        ForEach(GenerationMode.allCases) { m in
                            Text(m.rawValue).tag(m)
                        }
                    }
                    .pickerStyle(.segmented)
                    .onChange(of: mode) { _, _ in refreshPreview() }

                    if mode == .words {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Text("Nombre de mots :")
                                Spacer()
                                Text("\(wordCount) mot(s)")
                                    .fontWeight(.bold)
                                    .foregroundColor(.blue)
                            }

                            Picker("Nombre de mots", selection: $wordCount) {
                                Text("1 mot").tag(1)
                                Text("2 mots").tag(2)
                                Text("3 mots").tag(3)
                            }
                            .pickerStyle(.segmented)
                            .onChange(of: wordCount) { _, _ in refreshPreview() }
                        }
                        .padding(.vertical, 4)
                    } else {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Text("Longueur de la suite :")
                                Spacer()
                                Text("\(Int(randomLength)) caractères")
                                    .fontWeight(.bold)
                                    .foregroundColor(.blue)
                            }

                            Slider(value: $randomLength, in: 6...20, step: 1)
                                .onChange(of: randomLength) { _, _ in refreshPreview() }

                            Text("Les caractères ambigus (0, O, 1, l, I) sont exclus pour éviter toute erreur de frappe.")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                        .padding(.vertical, 4)
                    }
                }

                // Section 3 : Aperçu en direct
                Section("Aperçu d'un mot de passe généré") {
                    HStack {
                        Text(livePreview)
                            .font(.system(.title3, design: .monospaced, weight: .bold))
                            .foregroundColor(.primary)

                        Spacer()

                        Button {
                            refreshPreview()
                        } label: {
                            Label("Autre exemple", systemImage: "arrow.clockwise")
                                .font(.caption.bold())
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }
                    .padding(.vertical, 4)
                }
            }
            .navigationTitle("Générateur de Mots de Passe")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Annuler") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("Appliquer (\(targetCount))") {
                        applyGeneratedPasswords()
                    }
                    .font(.body.weight(.bold))
                }
            }
            .onAppear {
                refreshPreview()
            }
        }
        #if os(macOS)
        .frame(minWidth: 500, minHeight: 420)
        #endif
    }

    private func refreshPreview() {
        if mode == .words {
            livePreview = PasswordGenerator.generatePassphrase(wordCount: wordCount, language: appState.settings.language)
        } else {
            livePreview = PasswordGenerator.generateRandom(length: Int(randomLength))
        }
    }

    private func applyGeneratedPasswords() {
        var newPasswords: [Int: String] = [:]
        let targetList = targetStudentIds.isEmpty ? Set(appState.students.map { $0.id }) : targetStudentIds

        for id in targetList {
            if mode == .words {
                newPasswords[id] = PasswordGenerator.generatePassphrase(wordCount: wordCount, language: appState.settings.language)
            } else {
                newPasswords[id] = PasswordGenerator.generateRandom(length: Int(randomLength))
            }
        }

        Task {
            try? await appState.applyPasswords(newPasswords)
            await MainActor.run {
                dismiss()
            }
        }
    }
}
