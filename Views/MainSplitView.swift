//
//  MainSplitView.swift
//  Dropies
//
//  Navigation principale adaptative iPadOS & macOS (NavigationSplitView).
//  Sublimée avec le style Liquid Glass, barres translucides et sélecteur de Cloud actif.
//

import SwiftUI

public enum NavigationTab: String, Hashable, CaseIterable {
    case correction = "Correction d'un devoir"
    case students = "Gestion des Élèves"
    case portal = "Portail Élèves"
    case settings = "Réglages & Cloud"

    public var icon: String {
        switch self {
        case .correction: return "pencil.and.outline"
        case .students: return "person.2.fill"
        case .portal: return "globe"
        case .settings: return "gearshape.fill"
        }
    }

    public var tintColor: Color {
        switch self {
        case .correction: return Color(red: 0.15, green: 0.45, blue: 1.0)
        case .students: return Color(red: 0.55, green: 0.35, blue: 0.95)
        case .portal: return Color(red: 0.05, green: 0.75, blue: 0.45)
        case .settings: return Color(white: 0.45)
        }
    }
}

public struct MainSplitView: View {
    @Bindable public var appState: AppState
    @State private var selectedTab: NavigationTab? = .correction

    @State private var showFolderPicker: Bool = false
    @State private var showCloudSetupSheet: Bool = false

    public init(appState: AppState) {
        self.appState = appState
    }

    private var activeRootPath: String {
        if let dropbox = appState.storageManager.activeProvider as? DropboxStorageProvider {
            return dropbox.rootFolderPath.isEmpty ? "/" : dropbox.rootFolderPath
        }
        return "Local"
    }

    public var body: some View {
        NavigationSplitView {
            List(selection: $selectedTab) {
                // MARK: - En-tête Dropies
                Section {
                    HStack(spacing: 12) {
                        DropiesMascotView(size: 36, hasShadow: true)

                        VStack(alignment: .leading, spacing: 2) {
                            Text("Dropies")
                                .font(.system(.headline, design: .rounded, weight: .bold))
                            Text("Studio Enseignant")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }

                        Spacer()

                        Text("v1.0")
                            .font(.system(size: 10, weight: .semibold))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.secondary.opacity(0.15))
                            .clipShape(Capsule())
                    }
                    .padding(.vertical, 4)
                }

                // MARK: - Sélecteur de Compte & Dossier Cloud Actif (Menu Déroulant)
                Section {
                    Menu {
                        Section("Stockage Actif") {
                            Label(appState.storageManager.activeProvider.providerType.displayName, systemImage: appState.storageManager.activeProvider.providerType.iconName)
                            Label("Dossier : \(activeRootPath)", systemImage: "folder")
                        }

                        Divider()

                        Button {
                            showFolderPicker = true
                        } label: {
                            Label("Changer de dossier Source...", systemImage: "folder.badge.gearshape")
                        }

                        Button {
                            showCloudSetupSheet = true
                        } label: {
                            Label("Changer de compte ou de Cloud...", systemImage: "arrow.triangle.2.circlepath")
                        }

                        Divider()

                        Button {
                            Task { await appState.loadInitialData() }
                        } label: {
                            Label("Recharger les données", systemImage: "arrow.clockwise")
                        }
                    } label: {
                        HStack(spacing: 8) {
                            Circle()
                                .fill(appState.storageManager.activeProvider.isConnected ? Color.green : Color.orange)
                                .frame(width: 8, height: 8)

                            CloudBrandIconView(type: appState.storageManager.activeProvider.providerType, size: 16)

                            VStack(alignment: .leading, spacing: 1) {
                                Text(appState.storageManager.activeProvider.providerType.displayName)
                                    .font(.system(size: 12, weight: .bold))
                                    .foregroundColor(.primary)

                                Text(activeRootPath)
                                    .font(.system(size: 10, design: .monospaced))
                                    .foregroundColor(.secondary)
                                    .lineLimit(1)
                            }

                            Spacer()

                            Image(systemName: "chevron.up.chevron.down")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 7)
                        .background(Color.primary.opacity(0.04))
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                    }
                    .buttonStyle(.plain)
                }

                Section("Flux de Correction") {
                    NavigationLink(value: NavigationTab.correction) {
                        sidebarItem(tab: .correction)
                    }
                }

                Section("Administration Scolaire") {
                    NavigationLink(value: NavigationTab.students) {
                        HStack {
                            sidebarItem(tab: .students)
                            Spacer()
                            Text("\(appState.students.count)")
                                .font(.caption2.bold())
                                .padding(.horizontal, 7)
                                .padding(.vertical, 2)
                                .background(Color.secondary.opacity(0.12))
                                .clipShape(Capsule())
                        }
                    }

                    NavigationLink(value: NavigationTab.portal) {
                        sidebarItem(tab: .portal)
                    }
                }

                Section("Configuration") {
                    NavigationLink(value: NavigationTab.settings) {
                        sidebarItem(tab: .settings)
                    }
                }
            }
            .listStyle(.sidebar)
            .navigationTitle("Dropies")
        } detail: {
            Group {
                switch selectedTab {
                case .correction:
                    CorrectionWorkflowView(appState: appState)
                case .students:
                    StudentsManagementView(appState: appState)
                case .portal:
                    PortalSettingsView(appState: appState)
                case .settings:
                    AppSettingsView(appState: appState)
                case .none:
                    CorrectionWorkflowView(appState: appState)
                }
            }
            .withLiquidGlassBackground()
        }
        .sheet(isPresented: $showFolderPicker) {
            CloudFolderPickerSheet(
                provider: appState.storageManager.activeProvider,
                initialPath: (appState.storageManager.activeProvider as? DropboxStorageProvider)?.rootFolderPath ?? ""
            ) { chosenPath in
                if let dropbox = appState.storageManager.activeProvider as? DropboxStorageProvider {
                    dropbox.configure(
                        appKey: dropbox.appKey,
                        refreshToken: dropbox.refreshToken,
                        accessToken: dropbox.accessToken,
                        rootFolderPath: chosenPath
                    )
                }
                Task {
                    try? await appState.storageManager.ensureSourceFolderStructure()
                    await appState.loadInitialData()
                }
            }
        }
        .sheet(isPresented: $showCloudSetupSheet) {
            SplashSetupView(appState: appState) {
                showCloudSetupSheet = false
            }
        }
        .task {
            await appState.loadInitialData()
        }
    }

    @ViewBuilder
    private func sidebarItem(tab: NavigationTab) -> some View {
        HStack(spacing: 10) {
            Image(systemName: tab.icon)
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(.white)
                .frame(width: 28, height: 28)
                .background(
                    LinearGradient(
                        colors: [tab.tintColor, tab.tintColor.opacity(0.8)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                .shadow(color: tab.tintColor.opacity(0.3), radius: 3, y: 1)

            Text(tab.rawValue)
                .font(.system(size: 14, weight: .medium))
        }
        .padding(.vertical, 2)
    }
}
