// SettingsStore.swift — INI-backed settings for SwiftUI
// SPDX-License-Identifier: GPL-3.0+

import SwiftUI

/// [P51] OSD preset levels
enum OsdPreset: Int, CaseIterable {
    case off = 0
    case simple = 1    // FPS + CPU usage
    case detail = 2    // All except frame times graph
    case full = 3      // Everything

    var label: String {
        switch self {
        case .off: return "OFF"
        case .simple: return "Simple"
        case .detail: return "Detail"
        case .full: return "Full"
        }
    }
}

@Observable
final class SettingsStore: @unchecked Sendable {
    static let shared = SettingsStore()

    // ── Emulator / CPU ──
    var eeCoreType: Int {
        didSet { iPSX2Bridge.setINIInt("EmuCore/CPU", key: "CoreType", value: Int32(eeCoreType)) }
    }
    var iopRecompiler: Bool {
        didSet { iPSX2Bridge.setINIBool("EmuCore/CPU/Recompiler", key: "EnableIOP", value: iopRecompiler) }
    }
    var vu0Recompiler: Bool {
        didSet { iPSX2Bridge.setINIBool("EmuCore/CPU/Recompiler", key: "EnableVU0", value: vu0Recompiler) }
    }
    var vu1Recompiler: Bool {
        didSet { iPSX2Bridge.setINIBool("EmuCore/CPU/Recompiler", key: "EnableVU1", value: vu1Recompiler) }
    }
    var fastBoot: Bool {
        didSet { iPSX2Bridge.setINIBool("GameISO", key: "FastBoot", value: fastBoot) }
    }
    var fastmem: Bool {
        didSet { iPSX2Bridge.setINIBool("EmuCore/CPU/Recompiler", key: "EnableFastmem", value: fastmem) }
    }

    // ── Boot ──
    var fastCDVD: Bool {
        didSet { iPSX2Bridge.setINIBool("EmuCore/Speedhacks", key: "fastCDVD", value: fastCDVD) }
    }

    // ── Advanced Speedhacks ──
    var eeCycleRate: Int {
        didSet { iPSX2Bridge.setINIInt("EmuCore/Speedhacks", key: "EECycleRate", value: Int32(eeCycleRate)) }
    }
    var vu1Instant: Bool {
        didSet { iPSX2Bridge.setINIBool("EmuCore/Speedhacks", key: "vu1Instant", value: vu1Instant) }
    }
    var waitLoop: Bool {
        didSet { iPSX2Bridge.setINIBool("EmuCore/Speedhacks", key: "WaitLoop", value: waitLoop) }
    }
    var intcStat: Bool {
        didSet { iPSX2Bridge.setINIBool("EmuCore/Speedhacks", key: "IntcStat", value: intcStat) }
    }

    // ── Graphics ──
    var renderer: Int {
        didSet { iPSX2Bridge.setINIInt("EmuCore/GS", key: "Renderer", value: Int32(renderer)) }
    }
    var upscaleMultiplier: Float {
        didSet { iPSX2Bridge.setINIFloat("EmuCore/GS", key: "upscale_multiplier", value: upscaleMultiplier) }
    }
    var vsyncQueueSize: Int {
        didSet { iPSX2Bridge.setINIInt("EmuCore/GS", key: "VsyncQueueSize", value: Int32(vsyncQueueSize)) }
    }
    var textureFiltering: Int {
        didSet { iPSX2Bridge.setINIInt("EmuCore/GS", key: "filter", value: Int32(textureFiltering)) }
    }
    var fxaa: Bool {
        didSet { iPSX2Bridge.setINIBool("EmuCore/GS", key: "fxaa", value: fxaa) }
    }
    var casMode: Int {
        didSet { iPSX2Bridge.setINIInt("EmuCore/GS", key: "CASMode", value: Int32(casMode)) }
    }
    var casSharpness: Int {
        didSet { iPSX2Bridge.setINIInt("EmuCore/GS", key: "CASSharpness", value: Int32(casSharpness)) }
    }
    var interlaceMode: Int {
        didSet { iPSX2Bridge.setINIInt("EmuCore/GS", key: "deinterlace_mode", value: Int32(interlaceMode)) }
    }
    var aspectRatio: Int {
        didSet { iPSX2Bridge.setINIInt("EmuCore/GS", key: "AspectRatio", value: Int32(aspectRatio)) }
    }
    var blendingAccuracy: Int {
        didSet { iPSX2Bridge.setINIInt("EmuCore/GS", key: "accurate_blending_unit", value: Int32(blendingAccuracy)) }
    }
    var dithering: Int {
        didSet { iPSX2Bridge.setINIInt("EmuCore/GS", key: "dithering_ps2", value: Int32(dithering)) }
    }

