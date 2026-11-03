//
//  Step2LoadingView.swift
//  Dropies
//
//  Étape 2 : Chargement des copies & Préparation de l'évaluation.
//  Gère à la fois les nouvelles évaluations et les rattrapages d'élèves absents
//  avec fusion automatique du backup et auto-complétion.
//

import SwiftUI
import PDFKit
import UniformTypeIdentifiers

public struct Step2LoadingView: View {
    @Bindable public var appState: AppState
    @Binding public var currentStep: Int

    public enum LoadingMode: String, CaseIterable, Identifiable {
        case newEvaluation = "Nouvelle évaluation"
        case catchUpAbsents = "Rattrapage d'élèves absents"

        public var id: String { rawValue }
    }

    @State private var mode: LoadingMode = .newEvaluation
    @State private var availableScans: [StorageManager.ScanItem] = []
    @State private var selectedScan: StorageManager.ScanItem? = nil
    @State private var existingBackups: [StorageManager.ExistingBackup] = []
    @State private var selectedBackup: StorageManager.ExistingBackup? = nil

    @State private var pdfURL: URL? = nil
    @State private var loadedPDFDoc: PDFDocument? = nil
    @State private var isExternalPickerPresented: Bool = false

    // Métadonnées
    @State private var selectedClassId: String? = nil
    @State private var evalTitle: String = ""
    @State private var evalDate: Date = Date()
    @State private var evalMaxScore: Double = 20.0
    @State private var pagesPerCopy: Int = 2

    public init(appState: AppState, currentStep: Binding<Int>) {
        self.appState = appState
        self._currentStep = currentStep
    }

    private var totalPages: Int {
        loadedPDFDoc?.pageCount ?? 0
    }

    private var estimatedCopiesCount: Int {
        guard totalPages > 0 else { return 0 }
        return Int(ceil(Double(totalPages) / Double(max(1, pagesPerCopy))))
    }

