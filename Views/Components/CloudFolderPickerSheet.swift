//
//  CloudFolderPickerSheet.swift
//  Droopies
//
//  Explorateur et sélecteur de dossier Source dans le Cloud.
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

    @State private var showCreateFolderDialog: Bool = false
    @State private var newFolderName: String = ""

    public init(provider: StorageProvider, initialPath: String = "", onSelect: @escaping (String) -> Void) {
        self.provider = provider
        self._currentPath = State(initialValue: initialPath.isEmpty ? "" : initialPath)
        self.onSelect = onSelect
    }

    private var cleanDisplayPath: String {
        currentPath.isEmpty ? "/" : (currentPath.hasPrefix("/") ? currentPath : "/\(currentPath)")
    }

    public var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // MARK: - Barre de navigation dans l'arborescence
                HStack(spacing: 10) {
                    Button {
                        navigateUp()
                    } label: {
                        Image(systemName: "arrow.up.circle.fill")
                            .font(.title3)
                            .foregroundColor(currentPath.isEmpty ? .secondary.opacity(0.3) : .blue)
                    }
                    .disabled(currentPath.isEmpty)
                    .buttonStyle(.plain)

                    HStack(spacing: 6) {
                        Image(systemName: provider.providerType.iconName)
                            .foregroundColor(.blue)
                        Text(cleanDisplayPath)
                            .font(.system(.subheadline, design: .monospaced, weight: .bold))
                            .lineLimit(1)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Color.primary.opacity(0.06))
                    .clipShape(RoundedRectangle(cornerRadius: 8))

                    Spacer()

                    // Bouton Créer un nouveau dossier
                    Button {
                        newFolderName = ""
                        showCreateFolderDialog = true
                    } label: {
                        Label("Nouveau dossier", systemImage: "folder.badge.plus")
                            .font(.caption.bold())
                    }
                    .buttonStyle(.bordered)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .background(.ultraThinMaterial)

                Divider()

                // MARK: - Liste des sous-dossiers
                if isLoading {
                    VStack(spacing: 12) {
                        Spacer()
                        ProgressView()
                            .scaleEffect(1.2)
                        Text("Chargement des dossiers...")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Spacer()
                    }
                } else if folders.isEmpty {
                    VStack(spacing: 14) {
                        Spacer()
                        Image(systemName: "folder")
                            .font(.system(size: 44))
                            .foregroundColor(.secondary.opacity(0.6))
                        Text("Aucun sous-dossier à cet emplacement")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                        Button {
                            newFolderName = ""
                            showCreateFolderDialog = true
                        } label: {
                            Label("Créer un dossier ici", systemImage: "plus.circle.fill")
                        }
                        .buttonStyle(.borderedProminent)
                        Spacer()
                    }
                } else {
                    List {
                        ForEach(folders) { item in
                            Button {
                                navigateInto(folder: item)
                            } label: {
                                HStack(spacing: 12) {
                                    Image(systemName: "folder.fill")
                                        .font(.title3)
                                        .foregroundColor(.blue)

                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(item.name)
                                            .font(.system(size: 14, weight: .medium))
                                            .foregroundColor(.primary)
                                    }

                                    Spacer()

                                    Image(systemName: "chevron.right")
                                        .font(.caption2.bold())
                                        .foregroundColor(.secondary.opacity(0.5))
                                }
                                .padding(.vertical, 4)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .listStyle(.plain)
                }

                if let err = errorMessage {
                    HStack(spacing: 8) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundColor(.red)
                        Text(err)
                            .font(.caption)
                            .foregroundColor(.red)
                    }
                    .padding(8)
                }

                Divider()

                // MARK: - Barre d'action inférieure (Sélection finale)
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Dossier Source qui sera utilisé :")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                        Text(cleanDisplayPath)
                            .font(.subheadline.bold())
                            .foregroundColor(.blue)
                    }

                    Spacer()

                    Button {
                        onSelect(cleanDisplayPath)
                        dismiss()
                    } label: {
                        Text("Sélectionner ce dossier")
                            .font(.subheadline.bold())
                    }
                    .buttonStyle(VibrantGradientButtonStyle(gradient: .emeraldGreen, isCompact: true))
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .background(.ultraThinMaterial)
            }
            .navigationTitle("Choisir le dossier Source")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Annuler") {
                        dismiss()
                    }
                }
            }
            .alert("Nouveau dossier", isPresented: $showCreateFolderDialog) {
                TextField("Nom du dossier (ex: Devoirs 2026)", text: $newFolderName)
                Button("Créer") {
                    createNewFolder(named: newFolderName)
                }
                Button("Annuler", role: .cancel) {}
            } message: {
                Text("Créez un nouveau dossier dans \(cleanDisplayPath)")
            }
            .task {
                await loadFolders()
            }
        }
        #if os(macOS)
        .frame(minWidth: 540, minHeight: 460)
        #endif
    }

    // MARK: - Navigation & Chargement

    private func loadFolders() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            let items = try await provider.listContents(at: currentPath)
            self.folders = items.filter { $0.isDirectory }.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        } catch {
            self.errorMessage = "Impossible de lister les dossiers : \(error.localizedDescription)"
        }
    }

    private func navigateInto(folder: CloudItem) {
        let clean = folder.name.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        if currentPath.isEmpty || currentPath == "/" {
            currentPath = "/\(clean)"
        } else {
            currentPath = "\(currentPath)/\(clean)"
        }
        Task { await loadFolders() }
    }

    private func navigateUp() {
        guard !currentPath.isEmpty && currentPath != "/" else { return }
        var components = currentPath.split(separator: "/").map(String.init)
        if !components.isEmpty {
            components.removeLast()
        }
        currentPath = components.isEmpty ? "" : "/\(components.joined(separator: "/"))"
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
                try await provider.createDirectory(at: targetPath)
                await loadFolders()
            } catch {
                await MainActor.run {
                    self.errorMessage = "Erreur création dossier : \(error.localizedDescription)"
                }
            }
        }
    }
}
