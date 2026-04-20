// BIOSListView.swift — BIOS file list with default selection
// SPDX-License-Identifier: GPL-3.0+

import SwiftUI

struct BIOSListView: View {
    @State private var bioses: [String] = []
    @State private var defaultBIOS: String = ""

    var body: some View {
        NavigationStack {
            Group {
                if bioses.isEmpty {
                    emptyState
                } else {
                    List {
                        ForEach(bioses, id: \.self) { bios in
                            biosRow(bios)
                        }
                    }
                }
            }
            .navigationTitle("BIOS")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { loadBIOSes() } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                }
            }
        }
        .onAppear { loadBIOSes() }
    }

    private func biosRow(_ bios: String) -> some View {
        Button {
            iPSX2Bridge.setDefaultBIOS(bios)
            defaultBIOS = bios
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(bios)
                        .font(.body)
                        .foregroundStyle(.primary)
                    Text(regionGuess(bios))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if bios == defaultBIOS {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.blue)
                }
            }
        }
        .foregroundStyle(.primary)
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "cpu")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)
            Text("No BIOS Found")
                .font(.title2)
                .fontWeight(.semibold)
            Text("Place PS2 BIOS files (.bin) in:\nDocuments/bios/")
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Text("Use the Files app or iTunes File Sharing\nto transfer BIOS files.")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
        }
        .padding()
    }

    private func loadBIOSes() {
        bioses = iPSX2Bridge.availableBIOSes()
        defaultBIOS = iPSX2Bridge.defaultBIOSName()
    }

    private func regionGuess(_ name: String) -> String {
        let upper = name.uppercased()
        if upper.contains("JP") || upper.contains("JAPAN") || upper.contains("70000") || upper.contains("50000") {
            return "Japan"
        } else if upper.contains("US") || upper.contains("AMERICA") || upper.contains("30001") || upper.contains("39001") {
            return "North America"
        } else if upper.contains("EU") || upper.contains("EUROPE") || upper.contains("30004") || upper.contains("39004") {
            return "Europe"
        }
        return "Unknown Region"
    }
}
