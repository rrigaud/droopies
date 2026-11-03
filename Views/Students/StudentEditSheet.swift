//
//  StudentEditSheet.swift
//  Dropies
//
//  Feuille modale d'ajout ou d'édition d'un élève.
//

import SwiftUI

public struct StudentEditSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Bindable public var appState: AppState

    public var studentToEdit: Student? = nil

    @State private var name: String = ""
    @State private var classe: String = ""
    @State private var gender: Student.Gender = .male
    @State private var login: String = ""
    @State private var password: String = ""
    @State private var urlDropbox: String = ""

    public init(appState: AppState, studentToEdit: Student? = nil) {
        self.appState = appState
        self.studentToEdit = studentToEdit
    }

    private var isNewStudent: Bool {
        studentToEdit == nil
    }

    public var body: some View {
        NavigationStack {
            Form {
                Section("Identité de l'élève") {
                    TextField("Nom & Prénom (ex: DUPONT Jules)", text: $name)
                    TextField("Classe (ex: 4B, 3e1)", text: $classe)
                    Picker("Genre", selection: $gender) {
                        Text("Masculin (M)").tag(Student.Gender.male)
                        Text("Féminin (F)").tag(Student.Gender.female)
                    }
                }

                Section("Accès au portail élève") {
                    TextField("Identifiant de connexion", text: $login)
                    TextField("Mot de passe", text: $password)
                }

                Section("Lien de dossier Cloud (optionnel)") {
                    TextField("https://www.dropbox.com/...", text: $urlDropbox)
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
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty || classe.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .onAppear {
                if let student = studentToEdit {
                    name = student.name
                    classe = student.classe
                    gender = student.gender
                    login = student.login
                    password = student.password
                    urlDropbox = student.urlDropbox
                } else {
                    classe = appState.selectedClass?.name ?? ""
                }
            }
        }
        #if os(macOS)
        .frame(minWidth: 460, minHeight: 400)
        #endif
    }

    private func saveStudent() {
        let cleanName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanClasse = classe.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanLogin = login.isEmpty ? Student.generateLogin(from: cleanName) : login.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanPassword = password.isEmpty ? "droopy" : password.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanUrl = urlDropbox.trimmingCharacters(in: .whitespacesAndNewlines)

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
                try? await appState.updateStudent(updated)
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
            await MainActor.run {
                dismiss()
            }
        }
    }
}
