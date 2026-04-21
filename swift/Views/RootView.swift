// RootView.swift — Root view switching between menu and game
// SPDX-License-Identifier: GPL-3.0+

import SwiftUI
import UIKit

struct RootView: View {
    @State private var appState = AppState.shared
    @State private var fileImporter = FileImportHandler.shared
    @AppStorage("colorScheme") private var colorSchemeRaw: String = "system"

    var body: some View {
        ZStack {
            switch appState.currentScreen {
            case .menu:
                Color(uiColor: .systemGroupedBackground)
                    .ignoresSafeArea()
                MenuTabView()
            case .playing:
                GameScreenView()
            }
        }
        .onAppear { applyTheme(colorSchemeRaw) }
        .onChange(of: colorSchemeRaw) { _, newValue in applyTheme(newValue) }
        .onOpenURL { url in
            fileImporter.handleURL(url)
        }
        .alert("File Import", isPresented: $fileImporter.showImportAlert) {
            Button("OK") {}
        } message: {
            Text(fileImporter.lastImportMessage ?? "")
        }
    }

    private func applyTheme(_ scheme: String) {
        let style: UIUserInterfaceStyle
        switch scheme {
        case "light": style = .light
        case "dark":  style = .dark
        default:      style = .unspecified
        }
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap { $0.windows }
            .forEach { $0.overrideUserInterfaceStyle = style }
    }
}

struct MenuTabView: View {
    @State private var appState = AppState.shared
    @State private var selectedTab = 0

    var body: some View {
        TabView(selection: $selectedTab) {
            GameListView()
                .tabItem {
                    Label("Games", systemImage: "gamecontroller")
                }
                .tag(0)

            BIOSListView()
                .tabItem {
                    Label("BIOS", systemImage: "cpu")
                }
                .tag(1)

            HelpView()
                .tabItem {
                    Label("Help", systemImage: "questionmark.circle")
                }
                .tag(2)

            NavigationStack {
                SettingsRootView()
            }
            .tabItem {
                Label("Settings", systemImage: "gearshape")
            }
            .tag(3)
        }
        .tint(.blue)
    }
}