    // ── OSD Overlay ──
    var osdPreset: OsdPreset {
        didSet {
            iPSX2Bridge.setINIInt("iPSX2/UI", key: "OsdPreset", value: Int32(osdPreset.rawValue))
            applyOsdPreset(osdPreset)
        }
    }
    var osdShowFPS: Bool {
        didSet { iPSX2Bridge.setINIBool("EmuCore/GS", key: "OsdShowFPS", value: osdShowFPS) }
    }
    var osdShowSpeed: Bool {
        didSet { iPSX2Bridge.setINIBool("EmuCore/GS", key: "OsdShowSpeed", value: osdShowSpeed) }
    }
    var osdShowCPU: Bool {
        didSet { iPSX2Bridge.setINIBool("EmuCore/GS", key: "OsdShowCPU", value: osdShowCPU) }
    }
    var osdShowResolution: Bool {
        didSet { iPSX2Bridge.setINIBool("EmuCore/GS", key: "OsdShowResolution", value: osdShowResolution) }
    }
    var osdShowFrameTimes: Bool {
        didSet { iPSX2Bridge.setINIBool("EmuCore/GS", key: "OsdShowFrameTimes", value: osdShowFrameTimes) }
    }

    // ── Gamepad / UI ──
    var padOpacity: Float {
        didSet { iPSX2Bridge.setINIFloat("iPSX2/UI", key: "PadOpacity", value: padOpacity) }
    }
    var hapticFeedback: Bool {
        didSet { iPSX2Bridge.setINIBool("iPSX2/UI", key: "HapticFeedback", value: hapticFeedback) }
    }

    // ── Init from INI ──
    private init() {
        // CPU
        eeCoreType = Int(iPSX2Bridge.getINIInt("EmuCore/CPU", key: "CoreType", defaultValue: 0))
        iopRecompiler = iPSX2Bridge.getINIBool("EmuCore/CPU/Recompiler", key: "EnableIOP", defaultValue: true)
        vu0Recompiler = iPSX2Bridge.getINIBool("EmuCore/CPU/Recompiler", key: "EnableVU0", defaultValue: true)
        vu1Recompiler = iPSX2Bridge.getINIBool("EmuCore/CPU/Recompiler", key: "EnableVU1", defaultValue: true)
        fastBoot = iPSX2Bridge.getINIBool("GameISO", key: "FastBoot", defaultValue: false)
        fastmem = iPSX2Bridge.getINIBool("EmuCore/CPU/Recompiler", key: "EnableFastmem", defaultValue: true)
        // Boot
        fastCDVD = iPSX2Bridge.getINIBool("EmuCore/Speedhacks", key: "fastCDVD", defaultValue: false)
        // Advanced Speedhacks
        eeCycleRate = Int(iPSX2Bridge.getINIInt("EmuCore/Speedhacks", key: "EECycleRate", defaultValue: 0))
        vu1Instant = iPSX2Bridge.getINIBool("EmuCore/Speedhacks", key: "vu1Instant", defaultValue: true)
        waitLoop = iPSX2Bridge.getINIBool("EmuCore/Speedhacks", key: "WaitLoop", defaultValue: true)
        intcStat = iPSX2Bridge.getINIBool("EmuCore/Speedhacks", key: "IntcStat", defaultValue: true)
        // Graphics
        renderer = Int(iPSX2Bridge.getINIInt("EmuCore/GS", key: "Renderer", defaultValue: 17))
        upscaleMultiplier = iPSX2Bridge.getINIFloat("EmuCore/GS", key: "upscale_multiplier", defaultValue: 1.0)
        vsyncQueueSize = Int(iPSX2Bridge.getINIInt("EmuCore/GS", key: "VsyncQueueSize", defaultValue: 8))
        textureFiltering = Int(iPSX2Bridge.getINIInt("EmuCore/GS", key: "filter", defaultValue: 2))
        fxaa = iPSX2Bridge.getINIBool("EmuCore/GS", key: "fxaa", defaultValue: false)
        casMode = Int(iPSX2Bridge.getINIInt("EmuCore/GS", key: "CASMode", defaultValue: 0))
        casSharpness = Int(iPSX2Bridge.getINIInt("EmuCore/GS", key: "CASSharpness", defaultValue: 50))
        interlaceMode = Int(iPSX2Bridge.getINIInt("EmuCore/GS", key: "deinterlace_mode", defaultValue: 7))
        aspectRatio = Int(iPSX2Bridge.getINIInt("EmuCore/GS", key: "AspectRatio", defaultValue: 0))
        blendingAccuracy = Int(iPSX2Bridge.getINIInt("EmuCore/GS", key: "accurate_blending_unit", defaultValue: 1))
        dithering = Int(iPSX2Bridge.getINIInt("EmuCore/GS", key: "dithering_ps2", defaultValue: 2))
        // OSD
        osdPreset = OsdPreset(rawValue: Int(iPSX2Bridge.getINIInt("iPSX2/UI", key: "OsdPreset", defaultValue: 0))) ?? .off
        osdShowFPS = iPSX2Bridge.getINIBool("EmuCore/GS", key: "OsdShowFPS", defaultValue: false)
        osdShowSpeed = iPSX2Bridge.getINIBool("EmuCore/GS", key: "OsdShowSpeed", defaultValue: false)
        osdShowCPU = iPSX2Bridge.getINIBool("EmuCore/GS", key: "OsdShowCPU", defaultValue: false)
        osdShowResolution = iPSX2Bridge.getINIBool("EmuCore/GS", key: "OsdShowResolution", defaultValue: false)
        osdShowFrameTimes = iPSX2Bridge.getINIBool("EmuCore/GS", key: "OsdShowFrameTimes", defaultValue: false)
        // UI
        padOpacity = iPSX2Bridge.getINIFloat("iPSX2/UI", key: "PadOpacity", defaultValue: 0.6)
        hapticFeedback = iPSX2Bridge.getINIBool("iPSX2/UI", key: "HapticFeedback", defaultValue: true)
        // [P60] Force MTVU off (known buggy)
        iPSX2Bridge.setINIBool("EmuCore/Speedhacks", key: "vuThread", value: false)
        // Apply OSD preset
        iPSX2Bridge.applyOsdPreset(Int32(osdPreset.rawValue))
    }

