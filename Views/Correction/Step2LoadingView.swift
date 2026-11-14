//
//  Step2LoadingView.swift
//  Droopies
//
//  Étape 1 du workflow de Distribution :
//  Chargement des copies & Préparation de l'évaluation (Découpage, métadonnées et prévisualisation continue).
//  Architecture épurée :
//  - Le bouton "Identifier" est logé en haut à droite de la barre d'outils native.
//  - Affichage direct du paquet sélectionné (plus de menu déroulant imposé) + sélecteur pages/copie.
//  - Choix du mode via 2 chips ("Nouvelle distribution" / "Compléter une distribution" avec popover filtrable).
//  - Prévisualisation plein écran en bas sur tout l'espace restant.
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
    @Namespace private var pagesNamespace

    @State private var availableScans: [StorageManager.ScanItem] = []
    @State private var selectedScan: StorageManager.ScanItem? = nil
    @State private var existingBackups: [StorageManager.ExistingBackup] = []
    @State private var isLoadingBackups: Bool = true
    @State private var selectedBackup: StorageManager.ExistingBackup? = nil

    // Popover de sélection d'archive Backup (pour "Compléter une distribution")
    @State private var showBackupPickerPopover: Bool = false
    @State private var backupSearchQuery: String = ""
    @State private var selectedBackupClassFilter: String = "Toutes"

    @State private var pdfURL: URL? = nil
    @State private var loadedPDFDoc: PDFDocument? = nil
    @State private var isPreparingPage: Bool = true
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

    private static let backupDisplayDateFormatter: DateFormatter = {
        let df = DateFormatter()
        df.locale = Locale(identifier: "fr_FR")
        df.dateStyle = .medium
        df.timeStyle = .none
        return df
    }()

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

    private var displayedScanTitle: String {
        if let scan = selectedScan {
            return scan.cleanTitle
        }
        if let url = pdfURL {
            return url.deletingPathExtension().lastPathComponent
        }
        return "Aucune évaluation sélectionnée"
    }

    private var isSelectedScanCompleted: Bool {
        guard let scan = selectedScan else { return false }
        return scan.isCorrected || appState.evaluationsMetadata[scan.rawFileName]?.isEffectivelyCompleted == true
    }

    /// Liste unique et triée des classes disponibles dans les archives /Backup et dans la base élèves
    private var availableBackupClasses: [String] {
        var names = Set(appState.classes.map { $0.name })
        for backup in existingBackups where !backup.className.isEmpty {
            names.insert(backup.className)
        }
        return names.sorted { $0.localizedStandardCompare($1) == .orderedAscending }
    }

    private func backupCountForClass(_ className: String) -> Int {
        existingBackups.filter {
            $0.className.caseInsensitiveCompare(className) == .orderedSame ||
            Student.sanitizeFolderName($0.className).caseInsensitiveCompare(Student.sanitizeFolderName(className)) == .orderedSame
        }.count
    }

    private var filteredBackups: [StorageManager.ExistingBackup] {
        var list = existingBackups

        if selectedBackupClassFilter != "Toutes" {
            list = list.filter { backup in
                backup.className.caseInsensitiveCompare(selectedBackupClassFilter) == .orderedSame ||
                Student.sanitizeFolderName(backup.className).caseInsensitiveCompare(Student.sanitizeFolderName(selectedBackupClassFilter)) == .orderedSame
            }
        }

        let query = backupSearchQuery.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if !query.isEmpty {
            list = list.filter { backup in
                backup.evaluationTitle.lowercased().contains(query) ||
                backup.className.lowercased().contains(query) ||
                backup.fileName.lowercased().contains(query)
            }
        }

        return list
    }

    private var isShowingLoadingOverlay: Bool {
        isPreparingPage || isLoadingPDF
    }

    /// Validation stricte : toutes les informations nécessaires doivent être complétées
    private var isReadyToProceed: Bool {
        guard !isShowingLoadingOverlay else { return false }
        guard loadedPDFDoc != nil else { return false }
        guard pdfURL != nil else { return false }
        guard selectedClassId != nil else { return false }
        guard !evalTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return false }
        if mode == .catchUpAbsents {
            guard selectedBackup != nil else { return false }
        }
        return true
    }

    public var body: some View {
        ZStack {
            VStack(spacing: 10) {
                // Bloc 1 : Rappel compact du fonctionnement
                distributionInfoCard

                // Bloc 2 : Préparation de l'évaluation (Document, Mode en chips, Découpage, Métadonnées ou Archive)
                evaluationToDistributeCard

                // Bloc 3 : Prévisualisation PDF plein écran (prend tout l'espace restant en bas)
                pdfPreviewSection
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 14)
            .padding(.top, 6)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .blur(radius: isShowingLoadingOverlay ? 8 : 0)
            .allowsHitTesting(!isShowingLoadingOverlay)
            .accessibilityHidden(isShowingLoadingOverlay)

            if isShowingLoadingOverlay {
                Color.primary.opacity(0.04)
                    .ignoresSafeArea()
                    .contentShape(Rectangle())

                VStack(spacing: 14) {
                    ProgressView()
                        .controlSize(.large)
                        .tint(.blue)

                    VStack(spacing: 4) {
                        Text("Chargement de l'évaluation...")
                            .font(.system(size: 14.5, weight: .bold, design: .rounded))
                            .foregroundColor(.primary)

                        Text("Préparation du document, des classes et des archives")
                            .font(.system(size: 12))
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                    }
                }
                .padding(.horizontal, 28)
                .padding(.vertical, 22)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .stroke(Color.primary.opacity(0.10), lineWidth: 1)
                )
                .shadow(color: .black.opacity(0.12), radius: 20, x: 0, y: 8)
                .transition(.opacity.combined(with: .scale(scale: 0.96)))
            }
        }
        .animation(.easeInOut(duration: 0.22), value: isShowingLoadingOverlay)
        .onAppear {
            appState.canProceedDistributionStep1 = isReadyToProceed
        }
        .onDisappear {
            appState.canProceedDistributionStep1 = false
        }
        .onChange(of: isReadyToProceed) { _, ready in
            appState.canProceedDistributionStep1 = ready
        }
        .onChange(of: appState.proceedDistributionStep1Trigger) { _, _ in
            guard isReadyToProceed else { return }
            proceedToIdentification()
        }
        .onChange(of: showBackupPickerPopover) { _, isShown in
            if !isShown && mode == .catchUpAbsents && selectedBackup == nil && !CommandLine.arguments.contains("-testCatchUp") {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.75)) {
                    mode = .newEvaluation
                    handleModeChange(.newEvaluation)
                }
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
                self.selectedScan = nil
                let filename = url.lastPathComponent
                if let detectedClassId = detectClass(from: filename) {
                    self.selectedClassId = detectedClassId
                } else {
                    self.selectedClassId = nil
                }
                if mode == .newEvaluation {
                    self.evalTitle = url.deletingPathExtension().lastPathComponent
                }
                loadPDF(from: url)
            }
        }
    }

    // MARK: - Bloc 1 : Fonctionnement de la distribution

    private var distributionInfoCard: some View {
        HStack(alignment: .center, spacing: 10) {
            Image(systemName: "info.circle.fill")
                .foregroundColor(.blue)
                .font(.system(size: 14))

            Text("L'évaluation sera archivée dans `/Backup`, découpée en copies individuelles, puis associée à chaque élève avant l'envoi dans leur espace sécurisé.")
                .font(.system(size: 11.5))
                .foregroundColor(.secondary)
                .lineLimit(2)

            Spacer(minLength: 0)
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

    // MARK: - Bloc 2 : Carte de Préparation (Paquet, Chips Mode, Découpage, Infos)

    private var evaluationToDistributeCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Ligne 1 : Nom du PDF sélectionné (+ option Changer discret) & Sélecteur Pages / Copie
            HStack(spacing: 12) {
                HStack(spacing: 8) {
                    Image(systemName: isSelectedScanCompleted ? "checkmark.circle.fill" : "doc.text.fill")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(isSelectedScanCompleted ? Color(hex: "10B981") : .blue)

                    Text(displayedScanTitle)
                        .font(.system(size: 14, weight: .bold, design: .rounded))
                        .foregroundColor(pdfURL == nil ? .secondary : .primary)
                        .lineLimit(1)
                        .truncationMode(.middle)

                    if totalPages > 0 {
                        Text("\(totalPages) p.")
                            .font(.system(size: 11, weight: .bold, design: .rounded))
                            .padding(.horizontal, 7)
                            .padding(.vertical, 2)
                            .background(Color.primary.opacity(0.07))
                            .foregroundColor(.secondary)
                            .clipShape(Capsule())
                    }

                    // Menu discret pour changer de paquet ou importer un PDF externe
                    Menu {
                        if !availableScans.isEmpty {
                            let completed = correctedScans
                            let others = availableScans.filter { scan in !completed.contains(where: { $0.id == scan.id }) }

                            if !completed.isEmpty {
                                Section("Évaluations corrigées (100 %)") {
                                    ForEach(completed) { scan in
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
                            }

                            if !others.isEmpty {
                                Section("Autres évaluations") {
                                    ForEach(others) { scan in
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
                            }

                            Divider()
                        }

                        Button {
                            isExternalPickerPresented = true
                        } label: {
                            Label("Importer un PDF depuis le disque...", systemImage: "folder.badge.plus")
                        }
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "arrow.triangle.2.circlepath")
                                .font(.system(size: 10.5, weight: .semibold))
                            Text(pdfURL == nil ? "Choisir un PDF" : "Changer")
                                .font(.system(size: 11, weight: .semibold))
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.primary.opacity(0.06))
                        .foregroundColor(.secondary)
                        .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    .help("Choisir une autre évaluation ou importer un fichier PDF")
                }

                Spacer(minLength: 8)

                // À droite : Sélecteur glissant 1..4 avec '+' PUIS 'pages / copie' (toujours visible)
                HStack(spacing: 8) {
                    pagesPerCopySlidingSelector

                    Text("pages / copie")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.secondary)
                        .fixedSize(horizontal: true, vertical: false)
                }
            }

            Divider()

            // Ligne 2 : Type de distribution (2 Chips style StudentEditSheet)
            HStack(spacing: 10) {
                Text("Type :")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.secondary)

                // Chip 1 : Nouvelle distribution
                distributionModeChip(
                    title: "Nouvelle distribution",
                    icon: "doc.badge.plus",
                    isSelected: mode == .newEvaluation,
                    tint: .blue
                ) {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.75)) {
                        mode = .newEvaluation
                        handleModeChange(.newEvaluation)
                    }
                }

                // Chip 2 : Compléter une distribution (avec Popover filtrable des Backups)
                distributionModeChip(
                    title: mode == .catchUpAbsents && selectedBackup != nil
                        ? "Compléter : \(selectedBackup!.evaluationTitle)"
                        : "Compléter une distribution",
                    icon: "archivebox.fill",
                    isSelected: mode == .catchUpAbsents,
                    tint: .orange,
                    showChevron: true
                ) {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.75)) {
                        mode = .catchUpAbsents
                        handleModeChange(.catchUpAbsents)
                    }
                    prepareAndOpenBackupPopover()
                }
                .popover(isPresented: $showBackupPickerPopover, arrowEdge: .top) {
                    backupPickerPopoverContent
                }

                Spacer()
            }

            Divider()

            // Ligne 3 : Contextuelle selon le mode choisi
            if mode == .newEvaluation {
                newDistributionMetadataRow
            } else {
                catchUpSummaryRow
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(Color.primary.opacity(0.035))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color.primary.opacity(0.08), lineWidth: 1)
        )
    }

    @ViewBuilder
    private func distributionModeChip(
        title: String,
        icon: String,
        isSelected: Bool,
        tint: Color,
        showChevron: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: isSelected ? "checkmark" : icon)
                    .font(.system(size: 11, weight: .bold))

                Text(title)
                    .font(.system(size: 12.5, weight: isSelected ? .bold : .medium, design: .rounded))
                    .lineLimit(1)

                if showChevron {
                    Image(systemName: "chevron.down")
                        .font(.system(size: 9.5, weight: .bold))
                        .opacity(0.85)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6.5)
            .background(isSelected ? AnyShapeStyle(tint) : AnyShapeStyle(Color.primary.opacity(0.06)))
            .foregroundColor(isSelected ? .white : .primary)
            .clipShape(Capsule())
            .overlay(
                Capsule()
                    .strokeBorder(isSelected ? tint.opacity(0.4) : Color.primary.opacity(0.12), lineWidth: 1)
            )
            .shadow(color: isSelected ? tint.opacity(0.28) : .clear, radius: 4, x: 0, y: 2)
        }
        .buttonStyle(.plain)
    }

    private var newDistributionMetadataRow: some View {
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
                    .foregroundColor(selectedClassId == nil ? .orange : .blue)
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
                .labelsHidden()
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

    private var catchUpSummaryRow: some View {
        HStack(spacing: 10) {
            if let backup = selectedBackup {
                Image(systemName: "archivebox.fill")
                    .foregroundColor(.orange)
                    .font(.system(size: 13))

                Text("Archive cible :")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.secondary)

                if let d = backup.date {
                    HStack(spacing: 4) {
                        Image(systemName: "calendar")
                            .font(.system(size: 10.5))
                        Text(Self.backupDisplayDateFormatter.string(from: d))
                            .font(.system(size: 11.5, weight: .medium))
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Color.purple.opacity(0.10))
                    .foregroundColor(.purple)
                    .clipShape(Capsule())
                }

                HStack(spacing: 4) {
                    Image(systemName: "person.2.fill")
                        .font(.system(size: 10.5))
                    Text(backup.className)
                        .font(.system(size: 11.5, weight: .bold))
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(Color.blue.opacity(0.12))
                .foregroundColor(.blue)
                .clipShape(Capsule())

                Text(backup.evaluationTitle)
                    .font(.system(size: 12.5, weight: .bold, design: .rounded))
                    .foregroundColor(.primary)
                    .lineLimit(1)
                    .truncationMode(.tail)

                Spacer(minLength: 8)

                Button {
                    prepareAndOpenBackupPopover()
                } label: {
                    Text("Changer d'archive")
                        .font(.system(size: 11.5, weight: .semibold))
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .clipShape(Capsule())
            } else {
                Image(systemName: "exclamationmark.circle.fill")
                    .foregroundColor(.orange)
                    .font(.system(size: 14))

                Text("Aucune archive sélectionnée. Choisissez l'évaluation archivée dans `/Backup` à compléter.")
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
                    .lineLimit(1)

                Spacer(minLength: 8)

                Button {
                    prepareAndOpenBackupPopover()
                } label: {
                    Label("Choisir une archive...", systemImage: "archivebox")
                        .font(.system(size: 12, weight: .semibold))
                }
                .buttonStyle(.borderedProminent)
                .tint(.orange)
                .controlSize(.small)
                .clipShape(Capsule())
            }
        }
        .frame(minHeight: 28)
    }

    // MARK: - Popover de Sélection d'Archive Backup

    private var backupPickerPopoverContent: some View {
        Group {
            if existingBackups.isEmpty && isLoadingBackups {
                VStack(spacing: 14) {
                    ProgressView()
                        .controlSize(.regular)
                        .tint(.orange)

                    VStack(spacing: 6) {
                        Text("Chargement des archives `/Backup`...")
                            .font(.system(size: 14, weight: .bold, design: .rounded))
                            .foregroundColor(.primary)
                            .multilineTextAlignment(.center)
                            .fixedSize(horizontal: false, vertical: true)

                        Text("Récupération de la liste des évaluations archivées")
                            .font(.system(size: 12))
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(.horizontal, 24)
                .padding(.vertical, 22)
                .frame(width: 350)
                .frame(minHeight: 195, alignment: .center)
            } else if existingBackups.isEmpty {
                VStack(spacing: 14) {
                    Image(systemName: "archivebox")
                        .font(.system(size: 32, weight: .medium))
                        .foregroundColor(.orange.opacity(0.8))

                    VStack(spacing: 6) {
                        Text("Aucune évaluation archivée dans `/Backup`")
                            .font(.system(size: 14, weight: .bold, design: .rounded))
                            .foregroundColor(.primary)
                            .multilineTextAlignment(.center)
                            .fixedSize(horizontal: false, vertical: true)

                        Text("Distribuez d'abord une évaluation complète pour créer une archive réutilisable lors d'un rattrapage.")
                            .font(.system(size: 12))
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    Button("Fermer") {
                        showBackupPickerPopover = false
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .clipShape(Capsule())
                }
                .padding(.horizontal, 24)
                .padding(.vertical, 22)
                .frame(width: 350)
                .frame(minHeight: 195, alignment: .center)
            } else {
                VStack(alignment: .leading, spacing: 12) {
                    // En-tête
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Compléter une distribution")
                                .font(.system(size: 14, weight: .bold, design: .rounded))
                            Text("Sélectionnez l'archive `/Backup` cible pour fusionner ces copies")
                                .font(.system(size: 11.5))
                                .foregroundColor(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }

                        Spacer()

                        Text("\(filteredBackups.count)")
                            .font(.system(size: 11, weight: .bold, design: .rounded))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(Color.orange.opacity(0.14))
                            .foregroundColor(.orange)
                            .clipShape(Capsule())
                    }

                    // Barre de filtre : Recherche à gauche + Menu Classe à droite
                    HStack(spacing: 8) {
                        HStack(spacing: 6) {
                            Image(systemName: "magnifyingglass")
                                .foregroundColor(.secondary)
                                .font(.system(size: 12))
                            TextField("Rechercher une archive...", text: $backupSearchQuery)
                                .textFieldStyle(.plain)
                                .font(.system(size: 12.5))
                            if !backupSearchQuery.isEmpty {
                                Button {
                                    backupSearchQuery = ""
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
                        .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))

                        Menu {
                            Button {
                                selectedBackupClassFilter = "Toutes"
                            } label: {
                                HStack {
                                    Text("Toutes les classes (\(existingBackups.count))")
                                    if selectedBackupClassFilter == "Toutes" {
                                        Image(systemName: "checkmark")
                                    }
                                }
                            }

                            Divider()

                            ForEach(availableBackupClasses, id: \.self) { clsName in
                                Button {
                                    selectedBackupClassFilter = clsName
                                } label: {
                                    HStack {
                                        Text("\(clsName) (\(backupCountForClass(clsName)))")
                                        if selectedBackupClassFilter == clsName {
                                            Image(systemName: "checkmark")
                                        }
                                    }
                                }
                            }
                        } label: {
                            HStack(spacing: 5) {
                                Image(systemName: "line.3.horizontal.decrease.circle")
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundColor(.blue)

                                Text(selectedBackupClassFilter == "Toutes" ? "Toutes les classes" : selectedBackupClassFilter)
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundColor(.primary)
                                    .lineLimit(1)

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
                    }

                    Divider()

                    // Liste des Backups filtrés
                    if filteredBackups.isEmpty {
                        VStack(spacing: 10) {
                            Spacer()
                            Image(systemName: "magnifyingglass")
                                .font(.system(size: 26))
                                .foregroundColor(.secondary.opacity(0.45))
                            Text("Aucune archive trouvée")
                                .font(.system(size: 13, weight: .semibold))
                                .multilineTextAlignment(.center)
                                .fixedSize(horizontal: false, vertical: true)
                            if selectedBackupClassFilter != "Toutes" || !backupSearchQuery.isEmpty {
                                Button("Afficher toutes les classes (\(existingBackups.count))") {
                                    selectedBackupClassFilter = "Toutes"
                                    backupSearchQuery = ""
                                }
                                .buttonStyle(.bordered)
                                .controlSize(.small)
                                .clipShape(Capsule())
                            }
                            Spacer()
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else {
                        ScrollView {
                            LazyVStack(spacing: 6) {
                                ForEach(filteredBackups) { backup in
                                    let isChosen = (selectedBackup?.id == backup.id)
                                    Button {
                                        selectedBackup = backup
                                        applyBackupMetadata(backup)
                                        showBackupPickerPopover = false
                                    } label: {
                                        HStack(spacing: 10) {
                                            Image(systemName: isChosen ? "checkmark.circle.fill" : "archivebox.fill")
                                                .font(.system(size: 15, weight: .semibold))
                                                .foregroundColor(isChosen ? .blue : .orange)

                                            VStack(alignment: .leading, spacing: 3) {
                                                Text(backup.evaluationTitle)
                                                    .font(.system(size: 13, weight: .semibold))
                                                    .foregroundColor(.primary)
                                                    .lineLimit(1)

                                                HStack(spacing: 6) {
                                                    Text(backup.className)
                                                        .font(.system(size: 10.5, weight: .bold))
                                                        .padding(.horizontal, 6)
                                                        .padding(.vertical, 1.5)
                                                        .background(Color.blue.opacity(0.12))
                                                        .foregroundColor(.blue)
                                                        .clipShape(Capsule())

                                                    if let d = backup.date {
                                                        Text(Self.backupDisplayDateFormatter.string(from: d))
                                                            .font(.system(size: 11))
                                                            .foregroundColor(.secondary)
                                                    }
                                                }
                                            }

                                            Spacer()

                                            if !isChosen {
                                                Image(systemName: "chevron.right")
                                                    .font(.system(size: 11, weight: .semibold))
                                                    .foregroundColor(.secondary.opacity(0.5))
                                            }
                                        }
                                        .padding(.horizontal, 10)
                                        .padding(.vertical, 8)
                                        .background(isChosen ? Color.blue.opacity(0.10) : Color.primary.opacity(0.04))
                                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                                .stroke(isChosen ? Color.blue.opacity(0.35) : Color.clear, lineWidth: 1)
                                        )
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }
                    }
                }
                .padding(14)
                .frame(width: 460, height: 370)
            }
        }
    }

    private func prepareAndOpenBackupPopover() {
        backupSearchQuery = ""
        if let clsId = selectedClassId,
           let matchedClass = appState.classes.first(where: { $0.id == clsId }) {
            selectedBackupClassFilter = matchedClass.name
        } else {
            selectedBackupClassFilter = "Toutes"
        }
        showBackupPickerPopover = true
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
            if isShowingLoadingOverlay {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color.primary.opacity(0.02))
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
        // 1. Chargement instantané depuis le cache local (sans bloquer sur une synchro Cloud)
        let localScans = appState.availableScans.isEmpty
            ? appState.storageManager.listLocalScansSync()
            : appState.availableScans
        self.availableScans = localScans

        if let scanToLoad = pickPreferredScan(from: localScans) {
            selectScan(scanToLoad)
            if appState.targetScanForDistribution != nil {
                appState.targetScanForDistribution = nil
            }
            await pdfLoadingTask?.value
        } else {
            isLoadingPDF = false
        }

        // L'interface principale et la prévisualisation locale sont prêtes immédiatement
        isPreparingPage = false

        // 2. Tâches réseau non bloquantes en arrière-plan (archives /Backup + éventuels nouveaux scans Cloud)
        isLoadingBackups = true
        async let backupsFetch: [StorageManager.ExistingBackup]? = try? await appState.storageManager.listExistingBackups()
        async let cloudScansRefresh: Void = appState.refreshScans()

        if let backups = await backupsFetch {
            self.existingBackups = backups
            if mode == .catchUpAbsents, selectedBackup == nil, let first = backups.first {
                self.selectedBackup = first
                applyBackupMetadata(first)
            }
        }
        isLoadingBackups = false

        _ = await cloudScansRefresh
        let syncedScans = appState.availableScans
        if !syncedScans.isEmpty {
            self.availableScans = syncedScans
            // Si aucun scan local n'était encore disponible à l'ouverture, charger le premier reçu du Cloud
            if selectedScan == nil, pdfURL == nil, let scanToLoad = pickPreferredScan(from: syncedScans) {
                selectScan(scanToLoad)
                if appState.targetScanForDistribution != nil {
                    appState.targetScanForDistribution = nil
                }
            }
        }
    }

    private func pickPreferredScan(from scans: [StorageManager.ScanItem]) -> StorageManager.ScanItem? {
        if let target = appState.targetScanForDistribution,
           let matched = scans.first(where: { $0.path == target.path || $0.rawFileName == target.rawFileName }) {
            return matched
        }
        let corrected = scans.filter {
            $0.isCorrected || appState.evaluationsMetadata[$0.rawFileName]?.isEffectivelyCompleted == true
        }
        return corrected.first ?? scans.first
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
        if newMode == .newEvaluation {
            self.selectedBackup = nil
            self.evalDate = Date()
            if let scan = selectedScan {
                self.evalTitle = scan.cleanTitle.replacingOccurrences(of: ".pdf", with: "")
                self.selectedClassId = detectClass(from: scan.name)
            } else if let url = pdfURL {
                self.evalTitle = url.deletingPathExtension().lastPathComponent
                self.selectedClassId = detectClass(from: url.lastPathComponent)
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
                sourcePDFURL: selectedScan?.fileURL ?? pdfURL
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
