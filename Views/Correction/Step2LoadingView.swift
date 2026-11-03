//
//  Step2LoadingView.swift
//  Dropies
//
//  Étape 2 : Chargement des copies & Préparation de l'évaluation.
//  Gère à la fois les nouvelles évaluations et les rattrapages d'élèves absents
//  avec fusion automatique du backup et auto-complétion.
//  Sublimé avec onglets glissants Liquid Glass et cartes visionOS.
//

import SwiftUI
import PDFKit
import UniformTypeIdentifiers

public struct Step2LoadingView: View {
    @Bindable public var appState: AppState
    @Binding public var currentStep: Int

    public enum LoadingMode: String, CaseIterable, Identifiable {
        case newEvaluation = "Nouvelle évaluation"
        case catchUpAbsents = "Mode Rattrapage (Élèves absents)"

        public var id: String { rawValue }
    }

    @State private var mode: LoadingMode = .newEvaluation
    @Namespace private var modeTabNamespace

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
            // MARK: - Barre d'outils supérieure flottante
            HStack(spacing: 16) {
                Button {
                    currentStep = 1
                } label: {
                    Label("Atelier Stylet", systemImage: "chevron.left")
                        .font(.system(size: 13, weight: .medium))
                }
                .buttonStyle(.plain)
                .foregroundColor(.secondary)

                Divider().frame(height: 20)

                // Onglets Glissants Liquid Glass
                modeTabsControl

                Spacer()

                Button {
                    proceedToIdentification()
                } label: {
                    Label("Identifier (3) ➔", systemImage: "person.crop.rectangle.badge.plus")
                }
                .buttonStyle(VibrantGradientButtonStyle(gradient: .emeraldGreen, isCompact: true))
                .disabled(loadedPDFDoc == nil || evalTitle.trimmingCharacters(in: .whitespaces).isEmpty || selectedClassId == nil)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(.ultraThinMaterial)

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    // MARK: - En mode Rattrapage : Choix du Backup existant
                    if mode == .catchUpAbsents {
                        VStack(alignment: .leading, spacing: 12) {
                            HStack {
                                Image(systemName: "arrow.triangle.merge")
                                    .font(.title3)
                                    .foregroundColor(.orange)
                                Text("Sélection de l'évaluation archivée (Backup)")
                                    .font(.headline)
                            }

                            Text("Choisissez le devoir déjà distribué. Dropies pré-remplira automatiquement la classe, la date et le titre, et fusionnera ce nouveau scan à la fin du backup existant.")
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
                                .onChange(of: selectedBackup) { _, newBackup in
                                    if let b = newBackup {
                                        applyBackupMetadata(b)
                                    }
                                }
                            }
                        }
                        .padding(18)
                        .glassCard(cornerRadius: 18, strokeOpacity: 0.4)
                    }

