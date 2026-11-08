//
//  StudentEditSheet.swift
//  Droopies
//
//  Feuille modale d'ajout ou d'édition d'un élève.
//  - Classe en premier, puis Nom & Prénom
//  - Désactivation de l'autocapitalisation et de l'autocorrection sur identifiant et mot de passe
//  - Génération de mot de passe à la volée
//

import SwiftUI

public struct StudentEditSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Bindable public var appState: AppState

    public var studentToEdit: Student? = nil

    @State private var classe: String = ""
    @State private var name: String = ""
    @State private var gender: Student.Gender = .male
    @State private var login: String = ""
    @State private var password: String = ""
    @State private var urlDropbox: String = ""
    @State private var isSubmitting: Bool = false

    // Gestion du sélecteur dynamique de classes
    @State private var customClasses: [String] = []
    @State private var showNewClassPopover: Bool = false
    @State private var newClassName: String = ""

    public init(appState: AppState, studentToEdit: Student? = nil) {
        self.appState = appState
        self.studentToEdit = studentToEdit
    }

    private var isNewStudent: Bool {
        studentToEdit == nil
    }

    /// Liste de toutes les classes disponibles (issues de la BDD élèves, des groupes et des ajouts à la volée)
    private var availableClasses: [String] {
        var set = Set<String>()
        for c in appState.classes {
            let t = c.name.trimmingCharacters(in: .whitespacesAndNewlines)
            if !t.isEmpty { set.insert(t) }
        }
        for s in appState.students {
            let t = s.classe.trimmingCharacters(in: .whitespacesAndNewlines)
            if !t.isEmpty { set.insert(t) }
        }
        for c in customClasses {
            let t = c.trimmingCharacters(in: .whitespacesAndNewlines)
            if !t.isEmpty { set.insert(t) }
        }
        let cur = classe.trimmingCharacters(in: .whitespacesAndNewlines)
        if !cur.isEmpty { set.insert(cur) }

        return Array(set).sorted { $0.localizedStandardCompare($1) == .orderedAscending }
    }

    public var body: some View {
        NavigationStack {
            Form {
                // Section 1 : Identité scolaire (Classe avec SelectButton dynamique)
                Section {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Classe de l'élève")
                            .font(.caption.weight(.semibold))
                            .foregroundColor(.secondary)

                        // SelectButton horizontal défilant avec les classes existantes + bouton "+"
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 8) {
                                ForEach(availableClasses, id: \.self) { cl in
                                    let isSelected = (cl == classe)
                                    Button {
                                        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                            if isSelected {
                                                classe = ""
                                            } else {
                                                classe = cl
                                            }
                                        }
                                    } label: {
                                        HStack(spacing: 5) {
                                            if isSelected {
                                                Image(systemName: "checkmark")
                                                    .font(.system(size: 11, weight: .bold))
                                            }
                                            Text(cl)
                                                .font(.system(size: 13, weight: isSelected ? .bold : .medium, design: .rounded))
                                        }
                                        .padding(.horizontal, 14)
                                        .padding(.vertical, 8)
                                        .background(
                                            isSelected ?
                                                AnyShapeStyle(Color.blue) :
                                                AnyShapeStyle(Color.primary.opacity(0.06))
                                        )
                                        .foregroundColor(isSelected ? .white : .primary)
                                        .clipShape(Capsule())
                                        .overlay(
                                            Capsule()
                                                .strokeBorder(isSelected ? Color.blue.opacity(0.4) : Color.primary.opacity(0.12), lineWidth: 1)
                                        )
                                        .shadow(color: isSelected ? Color.blue.opacity(0.3) : .clear, radius: 4, x: 0, y: 2)
                                    }
                                    .buttonStyle(.plain)
                                }

                                // Bouton "+" pour créer et ajouter une nouvelle classe
                                Button {
                                    newClassName = ""
                                    showNewClassPopover = true
                                } label: {
                                    HStack(spacing: 5) {
                                        Image(systemName: "plus")
                                            .font(.system(size: 12, weight: .bold))
                                        Text("Nouvelle")
                                            .font(.system(size: 13, weight: .semibold, design: .rounded))
                                    }
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 8)
                                    .background(Color.blue.opacity(0.10))
                                    .foregroundColor(.blue)
                                    .clipShape(Capsule())
                                    .overlay(
                                        Capsule()
                                            .strokeBorder(Color.blue.opacity(0.30), lineWidth: 1)
                                    )
                                }
                                .buttonStyle(.plain)
                                .popover(isPresented: $showNewClassPopover, arrowEdge: .top) {
                                    newClassPopoverContent
                                }
                            }
                            .padding(.vertical, 2)
                        }
                    }
                    .padding(.vertical, 4)

                    TextField("Nom & Prénom (ex: DUPONT Jules)", text: $name)
                        .font(.body)

                    Picker("Genre", selection: $gender) {
                        Text("Masculin (Garçon)").tag(Student.Gender.male)
                        Text("Féminin (Fille)").tag(Student.Gender.female)
                    }
                } header: {
                    Text("Identité de l'élève")
                }

                // Section 2 : Accès Portail Élèves
                Section {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Identifiant de connexion")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        TextField("ex : prenom.nom", text: $login)
                            .font(.system(.body, design: .monospaced))
                            .disableAutocapitalization()
                            .autocorrectionDisabled(true)
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text("Mot de passe / Code d'accès")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            Spacer()
                            Button {
                                password = PasswordGenerator.generatePassphrase(wordCount: 2, language: appState.settings.language)
                            } label: {
                                Label("Générer", systemImage: "sparkles")
                                    .font(.caption2.weight(.semibold))
                            }
                            .buttonStyle(.borderless)
                        }

                        TextField("ex : mot-de-passe", text: $password)
                            .font(.system(.body, design: .monospaced))
                            .disableAutocapitalization()
                            .autocorrectionDisabled(true)
                    }
                } header: {
                    Text("Accès au portail élève")
                } footer: {
                    Text("L'identifiant et le mot de passe sont en minuscules par défaut pour faciliter la saisie par les élèves.")
                        .font(.caption2)
                }

                // Section 3 : Lien de partage Cloud
                Section("Lien de dossier Cloud partagé") {
                    TextField("Lien généré automatiquement (https://...)", text: $urlDropbox)
                        .font(.system(.caption, design: .monospaced))
                        .disableAutocapitalization()
                        .autocorrectionDisabled(true)
                        #if os(iOS)
                        .keyboardType(.URL)
                        .textContentType(.URL)
                        #endif
                }
            }
            .navigationTitle(isNewStudent ? "Nouvel Élève" : "Modifier l'Élève")
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
                    Button("Enregistrer") {
                        saveStudent()
                    }
                    .disabled(isSubmitting || name.trimmingCharacters(in: .whitespaces).isEmpty || classe.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .onAppear {
                if let student = studentToEdit {
                    classe = student.classe
                    name = student.name
                    gender = student.gender
                    login = student.login
                    password = student.password
                    urlDropbox = student.urlDropbox
                } else {
                    // Pour un nouvel élève : ne pas forcer de classe par défaut, l'utilisateur sélectionne librement
                    classe = ""
                    password = PasswordGenerator.generatePassphrase(wordCount: 2, language: appState.settings.language)
                }
            }
        }
        #if os(macOS)
        .frame(minWidth: 480, minHeight: 440)
        #endif
    }

    // MARK: - Popover d'Ajout Rapide de Classe

    private var newClassPopoverContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "folder.badge.plus")
                    .foregroundColor(.blue)
                    .font(.subheadline)
                Text("Ajouter une classe")
                    .font(.subheadline.bold())
                Spacer()
                Button {
                    showNewClassPopover = false
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.secondary.opacity(0.7))
                }
                .buttonStyle(.plain)
            }

            Text("Entrez le nom de la nouvelle classe :")
                .font(.caption)
                .foregroundColor(.secondary)

            HStack(spacing: 8) {
                TextField("ex : 5e3, 4B...", text: $newClassName)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(.body, design: .rounded, weight: .semibold))
                    #if os(iOS)
                    .textInputAutocapitalization(.never)
                    #endif
                    .autocorrectionDisabled(true)
                    .onSubmit {
                        confirmAddNewClass()
                    }

                Button("Ajouter") {
                    confirmAddNewClass()
                }
                .buttonStyle(.borderedProminent)
                .tint(.blue)
                .disabled(newClassName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(16)
        .frame(width: 290)
        .presentationCompactAdaptation(.popover)
    }

    private func confirmAddNewClass() {
        let clean = newClassName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else { return }
        if !customClasses.contains(clean) {
            customClasses.append(clean)
        }
        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
            classe = clean
        }
        newClassName = ""
        showNewClassPopover = false
    }

    private func saveStudent() {
        guard !isSubmitting else { return }
        isSubmitting = true

        let cleanName = Student.sanitizeName(name)
        let cleanClasse = classe.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanLogin = login.isEmpty ? Student.generateLogin(from: cleanName) : login.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let cleanPassword = password.isEmpty ? PasswordGenerator.generatePassphrase(wordCount: 2, language: appState.settings.language) : password.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanUrl = urlDropbox.trimmingCharacters(in: .whitespacesAndNewlines)

        // Fermeture immédiate de la feuille modale pour une UX fluide et sans blocage
        dismiss()

        Task {
            if let existing = studentToEdit {
                let updated = Student(
                    id: existing.id,
                    name: cleanName,
                    classe: cleanClasse,
                    gender: gender,
                    login: cleanLogin,
                    password: cleanPassword,
                    urlDropbox: cleanUrl
                )
                try? await appState.updateStudent(updated, oldStudent: existing)
            } else {
                let nextId = (appState.students.map { $0.id }.max() ?? 0) + 1
                let newStudent = Student(
                    id: nextId,
                    name: cleanName,
                    classe: cleanClasse,
                    gender: gender,
                    login: cleanLogin,
                    password: cleanPassword,
                    urlDropbox: cleanUrl
                )
                try? await appState.addStudent(newStudent)
            }
        }
    }
}
