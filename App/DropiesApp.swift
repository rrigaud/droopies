//
//  DropiesApp.swift
//  Dropies
//
//  Point d'entrée principal de l'application native Dropies (@main).
//  Supporte nativement macOS Sonoma+ et iPadOS 17+.
//

import SwiftUI

@main
struct DropiesApp: App {
    @State private var appState = AppState()

    var body: some Scene {
        WindowGroup {
            MainSplitView(appState: appState)
                #if os(macOS)
                .frame(minWidth: 950, minHeight: 650)
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
