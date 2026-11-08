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

                    // Toolbar 2 : Droite (Widget Menu Cloud actif)
                    topTrailingCloudToolbar
                        .glassCapsule(strokeOpacity: 0.4)
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
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(appState.isOnline ? .primary : .secondary)
                    }
                    .padding(.horizontal, isCompact ? 12 : 14)
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
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(appState.isOnline ? .primary : .secondary)
                    }
                    .padding(.horizontal, isCompact ? 12 : 14)
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
            .background(Color.primary.opacity(0.04))
            .clipShape(Capsule())
            .padding(.horizontal, 6)
            .padding(.vertical, 4)
            .glassCapsule(strokeOpacity: 0.4)

        default:
            EmptyView()
        }
    }

    // MARK: - Toolbar 1 : Haut-Gauche (Sidebar Toggle + Correction / Distribution)

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

            // Sélecteur Mode Principal : Correction vs Distribution
            HStack(spacing: 3) {
                primaryModeButton(
                    screen: .correction,
                    title: appState.t(.tabCorrection),
                    icon: "pencil.and.outline",
                    gradient: LinearGradient.electricBlue
                )

                primaryModeButton(
                    screen: .distribution,
                    title: appState.t(.tabDistribution),
                    icon: "paperplane.fill",
                    gradient: LinearGradient.emeraldGreen
                )
            }
            .padding(3)
            .background(Color.primary.opacity(0.04))
            .clipShape(Capsule())
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 4)
    }

    @ViewBuilder
    private func primaryModeButton(
        screen: AppScreen,
        title: String,
        icon: String,
        gradient: LinearGradient
    ) -> some View {
        let isSelected = activeScreen == screen

        Button {
            withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                activeScreen = screen
                if isSidebarOpen {
                    isSidebarOpen = false
                }
            }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 13, weight: .semibold))

                Text(title)
                    .font(.system(size: 13, weight: isSelected ? .bold : .medium))
            }
            .foregroundColor(isSelected ? .white : .primary)
            .padding(.horizontal, 14)
            .padding(.vertical, 7)
            .background(
                Group {
                    if isSelected {
                        Capsule()
                            .fill(gradient)
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
