//
//  StudentsManagementView.swift
//  Droopies
//
//  Section Administrative : Gestion complète des élèves et des classes.
//  - Colonnes dans l'ordre : Classe, Nom, Sexe, Identifiant, Mot de passe, Dossier, Partage, URL, Actions
//  - Mode sélection multiple native avec Barre d'actions groupées (Batch Actions) flottante
//  - Synchronisation continue avec le Cloud et génération instantanée des mots de passe.
//

import SwiftUI
import UniformTypeIdentifiers

#if canImport(AppKit)
import AppKit
#elseif canImport(UIKit)
import UIKit
#endif

public struct StudentsManagementView: View {
    @Bindable public var appState: AppState

    public enum ActiveSheet: Identifiable {
        case editStudent(Student)
        case passwordGen(Set<Int>)
        case teacherMemo(Set<Int>)
        case labels(Set<Int>)
        case shareFile(URL)

        public var id: String {
            switch self {
            case .editStudent(let s): return "edit-\(s.id)"
            case .passwordGen(let ids): return "pwd-\(ids.count)"
            case .teacherMemo(let ids): return "memo-\(ids.count)"
            case .labels(let ids): return "labels-\(ids.count)"
            case .shareFile(let url): return "share-\(url.lastPathComponent)"
            }
        }
    }

    // Filtres et recherche
    @State private var selectedClassFilter: String = "Toutes"
    @State private var searchQuery: String = ""

    // Sélection multiple
    @State private var isSelectionMode: Bool = false
    @State private var selectedStudentIds: Set<Int> = []

    // Modales & Confirmations
    @State private var activeSheet: ActiveSheet? = nil
    @State private var showDeleteConfirmation: Bool = false
    @State private var studentToDelete: Student? = nil
    @State private var showBatchDeleteConfirmation: Bool = false
    @State private var copiedUrlStudentId: Int? = nil
    @State private var toastMessage: String? = nil
    @State private var isExportingCSV: Bool = false

    // Mode Accordéon pour affichage compact / Portrait
    @State private var expandedStudentIds: Set<Int> = []

