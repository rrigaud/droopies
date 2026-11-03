//
//  MainSplitView.swift
//  Dropies
//
//  Navigation principale adaptative iPadOS & macOS (NavigationSplitView).
//  Garantit une ergonomie fluide au doigt, à l'Apple Pencil et au clavier/trackpad.
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
                Section("Flux de Correction") {
                    NavigationLink(value: NavigationTab.correction) {
                        Label(NavigationTab.correction.rawValue, systemImage: NavigationTab.correction.icon)
                    }
                }

                Section("Administration Scolaire") {
                    NavigationLink(value: NavigationTab.students) {
                        HStack {
                            Label(NavigationTab.students.rawValue, systemImage: NavigationTab.students.icon)
                            Spacer()
                            Text("\(appState.students.count)")
                                .font(.caption2.bold())
                                .foregroundColor(.secondary)
                        }
                    }

                    NavigationLink(value: NavigationTab.portal) {
                        Label(NavigationTab.portal.rawValue, systemImage: NavigationTab.portal.icon)
                    }
                }

                Section("Configuration") {
                    NavigationLink(value: NavigationTab.settings) {
                        Label(NavigationTab.settings.rawValue, systemImage: NavigationTab.settings.icon)
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
}
