# 🎮 iPSX2 – A PS2 Emulator for iOS with JIT (Ported from PCSX2 / ARMSX2)
This project brings PCSX2 and ARMSX2 to iOS devices.
The porting process was done using fully AI-assisted coding.
## 🛠️ Compatibility
    Confirmed working on iOS 26 and iOS 18 via StikDebug & UTM-Dolphin.js

## 🏆 Recommended Stack

- **Sidestore**: For easy sideloading and app management.
- **Stickdebug**: For enabling JIT (use with UTM-Dolphin JIT script).
- **Livecontainer**: Bypass the 3 app limit.

## 📦 Building an Unsigned IPA

This repository leverages a fully automated headless GitHub Actions pipeline to compile the C++ and Swift bridging components with CMake into a raw unsigned `.ipa`.

To build your own installer package:

1. Fork or push changes to your `main` branch.
2. Navigate to your repository's **Actions** tab.
3. Select the **Build Unsigned iPSX2.ipa** workflow and click **Run workflow**.
4. Once completed, download the `iPSX2-unsigned` artifact ZIP at the bottom of the workflow summary.
5. Extract the `.ipa` file and sideload it to your device using your preferred signing tool (e.g., AltStore, TrollStore, Sideloadly).