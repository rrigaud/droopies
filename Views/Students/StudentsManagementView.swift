//
//  StudentsManagementView.swift
//  Dropies
//
//  Section Administrative : Gestion complète des élèves, des classes,
//  création automatique des dossiers physiques et impression des fiches QR code.
//  Sublimé avec Liquid Glass et gestion modale robuste par ActiveSheet.
//

import SwiftUI

public struct StudentsManagementView: View {
    @Bindable public var appState: AppState

    public enum ActiveSheet: Identifiable {
        case addStudent
        case editStudent(Student)
        case csvImport
        case labels

        public var id: String {
            switch self {
            case .addStudent: return "add"
            case .editStudent(let s): return "edit-\(s.id)"
            case .csvImport: return "csv"
            case .labels: return "labels"
            }
        }
    }

    @State private var selectedClassFilter: String = "Toutes"
    @State private var searchQuery: String = ""
    @State private var activeSheet: ActiveSheet? = nil
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
                .background(Color.primary.opacity(0.06))
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .frame(maxWidth: 280)

                Spacer()

                // Boutons d'action rapides
                Button {
                    activeSheet = .addStudent
                } label: {
                    Label("Ajouter un élève", systemImage: "person.badge.plus")
                }
                .buttonStyle(VibrantGradientButtonStyle(gradient: .electricBlue, isCompact: true))

                Button {
                    activeSheet = .csvImport
                } label: {
                    Label("Importer CSV", systemImage: "arrow.down.doc")
                        .font(.system(size: 13, weight: .semibold))
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
                        activeSheet = .labels
                    } label: {
                        Label("Imprimer les fiches de connexion (QR)", systemImage: "printer.fill")
                    }
                } label: {
                    Label("Outils", systemImage: "ellipsis.circle")
                        .font(.system(size: 13, weight: .semibold))
                }
                .buttonStyle(.bordered)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(.ultraThinMaterial)

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

            Divider()

            // MARK: - Liste des élèves
            if filteredStudents.isEmpty {
                VStack(spacing: 16) {
                    Spacer()
                    Image(systemName: "person.2.slash")
                        .font(.system(size: 48))
                        .foregroundColor(.secondary)

                    if appState.students.isEmpty {
                        Text("Aucun élève dans la base eleves.json")
                            .font(.headline)
                        Text("Importez un fichier CSV (Pronote / Siècle) ou ajoutez manuellement vos premiers élèves.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                            .frame(maxWidth: 400)

                        Button {
                            activeSheet = .addStudent
                        } label: {
                            Label("Ajouter un premier élève", systemImage: "person.badge.plus")
                        }
                        .buttonStyle(VibrantGradientButtonStyle(gradient: .electricBlue))
                    } else {
                        Text("Aucun élève ne correspond à votre recherche")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                }
            } else {
                VStack(spacing: 0) {
                    // En-têtes du tableau
                    HStack {
                        Text("Nom & Prénom")
                            .font(.caption.bold())
                            .foregroundColor(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)

                        Text("Classe")
                            .font(.caption.bold())
                            .foregroundColor(.secondary)
                            .frame(width: 80, alignment: .center)

                        Text("Genre")
                            .font(.caption.bold())
                            .foregroundColor(.secondary)
                            .frame(width: 60, alignment: .center)

                        Text("Identifiant")
                            .font(.caption.bold())
                            .foregroundColor(.secondary)
                            .frame(width: 140, alignment: .leading)

                        Text("Mot de passe")
                            .font(.caption.bold())
                            .foregroundColor(.secondary)
                            .frame(width: 130, alignment: .leading)

                        Text("Dossier")
                            .font(.caption.bold())
                            .foregroundColor(.secondary)
                            .frame(width: 120, alignment: .center)

                        Text("Actions")
                            .font(.caption.bold())
                            .foregroundColor(.secondary)
                            .frame(width: 80, alignment: .trailing)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(Color.primary.opacity(0.04))

                    Divider()

                    List {
                        ForEach(filteredStudents) { student in
                            HStack {
                                Text(student.name)
                                    .fontWeight(.medium)
                                    .frame(maxWidth: .infinity, alignment: .leading)

                                BadgeView(student.classe, style: .info)
                                    .frame(width: 80, alignment: .center)

                                Text(student.gender.rawValue)
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
                                    if !student.urlDropbox.isEmpty {
                                        BadgeView("Lien OK", icon: "link", style: .success)
                                    } else {
                                        BadgeView("Local", icon: "folder", style: .neutral)
                                    }
                                }
                                .frame(width: 120, alignment: .center)

                                HStack(spacing: 8) {
                                    Button {
                                        activeSheet = .editStudent(student)
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
        .sheet(item: $activeSheet) { sheet in
            switch sheet {
            case .addStudent:
                StudentEditSheet(appState: appState)
            case .editStudent(let student):
                StudentEditSheet(appState: appState, studentToEdit: student)
            case .csvImport:
                CSVImportWizardSheet(appState: appState)
            case .labels:
                StudentLabelsView(appState: appState)
            }
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
            .background(isSelected ? Color.blue : Color.primary.opacity(0.06))
            .foregroundColor(isSelected ? .white : .primary)
            .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}
