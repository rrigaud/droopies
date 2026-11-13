//
//  MainSplitView.swift
//  Droopies
//
//  Architecture d'interface "Liquid Glass" inspirée de PDF Expert (Readdle) :
//  - 100% Plein Écran sans barre latérale rigide permanente
//  - Toolbar 1 flottante en haut à gauche (Bouton Sidebar + Sélecteur Correction / Distribution)
//  - Toolbar 2 flottante en haut à droite (Widget Cloud discret avec menu contextuel)
//  - Sidebar flottante en verre dépoli (Liquid Glass Drawer) qui se déploie à gauche
//    et disparaît en cliquant sur le contenu de fond.
//

import SwiftUI

public enum AppScreen: String, Hashable, CaseIterable {
    case mosaic = "Évaluations"
    case distribution = "Distribution"
    case students = "Gestion des Élèves"
    case portal = "Portail Élèves"
    case settings = "Réglages & Cloud"

    public var icon: String {
        switch self {
        case .mosaic: return "doc.text.fill"
        case .distribution: return "paperplane.fill"
        case .students: return "person.2.fill"
        case .portal: return "globe"
        case .settings: return "gearshape.fill"
        }
    }

    public var tintColor: Color {
        switch self {
        case .mosaic: return Color(red: 0.15, green: 0.45, blue: 1.0)
        case .distribution: return Color(red: 0.05, green: 0.72, blue: 0.55)
        case .students: return Color(red: 0.55, green: 0.35, blue: 0.95)
        case .portal: return Color(red: 0.05, green: 0.75, blue: 0.45)
        case .settings: return Color(white: 0.45)
        }
    }
}

public struct MainSplitView: View {
    @Bindable public var appState: AppState

    // Écran actif (Mosaïque par défaut, le Hub de base)
    @State private var activeScreen: AppScreen = .mosaic

    // État d'ouverture de la sidebar flottante
    @State private var isSidebarOpen: Bool = false

    // Boîtes de dialogue Cloud
    @State private var showFolderPicker: Bool = false
    @State private var showCloudSetupSheet: Bool = false

    @Namespace private var toolbarNamespace

    public init(appState: AppState) {
        self.appState = appState
    }

    private var activeRootPath: String {
        let clean = appState.currentRootFolderPath.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        return clean.isEmpty ? "/" : "/\(clean)"
    }