                    // MARK: - Choix du Scan PDF
                    VStack(alignment: .leading, spacing: 14) {
                        HStack {
                            Image(systemName: "doc.viewfinder")
                                .font(.title3)
                                .foregroundColor(.blue)
                            Text("Sélection du paquet de copies numérisé")
                                .font(.headline)
                        }

                        if !availableScans.isEmpty {
                            VStack(alignment: .leading, spacing: 8) {
                                Text("Paquets détectés dans Evaluations/A corriger/ :")
                                    .font(.caption.bold())
                                    .foregroundColor(.secondary)

                                ForEach(availableScans) { scan in
                                    Button {
                                        selectScan(scan)
                                    } label: {
                                        HStack {
                                            Image(systemName: scan.isCorrected ? "checkmark.seal.fill" : "doc.text.fill")
                                                .foregroundColor(scan.isCorrected ? .green : .blue)
                                            Text(scan.cleanTitle)
                                                .fontWeight(selectedScan?.id == scan.id ? .bold : .medium)

                                            Spacer()

                                            if scan.isCorrected {
                                                BadgeView("CORRIGÉ", style: .success)
                                            } else {
                                                BadgeView("En attente", style: .neutral)
                                            }

                                            if selectedScan?.id == scan.id {
                                                Image(systemName: "checkmark.circle.fill")
                                                    .foregroundColor(.blue)
                                            }
                                        }
                                        .padding(.horizontal, 14)
                                        .padding(.vertical, 10)
                                        .background(selectedScan?.id == scan.id ? Color.blue.opacity(0.12) : Color.primary.opacity(0.04))
                                        .clipShape(RoundedRectangle(cornerRadius: 10))
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }

                        Button {
                            isExternalPickerPresented = true
                        } label: {
                            Label("Importer un autre PDF depuis le disque...", systemImage: "plus.rectangle.on.folder")
                                .font(.subheadline)
                        }
                    }
                    .padding(18)
                    .glassCard(cornerRadius: 18)

                    // MARK: - Métadonnées du devoir
                    VStack(alignment: .leading, spacing: 14) {
                        HStack {
                            Image(systemName: "slider.horizontal.3")
                                .font(.title3)
                                .foregroundColor(.purple)
                            Text("Informations sur l'évaluation")
                                .font(.headline)
                        }

                        Grid(alignment: .leading, horizontalSpacing: 20, verticalSpacing: 14) {
                            GridRow {
                                Text("Classe concernée :")
                                    .font(.subheadline)
                                    .foregroundColor(.secondary)
                                Picker("Classe", selection: $selectedClassId) {
                                    Text("— Sélectionner une classe —").tag(nil as String?)
                                    ForEach(appState.classes) { cls in
                                        Text("\(cls.name) (\(cls.studentCount) élèves)").tag(cls.id as String?)
                                    }
                                }
                                .pickerStyle(.menu)
                            }

                            GridRow {
                                Text("Titre de l'évaluation :")
                                    .font(.subheadline)
                                    .foregroundColor(.secondary)
                                TextField("Ex: Devoir Maison n°3, Contrôle Chapitre 4...", text: $evalTitle)
                                    .textFieldStyle(.roundedBorder)
                            }

                            GridRow {
                                Text("Date de passation :")
                                    .font(.subheadline)
                                    .foregroundColor(.secondary)
                                DatePicker("", selection: $evalDate, displayedComponents: .date)
                                    .labelsHidden()
                            }

                            GridRow {
                                Text("Note maximale (Barème) :")
                                    .font(.subheadline)
                                    .foregroundColor(.secondary)
                                HStack {
                                    TextField("20", value: $evalMaxScore, format: .number)
                                        .textFieldStyle(.roundedBorder)
                                        .frame(width: 80)
                                    Text("points")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                            }
                        }
                    }
                    .padding(18)
                    .glassCard(cornerRadius: 18)

                    // MARK: - Paramètres de découpage des copies
                    VStack(alignment: .leading, spacing: 14) {
                        HStack {
                            Image(systemName: "scissors")
                                .font(.title3)
                                .foregroundColor(.teal)
                            Text("Découpage des copies")
                                .font(.headline)
                        }

                        HStack(spacing: 20) {
                            VStack(alignment: .leading, spacing: 6) {
                                Text("Nombre de pages par copie élève :")
                                    .font(.subheadline)
                                    .foregroundColor(.secondary)

                                Picker("Pages par copie", selection: $pagesPerCopy) {
                                    ForEach(1...6, id: \.self) { n in
                                        Text("\(n) \(n > 1 ? "pages" : "page")").tag(n)
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
                    .padding(18)
                    .glassCard(cornerRadius: 18)
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

    // MARK: - Contrôle d'onglets Liquid Glass

    private var modeTabsControl: some View {
        HStack(spacing: 6) {
            ForEach(LoadingMode.allCases) { m in
                let isSelected = mode == m
                Button {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                        mode = m
                        handleModeChange(m)
                    }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: m == .newEvaluation ? "doc.badge.plus" : "arrow.triangle.merge")
                            .font(.system(size: 12))
                        Text(m.rawValue)
                            .font(.system(size: 13, weight: isSelected ? .bold : .medium))
                    }
                    .foregroundColor(isSelected ? .white : .primary)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(
                        Group {
                            if isSelected {
                                Capsule()
                                    .fill(LinearGradient.electricBlue)
                                    .matchedGeometryEffect(id: "modeTabPill", in: modeTabNamespace)
                                    .shadow(color: Color.blue.opacity(0.35), radius: 6, y: 2)
                            } else {
                                Color.clear
                            }
                        }
                    )
                    .clipShape(Capsule())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(4)
        .background(Color.primary.opacity(0.06))
        .clipShape(Capsule())
    }

    // MARK: - Actions

    private func loadInitialScansAndBackups() async {
        if let scans = try? await appState.storageManager.listScans() {
            self.availableScans = scans
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
