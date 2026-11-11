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
    case correction = "Correction"
    case distribution = "Distribution"
    case students = "Gestion des Élèves"
    case portal = "Portail Élèves"
    case settings = "Réglages & Cloud"

    public var icon: String {
        switch self {
        case .correction: return "pencil.and.outline"
        case .distribution: return "paperplane.fill"
        case .students: return "person.2.fill"
        case .portal: return "globe"
        case .settings: return "gearshape.fill"
        }
    }

    public var tintColor: Color {
        switch self {
        case .correction: return Color(red: 0.15, green: 0.45, blue: 1.0)
        case .distribution: return Color(red: 0.05, green: 0.72, blue: 0.55)
        case .students: return Color(red: 0.55, green: 0.35, blue: 0.95)
        case .portal: return Color(red: 0.05, green: 0.75, blue: 0.45)
        case .settings: return Color(white: 0.45)
        }
    }
}

public struct MainSplitView: View {
    @Bindable public var appState: AppState

    // Écran actif (Correction par défaut, coeur de l'usage iPad)
    @State private var activeScreen: AppScreen = .correction

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
            let isCompact = geometry.size.width < 760
            let isPortrait = geometry.size.height > geometry.size.width

            NavigationStack {
                ZStack(alignment: .topLeading) {
                    // MARK: - 1. Fond Ambiant Liquid Glass & Contenu Plein Écran
                    LiquidGlassBackground()

                    // Contenu principal occupant 100% de la fenêtre (architecture native Apple)
                    Group {
                        switch activeScreen {
                        case .correction:
                            Step1CorrectionStudioView(appState: appState, currentStep: .constant(1))
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
                .navigationTitle("")
                #if os(iOS)
                .navigationBarTitleDisplayMode(.inline)
                .background {
                    CenterItemGroupsBridge(
                        screen: activeScreen,
                        isOnline: appState.isOnline,
                        isPortalGenerating: appState.isPortalGenerating,
                        studentsEmpty: appState.students.isEmpty,
                        portalSyncStatus: appState.portalSyncStatus,
                        isCompact: isCompact,
                        onAddStudent: {
                            if appState.isOnline {
                                appState.showAddStudentSheet = true
                            }
                        },
                        onImportCSV: {
                            if appState.isOnline {
                                appState.showCSVImportSheet = true
                            }
                        },
                        onGeneratePortal: {
                            if appState.isOnline && !appState.isPortalGenerating && !appState.students.isEmpty {
                                appState.triggerPortalGeneration += 1
                            }
                        }
                    )
                }
                #endif
                .toolbar {
                    #if os(macOS)
                    ToolbarItem(placement: .navigation) {
                        sidebarToggleButton
                    }

                    ToolbarItem(placement: .navigation) {
                        HStack(spacing: 0) {
                            mainModeTabsControlGroup
                        }
                        .padding(.leading, 8)
                    }
                    #else
                    ToolbarItem(placement: .topBarLeading) {
                        sidebarToggleButton
                    }

                    ToolbarItem(placement: .navigation) {
                        mainModeTabsControlGroup
                    }
                    #endif

                    if hasCenterToolbar {
                        ToolbarItem(placement: .principal) {
                            topCenterToolbar(isCompact: isCompact, isPortrait: isPortrait)
                        }
                    }

                    ToolbarItem(placement: .primaryAction) {
                        if activeScreen == .correction && appState.activeCorrectionScan != nil {
                            topTrailingHistoryToolbar
                        } else {
                            topTrailingCloudToolbar
                        }
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
            if CommandLine.arguments.contains("-testManyClasses") {
                if !appState.students.contains(where: { $0.classe == "3e1" }) {
                    appState.students.append(contentsOf: [
                        Student(id: 101, name: "Lucas A.", classe: "3e1", login: "la", password: "p1"),
                        Student(id: 102, name: "Chloé B.", classe: "3e4", login: "cb", password: "p2"),
                        Student(id: 103, name: "Théo C.", classe: "3e5", login: "tc", password: "p3"),
                    ])
                }
            }
            if CommandLine.arguments.contains("-testStudents") {
                activeScreen = .students
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
                activeScreen = .correction
            } else if CommandLine.arguments.contains("-testPortal") {
                activeScreen = .portal
            }
        }
        .onChange(of: activeScreen) { _, newScreen in
            if newScreen == .distribution && !appState.isOnline {
                activeScreen = .correction
                return
            }
            if newScreen == .correction {
                appState.activeCorrectionScan = nil
            }
            if isSidebarOpen {
                isSidebarOpen = false
            }
        }
    }

    // MARK: - Outils Contextuels Centraux

    private var hasCenterToolbar: Bool {
        #if os(iOS)
        // Sur iOS/iPadOS, les boutons étudiants et portail sont gérés nativement par UIBarButtonItemGroup
        // via centerItemGroups, pour avoir exactement les bulles natives Liquid Glass d'Aperçu.
        switch activeScreen {
        case .correction:
            return appState.activeCorrectionScan != nil || !appState.openCorrectionScans.isEmpty
        case .distribution:
            return appState.isOnline
        default:
            return false
        }
        #else
        switch activeScreen {
        case .correction:
            return appState.activeCorrectionScan != nil || !appState.openCorrectionScans.isEmpty
        case .distribution:
            return appState.isOnline
        case .students:
            return true
        case .portal:
            return true
        default:
            return false
        }
        #endif
    }

    @ViewBuilder
    private func topCenterToolbar(isCompact: Bool, isPortrait: Bool) -> some View {
        switch activeScreen {
        case .correction:
            correctionCenterTabsToolbar(isCompact: isCompact, isPortrait: isPortrait)

        case .distribution:
            distributionStepperToolbar(isCompact: isCompact || isPortrait)

        case .students:
            studentsCenterActionToolbar(isCompact: isCompact)

        case .portal:
            portalCenterActionToolbar(isCompact: isCompact)

        default:
            EmptyView()
        }
    }

    // MARK: - Center Toolbar : Actions du Portail Élèves (macOS)

    private func portalCenterActionToolbar(isCompact: Bool) -> some View {
        Button {
            if appState.isOnline && !appState.isPortalGenerating && !appState.students.isEmpty {
                appState.triggerPortalGeneration += 1
            }
        } label: {
            HStack(spacing: 6) {
                switch appState.portalSyncStatus {
                case .generating:
                    ProgressView()
                        .controlSize(.small)
                    Text(isCompact ? "Génération..." : "Génération en cours...")
                case .upToDateOnline:
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.green)
                    Text(isCompact ? "À jour" : "Portail à jour")
                case .generatedReadyToUpload:
                    Image(systemName: "arrow.up.circle.fill")
                        .foregroundColor(.blue)
                    Text(isCompact ? "Publier" : "Mettre en ligne")
                default:
                    Image(systemName: "bolt.badge.clock.fill")
                    Text(isCompact ? "Générer" : "Générer le portail")
                }
            }
            .font(.system(size: 13, weight: .medium))
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .contentShape(Capsule())
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

    // MARK: - Center Toolbar : Actions Gestion des Élèves (macOS)

    private func studentsCenterActionToolbar(isCompact: Bool) -> some View {
        HStack(spacing: 8) {
            Button {
                if appState.isOnline {
                    appState.showAddStudentSheet = true
                }
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: "person.badge.plus")
                    Text(isCompact ? "Ajouter" : "Ajouter un élève")
                }
                .font(.system(size: 13, weight: .medium))
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .contentShape(Capsule())
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
                    Text(isCompact ? "Importer" : "Importer CSV")
                }
                .font(.system(size: 13, weight: .medium))
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .contentShape(Capsule())
            }
            .disabled(!appState.isOnline)
            .help(appState.isOnline ? "Importer un fichier CSV" : "Disponible en ligne uniquement")
        }
    }

    // MARK: - Center Toolbar : Onglets d'Évaluations (Correction)

    private func correctionCenterTabsToolbar(isCompact: Bool, isPortrait: Bool) -> some View {
        let shouldCollapse = (isPortrait || isCompact)
            ? appState.openCorrectionScans.count >= 3
            : appState.openCorrectionScans.count > 4

        return Group {
            if shouldCollapse {
                compactEvaluationsMenu
            } else {
                HStack(spacing: 6) {
                    ForEach(appState.openCorrectionScans) { scan in
                        evaluationTabItem(scan: scan)
                    }
                }
            }
        }
    }

    private func evaluationTabItem(scan: StorageManager.ScanItem) -> some View {
        let isTabActive = (activeScreen == .correction && appState.activeCorrectionScan?.id == scan.id)

        return HStack(spacing: 5) {
            Button {
                withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                    activeScreen = .correction
                    appState.activeCorrectionScan = scan
                    if isSidebarOpen {
                        isSidebarOpen = false
                    }
                }
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: scan.isCorrected ? "checkmark.seal.fill" : "doc.text.fill")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(isTabActive ? .white : (scan.isCorrected ? Color(hex: "10B981") : .secondary))

                    Text(scan.cleanTitle)
                        .font(.system(size: 12, weight: isTabActive ? .bold : .medium))
                        .lineLimit(1)
                        .frame(maxWidth: 130)
                }
            }
            .buttonStyle(.plain)

            Button {
                closeCorrectionTab(scan)
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundColor(isTabActive ? .white.opacity(0.85) : .secondary)
                    .frame(width: 16, height: 16)
                    .background(isTabActive ? Color.white.opacity(0.2) : Color.primary.opacity(0.08))
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)
            .help("Fermer l'évaluation « \(scan.cleanTitle) »")
        }
        .padding(.leading, 10)
        .padding(.trailing, 6)
        .padding(.vertical, 5)
        .background(
            isTabActive
                ? Color.accentColor
                : Color.primary.opacity(0.06)
        )
        .foregroundColor(isTabActive ? .white : .primary)
        .clipShape(Capsule())
    }

    private var compactEvaluationsMenu: some View {
        Menu {
            Section("Évaluations ouvertes (\(appState.openCorrectionScans.count))") {
                ForEach(appState.openCorrectionScans) { scan in
                    Button {
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                            activeScreen = .correction
                            appState.activeCorrectionScan = scan
                            if isSidebarOpen {
                                isSidebarOpen = false
                            }
                        }
                    } label: {
                        HStack {
                            Label(scan.cleanTitle, systemImage: scan.isCorrected ? "checkmark.seal.fill" : "doc.text.fill")
                            if appState.activeCorrectionScan?.id == scan.id && activeScreen == .correction {
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                }
            }

            Divider()

            Button(role: .destructive) {
                closeAllCorrectionTabs()
            } label: {
                Label("Fermer toutes les évaluations", systemImage: "xmark.circle")
            }
        } label: {
            HStack(spacing: 5) {
                let activeScan = (activeScreen == .correction) ? appState.activeCorrectionScan : nil
                Image(systemName: (activeScan?.isCorrected == true) ? "checkmark.seal.fill" : (activeScan != nil ? "doc.text.fill" : "doc.on.doc.fill"))
                Text(activeScan?.cleanTitle ?? "\(appState.openCorrectionScans.count) évaluations")
                    .lineLimit(1)
            }
        }
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

    // MARK: - Toolbar Haut-Gauche : Bouton Sidebar, Sélecteur de Mode et Retour Mosaïque

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

    private var mainModeTabsControlGroup: some View {
        ControlGroup {
            Button {
                if activeScreen != .correction {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                        activeScreen = .correction
                        appState.activeCorrectionScan = nil
                    }
                }
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: activeScreen == .correction ? "checkmark.circle.fill" : "pencil.and.outline")
                        .foregroundColor(activeScreen == .correction ? .blue : .secondary)
                    if activeScreen == .correction {
                        Text(appState.t(.tabCorrection))
                            .fontWeight(.semibold)
                    }
                }
            }
            .help("Atelier de correction au stylet")

            Button {
                if activeScreen != .distribution && appState.isOnline {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                        activeScreen = .distribution
                    }
                }
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: activeScreen == .distribution ? "checkmark.circle.fill" : "paperplane.fill")
                        .foregroundColor(activeScreen == .distribution ? Color(red: 0.05, green: 0.72, blue: 0.55) : .secondary)
                    if activeScreen == .distribution {
                        Text(appState.t(.tabDistribution))
                            .fontWeight(.semibold)
                    }
                }
            }
            .disabled(!appState.isOnline)
            .help(appState.isOnline ? "Distribution des copies aux élèves" : "Distribution disponible en ligne uniquement")
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

    // MARK: - Toolbar 2 : Haut-Droite (Historique Undo/Redo Dédié à la Correction)

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

    // MARK: - Toolbar 2 : Haut-Droite (Widget Cloud Déroulant façon Aperçu)

    private var topTrailingCloudToolbar: some View {
        Menu {
            cloudMenuSections
        } label: {
            HStack(spacing: 6) {
                Circle()
                    .fill(!appState.isOnline ? Color.orange : (appState.storageManager.activeProvider.isConnected ? Color.green : Color.orange))
                    .frame(width: 7, height: 7)

                Image(systemName: !appState.isOnline ? "bolt.slash.fill" : appState.storageManager.activeProvider.providerType.iconName)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(!appState.isOnline ? .orange : .accentColor)

                Text(!appState.isOnline ? "Hors-ligne" : appState.storageManager.activeProvider.providerType.displayName)
                    .font(.system(size: 13, weight: .medium))
            }
        }
    }

    @ViewBuilder
    private var cloudMenuSections: some View {
        if !appState.isOnline {
            Section("Mode Hors-Ligne") {
                Label("Connexion Internet inactive", systemImage: "bolt.slash.fill")
                Text("Vos copies annotées sont enregistrées localement et seront synchronisées dès le retour de la connexion.")
            }

            Divider()

            Button {
                Task { await appState.loadInitialData() }
            } label: {
                Label(appState.t(.navReloadData), systemImage: "arrow.clockwise")
            }
        } else {
            Section {
                Label(appState.storageManager.activeProvider.providerType.displayName, systemImage: appState.storageManager.activeProvider.providerType.iconName)
                Label("Dossier Source : \(activeRootPath)", systemImage: "folder")
            } header: {
                Text("Stockage Cloud Actif")
            }

            Divider()

            Button {
                showFolderPicker = true
            } label: {
                Label(appState.t(.navChangeFolder), systemImage: "folder.badge.gearshape")
            }

            Button {
                showCloudSetupSheet = true
            } label: {
                Label(appState.t(.navChangeCloud), systemImage: "arrow.triangle.2.circlepath")
            }

            Divider()

            Button {
                Task { await appState.loadInitialData() }
            } label: {
                Label(appState.t(.navReloadData), systemImage: "arrow.clockwise")
            }
        }
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

            // Liste de navigation
            VStack(alignment: .leading, spacing: 18) {
                // Section Cœur Enseignant
                VStack(alignment: .leading, spacing: 4) {
                    Text(appState.t(.navCorrectionFlow).uppercased())
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(.secondary.opacity(0.8))
                        .padding(.horizontal, 8)

                    sidebarNavigationRow(screen: .correction, title: appState.t(.tabCorrection))
                    sidebarNavigationRow(screen: .distribution, title: appState.t(.tabDistribution))
                }

                // Section Administration Scolaire
                VStack(alignment: .leading, spacing: 4) {
                    Text(appState.t(.navSchoolAdmin).uppercased())
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(.secondary.opacity(0.8))
                        .padding(.horizontal, 8)

                    sidebarNavigationRow(
                        screen: .students,
                        title: appState.t(.navStudents),
                        badgeText: "\(appState.students.count)"
                    )
                    sidebarNavigationRow(screen: .portal, title: appState.t(.navPortal))
                }

                // Section Configuration
                VStack(alignment: .leading, spacing: 4) {
                    Text(appState.t(.navConfiguration).uppercased())
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(.secondary.opacity(0.8))
                        .padding(.horizontal, 8)

                    sidebarNavigationRow(screen: .settings, title: appState.t(.navSettings))
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
    private func sidebarNavigationRow(
        screen: AppScreen,
        title: String,
        badgeText: String? = nil
    ) -> some View {
        let isSelected = activeScreen == screen
        let isScreenAvailable = (screen == .correction || screen == .settings || appState.isOnline)

        Button {
            guard isScreenAvailable else { return }
            withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                activeScreen = screen
                if screen == .correction {
                    appState.activeCorrectionScan = nil
                }
                isSidebarOpen = false
            }
        } label: {
            HStack(spacing: 10) {
                Image(systemName: screen.icon)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.white)
                    .frame(width: 28, height: 28)
                    .background(
                        LinearGradient(
                            colors: [screen.tintColor, screen.tintColor.opacity(0.8)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .shadow(color: screen.tintColor.opacity(isSelected ? 0.4 : 0.15), radius: 3, y: 1)

                Text(title)
                    .font(.system(size: 13, weight: isSelected ? .bold : .medium))
                    .foregroundColor(isSelected ? .primary : (isScreenAvailable ? .secondary : .secondary.opacity(0.4)))

                Spacer()

                if !isScreenAvailable {
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
            .opacity(isScreenAvailable ? 1.0 : 0.55)
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
        .disabled(!isScreenAvailable)
    }
}

// MARK: - Bridge UIKit pour les Bulles Liquid Glass Natives (iPadOS)
// En utilisant UIBarButtonItemGroup avec centerItemGroups et le style .editor de Desktop-Class iPad,
// iPadOS génère automatiquement la bulle Liquid Glass flottante exacte d'Apple (identique à Aperçu)
// avec ses séparateurs natifs et son effet de survol pointer morphing parfait.

#if os(iOS)
import UIKit

final class CenterItemGroupsViewController: UIViewController {
    var updateHandler: ((UINavigationItem?) -> Void)?

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .clear
        view.isUserInteractionEnabled = false
    }

    override func didMove(toParent parent: UIViewController?) {
        super.didMove(toParent: parent)
        findAndConfigureNavigationItem()
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        findAndConfigureNavigationItem()
    }

    func findAndConfigureNavigationItem() {
        var targetVC: UIViewController? = self.parent
        if targetVC == nil {
            targetVC = self.navigationController?.topViewController
        }
        while let p = targetVC?.parent, !(p is UINavigationController) {
            targetVC = p
        }
        let navItem = targetVC?.navigationItem ?? self.navigationController?.topViewController?.navigationItem
        updateHandler?(navItem)
    }
}

struct CenterItemGroupsBridge: UIViewControllerRepresentable {
    let screen: AppScreen
    let isOnline: Bool
    let isPortalGenerating: Bool
    let studentsEmpty: Bool
    let portalSyncStatus: PortalSyncStatus
    let isCompact: Bool
    let onAddStudent: () -> Void
    let onImportCSV: () -> Void
    let onGeneratePortal: () -> Void

    func makeUIViewController(context: Context) -> CenterItemGroupsViewController {
        let vc = CenterItemGroupsViewController()
        vc.updateHandler = { navItem in
            configure(navItem: navItem)
        }
        return vc
    }

    func updateUIViewController(_ uiViewController: CenterItemGroupsViewController, context: Context) {
        uiViewController.updateHandler = { navItem in
            configure(navItem: navItem)
        }
        DispatchQueue.main.async {
            uiViewController.findAndConfigureNavigationItem()
        }
    }

    private func configure(navItem: UINavigationItem?) {
        guard let navItem else { return }
        navItem.style = .editor

        switch screen {
        case .students:
            var addConfig = UIButton.Configuration.plain()
            addConfig.title = isCompact ? "Ajouter" : "Ajouter un élève"
            addConfig.image = UIImage(systemName: "person.badge.plus")
            addConfig.imagePadding = 6
            addConfig.baseForegroundColor = .label
            addConfig.contentInsets = NSDirectionalEdgeInsets(top: 4, leading: 8, bottom: 4, trailing: 8)
            let btnAddView = UIButton(configuration: addConfig, primaryAction: UIAction { _ in
                onAddStudent()
            })
            btnAddView.isEnabled = isOnline
            let btnAdd = UIBarButtonItem(customView: btnAddView)

            var importConfig = UIButton.Configuration.plain()
            importConfig.title = isCompact ? "Importer" : "Importer CSV"
            importConfig.image = UIImage(systemName: "arrow.down.doc")
            importConfig.imagePadding = 6
            importConfig.baseForegroundColor = .label
            importConfig.contentInsets = NSDirectionalEdgeInsets(top: 4, leading: 8, bottom: 4, trailing: 8)
            let btnImportView = UIButton(configuration: importConfig, primaryAction: UIAction { _ in
                onImportCSV()
            })
            btnImportView.isEnabled = isOnline
            let btnImport = UIBarButtonItem(customView: btnImportView)

            let sepView = UIView()
            sepView.backgroundColor = UIColor.separator.withAlphaComponent(0.35)
            sepView.translatesAutoresizingMaskIntoConstraints = false
            NSLayoutConstraint.activate([
                sepView.widthAnchor.constraint(equalToConstant: 1),
                sepView.heightAnchor.constraint(equalToConstant: 16)
            ])
            let sepItem = UIBarButtonItem(customView: sepView)

            let group = UIBarButtonItemGroup(barButtonItems: [btnAdd, sepItem, btnImport], representativeItem: nil)
            navItem.centerItemGroups = [group]

        case .portal:
            let (title, imageName): (String, String) = {
                switch portalSyncStatus {
                case .generating:
                    return (isCompact ? "Génération..." : "Génération en cours...", "arrow.triangle.2.circlepath")
                case .upToDateOnline:
                    return (isCompact ? "À jour" : "Portail à jour", "checkmark.circle.fill")
                case .generatedReadyToUpload:
                    return (isCompact ? "Publier" : "Mettre en ligne", "arrow.up.circle.fill")
                default:
                    return (isCompact ? "Générer" : "Générer le portail", "bolt.badge.clock.fill")
                }
            }()

            var config = UIButton.Configuration.plain()
            config.title = title
            config.image = UIImage(systemName: imageName)
            config.imagePadding = 6
            config.baseForegroundColor = .label
            config.contentInsets = NSDirectionalEdgeInsets(top: 4, leading: 8, bottom: 4, trailing: 8)

            let button = UIButton(configuration: config, primaryAction: UIAction { _ in
                onGeneratePortal()
            })
            button.isEnabled = isOnline && !isPortalGenerating && !studentsEmpty

            let btnGen = UIBarButtonItem(customView: button)
            let group = UIBarButtonItemGroup(barButtonItems: [btnGen], representativeItem: nil)
            navItem.centerItemGroups = [group]

        default:
            navItem.centerItemGroups = []
        }
    }
}
#endif
