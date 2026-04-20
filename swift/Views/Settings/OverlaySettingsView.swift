// OverlaySettingsView.swift — OSD preset selector
// SPDX-License-Identifier: GPL-3.0+

import SwiftUI

struct OverlaySettingsView: View {
    @State private var settings = SettingsStore.shared

    var body: some View {
        Form {
            Section("Performance Overlay") {
                Picker("Preset", selection: $settings.osdPreset) {
                    ForEach(OsdPreset.allCases, id: \.self) { preset in
                        Text(preset.label).tag(preset)
                    }
                }
                .pickerStyle(.segmented)
            }

            Section {
                switch settings.osdPreset {
                case .off:
                    Text("Overlay is hidden.")
                        .foregroundStyle(.secondary)
                case .simple:
                    Label("FPS", systemImage: "checkmark")
                    Label("CPU Usage (EE/GS)", systemImage: "checkmark")
                case .detail:
                    Label("FPS", systemImage: "checkmark")
                    Label("Speed %", systemImage: "checkmark")
                    Label("CPU Usage (EE/GS)", systemImage: "checkmark")
                    Label("Resolution", systemImage: "checkmark")
                case .full:
                    Label("FPS", systemImage: "checkmark")
                    Label("Speed %", systemImage: "checkmark")
                    Label("CPU Usage (EE/GS)", systemImage: "checkmark")
                    Label("Resolution", systemImage: "checkmark")
                    Label("Frame Times Graph", systemImage: "checkmark")
                }
            } header: {
                Text("Displayed Items")
            }
        }
        .navigationTitle("Overlay")
        .navigationBarTitleDisplayMode(.inline)
    }
}
