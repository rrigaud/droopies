//
//  Step2LoadingView.swift
//  Droopies
//
//  Étape 1 du workflow de Distribution :
//  Chargement des copies & Préparation de l'évaluation (Découpage, métadonnées et prévisualisation continue).
//  Architecture compacte à 4 blocs optimisée pour visionOS / iPadOS 18 :
//  1. Fonctionnement de la distribution (explication claire)
//  2. Sélection de l'évaluation corrigée + Pages par copie (selectbutton 1 à 4 avec bouton '+' popover)
//  3. Informations sur l'évaluation (Date YYYY-MM-DD, Classe, Nom, Barème)
//  4. Prévisualisation plein écran à 100% de la largeur avec défilement continu
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
    @Namespace private var pagesNamespace

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

    // Découpage et options de pages
    @State private var pagesPerCopy: Int = 2
    @State private var availablePageStops: [Int] = [1, 2, 3, 4]
    @State private var showCustomPagesPopover: Bool = false
    @State private var customPagesInput: String = ""

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

    private var correctedScans: [StorageManager.ScanItem] {
        availableScans.filter { $0.isCorrected }
    }

    public var body: some View {
        VStack(spacing: 0) {
            // MARK: - Barre d'outils supérieure flottante
            HStack(spacing: 16) {
                // Onglets Glissants Liquid Glass
                modeTabsControl

                Spacer()

                Button {
                    proceedToIdentification()
                } label: {
                    Label("Découper puis identifier (2) ➔", systemImage: "scissors")
                }
                .buttonStyle(VibrantGradientButtonStyle(gradient: .emeraldGreen, isCompact: true))
                .disabled(loadedPDFDoc == nil || evalTitle.trimmingCharacters(in: .whitespaces).isEmpty || selectedClassId == nil)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(.ultraThinMaterial)

            Divider()

            // MARK: - Les 4 Blocs
            VStack(spacing: 10) {
                // Bloc 1 : Fonctionnement de la distribution
                distributionInfoCard

                // Bloc 2 : Sélection de l'évaluation corrigée + Pages par copie (sur 1 seule ligne)
                evaluationSelectionBar

                // Bloc 3 : Informations sur l'évaluation (sur 1 seule ligne)
                evaluationMetadataBar

                // Bloc 4 : Prévisualisation PDF (prend tout l'espace restant, 100% largeur)
                pdfPreviewSection
            }
            .padding(14)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
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

    // MARK: - En-tête : Onglets Glissants Liquid Glass

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

    // MARK: - Bloc 1 : Fonctionnement de la distribution

    private var distributionInfoCard: some View {
        HStack(alignment: .center, spacing: 10) {
            Image(systemName: "info.circle.fill")
                .foregroundColor(.blue)
                .font(.system(size: 15))

            VStack(alignment: .leading, spacing: 2) {
                Text("Fonctionnement de la distribution")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(.primary)

                Text("Lorsque vous aurez sélectionné et identifié votre évaluation, elle sera archivée dans le dossier /Backup et découpée en copies individuelles, qu'il faudra alors identifier à chaque élève de la classe pour pouvoir leur distribuer dans leur espace sécurisé en ligne.")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                    .lineLimit(2)
            }

            Spacer()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(Color.primary.opacity(0.035))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color.primary.opacity(0.08), lineWidth: 1)
        )
    }

    // MARK: - Bloc 2 : Sélection de l'évaluation corrigée + Pages par copie (1 seule ligne)

    private var evaluationSelectionBar: some View {
        HStack(spacing: 14) {
            // Menulist natif proposant les évaluations corrigées
            HStack(spacing: 6) {
                Image(systemName: "checkmark.seal.fill")
                    .foregroundColor(Color(hex: "10B981"))
                    .font(.system(size: 13))

                Menu {
                    if correctedScans.isEmpty {
                        Text("Aucune évaluation corrigée trouvée").foregroundColor(.secondary)
                    } else {
                        ForEach(correctedScans) { scan in
                            Button {
                                selectScan(scan)
                            } label: {
                                HStack {
                                    Text(scan.cleanTitle)
                                    if selectedScan?.id == scan.id {
                                        Image(systemName: "checkmark")
                                    }
                                }
                            }
                        }
                    }

                    Divider()

                    Button {
                        isExternalPickerPresented = true
                    } label: {
                        Label("Importer un autre PDF depuis le disque...", systemImage: "plus.rectangle.on.folder")
                    }
                } label: {
                    HStack(spacing: 6) {
                        Text(selectedScan?.cleanTitle ?? (correctedScans.isEmpty ? "Aucune évaluation corrigée" : "Sélectionner une évaluation corrigée..."))
                            .font(.system(size: 12.5, weight: .semibold))
                            .foregroundColor(selectedScan != nil ? .primary : .secondary)
                            .lineLimit(1)
                            .frame(maxWidth: 290, alignment: .leading)

                        Image(systemName: "chevron.up.chevron.down")
                            .font(.system(size: 8.5, weight: .bold))
                            .foregroundColor(.secondary)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Color.primary.opacity(0.05))
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                }
                .buttonStyle(.plain)
            }

            // En mode rattrapage : choix du backup existant
            if mode == .catchUpAbsents {
                HStack(spacing: 6) {
                    Image(systemName: "arrow.triangle.merge")
                        .foregroundColor(.orange)
                        .font(.system(size: 12))

                    Picker("Backup", selection: $selectedBackup) {
                        Text("— Backup archivé —").tag(nil as StorageManager.ExistingBackup?)
                        ForEach(existingBackups) { backup in
                            Text("\(backup.className) • \(backup.evaluationTitle)").tag(backup as StorageManager.ExistingBackup?)
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

            Spacer()

            // À droite : "Nombre de pages par copies :" + selectbutton glissant 1..4 avec bouton '+'
            HStack(spacing: 8) {
                Text("Nombre de pages par copies :")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.secondary)

                pagesPerCopySlidingSelector
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .glassCard(cornerRadius: 12, strokeOpacity: 0.3)
    }

    // MARK: - Sélecteur Glissant de Pages par Copie

    private var pagesPerCopySlidingSelector: some View {
        HStack(spacing: 2) {
            ForEach(availablePageStops, id: \.self) { num in
                let isSelected = (pagesPerCopy == num)
                Button {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.75)) {
                        pagesPerCopy = num
                    }
                } label: {
                    Text("\(num)")
                        .font(.system(size: 12, weight: isSelected ? .bold : .medium))
                        .foregroundColor(isSelected ? .white : .primary)
                        .frame(width: 28, height: 26)
                        .background(
                            Group {
                                if isSelected {
                                    Capsule()
                                        .fill(LinearGradient.electricBlue)
                                        .matchedGeometryEffect(id: "pagesPerCopyPill", in: pagesNamespace)
                                        .shadow(color: Color.blue.opacity(0.35), radius: 4, y: 1)
                                } else {
                                    Color.clear
                                }
                            }
                        )
                        .clipShape(Capsule())
                }
                .buttonStyle(.plain)
            }

            // Bouton + affichant le popover de saisie personnalisée
            Button {
                customPagesInput = ""
                showCustomPagesPopover = true
            } label: {
                Image(systemName: "plus")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(.secondary)
                    .frame(width: 24, height: 26)
                    .background(Color.primary.opacity(0.04))
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)
            .popover(isPresented: $showCustomPagesPopover) {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Pages par copie personnalisé")
                        .font(.system(size: 12, weight: .bold))

                    HStack {
                        TextField("Ex: 5, 6, 8...", text: $customPagesInput)
                            #if os(iOS)
                            .keyboardType(.numberPad)
                            #endif
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 90)

                        Button("Ajouter") {
                            if let val = Int(customPagesInput), val > 0 {
                                if !availablePageStops.contains(val) {
                                    availablePageStops.append(val)
                                    availablePageStops.sort()
                                }
                                withAnimation(.spring(response: 0.3, dampingFraction: 0.75)) {
                                    pagesPerCopy = val
                                }
                                showCustomPagesPopover = false
                            }
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(Int(customPagesInput) == nil || (Int(customPagesInput) ?? 0) <= 0)
                    }
                }
                .padding(14)
                .frame(width: 230)
            }
        }
        .padding(3)
        .background(Color.primary.opacity(0.06))
        .clipShape(Capsule())
    }

    // MARK: - Bloc 3 : Informations sur l'évaluation (1 seule ligne)

    private var evaluationMetadataBar: some View {
        HStack(spacing: 16) {
            // 1. Date (Datepicker natif, date du jour par défaut)
            HStack(spacing: 6) {
                Image(systemName: "calendar")
                    .foregroundColor(.purple)
                    .font(.system(size: 13))

                Text("Date :")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.secondary)

                DatePicker("", selection: $evalDate, displayedComponents: .date)
                    .labelsHidden()
            }

            Divider().frame(height: 18)

            // 2. Classe (Menulist natif)
            HStack(spacing: 6) {
                Image(systemName: "person.2.fill")
                    .foregroundColor(.blue)
                    .font(.system(size: 13))

                Text("Classe :")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.secondary)

                Menu {
                    ForEach(appState.classes) { cls in
                        Button {
                            selectedClassId = cls.id
                            if let doc = loadedPDFDoc {
                                autoSelectPagesPerCopy(for: doc)
                            }
                        } label: {
                            HStack {
                                Text("\(cls.name) (\(cls.studentCount) élèves)")
                                if selectedClassId == cls.id {
                                    Image(systemName: "checkmark")
                                }
                            }
                        }
                    }
                } label: {
                    HStack(spacing: 5) {
                        let currentClass = appState.classes.first(where: { $0.id == selectedClassId })
                        Text(currentClass != nil ? "\(currentClass!.name) (\(currentClass!.studentCount) élèves)" : "— Choisir une classe —")
                            .font(.system(size: 12.5, weight: .semibold))
                            .foregroundColor(currentClass != nil ? .primary : .secondary)

                        Image(systemName: "chevron.up.chevron.down")
                            .font(.system(size: 8.5, weight: .bold))
                            .foregroundColor(.secondary)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Color.primary.opacity(0.05))
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                }
                .buttonStyle(.plain)
            }

            Divider().frame(height: 18)

            // 3. Nom de l'évaluation
            HStack(spacing: 6) {
                Image(systemName: "pencil")
                    .foregroundColor(.orange)
                    .font(.system(size: 13))

                Text("Nom :")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.secondary)

                TextField("Nom de l'évaluation...", text: $evalTitle)
                    .font(.system(size: 12.5))
                    .textFieldStyle(.roundedBorder)
            }

            // Note maximale (Barème)
            HStack(spacing: 4) {
                Text("/")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(.secondary)

                TextField("20", value: $evalMaxScore, format: .number)
                    .font(.system(size: 12, weight: .semibold))
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 44)

                Text("pts")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .glassCard(cornerRadius: 12, strokeOpacity: 0.3)
    }

    // MARK: - Bloc 4 : Prévisualisation PDF Plein Écran Défilable

    private var pdfPreviewSection: some View {
        Group {
            if let doc = loadedPDFDoc {
                VStack(spacing: 0) {
                    HStack {
                        Label("\(totalPages) page(s) au total", systemImage: "doc.text")
                            .font(.caption2)
                            .foregroundColor(.secondary)

                        Spacer()

                        Text("Estimation : \(estimatedCopiesCount) copie(s) élève(s)")
                            .font(.caption.bold())
                            .foregroundColor(Color(hex: "10B981"))
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 6)
                    .background(Color.primary.opacity(0.03))

                    Divider()

                    PDFContinuousPreviewView(document: doc)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                .glassCard(cornerRadius: 14, strokeOpacity: 0.35)
            } else {
                VStack(spacing: 12) {
                    Image(systemName: "doc.viewfinder")
                        .font(.system(size: 38))
                        .foregroundColor(.secondary.opacity(0.35))

                    Text("Aucune évaluation sélectionnée pour la prévisualisation")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .glassCard(cornerRadius: 14, strokeOpacity: 0.3)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Actions & Logique Métier

    private func loadInitialScansAndBackups() async {
        if let scans = try? await appState.storageManager.listScans() {
            self.availableScans = scans
            let corrected = scans.filter { $0.isCorrected }
            if let firstCorrected = corrected.first {
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
            autoSelectPagesPerCopy(for: doc)
        }
    }

    private func autoSelectPagesPerCopy(for doc: PDFDocument) {
        let classSize = appState.studentsInSelectedClass.count > 0 ? appState.studentsInSelectedClass.count : 28
        let estimated = Evaluation.estimatePagesPerCopy(totalPages: doc.pageCount, expectedClassSize: classSize)
        if !availablePageStops.contains(estimated) {
            availablePageStops.append(estimated)
            availablePageStops.sort()
        }
        withAnimation(.spring(response: 0.3, dampingFraction: 0.75)) {
            self.pagesPerCopy = estimated
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
        currentStep = 2
    }
}