    public var body: some View {
        GeometryReader { geometry in
            NavigationStack {
                ZStack(alignment: .topLeading) {
                    // MARK: - 1. Fond Ambiant Liquid Glass & Contenu Plein Écran
                    LiquidGlassBackground()

                    // Contenu principal occupant 100% de la fenêtre (architecture native Apple)
                    Group {
                        switch activeScreen {
                        case .mosaic:
                            Step1CorrectionStudioView(
                                appState: appState,
                                currentStep: .constant(1),
                                onDistributeScan: { scan in
                                    appState.targetScanForDistribution = scan
                                    withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                                        activeScreen = .distribution
                                        appState.distributionStep = 1
                                    }
                                }
                            )
                        case .distribution:
                            CorrectionWorkflowView(appState: appState)
                        case .students:
                            StudentsManagementView(appState: appState)
                        case .portal:
                            PortalSettingsView(appState: appState)
                        case .settings:
                            AppSettingsView(appState: appState)
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

                    // MARK: - 2. Fond Estompé (Dimmer) pour fermer la sidebar en cliquant ailleurs
                    if isSidebarOpen {
                        Color.black.opacity(0.3)
                            .ignoresSafeArea()
                            .transition(.opacity)
                            .onTapGesture {
                                withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                                    isSidebarOpen = false
                                }
                            }
                            .zIndex(10)
                    }

                    // MARK: - 3. Sidebar Flottante en Liquid Glass (Se déploie à gauche)
                    if isSidebarOpen {
                        floatingSidebarDrawer
                            .transition(.move(edge: .leading).combined(with: .opacity))
                            .zIndex(20)
                    }
                }
                .navigationTitle(currentNavigationTitle)
                #if os(iOS)
                .navigationBarTitleDisplayMode(.inline)
                #endif
                .toolbar {
                    #if os(macOS)
                    ToolbarItem(placement: .navigation) {
                        leadingToolbarItem
                    }
                    #else
                    ToolbarItem(placement: .topBarLeading) {
                        leadingToolbarItem
                    }
                    #endif

                    if hasPrincipalToolbarItem {
                        ToolbarItem(placement: .principal) {
                            principalToolbarItem
                        }
                    }

                    ToolbarItemGroup(placement: .primaryAction) {
                        trailingToolbarItem
                    }
                }
                #if os(macOS)
                .toolbarBackground(.hidden, for: .windowToolbar)
                #endif
            }
        }
        .sheet(isPresented: $showFolderPicker) {
            CloudFolderPickerSheet(
                provider: appState.storageManager.activeProvider,
                initialPath: appState.currentRootFolderPath
            ) { chosenPath in
                Task {
                    await appState.switchSourceFolder(to: chosenPath)
                }
            }
        }
        .sheet(isPresented: $showCloudSetupSheet) {
            NavigationStack {
                SplashSetupView(appState: appState, isSwitcherMode: true) {
                    showCloudSetupSheet = false
                    if let dropbox = appState.storageManager.activeProvider as? DropboxStorageProvider {
                        appState.currentRootFolderPath = dropbox.rootFolderPath
                    }
                    Task {
                        await appState.loadInitialData()
                    }
                }
            }
        }
        .sheet(isPresented: $appState.showAddStudentSheet) {
            StudentEditSheet(appState: appState)
        }
        #if os(iOS)
        .fullScreenCover(isPresented: $appState.showCSVImportSheet) {
            CSVImportWizardSheet(appState: appState)
        }
        #else
        .sheet(isPresented: $appState.showCSVImportSheet) {
            CSVImportWizardSheet(appState: appState)
                .frame(minWidth: 1050, minHeight: 720)
        }
        #endif
        .task {
            await appState.loadInitialData()
        }
        .onAppear {
            if CommandLine.arguments.contains("-testOffline") {
                appState.isOnline = false
            }
            if CommandLine.arguments.contains("-testSidebar") {
                isSidebarOpen = true
            }
            if CommandLine.arguments.contains("-testManyClasses") {
                if !appState.students.contains(where: { $0.classe == "3e1" }) {
                    appState.students.append(contentsOf: [
                        Student(id: 101, name: "Lucas A.", classe: "3e1", login: "la", password: "p1"),
                        Student(id: 102, name: "Chloé B.", classe: "3e4", login: "cb", password: "p2"),
                        Student(id: 103, name: "Théo C.", classe: "3e5", login: "tc", password: "p3"),
                    ])
                }
            }
            if CommandLine.arguments.contains("-testResumeButton") {
                let scans = appState.storageManager.listLocalScansSync()
                for scan in scans.prefix(2) {
                    if !appState.openCorrectionScans.contains(where: { $0.id == scan.id }) {
                        appState.openCorrectionScans.append(scan)
                    }
                }
                appState.activeCorrectionScan = nil
                activeScreen = .mosaic
            }
            if CommandLine.arguments.contains("-testStudents") {
                activeScreen = .students
                if CommandLine.arguments.contains("-testAddStudentSheet") {
                    appState.showAddStudentSheet = true
                }
            } else if CommandLine.arguments.contains("-testDistributionStep2") {
                activeScreen = .distribution
                appState.distributionStep = 2
                if appState.currentEvaluation == nil {
                    let defaultClass = appState.classes.first?.name ?? "3e1"
                    let defaultClassId = appState.classes.first?.id
                    let sampleScanURL = appState.storageManager.listLocalScansSync().first?.fileURL
                    var mockEval = Evaluation(
                        title: "Devoir_SVT_Genetique_3e3",
                        date: Date(),
                        className: defaultClass,
                        maxScore: 20.0,
                        pagesPerCopy: 2,
                        isCatchUp: CommandLine.arguments.contains("-testCatchUp"),
                        existingBackupFileName: nil,
                        sourcePDFURL: sampleScanURL
                    )
                    if CommandLine.arguments.contains("-testAllIdentified") {
                        mockEval.copies = [
                            StudentCopy(index: 1, pageStart: 1, pageEnd: 2, studentId: 1, studentName: "BERNARD Lucas", grade: 16.5),
                            StudentCopy(index: 2, pageStart: 3, pageEnd: 4, studentId: 2, studentName: "DUBOIS Chloé", grade: 14.0),
                            StudentCopy(index: 3, pageStart: 5, pageEnd: 6, studentId: 3, studentName: "DURAND Thomas", grade: 18.0)
                        ]
                    } else if CommandLine.arguments.contains("-testPartialIdentified") {
                        mockEval.copies = [
                            StudentCopy(index: 1, pageStart: 1, pageEnd: 2, studentId: 1, studentName: "BERNARD Lucas", grade: 16.5),
                            StudentCopy(index: 2, pageStart: 3, pageEnd: 4),
                            StudentCopy(index: 3, pageStart: 5, pageEnd: 6)
                        ]
                    } else {
                        mockEval.copies = [
                            StudentCopy(index: 1, pageStart: 1, pageEnd: 2),
                            StudentCopy(index: 2, pageStart: 3, pageEnd: 4),
                            StudentCopy(index: 3, pageStart: 5, pageEnd: 6)
                        ]
                    }
                    appState.currentEvaluation = mockEval
                    appState.selectedClassId = defaultClassId
                }
            } else if CommandLine.arguments.contains("-testDistributionStep3") {
                activeScreen = .distribution
                appState.distributionStep = 3
            } else if CommandLine.arguments.contains("-testDistribution") {
                activeScreen = .distribution
                if CommandLine.arguments.contains("-testMultipleTabs") && appState.openCorrectionScans.isEmpty {
                    let scans = appState.storageManager.listLocalScansSync()
                    for scan in scans.prefix(3) {
                        if !appState.openCorrectionScans.contains(where: { $0.id == scan.id }) {
                            appState.openCorrectionScans.append(scan)
                        }
                    }
                }
            } else if CommandLine.arguments.contains("-testCorrectionStudio") || CommandLine.arguments.contains("-testMultipleTabs") || CommandLine.arguments.contains("-testTwoTabs") {
                activeScreen = .mosaic
            } else if CommandLine.arguments.contains("-testPortal") {
                activeScreen = .portal
            } else if CommandLine.arguments.contains("-testSettings") {
                activeScreen = .settings
            }
        }
    }

