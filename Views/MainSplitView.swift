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

            ZStack(alignment: .topLeading) {
                // MARK: - 1. Fond Ambiant Liquid Glass & Contenu Plein Écran
                LiquidGlassBackground()

                // Contenu principal occupant 100% de la fenêtre (architecture Liquid Glass sans démarcation)
                Group {
                    switch activeScreen {
                    case .correction:
                        Step1CorrectionStudioView(appState: appState, currentStep: .constant(1))
                    case .distribution:
                        CorrectionWorkflowView(appState: appState)
                    case .students:
                        StudentsManagementView(appState: appState)
                            .padding(.top, 58)
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

                // MARK: - 3. Barres d'Outils Flottantes Supérieures (Liquid Glass Bars)
                HStack(alignment: .center, spacing: 0) {
                    // Toolbar 1 : Gauche (Bouton Sidebar + Sélecteur Correction / Distribution)
                    topLeadingToolbar(isCompact: isCompact)
                        .glassCapsule(strokeOpacity: 0.4)

                    Spacer(minLength: 8)

                    // Toolbar Centrale Flottante (Outils contextuels selon l'écran actif)
                    if hasCenterToolbar {
                        topCenterToolbar(isCompact: isCompact, isPortrait: isPortrait)
                        Spacer(minLength: 8)
                    }

                    // Toolbar 2 : Droite (Historique Undo/Redo si copie active, sinon Menu Cloud)
                    if activeScreen == .correction && appState.activeCorrectionScan != nil {
                        topTrailingHistoryToolbar
                            .glassCapsule(strokeOpacity: 0.4)
                    } else {
                        topTrailingCloudToolbar
                            .glassCapsule(strokeOpacity: 0.4)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 10)
                .zIndex(15)

                // MARK: - 4. Sidebar Flottante en Liquid Glass (Se déploie à gauche)
                if isSidebarOpen {
                    floatingSidebarDrawer
                        .transition(.move(edge: .leading).combined(with: .opacity))
                        .zIndex(20)
                }
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
            } else if CommandLine.arguments.contains("-testCorrectionStudio") || CommandLine.arguments.contains("-testMultipleTabs") {
                activeScreen = .correction
            } else if CommandLine.arguments.contains("-testPortal") {
                activeScreen = .portal
            }
        }
    }

    // MARK: - Outils Contextuels Centraux

    private var hasCenterToolbar: Bool {
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
    }

    @ViewBuilder
    private func topCenterToolbar(isCompact: Bool, isPortrait: Bool) -> some View {
        switch activeScreen {
        case .correction:
            correctionCenterTabsToolbar(isCompact: isCompact, isPortrait: isPortrait)

        case .distribution:
            distributionStepperToolbar(isCompact: isCompact)

        case .students:
            studentsCenterActionToolbar(isCompact: isCompact)

        case .portal:
            portalCenterActionToolbar(isCompact: isCompact)

        default:
            EmptyView()
        }
    }

    // MARK: - Center Toolbar : Actions du Portail Élèves

    private func portalCenterActionToolbar(isCompact: Bool) -> some View {
        HStack(spacing: 3) {
            Button {
                if appState.isOnline && !appState.isPortalGenerating {
                    appState.triggerPortalGeneration += 1
                }
            } label: {
                HStack(spacing: 6) {
                    switch appState.portalSyncStatus {
                    case .generating:
                        ProgressView()
                            .controlSize(.small)
                        Text(isCompact ? "Génération..." : "Génération du portail...")
                            .font(.system(size: 12.5, weight: .bold))
                            .foregroundColor(.primary)

                    case .checking:
                        ProgressView()
                            .controlSize(.small)
                        Text(isCompact ? "Vérification..." : "Vérification du portail...")
                            .font(.system(size: 12.5, weight: .medium))
                            .foregroundColor(.secondary)

                    case .needsGeneration:
                        Image(systemName: "bolt.badge.clock.fill")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundColor(.orange)
                        Text(isCompact ? "Générer (MAJ)" : "Générer le portail (MAJ Nécessaire)")
                            .font(.system(size: 12.5, weight: .bold))
                            .foregroundColor(.orange)

                    case .generatedReadyToUpload:
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundColor(.orange)
                        Text(isCompact ? "À mettre en ligne" : "Portail généré (À mettre en ligne)")
                            .font(.system(size: 12.5, weight: .semibold))
                            .foregroundColor(.orange)

                    case .upToDateOnline:
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundColor(.green)
                        Text(isCompact ? "À jour" : "Portail à jour")
                            .font(.system(size: 12.5, weight: .semibold))
                            .foregroundColor(.green)

                    case .noStudents:
                        Image(systemName: "person.slash")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(.secondary)
                        Text("Aucun élève")
                            .font(.system(size: 12.5, weight: .medium))
                            .foregroundColor(.secondary)
                    }
                }
                .padding(.horizontal, isCompact ? 11 : 14)
                .frame(height: 32)
                .background(
                    Group {
                        if appState.portalSyncStatus == .needsGeneration {
                            Color.orange.opacity(0.12)
                        } else if appState.portalSyncStatus == .generatedReadyToUpload {
                            Color.orange.opacity(0.08)
                        } else if case .upToDateOnline = appState.portalSyncStatus {
                            Color.green.opacity(0.08)
                        } else {
                            Color.primary.opacity(0.04)
                        }
                    }
                )
                .clipShape(Capsule())
            }
            .buttonStyle(.plain)
            .disabled(!appState.isOnline || appState.isPortalGenerating || appState.students.isEmpty)
            .opacity((appState.isOnline && !appState.isPortalGenerating && !appState.students.isEmpty) ? 1.0 : 0.45)
            .help(
                !appState.isOnline
                    ? "Disponible en ligne uniquement"
                    : (appState.students.isEmpty
                       ? "Veuillez d'abord importer des élèves"
                       : (appState.portalSyncStatus == .generatedReadyToUpload
                          ? "Portail généré prêt à être mis en ligne sur votre hébergeur. Cliquez pour re-générer."
                          : "Générer et publier le portail web chiffré"))
            )
        }
        .padding(3)
        .glassCapsule(strokeOpacity: 0.4)
    }

    private func studentsCenterActionToolbar(isCompact: Bool) -> some View {
        HStack(spacing: 3) {
            // Bouton 1 : Ajouter un élève
            Button {
                if appState.isOnline {
                    appState.showAddStudentSheet = true
                }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "person.badge.plus")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(appState.isOnline ? .blue : .secondary)

                    Text(isCompact ? "Ajouter" : "Ajouter un élève")
                        .font(.system(size: 12.5, weight: .semibold))
                        .foregroundColor(appState.isOnline ? .primary : .secondary)
                        .lineLimit(1)
                        .fixedSize(horizontal: true, vertical: false)
                }
                .padding(.horizontal, isCompact ? 11 : 14)
                .frame(height: 32)
                .background(Color.primary.opacity(0.04))
                .clipShape(Capsule())
            }
            .buttonStyle(.plain)
            .disabled(!appState.isOnline)
            .opacity(appState.isOnline ? 1.0 : 0.45)
            .help(appState.isOnline ? "Ajouter un élève" : "Disponible en ligne uniquement")

            // Bouton 2 : Importer CSV
            Button {
                if appState.isOnline {
                    appState.showCSVImportSheet = true
                }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "arrow.down.doc")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(appState.isOnline ? .blue : .secondary)

                    Text(isCompact ? "Importer" : "Importer CSV")
                        .font(.system(size: 12.5, weight: .semibold))
                        .foregroundColor(appState.isOnline ? .primary : .secondary)
                        .lineLimit(1)
                        .fixedSize(horizontal: true, vertical: false)
                }
                .padding(.horizontal, isCompact ? 11 : 14)
                .frame(height: 32)
                .background(Color.primary.opacity(0.04))
                .clipShape(Capsule())
            }
            .buttonStyle(.plain)
            .disabled(!appState.isOnline)
            .opacity(appState.isOnline ? 1.0 : 0.45)
            .help(appState.isOnline ? "Importer un fichier CSV" : "Disponible en ligne uniquement")
        }
        .padding(3)
        .glassCapsule(strokeOpacity: 0.4)
    }

    // MARK: - Center Toolbar : Onglets d'Évaluations (Correction)

    private func correctionCenterTabsToolbar(isCompact: Bool, isPortrait: Bool) -> some View {
        let shouldCollapse = (isPortrait && appState.openCorrectionScans.count >= 3)
            || (isCompact && appState.openCorrectionScans.count >= 3)
            || (appState.openCorrectionScans.count > 4)

        return HStack(spacing: 4) {
            if shouldCollapse {
                compactEvaluationsMenuPill
            } else {
                ForEach(appState.openCorrectionScans) { scan in
                    evaluationTabButton(for: scan)
                }
            }
        }
        .padding(3)
        .glassCapsule(strokeOpacity: 0.4)
    }

    // MARK: - Toolbar 1 : Haut-Gauche (Sidebar Toggle + Navigation Correction / Distribution)

    private func topLeadingToolbar(isCompact: Bool) -> some View {
        HStack(spacing: 8) {
            // Bouton Sidebar (Icone qui ouvre / referme la sidebar)
            Button {
                withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                    isSidebarOpen.toggle()
                }
            } label: {
                Image(systemName: isSidebarOpen ? "sidebar.left" : "sidebar.leading")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(isSidebarOpen ? .accentColor : .primary)
                    .frame(width: 32, height: 32)
                    .background(Color.primary.opacity(isSidebarOpen ? 0.12 : 0.05))
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)
            .help("Afficher ou masquer la barre latérale")

            Divider()
                .frame(height: 18)
                .opacity(0.3)

            // Sélecteur Mode Principal (Voie 2 : Taille 100% stable et fixe)
            HStack(spacing: 3) {
                correctionMainButton
                distributionMainButton
            }
            .padding(3)
            .background(Color.primary.opacity(0.04))
            .clipShape(Capsule())
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 4)
    }

    private var isCorrectionSelected: Bool {
        activeScreen == .correction
    }

    private var correctionMainButton: some View {
        Button {
            withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                activeScreen = .correction
                appState.activeCorrectionScan = nil
                if isSidebarOpen {
                    isSidebarOpen = false
                }
            }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "pencil.and.outline")
                    .font(.system(size: 13, weight: .semibold))

                Text(appState.t(.tabCorrection))
                    .font(.system(size: 13, weight: isCorrectionSelected ? .bold : .medium))
            }
            .foregroundColor(isCorrectionSelected ? .white : .primary)
            .padding(.horizontal, 11)
            .padding(.vertical, 7)
            .background(
                Group {
                    if isCorrectionSelected {
                        Capsule()
                            .fill(LinearGradient.electricBlue)
                            .matchedGeometryEffect(id: "activeMainPill", in: toolbarNamespace)
                            .shadow(color: Color.blue.opacity(0.3), radius: 6, y: 2)
                    } else {
                        Color.clear
                    }
                }
            )
            .clipShape(Capsule())
        }
        .buttonStyle(.plain)
        .help(appState.activeCorrectionScan != nil ? "Retourner à la mosaïque des devoirs" : "Accueil de la correction")
    }

    @ViewBuilder
    private func evaluationTabButton(for scan: StorageManager.ScanItem) -> some View {
        let isTabActive = (activeScreen == .correction && appState.activeCorrectionScan?.id == scan.id)

        HStack(spacing: 5) {
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
                        .foregroundColor(isTabActive ? (scan.isCorrected ? Color(hex: "10B981") : .white) : (scan.isCorrected ? Color(hex: "10B981") : .secondary))

                    Text(scan.cleanTitle)
                        .font(.system(size: 12, weight: isTabActive ? .bold : .medium))
                        .lineLimit(1)
                        .frame(maxWidth: 120)
                }
            }
            .buttonStyle(.plain)

            // Bouton Croix de fermeture
            Button {
                closeCorrectionTab(scan)
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 7.5, weight: .bold))
                    .foregroundColor(isTabActive ? .white.opacity(0.9) : .secondary)
                    .frame(width: 16, height: 16)
                    .background(isTabActive ? Color.white.opacity(0.25) : Color.primary.opacity(0.08))
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)
            .help("Fermer l'onglet \(scan.cleanTitle)")
        }
        .foregroundColor(isTabActive ? .white : .primary)
        .padding(.leading, 10)
        .padding(.trailing, 6)
        .padding(.vertical, 5)
        .background(
            Group {
                if isTabActive {
                    Capsule()
                        .fill(LinearGradient.electricBlue)
                        .matchedGeometryEffect(id: "activeCenterTabPill", in: toolbarNamespace)
                        .shadow(color: Color.blue.opacity(0.3), radius: 6, y: 2)
                } else {
                    Capsule()
                        .fill(Color.primary.opacity(0.04))
                }
            }
        )
        .clipShape(Capsule())
    }

    private var compactEvaluationsMenuPill: some View {
        let activeScan = (activeScreen == .correction) ? appState.activeCorrectionScan : nil
        let isTabActive = (activeScan != nil)

        return HStack(spacing: 4) {
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
                    Image(systemName: (activeScan?.isCorrected == true) ? "checkmark.seal.fill" : (activeScan != nil ? "doc.text.fill" : "doc.on.doc.fill"))
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(isTabActive ? (activeScan?.isCorrected == true ? Color(hex: "10B981") : .white) : .primary)

                    Text(activeScan?.cleanTitle ?? "\(appState.openCorrectionScans.count) évaluations")
                        .font(.system(size: 12, weight: isTabActive ? .bold : .medium))
                        .lineLimit(1)
                        .frame(maxWidth: 105)

                    Text("\(appState.openCorrectionScans.count)")
                        .font(.system(size: 10, weight: .bold))
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1.5)
                        .background(isTabActive ? Color.white.opacity(0.25) : Color.primary.opacity(0.08))
                        .foregroundColor(isTabActive ? .white : .secondary)
                        .clipShape(Capsule())

                    Image(systemName: "chevron.up.chevron.down")
                        .font(.system(size: 8.5, weight: .bold))
                        .foregroundColor(isTabActive ? .white.opacity(0.8) : .secondary)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            // Bouton Croix de fermeture de l'évaluation active
            if let current = activeScan {
                Button {
                    closeCorrectionTab(current)
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 7.5, weight: .bold))
                        .foregroundColor(isTabActive ? .white.opacity(0.9) : .secondary)
                        .frame(width: 16, height: 16)
                        .background(isTabActive ? Color.white.opacity(0.25) : Color.primary.opacity(0.08))
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
                .help("Fermer l'évaluation active \(current.cleanTitle)")
            }
        }
        .foregroundColor(isTabActive ? .white : .primary)
        .padding(.leading, 10)
        .padding(.trailing, activeScan != nil ? 6 : 8)
        .padding(.vertical, 5)
        .background(
            Group {
                if isTabActive {
                    Capsule()
                        .fill(LinearGradient.electricBlue)
                        .matchedGeometryEffect(id: "activeCenterTabPill", in: toolbarNamespace)
                        .shadow(color: Color.blue.opacity(0.3), radius: 6, y: 2)
                } else {
                    Capsule()
                        .fill(Color.primary.opacity(0.04))
                }
            }
        )
        .clipShape(Capsule())
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

    private var isDistributionSelected: Bool {
        activeScreen == .distribution
    }

    private var distributionMainButton: some View {
        Button {
            withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                activeScreen = .distribution
                if isSidebarOpen {
                    isSidebarOpen = false
                }
            }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "paperplane.fill")
                    .font(.system(size: 13, weight: .semibold))

                Text(appState.t(.tabDistribution))
                    .font(.system(size: 13, weight: isDistributionSelected ? .bold : .medium))
            }
            .foregroundColor(isDistributionSelected ? .white : .primary)
            .padding(.horizontal, 11)
            .padding(.vertical, 7)
            .background(
                Group {
                    if isDistributionSelected {
                        Capsule()
                            .fill(LinearGradient.emeraldGreen)
                            .matchedGeometryEffect(id: "activeMainPill", in: toolbarNamespace)
                            .shadow(color: Color.green.opacity(0.3), radius: 6, y: 2)
                    } else {
                        Color.clear
                    }
                }
            )
            .clipShape(Capsule())
        }
        .buttonStyle(.plain)
        .help("Distribution et envoi des devoirs")
    }

    // MARK: - Stepper Flottant de Distribution (Option B)

    private func distributionStepperToolbar(isCompact: Bool) -> some View {
        HStack(spacing: 4) {
            distributionStepItem(step: 1, title: "Chargement", icon: "tray.and.arrow.down.fill")
            distributionStepChevron
            distributionStepItem(step: 2, title: "Identification", icon: "viewfinder")
            distributionStepChevron
            distributionStepItem(step: 3, title: "Envoi", icon: "paperplane.fill")
        }
        .padding(3)
        .glassCapsule(strokeOpacity: 0.4)
    }

    private var distributionStepChevron: some View {
        Image(systemName: "chevron.right")
            .font(.system(size: 8, weight: .bold))
            .foregroundColor(.secondary.opacity(0.35))
            .padding(.horizontal, 2)
    }

    @ViewBuilder
    private func distributionStepItem(step: Int, title: String, icon: String) -> some View {
        let isActive = (appState.distributionStep == step)
        let isDone = (appState.distributionStep > step)
        let canNavigateToStep = (step <= appState.distributionStep)

        Button {
            guard canNavigateToStep else { return }
            withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                appState.distributionStep = step
            }
        } label: {
            HStack(spacing: 5) {
                ZStack {
                    if isDone {
                        Circle()
                            .fill(Color(hex: "10B981"))
                            .frame(width: 17, height: 17)
                        Image(systemName: "checkmark")
                            .font(.system(size: 8.5, weight: .bold))
                            .foregroundColor(.white)
                    } else if isActive {
                        Circle()
                            .fill(Color.white)
                            .frame(width: 17, height: 17)
                        Text("\(step)")
                            .font(.system(size: 9.5, weight: .bold))
                            .foregroundColor(Color(hex: "059669"))
                    } else {
                        Circle()
                            .fill(Color.primary.opacity(0.08))
                            .frame(width: 17, height: 17)
                        Text("\(step)")
                            .font(.system(size: 9.5, weight: .semibold))
                            .foregroundColor(.secondary)
                    }
                }

                Text(title)
                    .font(.system(size: 11.5, weight: isActive ? .bold : .medium))
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
                    .foregroundColor(isActive ? .white : (isDone ? .primary : .secondary.opacity(0.6)))
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(
                Group {
                    if isActive {
                        Capsule()
                            .fill(LinearGradient.emeraldGreen)
                            .matchedGeometryEffect(id: "activeDistributionStepPill", in: toolbarNamespace)
                            .shadow(color: Color.green.opacity(0.3), radius: 6, y: 2)
                    } else if isDone {
                        Capsule()
                            .fill(Color.green.opacity(0.06))
                    } else {
                        Color.clear
                    }
                }
            )
            .clipShape(Capsule())
        }
        .buttonStyle(.plain)
        .disabled(!canNavigateToStep)
    }

    // MARK: - Toolbar 2 : Haut-Droite (Historique Undo/Redo Dédié à la Correction)

    private var topTrailingHistoryToolbar: some View {
        HStack(spacing: 4) {
            // Bouton Annuler
            Button {
                appState.undoCorrectionTrigger += 1
            } label: {
                Image(systemName: "arrow.uturn.backward")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(appState.canUndoCorrection ? .primary : .secondary.opacity(0.35))
                    .frame(width: 30, height: 30)
                    .background(Color.primary.opacity(0.04))
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)
            .disabled(!appState.canUndoCorrection)
            .help("Annuler la dernière action (tracé, surlignage, tampon, texte)")

            Divider()
                .frame(height: 16)
                .opacity(0.3)

            // Bouton Rétablir
            Button {
                appState.redoCorrectionTrigger += 1
            } label: {
                Image(systemName: "arrow.uturn.forward")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(appState.canRedoCorrection ? .primary : .secondary.opacity(0.35))
                    .frame(width: 30, height: 30)
                    .background(Color.primary.opacity(0.04))
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)
            .disabled(!appState.canRedoCorrection)
            .help("Rétablir la dernière action")
        }
        .padding(3)
    }

    // MARK: - Toolbar 2 : Haut-Droite (Widget Cloud Déroulant)

    private var topTrailingCloudToolbar: some View {
        Menu {
            if !appState.isOnline {
                Section("Mode Hors-Ligne") {
                    Label("Connexion Internet inactive", systemImage: "bolt.slash.fill")
                    Text("Vos copies annotées sont enregistrées localement et seront envoyées sur Dropbox dès le retour de la connexion.")
                        .font(.caption2)
                }

                Divider()

                Button {
                    Task { await appState.loadInitialData() }
                } label: {
                    Label(appState.t(.navReloadData), systemImage: "arrow.clockwise")
                }
            } else {
                Section(appState.t(.navActiveStorage)) {
                    Label(appState.storageManager.activeProvider.providerType.displayName, systemImage: appState.storageManager.activeProvider.providerType.iconName)
                    Label("\(appState.t(.navSourceFolder)) \(activeRootPath)", systemImage: "folder")
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
        } label: {
            HStack(spacing: 8) {
                if !appState.isOnline {
                    Circle()
                        .fill(Color.orange)
                        .frame(width: 8, height: 8)

                    Image(systemName: "bolt.slash.fill")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.orange)

                    VStack(alignment: .leading, spacing: 1) {
                        Text("Hors-ligne")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundColor(.orange)

                        Text("Cache local actif")
                            .font(.system(size: 9))
                            .foregroundColor(.secondary)
                    }
                } else {
                    Circle()
                        .fill(appState.storageManager.activeProvider.isConnected ? Color.green : Color.orange)
                        .frame(width: 8, height: 8)

                    CloudBrandIconView(type: appState.storageManager.activeProvider.providerType, size: 16)

                    VStack(alignment: .leading, spacing: 1) {
                        Text(appState.storageManager.activeProvider.providerType.displayName)
                            .font(.system(size: 11, weight: .bold))
                            .foregroundColor(.primary)

                        HStack(spacing: 4) {
                            Text(activeRootPath)
                                .font(.system(size: 9, design: .monospaced))
                                .foregroundColor(.secondary)
                                .lineLimit(1)

                            if appState.isLoading || OfflineSyncEngine.shared.isSyncing {
                                ProgressView()
                                    .controlSize(.mini)
                                    .scaleEffect(0.5)
                            }
                        }
                    }
                }

                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundColor(.secondary)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
        }
        .buttonStyle(.plain)
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

        Button {
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
                    .foregroundColor(isSelected ? .primary : .secondary)

                Spacer()

                if let badge = badgeText {
                    Text(badge)
                        .font(.caption2.bold())
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.secondary.opacity(0.12))
                        .clipShape(Capsule())
                }
            }
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
    }
}
