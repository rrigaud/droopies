//
//  StudentsManagementView.swift
//  Dropies
//
//  Section Administrative : Gestion complète des élèves, des classes,
//  création automatique des dossiers physiques et impression des fiches QR code.
//

import SwiftUI

public struct StudentsManagementView: View {
    @Bindable public var appState: AppState

    @State private var selectedClassFilter: String = "Toutes"
    @State private var searchQuery: String = ""
    @State private var isAddStudentPresented: Bool = false
    @State private var studentToEdit: Student? = nil
    @State private var isCSVImportPresented: Bool = false
    @State private var isLabelsPresented: Bool = false
    @State private var showDeleteConfirmation: Bool = false
    @State private var studentToDelete: Student? = nil

    public init(appState: AppState) {
        self.appState = appState
    }

    private var filteredStudents: [Student] {
        var list = appState.students
        if selectedClassFilter != "Toutes" {
            list = list.filter { $0.classe == selectedClassFilter }
        }
        if !searchQuery.trimmingCharacters(in: .whitespaces).isEmpty {
            let q = searchQuery.lowercased()
            list = list.filter {
                $0.name.lowercased().contains(q) ||
                $0.login.lowercased().contains(q) ||
                $0.classe.lowercased().contains(q)
            }
        }
        return list.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    public var body: some View {
        VStack(spacing: 0) {
            // MARK: - Barre d'actions supérieure
            HStack(spacing: 12) {
                // Recherche
                HStack {
                    Image(systemName: "magnifyingglass")
                        .foregroundColor(.secondary)
                    TextField("Rechercher un élève, identifiant...", text: $searchQuery)
                        .textFieldStyle(.plain)
                    if !searchQuery.isEmpty {
                        Button {
                            searchQuery = ""
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundColor(.secondary)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(Color(white: 0.5, opacity: 0.08))
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .frame(maxWidth: 280)

                Spacer()

                // Boutons d'action rapides
                Button {
                    isAddStudentPresented = true
                } label: {
                    Label("Ajouter", systemImage: "person.badge.plus")
                }
                .buttonStyle(.borderedProminent)

                Button {
                    isCSVImportPresented = true
                } label: {
                    Label("Importer CSV", systemImage: "arrow.down.doc")
                }
                .buttonStyle(.bordered)

                Menu {
                    Button {
                        Task { try? await appState.generateMissingFolders() }
                    } label: {
                        Label("Créer les dossiers physiques manquants", systemImage: "folder.badge.plus")
                    }

                    Button {
                        Task { try? await appState.generateRandomPasswords() }
                    } label: {
                        Label("Générer de nouveaux mots de passe", systemImage: "key.fill")
                    }

                    Divider()

                    Button {
                        isLabelsPresented = true
                    } label: {
                        Label("Imprimer les fiches de connexion (QR)", systemImage: "printer.fill")
                    }
                } label: {
                    Label("Outils", systemImage: "ellipsis.circle")
                }
                .buttonStyle(.bordered)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(Color(white: 0.5, opacity: 0.04))

            Divider()

            // MARK: - Onglets de filtrage par classe
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    classFilterChip(title: "Toutes", count: appState.students.count)

                    ForEach(appState.classes) { group in
                        classFilterChip(title: group.name, count: group.count)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
            }
            .background(Color(white: 0.5, opacity: 0.02))

            Divider()

            // MARK: - Tableau des élèves
            if filteredStudents.isEmpty {
                VStack(spacing: 14) {
                    Image(systemName: "person.2.slash")
                        .font(.system(size: 48))
                        .foregroundColor(.secondary)
                    Text("Aucun élève trouvé")
                        .font(.headline)
                    Text("Ajoutez un premier élève ou importez un fichier CSV de votre classe.")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                VStack(spacing: 0) {
                    // En-tête des colonnes
                    HStack {
                        Text("Nom & Prénom").frame(maxWidth: .infinity, alignment: .leading)
                        Text("Classe").frame(width: 80, alignment: .center)
                        Text("Genre").frame(width: 60, alignment: .center)
                        Text("Identifiant").frame(width: 140, alignment: .leading)
                        Text("Mot de passe").frame(width: 130, alignment: .leading)
                        Text("Dossier Cloud").frame(width: 120, alignment: .center)
                        Text("Actions").frame(width: 80, alignment: .trailing)
                    }
                    .font(.caption.bold())
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(Color(white: 0.5, opacity: 0.06))

                    Divider()

                    List {
                        ForEach(filteredStudents) { student in
                            HStack {
                                Text(student.name)
                                    .fontWeight(.medium)
                                    .frame(maxWidth: .infinity, alignment: .leading)

                                BadgeView(student.classe, style: .info)
                                    .frame(width: 80, alignment: .center)

                                Text(student.gender)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                    .frame(width: 60, alignment: .center)

                                Text(student.login)
                                    .font(.system(.caption, design: .monospaced))
                                    .foregroundColor(.secondary)
                                    .frame(width: 140, alignment: .leading)

                                Text(student.password)
                                    .font(.system(.caption, design: .monospaced))
                                    .foregroundColor(.secondary)
                                    .frame(width: 130, alignment: .leading)

                                Group {
                                    if student.urlDropbox != nil {
                                        BadgeView("Lien OK", icon: "link", style: .success)
                                    } else {
                                        BadgeView("Local", icon: "folder", style: .neutral)
                                    }
                                }
                                .frame(width: 120, alignment: .center)

                                HStack(spacing: 8) {
                                    Button {
                                        studentToEdit = student
                                    } label: {
                                        Image(systemName: "pencil")
                                            .foregroundColor(.blue)
                                    }
                                    .buttonStyle(.plain)

                                    Button {
                                        studentToDelete = student
                                        showDeleteConfirmation = true
                                    } label: {
                                        Image(systemName: "trash")
                                            .foregroundColor(.red)
                                    }
                                    .buttonStyle(.plain)
                                }
                                .frame(width: 80, alignment: .trailing)
                            }
                            .padding(.vertical, 4)
                        }
                    }
                    .listStyle(.plain)
                }
            }
        }
        .sheet(isPresented: $isAddStudentPresented) {
            StudentEditSheet(appState: appState)
        }
        .sheet(item: $studentToEdit) { student in
            StudentEditSheet(appState: appState, studentToEdit: student)
        }
        .sheet(isPresented: $isCSVImportPresented) {
            CSVImportWizardSheet(appState: appState)
        }
        .sheet(isPresented: $isLabelsPresented) {
            StudentLabelsView(appState: appState)
        }
        .confirmationDialog(
            "Supprimer cet élève ?",
            isPresented: $showDeleteConfirmation,
            titleVisibility: .visible
        ) {
            Button("Supprimer", role: .destructive) {
                if let s = studentToDelete {
                    Task { try? await appState.deleteStudent(s) }
                }
            }
            Button("Annuler", role: .cancel) {}
        } message: {
            if let s = studentToDelete {
                Text("Voulez-vous vraiment supprimer \(s.name) de la base eleves.json ?")
            }
        }
    }

    @ViewBuilder
    private func classFilterChip(title: String, count: Int) -> some View {
        let isSelected = selectedClassFilter == title
        Button {
            selectedClassFilter = title
        } label: {
            HStack(spacing: 6) {
                Text(title)
                    .fontWeight(isSelected ? .bold : .medium)
                Text("\(count)")
                    .font(.caption2)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(isSelected ? Color.white.opacity(0.3) : Color.secondary.opacity(0.15))
                    .clipShape(Capsule())
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(isSelected ? Color.blue : Color(white: 0.5, opacity: 0.08))
            .foregroundColor(isSelected ? .white : .primary)
            .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}