    /// Reload ALL settings from INI (call on VM start/stop)
    func reload() {
        eeCoreType = Int(iPSX2Bridge.getINIInt("EmuCore/CPU", key: "CoreType", defaultValue: 0))
        iopRecompiler = iPSX2Bridge.getINIBool("EmuCore/CPU/Recompiler", key: "EnableIOP", defaultValue: true)
        vu0Recompiler = iPSX2Bridge.getINIBool("EmuCore/CPU/Recompiler", key: "EnableVU0", defaultValue: true)
        vu1Recompiler = iPSX2Bridge.getINIBool("EmuCore/CPU/Recompiler", key: "EnableVU1", defaultValue: true)
        fastBoot = iPSX2Bridge.getINIBool("GameISO", key: "FastBoot", defaultValue: false)
        fastmem = iPSX2Bridge.getINIBool("EmuCore/CPU/Recompiler", key: "EnableFastmem", defaultValue: true)
        fastCDVD = iPSX2Bridge.getINIBool("EmuCore/Speedhacks", key: "fastCDVD", defaultValue: false)
        eeCycleRate = Int(iPSX2Bridge.getINIInt("EmuCore/Speedhacks", key: "EECycleRate", defaultValue: 0))
        vu1Instant = iPSX2Bridge.getINIBool("EmuCore/Speedhacks", key: "vu1Instant", defaultValue: true)
        waitLoop = iPSX2Bridge.getINIBool("EmuCore/Speedhacks", key: "WaitLoop", defaultValue: true)
        intcStat = iPSX2Bridge.getINIBool("EmuCore/Speedhacks", key: "IntcStat", defaultValue: true)
        renderer = Int(iPSX2Bridge.getINIInt("EmuCore/GS", key: "Renderer", defaultValue: 17))
        upscaleMultiplier = iPSX2Bridge.getINIFloat("EmuCore/GS", key: "upscale_multiplier", defaultValue: 1.0)
        vsyncQueueSize = Int(iPSX2Bridge.getINIInt("EmuCore/GS", key: "VsyncQueueSize", defaultValue: 8))
        textureFiltering = Int(iPSX2Bridge.getINIInt("EmuCore/GS", key: "filter", defaultValue: 2))
        fxaa = iPSX2Bridge.getINIBool("EmuCore/GS", key: "fxaa", defaultValue: false)
        casMode = Int(iPSX2Bridge.getINIInt("EmuCore/GS", key: "CASMode", defaultValue: 0))
        casSharpness = Int(iPSX2Bridge.getINIInt("EmuCore/GS", key: "CASSharpness", defaultValue: 50))
        interlaceMode = Int(iPSX2Bridge.getINIInt("EmuCore/GS", key: "deinterlace_mode", defaultValue: 7))
        aspectRatio = Int(iPSX2Bridge.getINIInt("EmuCore/GS", key: "AspectRatio", defaultValue: 0))
        blendingAccuracy = Int(iPSX2Bridge.getINIInt("EmuCore/GS", key: "accurate_blending_unit", defaultValue: 1))
        dithering = Int(iPSX2Bridge.getINIInt("EmuCore/GS", key: "dithering_ps2", defaultValue: 2))
        osdPreset = OsdPreset(rawValue: Int(iPSX2Bridge.getINIInt("iPSX2/UI", key: "OsdPreset", defaultValue: 0))) ?? .off
        osdShowFPS = iPSX2Bridge.getINIBool("EmuCore/GS", key: "OsdShowFPS", defaultValue: false)
        osdShowSpeed = iPSX2Bridge.getINIBool("EmuCore/GS", key: "OsdShowSpeed", defaultValue: false)
        osdShowCPU = iPSX2Bridge.getINIBool("EmuCore/GS", key: "OsdShowCPU", defaultValue: false)
        osdShowResolution = iPSX2Bridge.getINIBool("EmuCore/GS", key: "OsdShowResolution", defaultValue: false)
        osdShowFrameTimes = iPSX2Bridge.getINIBool("EmuCore/GS", key: "OsdShowFrameTimes", defaultValue: false)
        padOpacity = iPSX2Bridge.getINIFloat("iPSX2/UI", key: "PadOpacity", defaultValue: 0.6)
        hapticFeedback = iPSX2Bridge.getINIBool("iPSX2/UI", key: "HapticFeedback", defaultValue: true)
    }

