//
//  CloudCSVFilePickerSheet.swift
//  Droopies
//
//  Explorateur et sélecteur de fichier CSV natif dans le Cloud actif (Dropbox, OneDrive, etc.).
//  Permet de naviguer dans les dossiers et de sélectionner un fichier .csv ou .txt
//  pour l'importer directement dans Droopies.
//

import SwiftUI

public struct CloudCSVFilePickerSheet: View {
    @Environment(\.dismiss) private var dismiss
    public let provider: StorageProvider
    public var onSelect: (CloudItem) -> Void

    @State private var currentPath: String = ""
    @State private var items: [CloudItem] = []
    @State private var isLoading: Bool = false
    @State private var errorMessage: String? = nil
    @State private var searchText: String = ""

    public init(provider: StorageProvider, initialPath: String = "", onSelect: @escaping (CloudItem) -> Void) {
        self.provider = provider
        let clean = initialPath.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        self._currentPath = State(initialValue: clean.isEmpty ? "/" : "/\(clean)")
        self.onSelect = onSelect
    }

    private var cloudName: String {
        provider.providerType.displayName
    }

    private var currentFolderName: String {
        if currentPath.isEmpty || currentPath == "/" {
            return "Racine \(cloudName)"
        }
        return URL(fileURLWithPath: currentPath).lastPathComponent
    }

    /// Filtre les éléments : dossiers navigables et fichiers CSV
    private var filteredFolders: [CloudItem] {
        let q = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let folders = items.filter { $0.isDirectory }
        if q.isEmpty { return folders }
        return folders.filter { $0.name.lowercased().contains(q) }
    }

    private var filteredCSVFiles: [CloudItem] {
        let q = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let files = items.filter { item in
            if item.isDirectory { return false }
            let lower = item.name.lowercased()
            return lower.hasSuffix(".csv") || lower.hasSuffix(".txt")
        }
        if q.isEmpty { return files }
        return files.filter { $0.name.lowercased().contains(q) }
    }