    // État réel de l'existence des dossiers Cloud et du nombre de copies
    public enum StudentFolderStatus: Equatable {
        case checking
        case exists(copies: Int)
        case missing
    }
    @State private var folderStatuses: [Int: StudentFolderStatus] = [:]

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
        return list.sorted {
            if $0.classe == $1.classe {
                return $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
            }
            return $0.classe < $1.classe
        }
    }

    private var allFilteredAreSelected: Bool {
        let ids = Set(filteredStudents.map { $0.id })
        return !ids.isEmpty && ids.isSubset(of: selectedStudentIds)
    }

    public var body: some View {
        GeometryReader { geometry in
            let isCompact = geometry.size.width < 960

            ZStack(alignment: .bottom) {
                ScrollView {
                    VStack(spacing: 12) {
                        // MARK: - Barre de Filtre par Classe, Recherche & Sélection
                        classesFilterBar(isCompact: isCompact)
                            #if os(iOS)
                            .padding(.top, -12)
                            #else
                            .padding(.top, 12)
                            #endif

                        // MARK: - Tableau des élèves (Adaptatif : Accordéon si Portrait/Compact, Grand Tableau si Paysage/Large)
                        if isCompact {
                            studentsCompactAccordionView
                        } else {
                            studentsTableView
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 80)
                }
                .background(Color.clear)

                // MARK: - Barre d'Actions Groupées Flottante (Liquid Glass Batch Bar)
                if isSelectionMode && !selectedStudentIds.isEmpty && appState.isOnline {
                    floatingBatchActionBar(isCompact: isCompact)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                        .padding(.bottom, 20)
                }

                // MARK: - Toast de Confirmation Flottant
                if let toast = toastMessage {
                    HStack(spacing: 8) {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(.green)
                        Text(toast)
                            .font(.system(size: 13, weight: .semibold))
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(Capsule().fill(.ultraThinMaterial))
                    .overlay(Capsule().stroke(Color.primary.opacity(0.12), lineWidth: 1))
                    .shadow(color: .black.opacity(0.15), radius: 10, y: 5)
                    .padding(.bottom, (isSelectionMode && !selectedStudentIds.isEmpty) ? 80 : 24)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .zIndex(50)
                }
            }
        }
        .sheet(item: $activeSheet) { sheet in
            switch sheet {
            case .editStudent(let student):
                StudentEditSheet(appState: appState, studentToEdit: student)
            case .passwordGen(let ids):
                PasswordGenerationSheet(appState: appState, targetStudentIds: ids)
            case .teacherMemo(let ids):
                TeacherMemoSheet(appState: appState, targetStudentIds: ids) { url in
                    handleGeneratedPDF(url: url, title: "Mémo")
                }
            case .labels(let ids):
                StudentLabelsView(appState: appState, targetStudentIds: ids) { url in
                    handleGeneratedPDF(url: url, title: "Étiquettes")
                }
            case .shareFile(let url):
                #if os(iOS)
                ActivityView(activityItems: [url])
                #else
                EmptyView()
                #endif
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
                Text("Voulez-vous vraiment supprimer \(s.name) et son dossier Cloud ?")
            }
        }
        .confirmationDialog(
            "Supprimer les élèves sélectionnés ?",
            isPresented: $showBatchDeleteConfirmation,
            titleVisibility: .visible
        ) {
            Button("Supprimer (\(selectedStudentIds.count))", role: .destructive) {
                let toDelete = selectedStudentIds
                selectedStudentIds.removeAll()
                isSelectionMode = false
                Task { try? await appState.deleteStudents(ids: toDelete) }
            }
            Button("Annuler", role: .cancel) {}
        } message: {
            Text("Voulez-vous vraiment supprimer ces \(selectedStudentIds.count) élèves et leurs dossiers Cloud ? Cette action est irréversible.")
        }
        .task(id: appState.students) {
            await appState.autoSyncMissingFoldersAndShares()
            refreshAllFolderStatuses()
        }
        .onChange(of: appState.isOnline) { _, isOnline in
            if !isOnline && isSelectionMode {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                    isSelectionMode = false
                    selectedStudentIds.removeAll()
                }
            }
        }
    }

    // MARK: - Barre Unifiée : Recherche, Filtres de Classes & Sélection

    private func classesFilterBar(isCompact: Bool) -> some View {
        HStack(spacing: 10) {
            // MARK: - 1. Champ de Recherche à gauche
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(.secondary)
                    .font(.system(size: 13))
                TextField(isCompact ? "Rechercher..." : "Rechercher un élève, classe...", text: $searchQuery)
                    .textFieldStyle(.plain)
                    .font(.system(size: 13))
                if !searchQuery.isEmpty {
                    Button {
                        searchQuery = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.secondary)
                            .font(.system(size: 12))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 9)
            .padding(.vertical, 6)
            .background(Color.primary.opacity(0.06))
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .frame(width: isCompact ? 160 : 230)

            Divider()
                .frame(height: 18)
                .opacity(0.4)

            // MARK: - 2. Sélecteur de classes (Puces horizontales ou Menulist si Portrait & >4 classes)
            if isCompact && appState.classes.count > 4 {
                Menu {
                    Button {
                        selectedClassFilter = "Toutes"
                    } label: {
                        HStack {
                            Text("Toutes les classes (\(appState.students.count))")
                            if selectedClassFilter == "Toutes" {
                                Image(systemName: "checkmark")
                            }
                        }
                    }

                    Divider()

                    ForEach(appState.classes) { group in
                        Button {
                            selectedClassFilter = group.name
                        } label: {
                            HStack {
                                Text("\(group.name) (\(group.students.count) élèves)")
                                if selectedClassFilter == group.name {
                                    Image(systemName: "checkmark")
                                }
                            }
                        }
                    }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "line.3.horizontal.decrease.circle")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(.blue)

                        let currentCount = selectedClassFilter == "Toutes" ? appState.students.count : (appState.classes.first(where: { $0.name == selectedClassFilter })?.students.count ?? 0)
                        Text(selectedClassFilter == "Toutes" ? "Toutes les classes" : "Classe : \(selectedClassFilter)")
                            .font(.system(size: 12.5, weight: .semibold))
                            .foregroundColor(.primary)

                        Text("\(currentCount)")
                            .font(.system(size: 11, weight: .bold))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.blue.opacity(0.15))
                            .foregroundColor(.blue)
                            .clipShape(Capsule())

                        Image(systemName: "chevron.up.chevron.down")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundColor(.secondary)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Color.primary.opacity(0.06))
                    .clipShape(Capsule())
                }
                .buttonStyle(.plain)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        classFilterChip(title: "Toutes", count: appState.students.count)

                        ForEach(appState.classes) { group in
                            classFilterChip(title: group.name, count: group.students.count)
                        }
                    }
                    .padding(.vertical, 4)
                }
            }

            Spacer(minLength: 4)

            // MARK: - 3. Boutons d'Action / Mode Sélection ou Badge Hors-Ligne à droite
            HStack(spacing: 8) {
                if !appState.isOnline {
                    HStack(spacing: 5) {
                        Image(systemName: "bolt.slash.fill")
                            .font(.system(size: 11, weight: .bold))
                        Text("Lecture seule")
                            .font(.system(size: 11, weight: .bold))
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(Color.orange.opacity(0.15))
                    .foregroundColor(.orange)
                    .clipShape(Capsule())
                } else if isSelectionMode {
                    // "Tout sélectionner" placé immédiatement à gauche de "Terminé"
                    Button {
                        withAnimation {
                            if allFilteredAreSelected {
                                selectedStudentIds.removeAll()
                            } else {
                                selectedStudentIds = Set(filteredStudents.map { $0.id })
                            }
                        }
                    } label: {
                        Text(allFilteredAreSelected ? "Tout désélectionner" : "Tout sélectionner")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundColor(.blue)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 6)
                    }
                    .buttonStyle(.plain)

                    // "Terminé" toujours ancré à l'extrême droite
                    Button {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                            isSelectionMode = false
                            selectedStudentIds.removeAll()
                        }
                    } label: {
                        HStack(spacing: 5) {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.system(size: 12, weight: .bold))
                            Text("Terminé")
                                .font(.system(size: 12, weight: .semibold))
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.blue)
                } else {
                    Button {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                            isSelectionMode = true
                        }
                    } label: {
                        HStack(spacing: 5) {
                            Image(systemName: "checklist")
                                .font(.system(size: 12, weight: .semibold))
                            Text("Sélectionner")
                                .font(.system(size: 12, weight: .semibold))
                        }
                        .padding(.horizontal, 11)
                        .padding(.vertical, 6)
                    }
                    .buttonStyle(.bordered)
                    .clipShape(Capsule())
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(Color.clear)
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

    // MARK: - Tableau des Élèves (Colonnes dans l'ordre demandé)

    private var studentsTableView: some View {
        VStack(spacing: 0) {
            // En-tête du tableau
            HStack(spacing: 8) {
                if isSelectionMode {
                    Text("")
                        .frame(width: 28)
                }

                Text("Classe")
                    .font(.caption.bold())
                    .frame(width: 70, alignment: .center)

                Text("Nom & Prénom")
                    .font(.caption.bold())
                    .frame(maxWidth: .infinity, alignment: .leading)

                Text("Sexe")
                    .font(.caption.bold())
                    .frame(width: 50, alignment: .center)

                Text("Identifiant")
                    .font(.caption.bold())
                    .frame(width: 130, alignment: .leading)

                Text("Mot de passe")
                    .font(.caption.bold())
                    .frame(width: 130, alignment: .leading)

                Text("Dossier")
                    .font(.caption.bold())
                    .frame(width: 130, alignment: .center)

                Text("Partage")
                    .font(.caption.bold())
                    .frame(width: 80, alignment: .center)

                Text("URL")
                    .font(.caption.bold())
                    .frame(width: 70, alignment: .center)

                Text("Actions")
                    .font(.caption.bold())
                    .frame(width: 70, alignment: .trailing)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(Color.clear)

            if filteredStudents.isEmpty {
                emptyStudentsPlaceholder
            } else {
                LazyVStack(spacing: 6) {
                    ForEach(filteredStudents) { student in
                        studentRow(student: student)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 8)
                            .background(
                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .fill(
                                        selectedStudentIds.contains(student.id)
                                            ? Color.blue.opacity(0.12)
                                            : Color.primary.opacity(0.025)
                                    )
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .stroke(
                                        selectedStudentIds.contains(student.id)
                                            ? Color.blue.opacity(0.4)
                                            : Color.primary.opacity(0.06),
                                        lineWidth: 1
                                    )
                            )
                    }
                }
            }
        }
    }

    // MARK: - Vue Accordéon Compacte (Mode Portrait & Écrans Étroits)

    private var studentsCompactAccordionView: some View {
        VStack(spacing: 0) {
            // En-tête simplifié pour la vue compacte
            HStack(spacing: 10) {
                if isSelectionMode {
                    Text("")
                        .frame(width: 28)
                }

                Text("Classe")
                    .font(.caption.bold())
                    .frame(width: 58, alignment: .center)

                Text("Élève (\(filteredStudents.count))")
                    .font(.caption.bold())
                    .frame(maxWidth: .infinity, alignment: .leading)

                Text("Statut Cloud")
                    .font(.caption.bold())
                    .frame(width: 110, alignment: .center)

                Text("")
                    .frame(width: 24)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 6)
            .background(Color.clear)

            if filteredStudents.isEmpty {
                emptyStudentsPlaceholder
            } else {
                LazyVStack(spacing: 8) {
                    ForEach(filteredStudents) { student in
                        studentCompactAccordionCard(student: student)
                    }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
            }
        }
    }

    // MARK: - Carte Accordéon Élève (Option 3 Native)

    @ViewBuilder
    private func studentCompactAccordionCard(student: Student) -> some View {
        let isExpanded = expandedStudentIds.contains(student.id)
        let isSelected = selectedStudentIds.contains(student.id)

        VStack(spacing: 0) {
            // Ligne principale (Toujours visible et aérée)
            HStack(spacing: 10) {
                // Case de sélection
                if isSelectionMode {
                    Button {
                        withAnimation(.spring(response: 0.25, dampingFraction: 0.7)) {
                            if selectedStudentIds.contains(student.id) {
                                selectedStudentIds.remove(student.id)
                            } else {
                                selectedStudentIds.insert(student.id)
                            }
                        }
                    } label: {
                        Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                            .font(.system(size: 19))
                            .foregroundColor(isSelected ? .blue : .secondary.opacity(0.5))
                    }
                    .buttonStyle(.plain)
                    .frame(width: 28)
                }

                // 1. Badge Classe
                BadgeView(student.classe, style: .info)
                    .frame(width: 58, alignment: .center)

                // 2. Nom & Prénom (Priorité absolue avec tout l'espace disponible)
                Text(student.name)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(.primary)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)

                // 3. Statut Cloud compact combiné
                compactCloudStatusBadge(for: student)
                    .frame(width: 110, alignment: .center)

                // 4. Chevron interactif avec rotation fluide
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.secondary)
                    .rotationEffect(.degrees(isExpanded ? 90 : 0))
                    .frame(width: 24, alignment: .center)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .contentShape(Rectangle())
            .onTapGesture {
                withAnimation(.spring(response: 0.32, dampingFraction: 0.82)) {
                    if isExpanded {
                        expandedStudentIds.remove(student.id)
                    } else {
                        expandedStudentIds.insert(student.id)
                    }
                }
            }

            // Panneau dépliable avec détails complets natifs
            if isExpanded {
                VStack(spacing: 12) {
                    Divider()
                        .padding(.horizontal, 10)

                    // 2 Cartes côte à côte (Identifiants & Cloud)
                    HStack(alignment: .top, spacing: 12) {
                        // Carte Identifiants
                        VStack(alignment: .leading, spacing: 8) {
                            HStack(spacing: 6) {
                                Image(systemName: "person.text.rectangle")
                                    .foregroundColor(.blue)
                                Text("CONNEXION ÉLÈVE")
                                    .font(.system(size: 10, weight: .bold))
                                    .foregroundColor(.secondary)
                            }

                            HStack(spacing: 6) {
                                Text("Identifiant :")
                                    .font(.system(size: 12))
                                    .foregroundColor(.secondary)
                                Text(student.login)
                                    .font(.system(size: 12, weight: .bold, design: .monospaced))
                                    .foregroundColor(.primary)
                                Spacer()
                                Button {
                                    copyToClipboard(student.login, for: student.id)
                                } label: {
                                    Image(systemName: copiedUrlStudentId == student.id ? "checkmark" : "doc.on.doc")
                                        .font(.system(size: 11))
                                        .foregroundColor(.blue)
                                }
                                .buttonStyle(.plain)
                            }

                            HStack(spacing: 6) {
                                Text("Mot de passe :")
                                    .font(.system(size: 12))
                                    .foregroundColor(.secondary)
                                Text(student.password)
                                    .font(.system(size: 12, weight: .bold, design: .monospaced))
                                    .foregroundColor(.blue)
                                Spacer()
                                Button {
                                    copyToClipboard(student.password, for: student.id)
                                } label: {
                                    Image(systemName: copiedUrlStudentId == student.id ? "checkmark" : "doc.on.doc")
                                        .font(.system(size: 11))
                                        .foregroundColor(.blue)
                                }
                                .buttonStyle(.plain)
                            }

                            HStack(spacing: 6) {
                                Text("Genre :")
                                    .font(.system(size: 12))
                                    .foregroundColor(.secondary)
                                Text(student.gender == .female ? "Fille (F)" : "Garçon (M)")
                                    .font(.system(size: 12, weight: .medium))
                                    .foregroundColor(student.gender == .female ? .pink : .blue)
                            }
                        }
                        .padding(10)
                        .background(Color.primary.opacity(0.03))
                        .clipShape(RoundedRectangle(cornerRadius: 10))

                        // Carte Dossier Cloud & Partage
                        VStack(alignment: .leading, spacing: 8) {
                            HStack(spacing: 6) {
                                Image(systemName: "icloud.fill")
                                    .foregroundColor(.indigo)
                                Text("DOSSIER & PARTAGE")
                                    .font(.system(size: 10, weight: .bold))
                                    .foregroundColor(.secondary)
                            }

                            HStack(spacing: 6) {
                                Text("Dossier :")
                                    .font(.system(size: 12))
                                    .foregroundColor(.secondary)
                                folderStatusView(for: student)
                            }

                            HStack(spacing: 6) {
                                Text("Partage :")
                                    .font(.system(size: 12))
                                    .foregroundColor(.secondary)
                                if !student.urlDropbox.isEmpty {
                                    BadgeView("Actif", icon: "link", style: .success)
                                } else {
                                    BadgeView("En cours", style: .warning)
                                }
                            }

                            if !student.urlDropbox.isEmpty {
                                Button {
                                    copyToClipboard(student.urlDropbox, for: student.id)
                                } label: {
                                    HStack(spacing: 4) {
                                        Image(systemName: copiedUrlStudentId == student.id ? "checkmark" : "link")
                                        Text(copiedUrlStudentId == student.id ? "Lien copié !" : "Copier l'URL Cloud")
                                    }
                                    .font(.system(size: 11, weight: .semibold))
                                }
                                .buttonStyle(.bordered)
                                .controlSize(.mini)
                            }
                        }
                        .padding(10)
                        .background(Color.primary.opacity(0.03))
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                    }
                    .padding(.horizontal, 10)

                    // Barre d'actions rapides (Modifier / Supprimer)
                    HStack(spacing: 12) {
                        Spacer()

                        Button {
                            if appState.isOnline {
                                activeSheet = .editStudent(student)
                            }
                        } label: {
                            Label("Modifier", systemImage: "pencil")
                                .font(.system(size: 12, weight: .semibold))
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .disabled(!appState.isOnline)
                        .opacity(appState.isOnline ? 1.0 : 0.45)

                        Button(role: .destructive) {
                            if appState.isOnline {
                                studentToDelete = student
                                showDeleteConfirmation = true
                            }
                        } label: {
                            Label("Supprimer", systemImage: "trash")
                                .font(.system(size: 12, weight: .semibold))
                        }
                        .buttonStyle(.bordered)
                        .tint(.red)
                        .controlSize(.small)
                        .disabled(!appState.isOnline)
                        .opacity(appState.isOnline ? 1.0 : 0.45)
                    }
                    .padding(.horizontal, 12)
                    .padding(.bottom, 10)
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(isSelected ? Color.blue.opacity(0.07) : (isExpanded ? Color.primary.opacity(0.03) : Color.primary.opacity(0.015)))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(isSelected ? Color.blue.opacity(0.35) : (isExpanded ? Color.blue.opacity(0.2) : Color.primary.opacity(0.08)), lineWidth: 1)
        )
    }

    // MARK: - Placeholder si aucun élève

    private var emptyStudentsPlaceholder: some View {
        VStack(spacing: 12) {
            Image(systemName: "person.2.slash")
                .font(.system(size: 40))
                .foregroundColor(.secondary.opacity(0.5))

            Text("Aucun élève trouvé")
                .font(.headline)
                .foregroundColor(.secondary)

            Text("Ajoutez des élèves manuellement ou importez un fichier CSV pour démarrer.")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.top, 60)
    }

    // MARK: - Ligne Élève

    @ViewBuilder
    private func studentRow(student: Student) -> some View {
        HStack(spacing: 8) {
            // Case de sélection
            if isSelectionMode {
                Button {
                    withAnimation(.spring(response: 0.25, dampingFraction: 0.7)) {
                        if selectedStudentIds.contains(student.id) {
                            selectedStudentIds.remove(student.id)
                        } else {
                            selectedStudentIds.insert(student.id)
                        }
                    }
                } label: {
                    Image(systemName: selectedStudentIds.contains(student.id) ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 18))
                        .foregroundColor(selectedStudentIds.contains(student.id) ? .blue : .secondary.opacity(0.5))
                }
                .buttonStyle(.plain)
                .frame(width: 28)
            }

            // 1. Classe
            BadgeView(student.classe, style: .info)
                .frame(width: 70, alignment: .center)

            // 2. Nom & Prénom
            Text(student.name)
                .font(.system(size: 14, weight: .semibold))
                .frame(maxWidth: .infinity, alignment: .leading)

            // 3. Sexe
            Text(student.gender == .female ? "F" : "M")
                .font(.caption2.bold())
                .foregroundColor(student.gender == .female ? .pink : .blue)
                .frame(width: 50, alignment: .center)

            // 4. Identifiant
            Text(student.login)
                .font(.system(.caption, design: .monospaced))
                .foregroundColor(.secondary)
                .frame(width: 130, alignment: .leading)
                .lineLimit(1)

            // 5. Mot de passe
            Text(student.password)
                .font(.system(.caption, design: .monospaced, weight: .medium))
                .foregroundColor(.secondary)
                .frame(width: 130, alignment: .leading)
                .lineLimit(1)

            // 6. Dossier Cloud (Gestion 100% automatique)
            folderStatusView(for: student)
                .frame(width: 130, alignment: .center)

            // 7. Partage (Gestion 100% automatique)
            Group {
                if !student.urlDropbox.isEmpty {
                    BadgeView("Actif", icon: "link", style: .success)
                } else {
                    HStack(spacing: 4) {
                        ProgressView()
                            .controlSize(.mini)
                        Text("Création...")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundColor(.blue)
                    }
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(Color.blue.opacity(0.1))
                    .clipShape(Capsule())
                }
            }
            .frame(width: 80, alignment: .center)

            // 8. URL (Bouton copier / ouvrir)
            Group {
                if !student.urlDropbox.isEmpty {
                    Button {
                        copyToClipboard(student.urlDropbox, for: student.id)
                    } label: {
                        HStack(spacing: 2) {
                            Image(systemName: copiedUrlStudentId == student.id ? "checkmark" : "doc.on.doc")
                                .font(.caption2)
                            Text(copiedUrlStudentId == student.id ? "Copié" : "Copier")
                                .font(.system(size: 10, weight: .semibold))
                        }
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(Color.blue.opacity(0.1))
                        .foregroundColor(.blue)
                        .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                } else {
                    Text("—")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .frame(width: 70, alignment: .center)

            // 9. Actions (Modifier / Supprimer)
            HStack(spacing: 8) {
                Button {
                    if appState.isOnline {
                        activeSheet = .editStudent(student)
                    }
                } label: {
                    Image(systemName: "pencil")
                        .foregroundColor(appState.isOnline ? .blue : .secondary)
                }
                .buttonStyle(.plain)
                .disabled(!appState.isOnline)
                .opacity(appState.isOnline ? 1.0 : 0.45)

                Button {
                    if appState.isOnline {
                        studentToDelete = student
                        showDeleteConfirmation = true
                    }
                } label: {
                    Image(systemName: "trash")
                        .foregroundColor(appState.isOnline ? .red : .secondary)
                }
                .buttonStyle(.plain)
                .disabled(!appState.isOnline)
                .opacity(appState.isOnline ? 1.0 : 0.45)
            }
            .frame(width: 70, alignment: .trailing)
        }
        .padding(.vertical, 4)
    }

    // MARK: - Barre d'Actions Groupées Flottante (Floating Batch Bar)

    private func floatingBatchActionBar(isCompact: Bool) -> some View {
        HStack(spacing: isCompact ? 8 : 12) {
            HStack(spacing: 6) {
                Text("\(selectedStudentIds.count)")
                    .font(.system(size: 12, weight: .bold))
                    .padding(.horizontal, 7)
                    .padding(.vertical, 2)
                    .background(Color.white)
                    .foregroundColor(Color.blue)
                    .clipShape(Capsule())

                if !isCompact {
                    Text("sélectionné(s)")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.white)
                }
            }
            .padding(.trailing, 2)

            Divider()
                .frame(height: 20)
                .background(Color.white.opacity(0.3))

            // 1. Mots de passe
            Button {
                if appState.isOnline {
                    activeSheet = .passwordGen(selectedStudentIds)
                }
            } label: {
                Label(isCompact ? "MDP" : "Mots de passe", systemImage: "key.fill")
                    .font(.system(size: 12, weight: .semibold))
            }
            .buttonStyle(.bordered)
            .tint(.white)
            .disabled(!appState.isOnline)
            .opacity(appState.isOnline ? 1.0 : 0.45)

            // 2. Étiquettes de connexion QR
            Button {
                activeSheet = .labels(selectedStudentIds)
            } label: {
                Label(isCompact ? "QR Codes" : appState.t(.labelsBatchTitle), systemImage: "qrcode")
                    .font(.system(size: 12, weight: .semibold))
            }
            .buttonStyle(.bordered)
            .tint(.white)

            // 3. Mémo enseignant
            Button {
                activeSheet = .teacherMemo(selectedStudentIds)
            } label: {
                Label(isCompact ? "Mémo" : "Mémo enseignant", systemImage: "doc.text.fill")
                    .font(.system(size: 12, weight: .semibold))
            }
            .buttonStyle(.bordered)
            .tint(.white)

            // 4. Exporter CSV
            Button {
                guard !isExportingCSV else { return }
                let targets = appState.students.filter { selectedStudentIds.contains($0.id) }
                exportCSV(for: targets)
            } label: {
                HStack(spacing: 6) {
                    if isExportingCSV {
                        ProgressView()
                            .controlSize(.small)
                            .tint(.white)
                        Text(isCompact ? "Export..." : "Export en cours...")
                            .font(.system(size: 12, weight: .semibold))
                    } else {
                        Image(systemName: "arrow.up.doc.fill")
                            .font(.system(size: 12, weight: .semibold))
                        Text(isCompact ? "CSV" : "Exporter CSV")
                            .font(.system(size: 12, weight: .semibold))
                    }
                }
            }
            .buttonStyle(.bordered)
            .tint(.white)
            .disabled(isExportingCSV)

            Spacer()

            // 5. Supprimer la sélection
            Button(role: .destructive) {
                if appState.isOnline {
                    showBatchDeleteConfirmation = true
                }
            } label: {
                Image(systemName: "trash.fill")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundColor(.white)
                    .padding(8)
                    .background(Color.red.opacity(appState.isOnline ? 0.8 : 0.3))
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)
            .disabled(!appState.isOnline)
            .opacity(appState.isOnline ? 1.0 : 0.45)
        }
        .padding(.horizontal, isCompact ? 12 : 16)
        .padding(.vertical, 10)
        .background(
            Capsule()
                .fill(LinearGradient.electricBlue)
                .shadow(color: Color.blue.opacity(0.4), radius: 16, y: 6)
        )
        .overlay(
            Capsule().stroke(Color.white.opacity(0.35), lineWidth: 1)
        )
        .padding(.horizontal, isCompact ? 12 : 24)
    }

    // MARK: - Badges & Indicateurs Cloud

    @ViewBuilder
    private func compactCloudStatusBadge(for student: Student) -> some View {
        let status = folderStatuses[student.id] ?? (student.urlDropbox.isEmpty ? .missing : .checking)
        let hasShare = !student.urlDropbox.isEmpty

        switch status {
        case .exists(let copies):
            if hasShare {
                HStack(spacing: 4) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.green)
                        .font(.system(size: 10))
                    Text("Prêt (\(copies))")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(.green)
                }
                .padding(.horizontal, 7)
                .padding(.vertical, 3)
                .background(Color.green.opacity(0.12))
                .clipShape(Capsule())
            } else {
                HStack(spacing: 4) {
                    ProgressView()
                        .controlSize(.mini)
                    Text("Lien...")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.blue)
                }
                .padding(.horizontal, 7)
                .padding(.vertical, 3)
                .background(Color.blue.opacity(0.1))
                .clipShape(Capsule())
            }
        case .checking:
            HStack(spacing: 4) {
                ProgressView()
                    .controlSize(.mini)
                Text("Vérif...")
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(Color.primary.opacity(0.05))
            .clipShape(Capsule())
        case .missing:
            HStack(spacing: 4) {
                ProgressView()
                    .controlSize(.mini)
                Text("Création...")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(.blue)
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(Color.blue.opacity(0.1))
            .clipShape(Capsule())
        }
    }

    @ViewBuilder
    private func folderStatusView(for student: Student) -> some View {
        let status = folderStatuses[student.id] ?? (student.urlDropbox.isEmpty ? .missing : .checking)
        switch status {
        case .checking:
            HStack(spacing: 4) {
                ProgressView()
                    .controlSize(.mini)
                Text("Vérification...")
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(Color.primary.opacity(0.05))
            .clipShape(Capsule())
        case .exists(let copies):
            let copyText = copies <= 1 ? "\(copies) copie" : "\(copies) copies"
            BadgeView(copyText, icon: "checkmark.circle.fill", style: .success)
        case .missing:
            HStack(spacing: 4) {
                ProgressView()
                    .controlSize(.mini)
                Text("Création...")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(.blue)
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(Color.blue.opacity(0.1))
            .clipShape(Capsule())
        }
    }

    // MARK: - Actions Utilitaires

    private func copyToClipboard(_ text: String, for studentId: Int) {
        #if canImport(AppKit)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        #elseif canImport(UIKit)
        UIPasteboard.general.string = text
        #endif

        copiedUrlStudentId = studentId
        Task {
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            copiedUrlStudentId = nil
        }
    }

    private func showToast(_ msg: String) {
        withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
            toastMessage = msg
        }
        Task {
            try? await Task.sleep(nanoseconds: 3_500_000_000)
            await MainActor.run {
                withAnimation(.easeOut(duration: 0.25)) {
                    if toastMessage == msg {
                        toastMessage = nil
                    }
                }
            }
        }
    }

    private func escapeCSVField(_ value: String) -> String {
        if value.contains(";") || value.contains("\"") || value.contains("\n") || value.contains("\r") {
            return "\"\(value.replacingOccurrences(of: "\"", with: "\"\""))\""
        }
        return value
    }

    private func exportCSV(for students: [Student]) {
        let targets = students.isEmpty ? filteredStudents : students
        guard !targets.isEmpty else { return }

        isExportingCSV = true

        Task {
            do {
                // 1. Construction du contenu CSV standard compatible Microsoft Office Excel, LibreOffice Calc, Apple Numbers
                var lines: [String] = []
                // En-tête : Classe;Nom;Prénom;Sexe;Identifiant;Mot de passe;URL (sans l'ID Droopies)
                lines.append("Classe;Nom;Prénom;Sexe;Identifiant;Mot de passe;URL")

                for s in targets {
                    let row = [
                        escapeCSVField(s.classe),
                        escapeCSVField(s.lastName),
                        escapeCSVField(s.firstName),
                        escapeCSVField(s.gender.rawValue),
                        escapeCSVField(s.login),
                        escapeCSVField(s.password),
                        escapeCSVField(s.urlDropbox)
                    ].joined(separator: ";")
                    lines.append(row)
                }

                // Préfixe universel UTF-8 BOM (\u{FEFF}) + retours CRLF (\r\n) pour détection automatique immédiate par Excel
                let csvText = "\u{FEFF}" + lines.joined(separator: "\r\n") + "\r\n"
                let filename = "Droopies - Eleves.csv"
                let cloudPath = "Exports/\(filename)"

                guard let csvData = csvText.data(using: .utf8) else {
                    await MainActor.run { isExportingCSV = false }
                    return
                }

                // 2. S'assurer que le sous-dossier Exports existe dans le Cloud
                try await appState.storageManager.ensureSourceFolderStructure()

                // 3. Écriture directe et exclusive dans le Cloud actif (100% Cloud, sans pollution de fichiers locaux)
                try await appState.storageManager.activeProvider.writeData(csvData, to: cloudPath)

                await MainActor.run {
                    self.isExportingCSV = false
                    showToast("Export enregistré dans le Cloud (Exports/\(filename))")
                }
            } catch {
                await MainActor.run {
                    self.isExportingCSV = false
                    showToast("Erreur lors de l'export Cloud : \(error.localizedDescription)")
                }
            }
        }
    }

    // MARK: - Synchronisation & Diagnostic de l'existence des Dossiers Cloud

    private func checkFolderStatus(for student: Student) async {
        let exists = await appState.storageManager.studentFolderExists(student)
        if exists {
            let copies = await appState.storageManager.countStudentCopies(for: student)
            await MainActor.run {
                folderStatuses[student.id] = .exists(copies: copies)
            }
        } else {
            await MainActor.run {
                folderStatuses[student.id] = .missing
            }
        }
    }

    private func refreshAllFolderStatuses() {
        for student in appState.students {
            Task {
                await checkFolderStatus(for: student)
            }
        }
    }

    // MARK: - Gestion de l'Ouverture Système des PDF après Fermeture de la Modale

    private func handleGeneratedPDF(url: URL, title: String) {
        #if os(macOS)
        NSWorkspace.shared.open(url)
        showToast("\(title) enregistré dans Exports/ et ouvert avec succès !")
        #elseif os(iOS)
        // Laisser 0.35s à la modale de génération pour se fermer complètement avant d'ouvrir la feuille de partage/impression
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
            self.activeSheet = .shareFile(url)
            showToast("\(title) enregistré dans Exports/")
        }
        #endif
    }
}

// MARK: - Helper UIActivityViewController pour iPadOS / iOS

#if os(iOS)
private struct ActivityView: UIViewControllerRepresentable {
    let activityItems: [Any]
    let applicationActivities: [UIActivity]? = nil

    func makeUIViewController(context: Context) -> UIActivityViewController {
        let controller = UIActivityViewController(
            activityItems: activityItems,
            applicationActivities: applicationActivities
        )
        if let popover = controller.popoverPresentationController {
            popover.permittedArrowDirections = []
            if let window = UIApplication.shared.connectedScenes
                .compactMap({ $0 as? UIWindowScene })
                .flatMap({ $0.windows })
                .first(where: { $0.isKeyWindow }) {
                popover.sourceView = window
                popover.sourceRect = CGRect(x: window.bounds.midX, y: window.bounds.midY, width: 0, height: 0)
            }
        }
        return controller
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
#endif
