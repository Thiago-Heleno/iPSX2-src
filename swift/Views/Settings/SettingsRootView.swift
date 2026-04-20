// SettingsRootView.swift — Settings navigation root
// SPDX-License-Identifier: GPL-3.0+

import SwiftUI

struct SettingsRootView: View {
    @AppStorage("colorScheme") private var colorSchemeRaw: String = "system"

    var body: some View {
        List {
            Section("Appearance") {
                Picker("Theme", selection: $colorSchemeRaw) {
                    Text("System").tag("system")
                    Text("Light").tag("light")
                    Text("Dark").tag("dark")
                }
                .pickerStyle(.segmented)
            }

            Section {
                NavigationLink {
                    EmulatorSettingsView()
                } label: {
                    Label("Emulator", systemImage: "cpu")
                }
                NavigationLink {
                    GraphicsSettingsView()
                } label: {
                    Label("Graphics", systemImage: "paintbrush")
                }
                NavigationLink {
                    OverlaySettingsView()
                } label: {
                    Label("Overlay (OSD)", systemImage: "text.below.photo")
                }
                NavigationLink {
                    GamepadSettingsView()
                } label: {
                    Label("Game Controller", systemImage: "gamecontroller")
                }
                NavigationLink {
                    VirtualPadSettingsView()
                } label: {
                    Label("Virtual Pad", systemImage: "hand.draw")
                }
            }

            Section {
                NavigationLink {
                    LicenseView()
                } label: {
                    Label("Licenses & Credits", systemImage: "doc.text")
                }
            }

            Section("About") {
                HStack {
                    Text("Version")
                    Spacer()
                    Text(iPSX2Bridge.buildVersion())
                        .foregroundStyle(.secondary)
                        .font(.caption)
                }
            }
        }
        .navigationTitle("Settings")
        .navigationBarTitleDisplayMode(.inline)
    }
}
