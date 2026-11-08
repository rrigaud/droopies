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
            let isCompact = geometry.size.width < 960

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
                    topLeadingToolbar
                        .glassCapsule(strokeOpacity: 0.4)

                    Spacer(minLength: 12)

                    // Toolbar Centrale Flottante (Outils contextuels selon l'écran actif)
                    if hasCenterToolbar {
                        topCenterToolbar(isCompact: isCompact)
                        Spacer(minLength: 12)
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
            } else if CommandLine.arguments.contains("-testCorrectionStudio") || CommandLine.arguments.contains("-testMultipleTabs") {
                activeScreen = .correction
            }
        }
    }

    // MARK: - Outils Contextuels Centraux

    private var hasCenterToolbar: Bool {
        switch activeScreen {
        case .students:
            return true
        default:
            return false
        }
    }

    @ViewBuilder
    private func topCenterToolbar(isCompact: Bool) -> some View {
        switch activeScreen {
        case .students:
            Menu {
                Button {
                    if appState.isOnline {
                        appState.showAddStudentSheet = true
                    }
                } label: {
                    Label("Ajouter un élève", systemImage: "person.badge.plus")
                }
                .disabled(!appState.isOnline)

                Button {
                    if appState.isOnline {
                        appState.showCSVImportSheet = true
                    }
                } label: {
                    Label("Importer un fichier CSV", systemImage: "arrow.down.doc")
                }
                .disabled(!appState.isOnline)
            } label: {
                Image(systemName: "plus")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(appState.isOnline ? .blue : .secondary)
                    .frame(width: 32, height: 32)
                    .background(Color.primary.opacity(0.04))
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)
            .disabled(!appState.isOnline)
            .opacity(appState.isOnline ? 1.0 : 0.45)
            .help(appState.isOnline ? "Ajouter ou importer des élèves" : "Disponible en ligne uniquement")
            .padding(3)
            .glassCapsule(strokeOpacity: 0.4)

        default:
            EmptyView()
        }
    }

    // MARK: - Toolbar 1 : Haut-Gauche (Sidebar Toggle + Correction / Onglets Dynamiques / Distribution)

    private var topLeadingToolbar: some View {
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

            // Sélecteur Mode Principal + Onglets dynamiques des évaluations
            HStack(spacing: 3) {
                // 1. Bouton Correction (retour à la mosaïque d'accueil)
                correctionMainButton

                // 2. Onglets dynamiques des évaluations ouvertes
                if !appState.openCorrectionScans.isEmpty {
                    ForEach(appState.openCorrectionScans) { scan in
                        evaluationTabButton(for: scan)
                    }
                }

                // 3. Bouton Distribution (compacté à son icône seule si évaluations ouvertes)
                distributionMainButton
            }
            .padding(3)
            .background(Color.primary.opacity(0.04))
            .clipShape(Capsule())
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 4)
    }

    private var isCorrectionHomeSelected: Bool {
        activeScreen == .correction && appState.activeCorrectionScan == nil
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
                    .font(.system(size: 13, weight: isCorrectionHomeSelected ? .bold : .medium))
            }
            .foregroundColor(isCorrectionHomeSelected ? .white : .primary)
            .padding(.horizontal, 14)
            .padding(.vertical, 7)
            .background(
                Group {
                    if isCorrectionHomeSelected {
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
        .help("Accueil de la correction (mosaïque des paquets)")
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
                        .matchedGeometryEffect(id: "activeMainPill", in: toolbarNamespace)
                        .shadow(color: Color.blue.opacity(0.3), radius: 6, y: 2)
                } else {
                    Capsule()
                        .fill(Color.primary.opacity(0.04))
                }
            }
        )
        .clipShape(Capsule())
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

    private var distributionMainButton: some View {
        let isDistribution = (activeScreen == .distribution)
        let hasOpenScans = !appState.openCorrectionScans.isEmpty

        return Button {
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

                if !hasOpenScans {
                    Text(appState.t(.tabDistribution))
                        .font(.system(size: 13, weight: isDistribution ? .bold : .medium))
                }
            }
            .foregroundColor(isDistribution ? .white : .primary)
            .padding(.horizontal, hasOpenScans ? 10 : 14)
            .padding(.vertical, 7)
            .background(
                Group {
                    if isDistribution {
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
        .help(hasOpenScans ? appState.t(.tabDistribution) : "")
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
