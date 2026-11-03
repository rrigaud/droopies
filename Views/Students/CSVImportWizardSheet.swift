//
//  CSVImportWizardSheet.swift
//  Dropies
//
//  Assistant d'importation CSV en 2 étapes pour intégrer des listes de classe
//  (Pronote, Siècle, Excel) sans aucune friction.
//

import SwiftUI
import UniformTypeIdentifiers

public struct CSVImportWizardSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Bindable public var appState: AppState

    @State private var wizardStep: Int = 1
    @State private var rawCSVText: String = ""
    @State private var delimiter: Character = ";"
    @State private var hasHeaderRow: Bool = true

    // Correspondance des colonnes (index 0-based)
    @State private var lastNameColumnIndex: Int = 0
    @State private var firstNameColumnIndex: Int = 1
    @State private var classColumnIndex: Int = 2
    @State private var genderColumnIndex: Int = -1

    @State private var parsedPreviewRows: [[String]] = []
    @State private var preparedStudents: [(student: Student, isSelected: Bool)] = []
    @State private var isFilePickerPresented: Bool = false

    public init(appState: AppState) {
        self.appState = appState
    }

    public var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Stepper d'import
                HStack(spacing: 16) {
                    Label("1. Correspondance des colonnes", systemImage: "tablecells")
                        .font(.subheadline.bold())
                        .foregroundColor(wizardStep == 1 ? .blue : .secondary)

                    Image(systemName: "chevron.right")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    Label("2. Prévisualisation & Validation", systemImage: "checkmark.circle")
                        .font(.subheadline.bold())
                        .foregroundColor(wizardStep == 2 ? .blue : .secondary)
                }
                .padding(.vertical, 12)
                .frame(maxWidth: .infinity)
                .background(Color(white: 0.5, opacity: 0.05))

                Divider()

                if wizardStep == 1 {
                    step1ColumnMappingView
                } else {
                    step2PreviewValidationView
                }
            }
            .navigationTitle("Assistant d'Importation CSV")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Annuler") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    if wizardStep == 1 {
                        Button("Suivant ➔") {
                            prepareStudentsForValidation()
                            wizardStep = 2
                        }
                        .disabled(parsedPreviewRows.isEmpty)
                    } else {
                        Button("Importer \(selectedCount) élèves") {
                            executeImport()
                        }
                        .disabled(selectedCount == 0)
                    }
                }
            }
        }
        .frame(minWidth: 620, minHeight: 520)
        .fileImporter(
            isPresented: $isFilePickerPresented,
            allowedContentTypes: [.plainText, .commaSeparatedText, .tabSeparatedText],
            allowsMultipleSelection: false
        ) { result in
            if case .success(let urls) = result, let url = urls.first {
                if let content = try? String(contentsOf: url, encoding: .utf8) {
                    self.rawCSVText = content
                    parseCSV()
                }
            }
        }
    }

    // MARK: - Étape 1 : Correspondance

    private var step1ColumnMappingView: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Button {
                    isFilePickerPresented = true
                } label: {
                    Label("Charger un fichier .csv ou .txt", systemImage: "doc.badge.plus")
                }
                .buttonStyle(.bordered)

                Spacer()

                Toggle("1ère ligne = En-têtes", isOn: $hasHeaderRow)
                    .onChange(of: hasHeaderRow) { _, _ in parseCSV() }
            }

            if rawCSVText.isEmpty {
                TextEditor(text: $rawCSVText)
                    .font(.system(.body, design: .monospaced))
                    .frame(height: 120)
                    .padding(4)
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.secondary.opacity(0.2), lineWidth: 1))
                    .overlay(
                        Group {
                            if rawCSVText.isEmpty {
                                Text("Collez vos données CSV ici (ex: NOM;Prénom;Classe)...")
                                    .foregroundColor(.secondary)
                                    .padding(8)
                            }
                        },
                        alignment: .topLeading
                    )
                    .onChange(of: rawCSVText) { _, _ in parseCSV() }
            }

            if !parsedPreviewRows.isEmpty {
                let columnsCount = parsedPreviewRows.first?.count ?? 0

                // Sélecteurs de colonnes
                VStack(alignment: .leading, spacing: 10) {
                    Text("Associer les colonnes détectées :")
                        .font(.subheadline.bold())

                    HStack(spacing: 12) {
                        columnPicker(title: "Nom", selection: $lastNameColumnIndex, count: columnsCount)
                        columnPicker(title: "Prénom", selection: $firstNameColumnIndex, count: columnsCount)
                        columnPicker(title: "Classe", selection: $classColumnIndex, count: columnsCount)
                        columnPicker(title: "Sexe / Genre", selection: $genderColumnIndex, count: columnsCount, allowNone: true)
                    }
                }
                .padding(12)
                .background(Color(white: 0.5, opacity: 0.05))
                .clipShape(RoundedRectangle(cornerRadius: 8))

                // Aperçu des 5 premières lignes brutes
                VStack(alignment: .leading, spacing: 6) {
                    Text("Aperçu des premières lignes :")
                        .font(.caption.bold())
                        .foregroundColor(.secondary)

                    ScrollView(.horizontal) {
                        VStack(alignment: .leading, spacing: 4) {
                            ForEach(0..<min(5, parsedPreviewRows.count), id: \.self) { r in
                                HStack(spacing: 12) {
                                    ForEach(0..<parsedPreviewRows[r].count, id: \.self) { c in
                                        Text(parsedPreviewRows[r][c])
                                            .font(.caption)
                                            .padding(.horizontal, 6)
                                            .padding(.vertical, 2)
                                            .background(Color.secondary.opacity(0.1))
                                            .clipShape(RoundedRectangle(cornerRadius: 4))
                                    }
                                }
                            }
                        }
                    }
                }
            }

            Spacer()
        }
        .padding(16)
    }

    @ViewBuilder
    private func columnPicker(title: String, selection: Binding<Int>, count: Int, allowNone: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption.bold())
                .foregroundColor(.secondary)

            Picker("", selection: selection) {
                if allowNone {
                    Text("Aucun").tag(-1)
                }
                ForEach(0..<count, id: \.self) { i in
                    let label = hasHeaderRow && !parsedPreviewRows.isEmpty && i < parsedPreviewRows[0].count ?
                        "Col \(i + 1) (\(parsedPreviewRows[0][i]))" : "Colonne \(i + 1)"
                    Text(label).tag(i)
                }
            }
            .labelsHidden()
            .pickerStyle(.menu)
        }
    }

    // MARK: - Étape 2 : Prévisualisation

    private var step2PreviewValidationView: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("\(preparedStudents.count) élèves détectés")
                    .font(.headline)
                Spacer()
                Button("Tout cocher") {
                    setAllSelection(to: true)
                }
                .buttonStyle(.plain)
                .font(.caption)
                .foregroundColor(.blue)

                Text("•").foregroundColor(.secondary)

                Button("Tout décocher") {
                    setAllSelection(to: false)
                }
                .buttonStyle(.plain)
                .font(.caption)
                .foregroundColor(.blue)
            }

            ScrollView {
                VStack(spacing: 0) {
                    ForEach(0..<preparedStudents.count, id: \.self) { idx in
                        HStack {
                            Toggle("", isOn: $preparedStudents[idx].isSelected)
                                .labelsHidden()

                            let s = preparedStudents[idx].student
                            Text(s.name)
                                .fontWeight(.medium)
                                .frame(maxWidth: .infinity, alignment: .leading)

                            BadgeView(s.classe, style: .info)

                            Text(s.login)
                                .font(.caption.monospaced())
                                .foregroundColor(.secondary)
                                .frame(width: 140, alignment: .leading)

                            Text(s.password)
                                .font(.caption.monospaced())
                                .foregroundColor(.secondary)
                                .frame(width: 100, alignment: .leading)
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        Divider()
                    }
                }
            }
            .background(Color(white: 0.5, opacity: 0.04))
            .clipShape(RoundedRectangle(cornerRadius: 8))
        }
        .padding(16)
    }

    // MARK: - Traitement & Parsing

    private var selectedCount: Int {
        preparedStudents.filter { $0.isSelected }.count
    }

    private func setAllSelection(to val: Bool) {
        for i in 0..<preparedStudents.count {
            preparedStudents[i].isSelected = val
        }
    }

    private func parseCSV() {
        let lines = rawCSVText.components(separatedBy: .newlines).filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        guard !lines.isEmpty else {
            parsedPreviewRows = []
            return
        }

        // Détection automatique du séparateur (; , \t)
        let firstLine = lines[0]
        if firstLine.contains(";") { delimiter = ";" }
        else if firstLine.contains("\t") { delimiter = "\t" }
        else { delimiter = "," }

        parsedPreviewRows = lines.map { line in
            line.split(separator: delimiter, omittingEmptySubsequences: false).map {
                String($0).trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: "\"", with: "")
            }
        }
    }

    private func prepareStudentsForValidation() {
        guard !parsedPreviewRows.isEmpty else { return }
        let rows = hasHeaderRow ? Array(parsedPreviewRows.dropFirst()) : parsedPreviewRows
        var list: [(student: Student, isSelected: Bool)] = []

        var currentMaxId = appState.students.map { $0.id }.max() ?? 0

        for row in rows {
            guard !row.isEmpty else { continue }
            let nom = (lastNameColumnIndex >= 0 && lastNameColumnIndex < row.count) ? row[lastNameColumnIndex] : ""
            let prenom = (firstNameColumnIndex >= 0 && firstNameColumnIndex < row.count) ? row[firstNameColumnIndex] : ""
            let cl = (classColumnIndex >= 0 && classColumnIndex < row.count) ? row[classColumnIndex] : "Classe"
            let sx = (genderColumnIndex >= 0 && genderColumnIndex < row.count) ? row[genderColumnIndex] : "M"

            let fullName = prenom.isEmpty ? nom : "\(nom) \(prenom)"
            guard !fullName.trimmingCharacters(in: .whitespaces).isEmpty else { continue }

            currentMaxId += 1
            let student = Student(
                id: currentMaxId,
                name: fullName.trimmingCharacters(in: .whitespacesAndNewlines),
                classe: cl.trimmingCharacters(in: .whitespacesAndNewlines),
                gender: sx.uppercased().hasPrefix("F") ? .female : .male,
                login: Student.generateLogin(from: fullName),
                password: "droopy\(Int.random(in: 10...99))"
            )
            list.append((student, true))
        }

        self.preparedStudents = list
    }

    private func executeImport() {
        let toImport = preparedStudents.filter { $0.isSelected }.map { $0.student }
        Task {
            var updated = appState.students
            updated.append(contentsOf: toImport)
            try? await appState.storageManager.saveStudents(updated)
            await MainActor.run {
                self.appState.students = updated
                dismiss()
            }
        }
    }
}
