// VirtualPadSettingsView.swift — Virtual pad opacity, haptic, layout editing
// SPDX-License-Identifier: GPL-3.0+

import SwiftUI

struct VirtualPadSettingsView: View {
    @State private var settings = SettingsStore.shared
    @State private var showLayoutEditor = false

    var body: some View {
        Form {
            Section("Appearance") {
                VStack(alignment: .leading) {
                    Text("Opacity: \(Int(settings.padOpacity * 100))%")
                    Slider(value: $settings.padOpacity, in: 0.1...1.0, step: 0.05)
                }
            }

            Section("Feedback") {
                Toggle("Haptic Feedback", isOn: $settings.hapticFeedback)
            }

            Section {
                Group {
                    Text("Left Stick")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Toggle("Invert X axis", isOn: $settings.leftStickInvertX)
                    Toggle("Invert Y axis", isOn: $settings.leftStickInvertY)
                }
                Group {
                    Text("Right Stick")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .padding(.top, 4)
                    Toggle("Invert X axis", isOn: $settings.rightStickInvertX)
                    Toggle("Invert Y axis", isOn: $settings.rightStickInvertY)
                }
            } header: {
                Text("Analog Sticks")
            } footer: {
                Text("Flip the direction of a stick axis. Useful if movement feels reversed.")
            }

            Section("Layout") {
                Button {
                    showLayoutEditor = true
                } label: {
                    Label("Edit Layout", systemImage: "square.resize")
                }
                Text("Drag buttons to reposition. Pinch to resize.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle("Virtual Pad")
        .navigationBarTitleDisplayMode(.inline)
        .fullScreenCover(isPresented: $showLayoutEditor) {
            PadLayoutEditView()
        }
    }
}
