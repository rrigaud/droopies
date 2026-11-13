//
//  Step2LoadingView.swift
//  Droopies
//
//  Étape 1 du workflow de Distribution :
//  Chargement des copies & Préparation de l'évaluation (Découpage, métadonnées et prévisualisation continue).
//  Architecture compacte à 4 blocs optimisée pour visionOS / iPadOS 18 :
//  1. Fonctionnement de la distribution (explication claire)
//  2. Sélection de l'évaluation corrigée (Picker natif) + Pages par copie (selectbutton 1..4 avec '+' puis 'pages / copie')
//  3. Informations sur l'évaluation (Date YYYY-MM-DD avec fermeture auto, Classe via Picker natif, Nom)
//  4. Prévisualisation plein écran à 100% de la largeur avec défilement continu
//

import SwiftUI
import PDFKit
import UniformTypeIdentifiers

public struct Step2LoadingView: View {
    @Bindable public var appState: AppState
    @Binding public var currentStep: Int

    public enum LoadingMode: String, CaseIterable, Identifiable {
        case newEvaluation = "Nouvelle distribution"
        case catchUpAbsents = "Compléter une distribution"

        public var id: String { rawValue }
    }

    @State private var mode: LoadingMode = CommandLine.arguments.contains("-testCatchUp") ? .catchUpAbsents : .newEvaluation
    @Namespace private var modeTabNamespace
    @Namespace private var pagesNamespace

    @State private var availableScans: [StorageManager.ScanItem] = []
    @State private var selectedScan: StorageManager.ScanItem? = nil
    @State private var existingBackups: [StorageManager.ExistingBackup] = []
    @State private var selectedBackup: StorageManager.ExistingBackup? = nil