    // MARK: - Toolbar Haut-Gauche (Dynamique : Bouton Sidebar sur Mosaïque, Bouton Retour Flèche seule partout ailleurs)

    @ViewBuilder
    private var leadingToolbarItem: some View {
        if activeScreen != .mosaic || appState.activeCorrectionScan != nil {
            Button {
                withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                    if activeScreen != .mosaic {
                        activeScreen = .mosaic
                    }
                    if appState.activeCorrectionScan != nil {
                        appState.activeCorrectionScan = nil
                    }
                }
            } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 14, weight: .semibold))
                    .frame(width: 32, height: 32)
                    .contentShape(Circle())
            }
            .help("Retour aux évaluations")
        } else {
            sidebarToggleButton
        }
    }

    private var sidebarToggleButton: some View {
        Button {
            withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                isSidebarOpen.toggle()
            }
        } label: {
            Image(systemName: isSidebarOpen ? "sidebar.left" : "sidebar.leading")
                .font(.system(size: 14, weight: .medium))
                .frame(width: 32, height: 32)
                .contentShape(Circle())
        }
        .help("Afficher ou masquer la barre latérale")
    }

    // MARK: - Titre de Navigation Natif (100% HIG Apple, centré sans bulle)

    private var currentNavigationTitle: String {
        switch activeScreen {
        case .mosaic:
            if appState.activeCorrectionScan != nil {
                return ""
            } else {
                return "Évaluations (\(appState.availableScans.count))"
            }
        case .distribution:
            return ""
        case .students:
            return appState.t(.studentsTitle)
        case .portal:
            return appState.t(.navPortal)
        case .settings:
            return appState.t(.settingsTitle)
        }
    }

    private var hasPrincipalToolbarItem: Bool {
        switch activeScreen {
        case .mosaic:
            return appState.activeCorrectionScan != nil
        case .distribution:
            return appState.isOnline
        default:
            return false
        }
    }

    // MARK: - Toolbar Centre : Document ou Stepper (Uniquement contrôles interactifs)

    @ViewBuilder
    private var principalToolbarItem: some View {
        switch activeScreen {
        case .mosaic:
            if let activeScan = appState.activeCorrectionScan {
                correctionDocumentTitleMenu(activeScan: activeScan)
            }
        case .distribution:
            if appState.isOnline {
                distributionStepperToolbar(isCompact: false)
            }
        default:
            EmptyView()
        }
    }

    // MARK: - Toolbar Centre : Menu Titre Document d'Évaluation (Approche 1 Aperçu / Pages)

    private func correctionDocumentTitleMenu(activeScan: StorageManager.ScanItem) -> some View {
        Menu {
            Section("Évaluations ouvertes (\(appState.openCorrectionScans.count))") {
                ForEach(appState.openCorrectionScans) { scan in
                    Button {
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                            appState.activeCorrectionScan = scan
                            activeScreen = .mosaic
                            if isSidebarOpen {
                                isSidebarOpen = false
                            }
                        }
                    } label: {
                        HStack {
                            Label(scan.cleanTitle, systemImage: scan.isCorrected ? "checkmark.seal.fill" : "doc.text.fill")
                            if appState.activeCorrectionScan?.id == scan.id {
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                }
            }

            Divider()

            Button(role: .destructive) {
                closeCorrectionTab(activeScan)
            } label: {
                Label("Fermer cette évaluation", systemImage: "xmark")
            }

            if appState.openCorrectionScans.count > 1 {
                Button(role: .destructive) {
                    closeAllCorrectionTabs()
                } label: {
                    Label("Fermer toutes les évaluations", systemImage: "xmark.circle")
                }
            }

            Divider()

            Button {
                withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                    appState.activeCorrectionScan = nil
                    activeScreen = .mosaic
                    if isSidebarOpen {
                        isSidebarOpen = false
                    }
                }
            } label: {
                Label("Retour aux évaluations", systemImage: "doc.text")
            }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: activeScan.isCorrected ? "checkmark.seal.fill" : "doc.text.fill")
                    .foregroundColor(activeScan.isCorrected ? Color(hex: "10B981") : .accentColor)
                Text(activeScan.cleanTitle)
                    .fontWeight(.semibold)
                    .lineLimit(1)
                Image(systemName: "chevron.down")
                    .font(.caption2.bold())
                    .foregroundColor(.secondary)
            }
        }
        .help("Menu de l'évaluation : changer de copie ou fermer")
    }

    private func closeAllCorrectionTabs() {
        withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
            appState.openCorrectionScans.removeAll()
            appState.activeCorrectionScan = nil
        }
    }

    private func closeCorrectionTab(_ scan: StorageManager.ScanItem) {
        withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
            guard let idx = appState.openCorrectionScans.firstIndex(where: { $0.id == scan.id }) else { return }
            appState.openCorrectionScans.remove(at: idx)

            if appState.activeCorrectionScan?.id == scan.id {
                if !appState.openCorrectionScans.isEmpty {
                    let nextIndex = min(idx, appState.openCorrectionScans.count - 1)
                    appState.activeCorrectionScan = appState.openCorrectionScans[nextIndex]
                } else {
                    appState.activeCorrectionScan = nil
                }
            }
        }
    }

    // MARK: - Toolbar Haut-Droite (Actions Contextuelles Primaires 100% Natives)

    @ViewBuilder
    private var trailingToolbarItem: some View {
        switch activeScreen {
        case .mosaic:
            if appState.activeCorrectionScan != nil {
                topTrailingHistoryToolbar
            } else {
                Button {
                    appState.showPDFImporter = true
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: "plus")
                        Text("Importer")
                    }
                }
                .help("Importer un paquet de copies (PDF)")

                if !appState.openCorrectionScans.isEmpty {
                    Button {
                        if let scanToResume = appState.activeCorrectionScan ?? appState.lastActiveCorrectionScan ?? appState.openCorrectionScans.last ?? appState.openCorrectionScans.first {
                            withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                                appState.activeCorrectionScan = scanToResume
                            }
                        }
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "pencil.and.outline")
                            Text("Reprendre (\(appState.openCorrectionScans.count))")
                            Image(systemName: "chevron.right")
                                .font(.system(size: 11, weight: .bold))
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .help("Reprendre la correction des évaluations ouvertes")
                }
            }

        case .distribution:
            EmptyView()

        case .students:
            studentsActionToolbar

        case .portal:
            portalActionToolbar

        case .settings:
            EmptyView()
        }
    }

    // MARK: - Toolbar : Historique Undo/Redo Dédié à la Correction

    private var topTrailingHistoryToolbar: some View {
        ControlGroup {
            Button {
                appState.undoCorrectionTrigger += 1
            } label: {
                Label("Annuler", systemImage: "arrow.uturn.backward")
            }
            .disabled(!appState.canUndoCorrection)
            .help("Annuler la dernière action (tracé, surlignage, tampon, texte)")

            Button {
                appState.redoCorrectionTrigger += 1
            } label: {
                Label("Rétablir", systemImage: "arrow.uturn.forward")
            }
            .disabled(!appState.canRedoCorrection)
            .help("Rétablir la dernière action")
        }
    }

    // MARK: - Center Toolbar : Stepper Flottant de Distribution

    private func distributionStepperToolbar(isCompact: Bool) -> some View {
        Picker("Étape", selection: $appState.distributionStep) {
            Text(isCompact ? "1. Fichier" : "1. Chargement").tag(1)
            Text(isCompact ? "2. Élèves" : "2. Identification").tag(2)
            Text("3. Envoi").tag(3)
        }
        .pickerStyle(.segmented)
        .fixedSize()
    }

    // MARK: - Actions Gestion des Élèves (Modale)

    private var studentsActionToolbar: some View {
        ControlGroup {
            Button {
                if appState.isOnline {
                    appState.showAddStudentSheet = true
                }
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: "person.badge.plus")
                    Text("Ajouter")
                }
            }
            .disabled(!appState.isOnline)
            .help(appState.isOnline ? "Ajouter un élève" : "Disponible en ligne uniquement")

            Button {
                if appState.isOnline {
                    appState.showCSVImportSheet = true
                }
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: "arrow.down.doc")
                    Text("Importer")
                }
            }
            .disabled(!appState.isOnline)
            .help(appState.isOnline ? "Importer un fichier CSV" : "Disponible en ligne uniquement")
        }
    }

    // MARK: - Actions Portail Élèves (Modale)

    private var portalActionToolbar: some View {
        Button {
            if appState.isOnline && !appState.isPortalGenerating && !appState.students.isEmpty {
                appState.triggerPortalGeneration += 1
            }
        } label: {
            HStack(spacing: 6) {
                switch appState.portalSyncStatus {
                case .generating:
                    ProgressView().controlSize(.small)
                    Text("Génération...")
                case .upToDateOnline:
                    Image(systemName: "checkmark.circle.fill")
                    Text("Portail à jour")
                case .generatedReadyToUpload:
                    Image(systemName: "arrow.up.circle.fill")
                    Text("Mettre en ligne")
                default:
                    Image(systemName: "bolt.badge.clock.fill")
                    Text("Générer le portail")
                }
            }
        }
        .disabled(!appState.isOnline || appState.isPortalGenerating || appState.students.isEmpty)
        .help(!appState.isOnline
            ? "Disponible en ligne uniquement"
            : (appState.students.isEmpty
               ? "Veuillez d'abord importer des élèves"
               : (appState.portalSyncStatus == .generatedReadyToUpload
                  ? "Portail généré prêt à être mis en ligne sur votre hébergeur. Cliquez pour re-générer."
                  : "Générer et publier le portail web chiffré")))
    }

    // MARK: - 4. Sidebar Flottante en Liquid Glass (Tiroir suspendu)

    private var floatingSidebarDrawer: some View {
        VStack(alignment: .leading, spacing: 16) {
            // En-tête avec mascotte Droopies et bouton de fermeture
            HStack(spacing: 12) {
                DroopiesMascotView(size: 38, hasShadow: true)

                VStack(alignment: .leading, spacing: 2) {
                    Text("Droopies")
                        .font(.system(.headline, design: .rounded, weight: .bold))
                    Text(appState.t(.navStudioTeacher))
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }

                Spacer()

                Button {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                        isSidebarOpen = false
                    }
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 18))
                        .foregroundColor(.secondary.opacity(0.6))
                }
                .buttonStyle(.plain)
            }
            .padding(.bottom, 6)
            .overlay(
                Rectangle()
                    .fill(Color.primary.opacity(0.08))
                    .frame(height: 1)
                    .padding(.top, 44),
                alignment: .bottom
            )

            // Bloc d'information et d'actions Cloud & Connexion
            sidebarCloudSection

            // Liste de navigation
            VStack(alignment: .leading, spacing: 18) {
                // Section Cœur Enseignant
                VStack(alignment: .leading, spacing: 4) {
                    Text(appState.t(.navCorrectionFlow).uppercased())
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(.secondary.opacity(0.8))
                        .padding(.horizontal, 8)

                    sidebarActionRow(
                        icon: "doc.text.fill",
                        tintColor: Color(red: 0.15, green: 0.45, blue: 1.0),
                        title: "Évaluations",
                        isSelected: activeScreen == .mosaic && appState.activeCorrectionScan == nil
                    ) {
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                            activeScreen = .mosaic
                            appState.activeCorrectionScan = nil
                            isSidebarOpen = false
                        }
                    }

                    if let activeScan = appState.activeCorrectionScan {
                        sidebarActionRow(
                            icon: "pencil.and.outline",
                            tintColor: Color(red: 0.15, green: 0.45, blue: 1.0),
                            title: "Correction en cours",
                            badgeText: activeScan.cleanTitle,
                            isSelected: activeScreen == .mosaic && appState.activeCorrectionScan != nil
                        ) {
                            withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                                activeScreen = .mosaic
                                isSidebarOpen = false
                            }
                        }
                    }

                    sidebarActionRow(
                        icon: "paperplane.fill",
                        tintColor: Color(red: 0.05, green: 0.72, blue: 0.55),
                        title: appState.t(.tabDistribution),
                        isSelected: activeScreen == .distribution,
                        isAvailable: appState.isOnline
                    ) {
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                            activeScreen = .distribution
                            isSidebarOpen = false
                        }
                    }
                }

                // Section Administration Scolaire
                VStack(alignment: .leading, spacing: 4) {
                    Text(appState.t(.navSchoolAdmin).uppercased())
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(.secondary.opacity(0.8))
                        .padding(.horizontal, 8)

                    sidebarActionRow(
                        icon: "person.2.fill",
                        tintColor: Color(red: 0.55, green: 0.35, blue: 0.95),
                        title: appState.t(.navStudents),
                        badgeText: "\(appState.students.count)",
                        isSelected: activeScreen == .students
                    ) {
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                            activeScreen = .students
                            isSidebarOpen = false
                        }
                    }

                    sidebarActionRow(
                        icon: "globe",
                        tintColor: Color(red: 0.05, green: 0.75, blue: 0.45),
                        title: appState.t(.navPortal),
                        isSelected: activeScreen == .portal
                    ) {
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                            activeScreen = .portal
                            isSidebarOpen = false
                        }
                    }
                }

                // Section Configuration
                VStack(alignment: .leading, spacing: 4) {
                    Text(appState.t(.navConfiguration).uppercased())
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(.secondary.opacity(0.8))
                        .padding(.horizontal, 8)

                    sidebarActionRow(
                        icon: "gearshape.fill",
                        tintColor: Color(white: 0.45),
                        title: appState.t(.navSettings),
                        isSelected: activeScreen == .settings
                    ) {
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                            activeScreen = .settings
                            isSidebarOpen = false
                        }
                    }
                }
            }

            Spacer()

            // Pied de Sidebar
            HStack {
                Text("Droopies Native")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                Spacer()
                Text("v1.0")
                    .font(.caption2.bold())
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.secondary.opacity(0.12))
                    .clipShape(Capsule())
            }
        }
        .padding(18)
        .frame(width: 290)
        .frame(maxHeight: .infinity)
        .glassCard(cornerRadius: 24, strokeOpacity: 0.5)
        .padding(.leading, 12)
        .padding(.top, 10)
        .padding(.bottom, 16)
        .shadow(color: Color.black.opacity(0.25), radius: 24, x: 8, y: 12)
    }

    @ViewBuilder
    private func sidebarActionRow(
        icon: String,
        tintColor: Color,
        title: String,
        badgeText: String? = nil,
        isSelected: Bool = false,
        isAvailable: Bool = true,
        action: @escaping () -> Void
    ) -> some View {
        Button {
            guard isAvailable else { return }
            action()
        } label: {
            HStack(spacing: 10) {
                Image(systemName: icon)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.white)
                    .frame(width: 28, height: 28)
                    .background(
                        LinearGradient(
                            colors: [tintColor, tintColor.opacity(0.8)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .shadow(color: tintColor.opacity(isSelected ? 0.4 : 0.15), radius: 3, y: 1)

                Text(title)
                    .font(.system(size: 13, weight: isSelected ? .bold : .medium))
                    .foregroundColor(isSelected ? .primary : (isAvailable ? .secondary : .secondary.opacity(0.4)))

                Spacer()

                if !isAvailable {
                    Text("Hors-ligne")
                        .font(.system(size: 9.5, weight: .semibold))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.orange.opacity(0.15))
                        .foregroundColor(.orange)
                        .clipShape(Capsule())
                } else if let badge = badgeText {
                    Text(badge)
                        .font(.caption2.bold())
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.secondary.opacity(0.12))
                        .clipShape(Capsule())
                }
            }
            .opacity(isAvailable ? 1.0 : 0.55)
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(
                Group {
                    if isSelected {
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(Color.primary.opacity(0.08))
                    } else {
                        Color.clear
                    }
                }
            )
        }
        .buttonStyle(.plain)
        .disabled(!isAvailable)
    }

    // MARK: - Bloc d'information et d'actions Cloud (Sidebar)

    private var sidebarCloudSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Ligne 1 : Fournisseur et statut de connexion
            HStack(spacing: 8) {
                Image(systemName: !appState.isOnline ? "bolt.slash.fill" : appState.storageManager.activeProvider.providerType.iconName)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(!appState.isOnline ? .orange : .accentColor)

                VStack(alignment: .leading, spacing: 2) {
                    Text(!appState.isOnline ? "Mode Hors-ligne" : appState.storageManager.activeProvider.providerType.displayName)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.primary)

                    HStack(spacing: 5) {
                        Circle()
                            .fill(!appState.isOnline ? Color.orange : (appState.storageManager.activeProvider.isConnected ? Color.green : Color.orange))
                            .frame(width: 6, height: 6)
                        Text(!appState.isOnline ? "Non connecté" : (appState.storageManager.activeProvider.isConnected ? "Connecté & synchronisé" : "Connexion en cours"))
                            .font(.system(size: 10.5))
                            .foregroundColor(.secondary)
                    }
                }

                Spacer()

                Button {
                    Task { await appState.loadInitialData() }
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
                .help("Recharger les données du Cloud")
            }

            // Ligne 2 : Dossier Source
            HStack(spacing: 6) {
                Image(systemName: "folder")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                Text(activeRootPath)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.primary.opacity(0.04))
            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))

            // Ligne 3 : Boutons d'action Cloud natifs
            HStack(spacing: 8) {
                Button {
                    showFolderPicker = true
                } label: {
                    Label("Dossier", systemImage: "folder.badge.gearshape")
                        .font(.system(size: 11, weight: .medium))
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)

                Button {
                    showCloudSetupSheet = true
                } label: {
                    Label("Compte", systemImage: "arrow.triangle.2.circlepath")
                        .font(.system(size: 11, weight: .medium))
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
        }
        .padding(10)
        .background(Color.primary.opacity(0.04))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}
