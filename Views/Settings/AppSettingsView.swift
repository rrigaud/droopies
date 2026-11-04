//
//  AppSettingsView.swift
//  Droopies
//
//  Réglages de l'application : Dossier Source, Fournisseur Cloud (Dropbox, Local, Nextcloud),
//  état de la synchronisation et informations système.
//

import SwiftUI
import UniformTypeIdentifiers

public struct AppSettingsView: View {
    @Bindable public var appState: AppState

    @State private var isFolderPickerPresented: Bool = false
    @State private var selectedProvider: String = "local"
    @State private var dropboxToken: String = ""

    public init(appState: AppState) {
        self.appState = appState
    }

    public var body: some View {
        NavigationStack {
            Form {
                // Section Dossier Source
                Section("Dossier Source Enseignant") {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Emplacement actuel sur disque :")
                            .font(.caption)
                            .foregroundColor(.secondary)

                        HStack {
                            Image(systemName: "folder.fill")
                                .foregroundColor(.blue)
                            Text(appState.storageManager.rootURL.path)
                                .font(.system(.subheadline, design: .monospaced))
                                .lineLimit(1)
                                .truncationMode(.middle)
                        }
                        .padding(8)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color(white: 0.5, opacity: 0.08))
                        .clipShape(RoundedRectangle(cornerRadius: 6))

                        Button {
                            isFolderPickerPresented = true
                        } label: {
                            Label("Modifier le dossier Source...", systemImage: "folder.badge.gearshape")
                        }
                        .buttonStyle(.bordered)
                    }
                    .padding(.vertical, 4)
                }

                // Section Stockage Cloud
                Section("Fournisseur de Stockage") {
                    Picker("Service actif", selection: $selectedProvider) {
                        Text("Stockage Local / Fichiers").tag("local")
                        Text("Dropbox (OAuth2)").tag("dropbox")
                        Text("Nextcloud / Nuage (WebDAV)").tag("nextcloud")
                        Text("Google Drive").tag("gdrive")
                    }
                    .pickerStyle(.menu)

                    if selectedProvider == "dropbox" {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Connexion Dropbox v2 API")
                                .font(.caption.bold())
                                .foregroundColor(.secondary)

                            HStack {
                                BadgeView("Connecté", icon: "checkmark.circle.fill", style: .success)
                                Spacer()
                                Button("Re-synchroniser") {
                                    Task { await appState.loadInitialData() }
                                }
                                .buttonStyle(.bordered)
                            }
                        }
                    } else if selectedProvider == "nextcloud" {
                        VStack(alignment: .leading, spacing: 8) {
                            TextField("URL du serveur WebDAV (ex: https://nuage03.apps.education.fr/remote.php/dav/files/...)", text: .constant(""))
                                .textFieldStyle(.roundedBorder)
                        }
                    }
                }

                // Section Diagnostic & Synchronisation
                Section("État de la base de données") {
                    LabeledContent("Total élèves", value: "\(appState.students.count)")
                    LabeledContent("Classes configurées", value: "\(appState.classes.count)")
                    LabeledContent("Dernière synchronisation", value: appState.settings.studentsLastSyncedAt ?? "Jamais")

                    Button(role: .none) {
                        Task { await appState.loadInitialData() }
                    } label: {
                        Label("Recharger eleves.json et settings.json", systemImage: "arrow.triangle.2.circlepath")
                    }
                }

                // Section À Propos
                Section("À Propos") {
                    HStack {
                        Image(systemName: "app.badge.checkmark.fill")
                            .foregroundColor(.blue)
                        Text("Droopies Native")
                            .fontWeight(.medium)
                        Spacer()
                        Text("v1.0.0 (Swift 6)")
                            .foregroundColor(.secondary)
                    }

                    Text("Droopies est une application native Universal (iPadOS & macOS), conçue pour fonctionner à 100% en local et garantir la confidentialité des données scolaires (RGPD).")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .navigationTitle("Réglages & Stockage")
            .fileImporter(
                isPresented: $isFolderPickerPresented,
                allowedContentTypes: [.folder],
                allowsMultipleSelection: false
            ) { result in
                if case .success(let urls) = result, let url = urls.first {
                    let isAccessing = url.startAccessingSecurityScopedResource()
                    defer {
                        if isAccessing { url.stopAccessingSecurityScopedResource() }
                    }
                    appState.storageManager.rootURL = url
                    Task { await appState.loadInitialData() }
                }
            }
        }
    }
}
