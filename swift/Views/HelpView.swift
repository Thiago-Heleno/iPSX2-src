// HelpView.swift — Practical user guide
// SPDX-License-Identifier: GPL-3.0+

import SwiftUI

struct HelpSection: Identifiable {
    let id = UUID()
    let title: String
    let icon: String
    let items: [HelpItem]
}

struct HelpItem: Identifiable {
    let id = UUID()
    let question: String
    let answer: String
}

// [P51] Rewritten: practical file placement + settings explanations only
private let helpData: [HelpSection] = [
    HelpSection(title: "File Placement", icon: "folder", items: [
        HelpItem(
            question: "BIOS file",
            answer: "Place your PS2 BIOS (.bin / .rom) in Documents/bios/ via the Files app or iTunes File Sharing (Finder). Files placed in the Documents/ root folder are also detected automatically. Select the default BIOS in the BIOS tab."
        ),
        HelpItem(
            question: "Game files",
            answer: "Place ISO, BIN, CHD, IMG, or ELF game files in Documents/iso/. Files in the Documents/ root folder are also detected. They appear in the Games tab."
        ),
        HelpItem(
            question: "Where is the Documents folder?",
            answer: "On Mac: open Finder, select your iPhone in the sidebar, then the Files tab. On Windows: use iTunes > File Sharing. You can also use the iOS Files app (On My iPhone > iPSX2)."
        ),
    ]),
    HelpSection(title: "Settings Guide", icon: "gearshape", items: [
        HelpItem(
            question: "EE / IOP / VU0 / VU1 (JIT vs Interpreter)",
            answer: "JIT (Recompiler) is much faster. Interpreter is slower but more stable. If a game crashes or behaves incorrectly, try switching individual components to Interpreter. Changes take effect on next boot."
        ),
        HelpItem(
            question: "Fast Boot",
            answer: "Skips the PS2 BIOS intro and boots the game directly. Some games require this OFF to initialize correctly (e.g. missing 3D graphics)."
        ),
        HelpItem(
            question: "Fastmem",
            answer: "Speeds up EE memory access via direct mapping. Disable if 3D graphics are broken. Requires app restart."
        ),
        HelpItem(
            question: "MTVU",
            answer: "Offloads VU1 processing to a separate thread. Improves performance on multi-core devices, but may cause instability in some games."
        ),
        HelpItem(
            question: "Internal Resolution",
            answer: "1x = native PS2 resolution (recommended). 2x/3x provide higher resolution output but significantly increase GPU load."
        ),
        HelpItem(
            question: "VSync Queue Size",
            answer: "Number of pre-rendered frames. Higher values reduce frame drops but increase input latency. Default: 8."
        ),
    ]),
    HelpSection(title: "Overlay", icon: "speedometer", items: [
        HelpItem(
            question: "Overlay presets",
            answer: "OFF: No overlay. Simple: FPS + CPU usage. Detail: FPS, Speed, CPU, Resolution. Full: Everything including Frame Times graph. Configure in Settings > Overlay."
        ),
        HelpItem(
            question: "In-game toggle",
            answer: "Tap the menu button (top-right) during gameplay and select Show/Hide Overlay. This toggles visibility without changing your preset."
        ),
    ]),
    HelpSection(title: "Supported Formats", icon: "doc.circle", items: [
        HelpItem(question: "Game formats", answer: "ISO, BIN (>50MB), CHD, IMG"),
        HelpItem(question: "BIOS formats", answer: "BIN, ROM (1-50MB, dumped from your own PS2)"),
    ]),
]

struct HelpView: View {
    var body: some View {
        NavigationStack {
            List {
                ForEach(helpData) { section in
                    Section {
                        ForEach(section.items) { item in
                            DisclosureGroup {
                                Text(item.answer)
                                    .font(.body)
                                    .foregroundStyle(.secondary)
                                    .padding(.vertical, 4)
                            } label: {
                                Text(item.question)
                                    .font(.body)
                            }
                        }
                    } header: {
                        Label(section.title, systemImage: section.icon)
                    }
                }

                Section {
                    HStack {
                        Text("Version")
                        Spacer()
                        Text(iPSX2Bridge.buildVersion())
                            .foregroundStyle(.secondary)
                            .font(.caption)
                    }
                } header: {
                    Label("About", systemImage: "info.circle")
                }
            }
            .navigationTitle("Help")
        }
    }
}
