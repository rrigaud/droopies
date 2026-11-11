//
//  DroopiesApp.swift
//  Droopies
//
//  Point d'entrée principal de l'application native Droopies (@main).
//  Supporte nativement macOS Sonoma+ et iPadOS 17+.
//  Démarre par le SplashScreen de configuration environnementale si nécessaire.
//

import SwiftUI

@main
struct DroopiesApp: App {
    @State private var appState = AppState()
    @State private var isSetupCompleted: Bool = CommandLine.arguments.contains(where: {
        $0.hasPrefix("-test")
            && $0 != "-testOfflineFirstLaunch"
            && $0 != "-testSplash"
            && $0 != "-testStepper"
            && $0 != "-testStep1Selected"
            && $0 != "-testStep2"
            && $0 != "-testStep2Connected"
            && $0 != "-testStep3"
    })

    private var activeLocale: Locale {
        appState.settings.language.locale ?? Locale.autoupdatingCurrent
    }

    var body: some Scene {
        WindowGroup {
            Group {
                if isSetupCompleted {
                    MainSplitView(appState: appState)
                } else {
                    SplashSetupView(appState: appState) {
                        withAnimation(.spring(response: 0.45, dampingFraction: 0.8)) {
                            isSetupCompleted = true
                        }
                    }
                }
            }
            .environment(\.locale, activeLocale)
            #if os(macOS)
            .frame(minWidth: 950, minHeight: 650)
            .onAppear {
                NSApplication.shared.activate(ignoringOtherApps: true)
            }
            #endif
        }
        #if os(macOS)
        .defaultSize(width: 1150, height: 780)
        .commands {
            SidebarCommands()
            CommandGroup(replacing: .newItem) {}
        }
        #endif
    }
}
