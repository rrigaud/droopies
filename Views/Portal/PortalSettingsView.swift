//
//  PortalSettingsView.swift
//  Dropies
//
//  Configuration et prévisualisation directe du Portail Élèves en ligne
//  (Titres, Thème de couleur, URL Dropbox, chiffrage client-side).
//

import SwiftUI

public struct PortalSettingsView: View {
    @Bindable public var appState: AppState

    @State private var title: String = ""
    @State private var subtitle: String = ""
    @State private var selectedTheme: String = "emeraude"
    @State private var portalUrl: String = ""
    @State private var isSaving: Bool = false
    @State private var showSaveSuccess: Bool = false

    private let availableThemes = [
        ("emeraude", "Émeraude", Color.green),
        ("saphir", "Saphir", Color.blue),
        ("rubis", "Rubis", Color.red),
        ("amethyste", "Améthyste", Color.purple),
        ("ardoise", "Ardoise", Color(white: 0.25))
    ]

    public init(appState: AppState) {
        self.appState = appState
    }

    public var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    // MARK: - Prévisualisation directe du portail
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Aperçu du portail élève")
                            .font(.headline)

                        portalLivePreviewCard
                    }

                    // MARK: - Formulaire de personnalisation
                    VStack(alignment: .leading, spacing: 16) {
                        Text("Personnalisation & Liens")
                            .font(.headline)

                        VStack(alignment: .leading, spacing: 6) {
                            Text("Titre principal")
                                .font(.caption.bold())
                                .foregroundColor(.secondary)
                            TextField("Portail Élèves", text: $title)
                                .textFieldStyle(.roundedBorder)
                        }

                        VStack(alignment: .leading, spacing: 6) {
                            Text("Sous-titre descriptif")
                                .font(.caption.bold())
                                .foregroundColor(.secondary)
                            TextField("Évaluations & Documents de la classe", text: $subtitle)
                                .textFieldStyle(.roundedBorder)
                        }

                        // Sélecteur de thème de couleurs
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Thème graphique")
                                .font(.caption.bold())
                                .foregroundColor(.secondary)

                            HStack(spacing: 12) {
                                ForEach(availableThemes, id: \.0) { key, name, color in
                                    let isSelected = selectedTheme == key
                                    Button {
                                        selectedTheme = key
                                    } label: {
                                        HStack(spacing: 6) {
                                            Circle()
                                                .fill(color)
                                                .frame(width: 14, height: 14)
                                            Text(name)
                                                .font(.subheadline)
                                        }
                                        .padding(.horizontal, 12)
                                        .padding(.vertical, 8)
                                        .background(isSelected ? color.opacity(0.15) : Color(white: 0.5, opacity: 0.06))
                                        .foregroundColor(isSelected ? color : .primary)
                                        .clipShape(Capsule())
                                        .overlay(
                                            Capsule()
                                                .stroke(isSelected ? color : Color.clear, lineWidth: 2)
                                        )
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }

                        VStack(alignment: .leading, spacing: 6) {
                            Text("Adresse web publique (Lien Dropbox ou WebDAV)")
                                .font(.caption.bold())
                                .foregroundColor(.secondary)
                            TextField("https://www.dropbox.com/scl/fi/...", text: $portalUrl)
                                .textFieldStyle(.roundedBorder)
                        }

                        // Bouton d'enregistrement
                        HStack {
                            Button {
                                savePortalSettings()
                            } label: {
                                Label(isSaving ? "Enregistrement..." : "Enregistrer les modifications", systemImage: "checkmark.circle.fill")
                                    .fontWeight(.semibold)
                            }
                            .buttonStyle(.borderedProminent)
                            .disabled(isSaving)

                            if showSaveSuccess {
                                HStack(spacing: 6) {
                                    Image(systemName: "checkmark")
                                        .foregroundColor(.green)
                                    Text("settings.json mis à jour !")
                                        .font(.subheadline)
                                        .foregroundColor(.green)
                                }
                            }
                        }
                        .padding(.top, 8)
                    }
                    .padding(20)
                    .background(Color(white: 0.5, opacity: 0.04))
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                }
                .padding(20)
            }
            .navigationTitle("Portail Élèves & Partage")
            .onAppear {
                title = appState.settings.portalTitle
                subtitle = appState.settings.portalSubtitle
                selectedTheme = appState.settings.portalTheme
                portalUrl = appState.settings.portalUrl
            }
        }
    }

    // MARK: - Carte de prévisualisation

    private var currentThemeColor: Color {
        availableThemes.first(where: { $0.0 == selectedTheme })?.2 ?? .green
    }

    private var portalLivePreviewCard: some View {
        VStack(spacing: 16) {
            // En-tête simulant le portail
            VStack(spacing: 6) {
                Image(systemName: "graduationcap.fill")
                    .font(.system(size: 36))
                    .foregroundColor(currentThemeColor)

                Text(title.isEmpty ? "Portail Élèves" : title)
                    .font(.title3.bold())

                Text(subtitle.isEmpty ? "Évaluations & Documents" : subtitle)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding(.top, 8)

            // Faux formulaire élève
            VStack(spacing: 10) {
                Text("Connexion Sécurisée (Zero-Knowledge)")
                    .font(.caption2.bold())
                    .foregroundColor(.secondary)

                HStack {
                    Image(systemName: "key.fill")
                        .foregroundColor(.secondary)
                    Text("Code élève (ex: A7K9M2)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Spacer()
                }
                .padding(10)
                .background(Color(white: 0.5, opacity: 0.08))
                .clipShape(RoundedRectangle(cornerRadius: 6))

                Text("Consulter mes copies")
                    .font(.subheadline.bold())
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .background(currentThemeColor)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
            }
            .frame(maxWidth: 320)
            .padding(16)
            .background(Color(white: 0.5, opacity: 0.05))
            .clipShape(RoundedRectangle(cornerRadius: 10))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
        .background(Color(white: 0.5, opacity: 0.03))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(currentThemeColor.opacity(0.3), lineWidth: 1.5)
        )
    }

    private func savePortalSettings() {
        isSaving = true
        var updated = appState.settings
        updated.portalTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        updated.portalSubtitle = subtitle.trimmingCharacters(in: .whitespacesAndNewlines)
        updated.portalTheme = selectedTheme
        updated.portalUrl = portalUrl.trimmingCharacters(in: .whitespacesAndNewlines)
        updated.touchModification()

        Task {
            try? await appState.storageManager.saveSettings(updated)
            await MainActor.run {
                self.appState.settings = updated
                self.isSaving = false
                self.showSaveSuccess = true
                DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
                    self.showSaveSuccess = false
                }
            }
        }
    }
}
