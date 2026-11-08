//
//  CloudFolderPickerSheet.swift
//  Droopies
//
//  Explorateur et sélecteur de dossier Source natif dans le Cloud Dropbox.
//  Permet de parcourir l'arborescence, de créer un nouveau dossier
//  à la volée et de choisir n'importe quel dossier comme racine pour Droopies.
//

import SwiftUI

public struct CloudFolderPickerSheet: View {
    @Environment(\.dismiss) private var dismiss
    public let provider: StorageProvider
    public var onSelect: (String) -> Void

    @State private var currentPath: String = ""
    @State private var folders: [CloudItem] = []
    @State private var isLoading: Bool = false
    @State private var errorMessage: String? = nil
    @State private var searchText: String = ""

    @State private var showCreateFolderDialog: Bool = false
    @State private var newFolderName: String = ""

    public init(provider: StorageProvider, initialPath: String = "", onSelect: @escaping (String) -> Void) {
        self.provider = provider
        let clean = initialPath.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        self._currentPath = State(initialValue: clean.isEmpty ? "" : "/\(clean)")
        self.onSelect = onSelect
    }

    private var cleanDisplayPath: String {
        currentPath.isEmpty ? "/" : (currentPath.hasPrefix("/") ? currentPath : "/\(currentPath)")
    }

    private var currentFolderName: String {
        if currentPath.isEmpty || currentPath == "/" {
            return "Racine Dropbox"
        }
        return URL(fileURLWithPath: currentPath).lastPathComponent
    }

    private var filteredFolders: [CloudItem] {
        let q = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if q.isEmpty {
            return folders
        }
        return folders.filter { $0.name.lowercased().contains(q) }
    }

    /// Découpe le chemin actuel en segments interactifs pour le fil d'Ariane
    private var pathSegments: [(title: String, fullPath: String)] {
        var segments: [(title: String, fullPath: String)] = [("Dropbox", "")]
        let parts = currentPath.split(separator: "/").map(String.init)
        var cumulative = ""
        for part in parts {
            cumulative += "/\(part)"
            segments.append((part, cumulative))
        }
        return segments
    }

    public var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // MARK: - En-tête : Fil d'Ariane interactif & actions de navigation
                VStack(spacing: 8) {
                    HStack(spacing: 10) {
                        Button {
                            navigateUp()
                        } label: {
                            Image(systemName: "arrow.up.circle.fill")
                                .font(.title2)
                                .foregroundColor(currentPath.isEmpty || currentPath == "/" ? .secondary.opacity(0.3) : .blue)
                        }
                        .disabled(currentPath.isEmpty || currentPath == "/")
                        .buttonStyle(.plain)
                        .help("Remonter d'un niveau")

                        // Fil d'Ariane cliquable avec défilement horizontal
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 6) {
                                ForEach(Array(pathSegments.enumerated()), id: \.offset) { index, segment in
                                    let isLast = index == pathSegments.count - 1
                                    Button {
                                        if !isLast {
                                            currentPath = segment.fullPath
                                            Task { await loadFolders() }
                                        }
                                    } label: {
                                        HStack(spacing: 5) {
                                            if index == 0 {
                                                CloudBrandIconView(type: provider.providerType, size: 14)
                                            } else {
                                                Image(systemName: "folder.fill")
                                                    .font(.caption2)
                                                    .foregroundColor(isLast ? .blue : .secondary)
                                            }
                                            Text(segment.title)
                                                .font(.system(.subheadline, design: .rounded, weight: isLast ? .bold : .medium))
                                                .foregroundColor(isLast ? .primary : .secondary)
                                        }
                                        .padding(.horizontal, 8)
                                        .padding(.vertical, 5)
                                        .background(isLast ? Color.blue.opacity(0.12) : Color.primary.opacity(0.04))
                                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                                    }
                                    .buttonStyle(.plain)

                                    if !isLast {
                                        Image(systemName: "chevron.right")
                                            .font(.caption2.bold())
                                            .foregroundColor(.secondary.opacity(0.4))
                                    }
                                }
                            }
                            .padding(.horizontal, 2)
                        }

                        Spacer()

