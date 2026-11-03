//
//  MainSplitView.swift
//  Dropies
//
//  Navigation principale adaptative iPadOS & macOS (NavigationSplitView).
//  Sublimée avec le style Liquid Glass, barres translucides et icônes vibrantes.
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

    public init(appState: AppState) {
        self.appState = appState
    }

    public var body: some View {
        NavigationSplitView {
            List(selection: $selectedTab) {
                // MARK: - En-tête Dropies
                Section {
                    HStack(spacing: 12) {
                        Image(systemName: "dog.fill")
                            .font(.system(size: 20, weight: .bold))
                            .foregroundColor(.white)
                            .frame(width: 36, height: 36)
                            .background(
                                LinearGradient(
                                    colors: [Color.blue, Color.cyan],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                            .shadow(color: Color.blue.opacity(0.35), radius: 6, y: 2)

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