    private var pathSegments: [(title: String, fullPath: String)] {
        var segments: [(title: String, fullPath: String)] = [(cloudName, "/")]
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
                // Fil d'Ariane & Navigation
                headerNavigation

                Divider()

                // Barre de recherche
                HStack {
                    Image(systemName: "magnifyingglass")
                        .foregroundColor(.secondary)
                    TextField("Rechercher un dossier ou fichier CSV...", text: $searchText)
                        .textFieldStyle(.plain)
                    if !searchText.isEmpty {
                        Button { searchText = "" } label: {
                            Image(systemName: "xmark.circle.fill").foregroundColor(.secondary)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(Color.primary.opacity(0.04))

                Divider()

                // Liste du contenu Cloud
                ZStack {
                    Color(white: 0.97)
                        .ignoresSafeArea()

                    if isLoading {
                        VStack(spacing: 12) {
                            ProgressView()
                                .controlSize(.large)
                            Text("Chargement du dossier Cloud...")
                                .font(.system(size: 13, weight: .medium))
                                .foregroundColor(.secondary)
                        }
                    } else if let error = errorMessage {
                        VStack(spacing: 12) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .font(.largeTitle)
                                .foregroundColor(.orange)
                            Text(error)
                                .font(.system(size: 13))
                                .foregroundColor(.secondary)
                                .multilineTextAlignment(.center)
                            Button("Réessayer") {
                                Task { await loadItems() }
                            }
                            .buttonStyle(.bordered)
                        }
                        .padding(24)
                    } else if filteredFolders.isEmpty && filteredCSVFiles.isEmpty {
                        VStack(spacing: 12) {
                            Image(systemName: "doc.text.magnifyingglass")
                                .font(.system(size: 40))
                                .foregroundColor(.secondary.opacity(0.4))
                            Text("Aucun fichier CSV dans ce dossier")
                                .font(.headline)
                                .foregroundColor(.secondary)
                            Text("Naviguez dans un sous-dossier ou chargez votre CSV depuis un autre emplacement.")
                                .font(.caption)
                                .foregroundColor(.secondary.opacity(0.8))
                                .multilineTextAlignment(.center)
                        }
                        .padding(32)
                    } else {
                        List {
                            // Section 1 : Fichiers CSV détectés (Priorité)
                            if !filteredCSVFiles.isEmpty {
                                Section("Fichiers CSV à importer (\(filteredCSVFiles.count))") {
                                    ForEach(filteredCSVFiles) { file in
                                        Button {
                                            onSelect(file)
                                            dismiss()
                                        } label: {
                                            HStack(spacing: 12) {
                                                Image(systemName: "doc.text.fill")
                                                    .font(.title2)
                                                    .foregroundColor(.blue)

                                                VStack(alignment: .leading, spacing: 2) {
                                                    Text(file.name)
                                                        .font(.system(size: 14, weight: .semibold))
                                                        .foregroundColor(.primary)

                                                    HStack(spacing: 8) {
                                                        if let size = file.size {
                                                            Text(formatFileSize(size))
                                                                .font(.caption2)
                                                                .foregroundColor(.secondary)
                                                        }
                                                        Text("Fichier CSV")
                                                            .font(.caption2.bold())
                                                            .foregroundColor(.blue)
                                                    }
                                                }

                                                Spacer()

                                                Text("Sélectionner")
                                                    .font(.system(size: 12, weight: .semibold))
                                                    .padding(.horizontal, 10)
                                                    .padding(.vertical, 5)
                                                    .background(Color.blue)
                                                    .foregroundColor(.white)
                                                    .clipShape(Capsule())
                                            }
                                            .padding(.vertical, 4)
                                        }
                                        .buttonStyle(.plain)
                                    }
                                }
                            }

                            // Section 2 : Dossiers navigables
                            if !filteredFolders.isEmpty {
                                Section("Dossiers (\(filteredFolders.count))") {
                                    ForEach(filteredFolders) { folder in
                                        Button {
                                            currentPath = folder.path
                                            Task { await loadItems() }
                                        } label: {
                                            HStack(spacing: 12) {
                                                if folder.name.lowercased() == "configuration" {
                                                    Image(systemName: "folder.badge.gearshape")
                                                        .font(.title3)
                                                        .foregroundColor(.blue)
                                                } else {
                                                    Image(systemName: "folder.fill")
                                                        .font(.title3)
                                                        .foregroundColor(.blue.opacity(0.8))
                                                }

                                                VStack(alignment: .leading, spacing: 2) {
                                                    HStack(spacing: 6) {
                                                        Text(folder.name)
                                                            .font(.system(size: 14, weight: .medium))
                                                            .foregroundColor(.primary)

                                                        if folder.name.lowercased() == "configuration" {
                                                            Text("Configuration & CSV")
                                                                .font(.system(size: 10, weight: .bold))
                                                                .padding(.horizontal, 6)
                                                                .padding(.vertical, 2)
                                                                .background(Color.blue.opacity(0.12))
                                                                .foregroundColor(.blue)
                                                                .clipShape(Capsule())
                                                        }
                                                    }

                                                    Text("Dossier")
                                                        .font(.caption2)
                                                        .foregroundColor(.secondary)
                                                }

                                                Spacer()

                                                Image(systemName: "chevron.right")
                                                    .font(.caption.bold())
                                                    .foregroundColor(.secondary.opacity(0.4))
                                            }
                                            .padding(.vertical, 4)
                                        }
                                        .buttonStyle(.plain)
                                    }
                                }
                            }
                        }
                        #if os(iOS)
                        .listStyle(.insetGrouped)
                        #else
                        .listStyle(.inset)
                        #endif
                    }
                }
            }
            .navigationTitle("Fichier CSV sur \(cloudName)")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Fermer") {
                        dismiss()
                    }
                }
            }
            .task {
                await loadItems()
            }
        }
        #if os(macOS)
        .frame(minWidth: 550, minHeight: 480)
        #endif
    }

    private var headerNavigation: some View {
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

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(Array(pathSegments.enumerated()), id: \.offset) { index, segment in
                            let isLast = index == pathSegments.count - 1
                            Button {
                                if !isLast {
                                    currentPath = segment.fullPath
                                    Task { await loadItems() }
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
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    private func navigateUp() {
        guard !currentPath.isEmpty && currentPath != "/" else { return }
        let parent = URL(fileURLWithPath: currentPath).deletingLastPathComponent().path
        currentPath = (parent.isEmpty || parent == ".") ? "/" : parent
        Task { await loadItems() }
    }

    private func loadItems() async {
        isLoading = true
        errorMessage = nil
        do {
            let loaded = try await provider.listContents(at: currentPath)
            await MainActor.run {
                self.items = loaded
                self.isLoading = false
            }
        } catch {
            // Repli automatique sur le dossier parent si le sous-dossier initial n'existe pas encore
            if currentPath != "/" && !currentPath.isEmpty {
                let parent = URL(fileURLWithPath: currentPath).deletingLastPathComponent().path
                let fallbackPath = (parent.isEmpty || parent == ".") ? "/" : parent
                if let fallbackItems = try? await provider.listContents(at: fallbackPath) {
                    await MainActor.run {
                        self.currentPath = fallbackPath
                        self.items = fallbackItems
                        self.isLoading = false
                    }
                    return
                }
            }
            await MainActor.run {
                self.errorMessage = "Impossible de lire le contenu de \(cloudName) : \(error.localizedDescription)"
                self.isLoading = false
            }
        }
    }

    private func formatFileSize(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useKB, .useMB]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: bytes)
    }
}