    public var body: some View {
        VStack(spacing: 0) {
            // MARK: - Sélecteur de Mode en haut
            HStack(spacing: 20) {
                Button {
                    currentStep = 1
                } label: {
                    Label("Atelier Stylet", systemImage: "arrow.left")
                }
                .buttonStyle(.plain)
                .foregroundColor(.secondary)

                Divider().frame(height: 20)

                Picker("Type de devoir", selection: $mode) {
                    ForEach(LoadingMode.allCases) { m in
                        Text(m.rawValue).tag(m)
                    }
                }
                .pickerStyle(.segmented)
                .frame(maxWidth: 380)
                .onChange(of: mode) { _, newMode in
                    handleModeChange(newMode)
                }

                Spacer()

                Button {
                    proceedToIdentification()
                } label: {
                    Label("Identifier les copies (3) ➔", systemImage: "person.crop.rectangle.badge.plus")
                        .fontWeight(.semibold)
                }
                .buttonStyle(.borderedProminent)
                .tint(.green)
                .disabled(loadedPDFDoc == nil || evalTitle.trimmingCharacters(in: .whitespaces).isEmpty || selectedClassId == nil)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(Color(white: 0.5, opacity: 0.06))

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    // MARK: - En mode Rattrapage : Choix du Backup existant
                    if mode == .catchUpAbsents {
                        VStack(alignment: .leading, spacing: 10) {
                            HStack {
                                Image(systemName: "arrow.triangle.merge")
                                    .foregroundColor(.orange)
                                Text("Sélection de l'évaluation passée (Backup)")
                                    .font(.headline)
                            }

                            Text("Choisissez le devoir déjà distribué. Dropies remplira automatiquement la classe, la date et le titre, et fusionnera ce nouveau scan à la fin du backup existant.")
                                .font(.caption)
                                .foregroundColor(.secondary)

                            if existingBackups.isEmpty {
                                Text("Aucun backup trouvé dans Evaluations/Backup/")
                                    .font(.subheadline)
                                    .foregroundColor(.secondary)
                                    .italic()
                            } else {
                                Picker("Évaluation existante", selection: $selectedBackup) {
                                    Text("— Choisir une évaluation archivée —").tag(nil as StorageManager.ExistingBackup?)
                                    ForEach(existingBackups) { backup in
                                        Text("\(backup.className) • \(backup.evaluationTitle) (\(backup.fileName))")
                                            .tag(backup as StorageManager.ExistingBackup?)
                                    }
                                }
                                .pickerStyle(.menu)
                                .onChange(of: selectedBackup) { _, backup in
                                    if let b = backup {
                                        applyBackupMetadata(b)
                                    }
                                }
                            }
                        }
                        .padding(16)
                        .background(Color.orange.opacity(0.08))
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(Color.orange.opacity(0.3), lineWidth: 1)
                        )
                    }

                    // MARK: - Choix du scan brut PDF
                    VStack(alignment: .leading, spacing: 12) {
                        Text("1. Sélection du scan PDF")
                            .font(.headline)

                        if availableScans.isEmpty {
                            Text("Aucun PDF dans Evaluations/A corriger/")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                        } else {
                            VStack(spacing: 8) {
                                ForEach(availableScans) { scan in
                                    let isSelected = selectedScan?.path == scan.path
                                    Button {
                                        selectScan(scan)
                                    } label: {
                                        HStack {
                                            Image(systemName: scan.isCorrected ? "checkmark.seal.fill" : "doc.text.fill")
                                                .foregroundColor(scan.isCorrected ? .green : .blue)
                                            Text(scan.cleanTitle)
                                                .fontWeight(isSelected ? .bold : .medium)
                                            Spacer()
                                            if scan.isCorrected {
                                                BadgeView("Prêt (CORRIGÉ)", style: .success)
                                            }
                                        }
                                        .padding(12)
                                        .background(isSelected ? Color.blue.opacity(0.15) : Color(white: 0.5, opacity: 0.05))
                                        .clipShape(RoundedRectangle(cornerRadius: 8))
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 8)
                                                .stroke(isSelected ? Color.blue : Color.secondary.opacity(0.2), lineWidth: isSelected ? 2 : 1)
                                        )
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }

                        Button {
                            isExternalPickerPresented = true
                        } label: {
                            Label("Importer un autre fichier PDF...", systemImage: "plus.rectangle.on.folder")
                                .font(.caption)
                        }
                        .buttonStyle(.bordered)
                    }
                    .padding(16)
                    .background(Color(white: 0.5, opacity: 0.04))
                    .clipShape(RoundedRectangle(cornerRadius: 12))

                    // MARK: - Métadonnées du devoir
                    VStack(alignment: .leading, spacing: 14) {
                        Text("2. Informations sur le devoir")
                            .font(.headline)

                        HStack(spacing: 16) {
                            // Classe
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Classe").font(.caption.bold()).foregroundColor(.secondary)
                                Picker("Classe", selection: $selectedClassId) {
                                    Text("Choisir une classe").tag(nil as String?)
                                    ForEach(appState.classes) { group in
                                        Text(group.name).tag(group.id as String?)
                                    }
                                }
                                .pickerStyle(.menu)
                                .disabled(mode == .catchUpAbsents && selectedBackup != nil)
                            }
                            .frame(maxWidth: 160)

                            // Titre
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Titre de l'évaluation").font(.caption.bold()).foregroundColor(.secondary)
                                TextField("ex: DS 02 - Fractions", text: $evalTitle)
                                    .textFieldStyle(.roundedBorder)
                                    .disabled(mode == .catchUpAbsents && selectedBackup != nil)
                            }

                            // Date
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Date").font(.caption.bold()).foregroundColor(.secondary)
                                DatePicker("", selection: $evalDate, displayedComponents: .date)
                                    .labelsHidden()
                                    .disabled(mode == .catchUpAbsents && selectedBackup != nil)
                            }

                            // Barème
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Note max").font(.caption.bold()).foregroundColor(.secondary)
                                TextField("20", value: $evalMaxScore, format: .number)
                                    .textFieldStyle(.roundedBorder)
                                    .frame(width: 60)
                            }
                        }
                    }
                    .padding(16)
                    .background(Color(white: 0.5, opacity: 0.04))
                    .clipShape(RoundedRectangle(cornerRadius: 12))

                    // MARK: - Découpage & Ratio de pages
                    VStack(alignment: .leading, spacing: 14) {
                        Text("3. Réglage du découpage")
                            .font(.headline)

                        HStack(spacing: 20) {
                            VStack(alignment: .leading, spacing: 6) {
                                Text("Nombre de pages par copie :")
                                    .font(.subheadline)
                                    .foregroundColor(.secondary)

                                Picker("Pages", selection: $pagesPerCopy) {
                                    ForEach(1...6, id: \.self) { num in
                                        Text("\(num) \(num > 1 ? "pages" : "page")").tag(num)
                                    }
                                }
                                .pickerStyle(.segmented)
                                .frame(maxWidth: 320)
                            }

                            Divider().frame(height: 40)

                            VStack(alignment: .leading, spacing: 4) {
                                Text("Total : \(totalPages) page(s)")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                Text("Estimation : \(estimatedCopiesCount) copie(s) à découper")
                                    .font(.subheadline.bold())
                                    .foregroundColor(.blue)
                            }
                        }
                    }
                    .padding(16)
                    .background(Color(white: 0.5, opacity: 0.04))
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                }
                .padding(20)
            }
        }
        .task {
            await loadInitialScansAndBackups()
        }
        .fileImporter(
            isPresented: $isExternalPickerPresented,
            allowedContentTypes: [.pdf],
            allowsMultipleSelection: false
        ) { result in
            if case .success(let urls) = result, let url = urls.first {
                loadPDF(from: url)
            }
        }
    }

    // MARK: - Actions

    private func loadInitialScansAndBackups() async {
        if let scans = try? await appState.storageManager.listScans() {
            self.availableScans = scans
            // Pré-sélection du premier scan corrigé (CORRIGE_) s'il existe
            if let firstCorrected = scans.first(where: { $0.isCorrected }) {
                selectScan(firstCorrected)
            } else if let first = scans.first {
                selectScan(first)
            }
        }

        if let backups = try? await appState.storageManager.listExistingBackups() {
            self.existingBackups = backups
        }
    }

    private func selectScan(_ scan: StorageManager.ScanItem) {
        selectedScan = scan
        let url = appState.storageManager.localURL(for: "Evaluations/A corriger/\(scan.name)")
        loadPDF(from: url)
        if evalTitle.isEmpty {
            self.evalTitle = scan.cleanTitle.replacingOccurrences(of: ".pdf", with: "")
        }
    }

    private func loadPDF(from url: URL) {
        let isAccessing = url.startAccessingSecurityScopedResource()
        defer {
            if isAccessing { url.stopAccessingSecurityScopedResource() }
        }

        if let doc = try? PDFEngine.shared.loadDocument(from: url) {
            self.pdfURL = url
            self.loadedPDFDoc = doc
            if selectedClassId == nil, let first = appState.classes.first {
                self.selectedClassId = first.id
            }
            let classSize = appState.studentsInSelectedClass.count
            self.pagesPerCopy = Evaluation.estimatePagesPerCopy(totalPages: doc.pageCount, expectedClassSize: classSize)
        }
    }

    private func handleModeChange(_ newMode: LoadingMode) {
        if newMode == .catchUpAbsents {
            if let firstBackup = existingBackups.first {
                self.selectedBackup = firstBackup
                applyBackupMetadata(firstBackup)
            }
        }
    }

    private func applyBackupMetadata(_ backup: StorageManager.ExistingBackup) {
        self.evalTitle = backup.evaluationTitle
        if let d = backup.date {
            self.evalDate = d
        }
        if let matchingGroup = appState.classes.first(where: { $0.name.lowercased() == backup.className.lowercased() }) {
            self.selectedClassId = matchingGroup.id
        }
    }

    private func proceedToIdentification() {
        guard let doc = loadedPDFDoc else { return }
        let selectedGroup = appState.classes.first(where: { $0.id == selectedClassId })?.name ?? "Classe"

        var eval = Evaluation(
            title: evalTitle.trimmingCharacters(in: .whitespacesAndNewlines),
            date: evalDate,
            className: selectedGroup,
            maxScore: evalMaxScore,
            pagesPerCopy: pagesPerCopy,
            isCatchUp: mode == .catchUpAbsents,
            existingBackupFileName: selectedBackup?.fileName
        )

        // Découpage initial des copies
        var copies: [StudentCopy] = []
        var page = 1
        var copyIdx = 1

        while page <= doc.pageCount {
            let pageEnd = min(page + pagesPerCopy - 1, doc.pageCount)
            copies.append(StudentCopy(
                index: copyIdx,
                pageStart: page,
                pageEnd: pageEnd
            ))
            page += pagesPerCopy
            copyIdx += 1
        }

        eval.copies = copies
        appState.currentEvaluation = eval
        appState.selectedClassId = selectedClassId
        currentStep = 3
    }
}
