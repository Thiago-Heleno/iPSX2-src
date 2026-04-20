# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What This Is

iPSX2 is a PS2 emulator for iOS, porting PCSX2/ARMSX2 to iPhone/iPad. Target: iOS 18+, arm64 only. Confirmed working on iOS 26 and iOS 18 via StikDebug & UTM-Dolphin.js.

## Build System

CMake generates an Xcode project; all actual compilation happens in Xcode/xcodebuild.

**Generate Xcode project (simulator):**
```sh
cmake -S cpp -B build-sim -G Xcode \
  -DCMAKE_SYSTEM_NAME=iOS \
  -DiPSX2_REAL_DEVICE=OFF
```

**Generate Xcode project (real device):**
```sh
cmake -S cpp -B build-device -G Xcode \
  -DCMAKE_SYSTEM_NAME=iOS \
  -DiPSX2_REAL_DEVICE=ON
```

**Build from command line:**
```sh
xcodebuild -project build-sim/iPSX2.xcodeproj \
  -scheme iPSX2 -sdk iphonesimulator \
  -configuration Debug build
```

Real-device IPAs are re-signed with Sideloadly before sideloading — code signing is intentionally disabled in CMake (`CODE_SIGNING_REQUIRED=NO`).

No in-tree builds: CMake will error if `build/` is inside the source tree.

## Architecture

```
iPSX2-src-main/
├── cpp/              # C++/ObjC backend
│   ├── CMakeLists.txt       # Top-level build; adds common/ and pcsx2/
│   ├── common/              # Platform utilities (FileSystem, Threading, etc.)
│   ├── pcsx2/               # Core emulator (EE, IOP, GS, VU, SPU2, SIO…)
│   │   ├── arm64/           # arm64 JIT helpers (VIXL-based, partial)
│   │   ├── GS/Renderers/Metal/  # Metal renderer + .metal shaders
│   │   └── VMManager.cpp    # Central VM lifecycle (boot/pause/shutdown)
│   ├── ios_main.mm          # UIKit app entry; starts SDL3, spins emulator thread
│   ├── iPSX2Bridge.h/.mm    # ObjC++ class exposing emulator API to Swift
│   └── iPSX2-Bridging-Header.h  # Exposes ObjC types to Swift
└── swift/            # SwiftUI frontend
    ├── Views/               # SwiftUI screens
    │   ├── RootView.swift       # Top-level router (menu ↔ playing)
    │   ├── GameListView.swift   # ISO picker
    │   ├── GameScreenView.swift # In-game HUD wrapper
    │   ├── MetalGameView.swift  # UIViewRepresentable for Metal render surface
    │   ├── EmulatorView.swift   # Game screen + virtual pad
    │   ├── VirtualControllerView.swift
    │   └── Settings/            # Settings screens
    └── Models/
        ├── AppState.swift       # Screen state machine (menu/playing), boot actions
        ├── EmulatorBridge.swift # @Observable wrapper around iPSX2Bridge ObjC calls
        ├── SettingsStore.swift  # INI-backed settings via iPSX2Bridge getINI/setINI
        ├── PadLayoutStore.swift # Virtual pad button layout persistence
        ├── FileImportHandler.swift
        └── SwiftUIHost.swift    # UIHostingController bridging SwiftUI into UIKit
```

## Key Patterns

**C++ ↔ Swift boundary:** All calls cross via `iPSX2Bridge` (ObjC++ class). Swift calls `iPSX2Bridge.*()` directly through the bridging header. Never add direct C++ headers to Swift files.

**VM lifecycle notifications:** C++ posts `NSNotification` names (`iPSX2VMDidShutdown`, `iPSX2AutoBootDidStart`, `iPSX2ReturnToMenu`, `iPSX2EnterGameScreen`) that Swift observes. State changes flow one-way: C++ → notification → `AppState`.

**Settings:** All emulator settings read/written through `iPSX2Bridge getINI/setINI` which proxy to PCSX2's INI layer. Swift `SettingsStore` is the typed wrapper.

**Renderer:** Metal only. Shaders live in `cpp/pcsx2/GS/Renderers/Metal/*.metal` and are compiled into `default.metallib` by Xcode. The Metal layer is surfaced to SwiftUI via `MetalGameView` (UIViewRepresentable wrapping the view from `iPSX2Bridge.gameRenderView()`).

**JIT entitlement:** `Entitlements.plist` includes `com.apple.security.cs.allow-jit` — required for the emulator's JIT recompiler. Re-signing must preserve this.

**Swift version:** Swift 6.0, strict concurrency. Shared singletons (`AppState.shared`, `EmulatorBridge.shared`) are marked `@unchecked Sendable` to cross the actor boundary since they call ObjC synchronously.

## 3rd-Party Dependencies (vendored under `cpp/3rdparty/`)

SDL3, fmt, vixl (arm64 code gen), imgui, rapidyaml, libchdr, libzip, cubeb, rcheevos, freetype, soundtouch, lz4, lzma, zstd.