                        // Bouton Nouveau Dossier
                        Button {
                            newFolderName = ""
                            showCreateFolderDialog = true
                        } label: {
                            Label("Nouveau", systemImage: "folder.badge.plus")
                                .font(.caption.bold())
                        }
                        .buttonStyle(.bordered)
                        .tint(.blue)
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 12)
                    .padding(.bottom, 6)

                    // Raccourci Année Scolaire automatique (ex: /2026-2027)
                    if currentPath.isEmpty || currentPath == "/" {
                        let defaultYearFolder = "/\(AppSettings.currentSchoolYear)"
                        Button {
                            onSelect(defaultYearFolder)
                            dismiss()
                        } label: {
                            HStack(spacing: 10) {
                                Image(systemName: "sparkles")
                                    .font(.subheadline)
                                    .foregroundColor(.orange)

                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Utiliser l'année scolaire \(AppSettings.currentSchoolYear)")
                                        .font(.subheadline.bold())
                                        .foregroundColor(.primary)
                                    Text("Créera /Applications/Droopies/\(AppSettings.currentSchoolYear)")
                                        .font(.caption2)
                                        .foregroundColor(.secondary)
                                }

                                Spacer()

                                Text("Recommandé")
                                    .font(.caption2.bold())
                                    .foregroundColor(.blue)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                    .background(Color.blue.opacity(0.12))
                                    .clipShape(Capsule())
                            }
                            .padding(.horizontal, 14)
                            .padding(.vertical, 8)
                            .background(Color.blue.opacity(0.05))
                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                            .overlay(
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .stroke(Color.blue.opacity(0.18), lineWidth: 1)
                            )
                        }
                        .buttonStyle(.plain)
                        .padding(.horizontal, 16)
                        .padding(.bottom, 6)
                    }
                }
                .background(.ultraThinMaterial)

                Divider()

                // MARK: - Liste des sous-dossiers
                Group {
                    if isLoading {
                        VStack(spacing: 14) {
                            Spacer()
                            ProgressView()
                                .scaleEffect(1.2)
                            Text("Chargement de vos dossiers Dropbox...")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                            Spacer()
                        }
                    } else if let err = errorMessage {
                        VStack(spacing: 16) {
                            Spacer()
                            Image(systemName: "exclamationmark.triangle.fill")
                                .font(.system(size: 42))
                                .foregroundColor(.orange)
                            Text("Impossible de charger les dossiers")
                                .font(.headline)
                            Text(err)
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .multilineTextAlignment(.center)
                                .padding(.horizontal, 32)
                            Button {
                                Task { await loadFolders() }
                            } label: {
                                Label("Réessayer", systemImage: "arrow.clockwise")
                                    .font(.caption.bold())
                            }
                            .buttonStyle(.borderedProminent)
                            Spacer()
                        }
                    } else if filteredFolders.isEmpty {
                        VStack(spacing: 16) {
                            Spacer()
                            ZStack {
                                Circle()
                                    .fill(Color.blue.opacity(0.1))
                                    .frame(width: 72, height: 72)
                                Image(systemName: "folder")
                                    .font(.system(size: 34))
                                    .foregroundColor(.blue)
                            }

                            VStack(spacing: 4) {
                                Text(searchText.isEmpty ? "Aucun sous-dossier ici" : "Aucun dossier correspondant")
                                    .font(.headline)
                                Text(searchText.isEmpty
                                     ? "Vous pouvez créer un nouveau dossier ou sélectionner le dossier actuel ci-dessous."
                                     : "Modifiez votre recherche pour trouver votre dossier.")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                    .multilineTextAlignment(.center)
                                    .padding(.horizontal, 32)
                            }

                            if searchText.isEmpty {
                                Button {
                                    newFolderName = ""
                                    showCreateFolderDialog = true
                                } label: {
                                    Label("Créer un dossier ici", systemImage: "folder.badge.plus")
                                        .font(.subheadline.bold())
                                }
                                .buttonStyle(.borderedProminent)
                                .tint(.blue)
                            }
                            Spacer()
                        }
                    } else {
                        List {
                            ForEach(filteredFolders) { item in
                                Button {
                                    navigateInto(folder: item)
                                } label: {
                                    HStack(spacing: 12) {
                                        ZStack {
                                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                                .fill(Color.blue.opacity(0.12))
                                                .frame(width: 38, height: 38)
                                            Image(systemName: "folder.fill")
                                                .font(.system(size: 18))
                                                .foregroundColor(.blue)
                                        }

                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(item.name)
                                                .font(.system(size: 15, weight: .semibold))
                                                .foregroundColor(.primary)
                                            Text("Appuyer pour ouvrir")
                                                .font(.caption2)
                                                .foregroundColor(.secondary)
                                        }

                                        Spacer()

                                        // Bouton direct pour sélectionner immédiatement ce dossier sans y entrer
                                        Button {
                                            let chosen = item.path.hasPrefix("/") ? item.path : "/\(item.path)"
                                            onSelect(chosen)
                                            dismiss()
                                        } label: {
                                            Text("Choisir")
                                                .font(.caption2.bold())
                                                .foregroundColor(.blue)
                                                .padding(.horizontal, 10)
                                                .padding(.vertical, 5)
                                                .background(Color.blue.opacity(0.12))
                                                .clipShape(Capsule())
                                        }
                                        .buttonStyle(.plain)

                                        Image(systemName: "chevron.right")
                                            .font(.caption.bold())
                                            .foregroundColor(.secondary.opacity(0.4))
                                    }
                                    .padding(.vertical, 4)
                                    .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        #if os(iOS)
                        .listStyle(.insetGrouped)
                        #else
                        .listStyle(.inset(alternatesRowBackgrounds: true))
                        #endif
                    }
                }

                Divider()

                // MARK: - Barre d'action inférieure (Validation de la sélection)
                HStack(spacing: 14) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Dossier actif sélectionné :")
                            .font(.caption2)
                            .foregroundColor(.secondary)

                        HStack(spacing: 6) {
                            Image(systemName: "folder.fill")
                                .font(.caption)
                                .foregroundColor(.blue)
                            Text(currentFolderName)
                                .font(.system(.subheadline, design: .rounded, weight: .bold))
                                .foregroundColor(.primary)
                                .lineLimit(1)
                        }
                    }

                    Spacer()

                    let isAtRoot = currentPath.isEmpty || currentPath == "/"
                    Button {
                        if !isAtRoot {
                            onSelect(cleanDisplayPath)
                            dismiss()
                        }
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: isAtRoot ? "folder.badge.gearshape" : "checkmark.circle.fill")
                            Text(isAtRoot ? "Sélectionnez un sous-dossier" : "Choisir ce dossier")
                                .font(.subheadline.bold())
                        }
                    }
                    .buttonStyle(VibrantGradientButtonStyle(gradient: isAtRoot ? .subtleGray : .emeraldGreen, isCompact: true))
                    .disabled(isAtRoot)
                }
                .padding(.horizontal, 18)
                .padding(.vertical, 14)
                .background(.ultraThinMaterial)
            }
            .navigationTitle("Parcourir Dropbox")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .searchable(text: $searchText, prompt: "Filtrer les dossiers...")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Fermer") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        Task { await loadFolders() }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .help("Actualiser la liste")
                }
            }
            .alert("Nouveau dossier", isPresented: $showCreateFolderDialog) {
                TextField("Nom du dossier (ex: Devoirs 2026)", text: $newFolderName)
                Button("Créer") {
                    createNewFolder(named: newFolderName)
                }
                Button("Annuler", role: .cancel) {}
            } message: {
                Text("Créez un nouveau sous-dossier dans \(cleanDisplayPath)")
            }
            .task {
                await loadFolders()
            }
        }
        #if os(macOS)
        .frame(minWidth: 580, minHeight: 520)
        #endif
    }

    // MARK: - Navigation & Chargement

    private func loadFolders() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            if let dropbox = provider as? DropboxStorageProvider {
                let items = try await dropbox.listAccountFolders(at: currentPath)
                self.folders = items.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
            } else {
                let items = try await provider.listContents(at: currentPath)
                self.folders = items.filter { $0.isDirectory }.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
            }
        } catch {
            self.errorMessage = "\(error.localizedDescription)"
        }
    }

    private func navigateInto(folder: CloudItem) {
        let clean = folder.name.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        if currentPath.isEmpty || currentPath == "/" {
            currentPath = "/\(clean)"
        } else {
            currentPath = "\(currentPath)/\(clean)"
        }
        searchText = ""
        Task { await loadFolders() }
    }

    private func navigateUp() {
        guard !currentPath.isEmpty && currentPath != "/" else { return }
        var components = currentPath.split(separator: "/").map(String.init)
        if !components.isEmpty {
            components.removeLast()
        }
        currentPath = components.isEmpty ? "" : "/\(components.joined(separator: "/"))"
        searchText = ""
        Task { await loadFolders() }
    }

    private func createNewFolder(named name: String) {
        let cleanName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanName.isEmpty else { return }

        let targetPath: String
        if currentPath.isEmpty || currentPath == "/" {
            targetPath = cleanName
        } else {
            let cleanParent = currentPath.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            targetPath = "\(cleanParent)/\(cleanName)"
        }

        Task {
            do {
                if let dropbox = provider as? DropboxStorageProvider {
                    try await dropbox.createAccountFolder(at: targetPath)
                } else {
                    try await provider.createDirectory(at: targetPath)
                }
                await loadFolders()
            } catch {
                await MainActor.run {
                    self.errorMessage = "Erreur création dossier : \(error.localizedDescription)"
                }
            }
        }
    }
}