    /// Apply OSD preset — writes ALL OSD flags to INI + GSConfig
    private func applyOsdPreset(_ preset: OsdPreset) {
        iPSX2Bridge.applyOsdPreset(Int32(preset.rawValue))
        let isSimple = preset == .simple
        let isDetail = preset == .detail
        let isFull = preset == .full
        osdShowFPS = isSimple || isDetail || isFull
        osdShowSpeed = isDetail || isFull
        osdShowCPU = isSimple || isDetail || isFull
        osdShowResolution = isDetail || isFull
        osdShowFrameTimes = isFull
        iPSX2Bridge.setINIBool("EmuCore/GS", key: "OsdShowVPS", value: false)
        iPSX2Bridge.setINIBool("EmuCore/GS", key: "OsdShowVersion", value: false)
        iPSX2Bridge.setINIBool("EmuCore/GS", key: "OsdShowHardwareInfo", value: false)
        iPSX2Bridge.setINIBool("EmuCore/GS", key: "OsdShowGPU", value: false)
        iPSX2Bridge.setINIBool("EmuCore/GS", key: "OsdShowGSStats", value: false)
    }

    /// Reset emulator settings to PC PCSX2 defaults
    func resetEmulatorDefaults() {
        eeCoreType = 0          // JIT
        iopRecompiler = true
        vu0Recompiler = true    // PC PCSX2 default: microVU JIT
        vu1Recompiler = true    // PC PCSX2 default: microVU JIT
        fastBoot = false
        fastmem = true
        fastCDVD = false
        eeCycleRate = 0
        vu1Instant = true       // PC PCSX2 recommended default
        waitLoop = true         // PC PCSX2 recommended default
        intcStat = true         // PC PCSX2 recommended default
    }

    /// Reset graphics settings to PC PCSX2 defaults
    func resetGraphicsDefaults() {
        renderer = 17           // Metal
        upscaleMultiplier = 1.0 // Native PS2
        vsyncQueueSize = 8
        textureFiltering = 2    // Bilinear (PS2)
        fxaa = false
        casMode = 0             // Disabled
        casSharpness = 50
        interlaceMode = 7       // Adaptive
        aspectRatio = 0         // Auto 4:3/3:2
        blendingAccuracy = 1    // Basic
        dithering = 2           // Scaled
    }
}