    @State private var pdfURL: URL? = nil
    @State private var loadedPDFDoc: PDFDocument? = nil
    @State private var isLoadingPDF: Bool = false
    @State private var pdfLoadingTask: Task<Void, Never>? = nil
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
        availableScans.filter { scan in
            scan.isCorrected || appState.evaluationsMetadata[scan.rawFileName]?.isEffectivelyCompleted == true
        }
    }

    /// Validation stricte : toutes les informations nécessaires doivent être complétées
    private var isReadyToProceed: Bool {
        guard loadedPDFDoc != nil else { return false }
        guard selectedScan != nil else { return false }
        guard selectedClassId != nil else { return false }
        guard !evalTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return false }
        if mode == .catchUpAbsents {
            guard selectedBackup != nil else { return false }
        }
        return true
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
                // Temporairement débloqué sans condition pour permettre de travailler directement sur l'interface du Step 2
                // .disabled(!isReadyToProceed)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(.ultraThinMaterial)

            Divider()

            // MARK: - Les Blocs
            VStack(spacing: 10) {
                // Bloc 1 : Fonctionnement de la distribution
                distributionInfoCard

                // Bloc Mode Rattrapage (uniquement en mode rattrapage)
                if mode == .catchUpAbsents {
                    catchUpBackupBlock
                        .transition(.move(edge: .top).combined(with: .opacity))
                }

                // Bloc 2 : Évaluation à distribuer (regroupe sélection du PDF, découpage et métadonnées)
                evaluationToDistributeCard

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
                let filename = url.lastPathComponent
                if let detectedClassId = detectClass(from: filename) {
                    self.selectedClassId = detectedClassId
                } else {
                    self.selectedClassId = nil
                }
                self.evalTitle = url.deletingPathExtension().lastPathComponent
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
                        Image(systemName: m == .newEvaluation ? "doc.badge.plus" : "archivebox.fill")
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

    // MARK: - Bloc Compléter une distribution (Sélection de l'évaluation archivée)

    private var catchUpBackupBlock: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 8) {
                Image(systemName: "archivebox.fill")
                    .foregroundColor(.orange)
                    .font(.system(size: 13, weight: .semibold))

                Text("Compléter une distribution en sélectionnant l'évaluation archivée :")
                    .font(.system(size: 12.5, weight: .bold))
                    .foregroundColor(.primary)
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)

                Spacer()

                // Picker collé à droite
                Picker("Évaluation archivée", selection: $selectedBackup) {
                    Text("Sélectionner...").tag(nil as StorageManager.ExistingBackup?)
                    ForEach(existingBackups) { backup in
                        Text("\(backup.className) • \(backup.evaluationTitle)").tag(backup as StorageManager.ExistingBackup?)
                    }
                }
                .pickerStyle(.menu)
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
                .onChange(of: selectedBackup) { _, newBackup in
                    if let b = newBackup {
                        applyBackupMetadata(b)
                    }
                }
            }

            // Ligne d'information au-dessous
            HStack(spacing: 6) {
                Text("Les informations de cette évaluation archivée seront pré-chargées sur la page, et la nouvelle évaluation sera fusionnée à cette dernière.")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                    .lineLimit(1)

                Spacer()

                if let backup = selectedBackup {
                    HStack(spacing: 4) {
                        Image(systemName: "folder")
                            .font(.system(size: 10))
                            .foregroundColor(.secondary)
                        Text("/Backup/\(backup.className)/\(backup.fileName)")
                            .font(.system(size: 10.5, design: .monospaced))
                            .foregroundColor(.secondary)
                    }
                }
            }
            .padding(.leading, 21)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.orange.opacity(0.08))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color.orange.opacity(0.35), lineWidth: 1)
        )
    }

    // MARK: - Bloc 2 : Évaluation à distribuer (Regroupe sélection du PDF, découpage et métadonnées)

    private var evaluationToDistributeCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            // En-tête : Titre du bloc
            HStack(spacing: 7) {
                Image(systemName: "doc.text.fill")
                    .foregroundColor(.blue)
                    .font(.system(size: 13, weight: .semibold))

                Text("Évaluation à distribuer")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(.primary)

                Spacer()
            }

            // Ligne 1 : Sélection de l'évaluation corrigée + Pages par copie
            HStack(spacing: 14) {
                HStack(spacing: 6) {
                    Image(systemName: "folder")
                        .foregroundColor(.blue)
                        .font(.system(size: 13))

                    Text("Évaluation :")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.secondary)
                        .fixedSize(horizontal: true, vertical: false)

                    Picker("Évaluation", selection: $selectedScan) {
                        if correctedScans.isEmpty {
                            Text("Aucune évaluation corrigée").tag(nil as StorageManager.ScanItem?)
                        } else {
                            ForEach(correctedScans) { scan in
                                Text(scan.cleanTitle).tag(scan as StorageManager.ScanItem?)
                            }
                        }
                    }
                    .pickerStyle(.menu)
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
                    .onChange(of: selectedScan) { _, newScan in
                        if let scan = newScan {
                            selectScan(scan)
                        }
                    }

                    Button {
                        isExternalPickerPresented = true
                    } label: {
                        Image(systemName: "folder.badge.plus")
                            .font(.system(size: 12))
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                    .help("Importer un autre PDF depuis le disque...")
                }

                Spacer()

                // À droite : selectbutton glissant 1..4 avec '+' PUIS 'pages / copie'
                HStack(spacing: 8) {
                    pagesPerCopySlidingSelector

                    Text("pages / copie")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.secondary)
                }
            }

            Divider()

            // Ligne 2 : Informations sur l'évaluation (Date, Classe, Nom)
            HStack(spacing: 16) {
                // 1. Date (DatePicker natif Apple .compact)
                HStack(spacing: 6) {
                    Image(systemName: "calendar")
                        .foregroundColor(.purple)
                        .font(.system(size: 13))

                    Text("Date :")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.secondary)

                    DatePicker("", selection: $evalDate, displayedComponents: .date)
                        .labelsHidden()
                        .datePickerStyle(.compact)
                }
                .fixedSize(horizontal: true, vertical: false)

                Divider().frame(height: 18)

                // 2. Classe (Picker natif Apple .pickerStyle(.menu))
                HStack(spacing: 6) {
                    Image(systemName: "person.2.fill")
                        .foregroundColor(.blue)
                        .font(.system(size: 13))

                    Text("Classe :")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.secondary)

                    Picker("Classe", selection: $selectedClassId) {
                        Text("— Choisir une classe —").tag(nil as String?)
                        ForEach(appState.classes) { cls in
                            Text("\(cls.name) (\(cls.studentCount) élèves)").tag(cls.id as String?)
                        }
                    }
                    .pickerStyle(.menu)
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
                    .onChange(of: selectedClassId) { _, _ in
                        if let doc = loadedPDFDoc {
                            autoSelectPagesPerCopy(for: doc)
                        }
                    }
                }
                .fixedSize(horizontal: true, vertical: false)

                Divider().frame(height: 18)

                // 3. Nom de l'évaluation
                HStack(spacing: 6) {
                    Image(systemName: "pencil")
                        .foregroundColor(.orange)
                        .font(.system(size: 13))

                    Text("Nom :")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.secondary)
                        .fixedSize(horizontal: true, vertical: false)

                    TextField("Nom de l'évaluation...", text: $evalTitle)
                        .font(.system(size: 12.5))
                        .textFieldStyle(.roundedBorder)
                }
            }
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

    // MARK: - Bloc 4 : Prévisualisation PDF Plein Écran Défilable

    private var pdfPreviewSection: some View {
        Group {
            if isLoadingPDF {
                VStack(spacing: 16) {
                    ProgressView()
                        .controlSize(.large)
                        .tint(.blue)

                    VStack(spacing: 4) {
                        Text("Chargement de l'évaluation...")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(.primary)

                        Text("Préparation de l'affichage du document")
                            .font(.system(size: 12))
                            .foregroundColor(.secondary)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .glassCard(cornerRadius: 14, strokeOpacity: 0.3)
            } else if let doc = loadedPDFDoc {
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

    /// Détection automatique de la classe dans le nom du fichier (ex: Controle_3e2.pdf -> "3e2")
    private func detectClass(from fileName: String) -> String? {
        let baseName = fileName.replacingOccurrences(of: ".pdf", with: "", options: [.caseInsensitive])

        // Trier les classes par longueur de nom décroissante pour privilégier les noms plus spécifiques (ex: "3e10" avant "3e1")
        let sortedClasses = appState.classes.sorted { $0.name.count > $1.name.count }

        for cls in sortedClasses {
            let rawName = cls.name.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !rawName.isEmpty else { continue }

            var variations: [String] = [
                rawName,
                rawName.replacingOccurrences(of: " ", with: "_"),
                rawName.replacingOccurrences(of: " ", with: "-"),
                rawName.replacingOccurrences(of: " ", with: "")
            ]

            // Si le nom contient une forme condensée comme "3e1", tester aussi les variantes avec séparateur "3e 1", "3e_1", "3e-1"
            if let regexNumLet = try? NSRegularExpression(pattern: "^(\\d+e)(\\d+|[A-Za-z])$", options: .caseInsensitive) {
                let range = NSRange(location: 0, length: rawName.utf16.count)
                if let match = regexNumLet.firstMatch(in: rawName, options: [], range: range) {
                    if let r1 = Range(match.range(at: 1), in: rawName),
                       let r2 = Range(match.range(at: 2), in: rawName) {
                        let part1 = String(rawName[r1])
                        let part2 = String(rawName[r2])
                        variations.append("\(part1) \(part2)")
                        variations.append("\(part1)_\(part2)")
                        variations.append("\(part1)-\(part2)")
                    }
                }
            }

            for variation in Set(variations) {
                let escaped = NSRegularExpression.escapedPattern(for: variation)
                // Délimité par le début/fin de chaîne ou un délimiteur usuel (espace, _, -, ., (, ), [, ], #)
                let pattern = "(?i)(?:^|[\\s_\\-\\.\\[\\]()#])" + escaped + "(?:$|[\\s_\\-\\.\\[\\]()#])"
                if let regex = try? NSRegularExpression(pattern: pattern) {
                    let range = NSRange(location: 0, length: baseName.utf16.count)
                    if regex.firstMatch(in: baseName, options: [], range: range) != nil {
                        return cls.id
                    }
                }
            }
        }

        return nil
    }

    private func loadInitialScansAndBackups() async {
        isLoadingPDF = true
        if let scans = try? await appState.storageManager.listScans() {
            self.availableScans = scans
            let corrected = self.correctedScans
            if let target = appState.targetScanForDistribution, let matched = scans.first(where: { $0.path == target.path || $0.rawFileName == target.rawFileName }) {
                selectScan(matched)
                appState.targetScanForDistribution = nil
            } else if let firstCorrected = corrected.first {
                selectScan(firstCorrected)
            } else if let first = scans.first {
                selectScan(first)
            } else {
                isLoadingPDF = false
            }
        } else {
            isLoadingPDF = false
        }

        if let backups = try? await appState.storageManager.listExistingBackups() {
            self.existingBackups = backups
            if mode == .catchUpAbsents, let first = backups.first {
                self.selectedBackup = first
                applyBackupMetadata(first)
            }
        }
    }

    private func selectScan(_ scan: StorageManager.ScanItem) {
        selectedScan = scan
        if let detected = detectClass(from: scan.name) {
            self.selectedClassId = detected
        } else {
            self.selectedClassId = nil
        }
        self.evalTitle = scan.cleanTitle.replacingOccurrences(of: ".pdf", with: "")
        let url = appState.storageManager.localURL(for: "Evaluations/A corriger/\(scan.name)")
        loadPDF(from: url)
    }

    private func loadPDF(from url: URL) {
        pdfLoadingTask?.cancel()
        isLoadingPDF = true
        loadedPDFDoc = nil
        pdfURL = url

        pdfLoadingTask = Task {
            // Céder brièvement pour s'assurer que le spinner s'affiche immédiatement
            await Task.yield()

            let isAccessing = url.startAccessingSecurityScopedResource()
            defer {
                if isAccessing { url.stopAccessingSecurityScopedResource() }
            }

            let doc = try? PDFEngine.shared.loadDocument(from: url)

            guard !Task.isCancelled else { return }

            self.loadedPDFDoc = doc
            self.isLoadingPDF = false
            if let doc = doc {
                autoSelectPagesPerCopy(for: doc)
            }
        }
    }

    private func autoSelectPagesPerCopy(for doc: PDFDocument) {
        let matchingGroup = appState.classes.first(where: { $0.id == selectedClassId })
        let classSize = (matchingGroup?.studentCount ?? 0) > 0 ? (matchingGroup?.studentCount ?? 28) : (appState.studentsInSelectedClass.count > 0 ? appState.studentsInSelectedClass.count : 28)
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
        } else {
            self.selectedBackup = nil
            if let scan = selectedScan {
                self.evalTitle = scan.cleanTitle.replacingOccurrences(of: ".pdf", with: "")
            }
        }
    }

    private func applyBackupMetadata(_ backup: StorageManager.ExistingBackup) {
        // Pré-remplissage automatique des métadonnées (Date, Classe, Nom) à partir du nom du fichier archivé
        if let parsed = Evaluation.parseBackupFileName(backup.fileName) {
            if !parsed.title.isEmpty {
                self.evalTitle = parsed.title
            }
            if let d = parsed.date {
                self.evalDate = d
            }
            if let matchingGroup = appState.classes.first(where: {
                $0.name.lowercased() == parsed.className.lowercased() ||
                Student.sanitizeFolderName($0.name).lowercased() == Student.sanitizeFolderName(parsed.className).lowercased()
            }) {
                self.selectedClassId = matchingGroup.id
            }
        } else {
            if !backup.evaluationTitle.isEmpty {
                self.evalTitle = backup.evaluationTitle
            }
            if let d = backup.date {
                self.evalDate = d
            }
            if let matchingGroup = appState.classes.first(where: {
                $0.name.lowercased() == backup.className.lowercased() ||
                Student.sanitizeFolderName($0.name).lowercased() == Student.sanitizeFolderName(backup.className).lowercased()
            }) {
                self.selectedClassId = matchingGroup.id
            }
        }
    }

    private func proceedToIdentification() {
        if let doc = loadedPDFDoc {
            let selectedGroup = appState.classes.first(where: { $0.id == selectedClassId })?.name ?? "3e1"

            var eval = Evaluation(
                title: evalTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Évaluation" : evalTitle.trimmingCharacters(in: .whitespacesAndNewlines),
                date: evalDate,
                className: selectedGroup,
                maxScore: evalMaxScore,
                pagesPerCopy: pagesPerCopy,
                isCatchUp: mode == .catchUpAbsents,
                existingBackupFileName: selectedBackup?.fileName,
                sourcePDFURL: selectedScan?.fileURL
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
            appState.selectedClassId = selectedClassId ?? appState.classes.first?.id
        } else {
            // Mode de travail direct : génération de copies mock pour concevoir et itérer sur l'interface du Step 2 (Identification)
            let defaultClass = appState.classes.first?.name ?? "3e1"
            let defaultClassId = appState.classes.first?.id
            let sampleScanURL = appState.storageManager.listLocalScansSync().first?.fileURL
            var mockEval = Evaluation(
                title: evalTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Devoir_SVT_Genetique_3e3" : evalTitle,
                date: evalDate,
                className: defaultClass,
                maxScore: 20.0,
                pagesPerCopy: pagesPerCopy,
                isCatchUp: mode == .catchUpAbsents,
                existingBackupFileName: selectedBackup?.fileName,
                sourcePDFURL: sampleScanURL
            )
            mockEval.copies = [
                StudentCopy(index: 1, pageStart: 1, pageEnd: 2),
                StudentCopy(index: 2, pageStart: 3, pageEnd: 4),
                StudentCopy(index: 3, pageStart: 5, pageEnd: 6)
            ]
            appState.currentEvaluation = mockEval
            appState.selectedClassId = defaultClassId
        }

        withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
            currentStep = 2
        }
    }
}
