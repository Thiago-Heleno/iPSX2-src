// iPSX2Bridge.mm — ObjC bridge implementation
// SPDX-License-Identifier: GPL-3.0+

#import "iPSX2Bridge.h"
#include <SDL3/SDL.h>

extern "C" void iPSX2_SetSDLFullscreen(bool enabled);
#include "Common.h"
#include "CDVD/CDVD.h"
#include "VMManager.h"
#include "SIO/Pad/Pad.h"
#include "SIO/Pad/PadDualshock2.h"
#include "Counters.h"
#include "GS/GSState.h"
#include "pcsx2/INISettingsInterface.h"
#include "common/FileSystem.h"
#include "common/Path.h"

// Access the global settings interface from ios_main.mm
extern INISettingsInterface* g_p44_settings_interface;

static NSDate* s_lastNVMSaveDate = nil;

@implementation iPSX2Bridge

+ (UIView *)gameRenderView {
    extern UIView* g_gameRenderView;
    return g_gameRenderView;
}

+ (void)saveNVRAM {
    cdvdSaveNVRAM();
    s_lastNVMSaveDate = [NSDate date];
    NSLog(@"[iPSX2Bridge] NVM saved at %@", s_lastNVMSaveDate);
}

+ (void)saveMemoryCards {
    // FileMcd_EmuClose triggers save on all open memory cards
    // For now, MC saves happen automatically via the existing PCSX2 MC system
    NSLog(@"[iPSX2Bridge] Memory card save requested");
}

+ (void)saveAllState {
    [self saveNVRAM];
    [self saveMemoryCards];
}

+ (BOOL)isRunning {
    return VMManager::GetState() == VMState::Running;
}

+ (nullable NSDate *)lastNVMSaveDate {
    return s_lastNVMSaveDate;
}

+ (nullable NSString *)nvmFilePath {
    // NVM path is BIOS path with .nvm extension
    // We can't easily access BiosPath from here, so return nil for now
    return nil;
}

+ (BOOL)nvmFileExists {
    NSString* path = [self nvmFilePath];
    if (!path) return NO;
    return [[NSFileManager defaultManager] fileExistsAtPath:path];
}

+ (void)setPadButton:(iPSX2PadButton)button pressed:(BOOL)pressed {
    auto* pad = static_cast<PadDualshock2*>(Pad::GetPad(0, 0));
    if (!pad) return;

    static const u32 buttonMap[] = {
        PadDualshock2::Inputs::PAD_UP,       // Up
        PadDualshock2::Inputs::PAD_DOWN,     // Down
        PadDualshock2::Inputs::PAD_LEFT,     // Left
        PadDualshock2::Inputs::PAD_RIGHT,    // Right
        PadDualshock2::Inputs::PAD_CROSS,    // Cross
        PadDualshock2::Inputs::PAD_CIRCLE,   // Circle
        PadDualshock2::Inputs::PAD_SQUARE,   // Square
        PadDualshock2::Inputs::PAD_TRIANGLE, // Triangle
        PadDualshock2::Inputs::PAD_L1,       // L1
        PadDualshock2::Inputs::PAD_R1,       // R1
        PadDualshock2::Inputs::PAD_L2,       // L2
        PadDualshock2::Inputs::PAD_R2,       // R2
        PadDualshock2::Inputs::PAD_START,    // Start
        PadDualshock2::Inputs::PAD_SELECT,   // Select
        PadDualshock2::Inputs::PAD_L3,       // L3
        PadDualshock2::Inputs::PAD_R3,       // R3
    };

    if ((int)button < (int)(sizeof(buttonMap)/sizeof(buttonMap[0]))) {
        u32 idx = buttonMap[(int)button];
        pad->Set(idx, pressed ? 1.0f : 0.0f);
        // Update touch state so PumpMessagesOnCPUThread doesn't override
        extern bool g_touchPadState[64];
        if (idx < 64) g_touchPadState[idx] = pressed;
    }
}

+ (void)setLeftStickX:(float)x Y:(float)y {
    auto* pad = static_cast<PadDualshock2*>(Pad::GetPad(0, 0));
    if (!pad) return;
    // Convert axis (-1..+1) to individual direction values (0..1)
    pad->Set(PadDualshock2::Inputs::PAD_L_RIGHT, x > 0 ? x : 0.0f);
    pad->Set(PadDualshock2::Inputs::PAD_L_LEFT, x < 0 ? -x : 0.0f);
    pad->Set(PadDualshock2::Inputs::PAD_L_DOWN, y > 0 ? y : 0.0f);
    pad->Set(PadDualshock2::Inputs::PAD_L_UP, y < 0 ? -y : 0.0f);
}

+ (void)setRightStickX:(float)x Y:(float)y {
    auto* pad = static_cast<PadDualshock2*>(Pad::GetPad(0, 0));
    if (!pad) return;
    pad->Set(PadDualshock2::Inputs::PAD_R_RIGHT, x > 0 ? x : 0.0f);
    pad->Set(PadDualshock2::Inputs::PAD_R_LEFT, x < 0 ? -x : 0.0f);
    pad->Set(PadDualshock2::Inputs::PAD_R_DOWN, y > 0 ? y : 0.0f);
    pad->Set(PadDualshock2::Inputs::PAD_R_UP, y < 0 ? -y : 0.0f);
}

+ (nonnull NSString *)biosName {
    return @"PS2";
}

+ (void)requestVMStop {
    extern std::atomic<bool> s_requestVMStop;
    s_requestVMStop.store(true);
    [[NSNotificationCenter defaultCenter] postNotificationName:@"iPSX2VMDidShutdown" object:nil];
}

+ (void)setFullScreen:(BOOL)enabled {
    iPSX2_SetSDLFullscreen(enabled ? true : false);
}

+ (nonnull NSString *)buildVersion {
    NSString *ver = [[NSBundle mainBundle] objectForInfoDictionaryKey:@"CFBundleShortVersionString"] ?: @"?";
    return [NSString stringWithFormat:@"iPSX2 v%@", ver];
}

+ (nullable NSString *)currentISOPath {
    NSString *docsPath = [NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES) firstObject];
    NSString *iniPath = [docsPath stringByAppendingPathComponent:@"PCSX2-iOS.ini"];
    // Read BootISO from INI
    FILE *f = fopen(iniPath.UTF8String, "r");
    if (!f) return nil;
    char line[512];
    bool inSection = false;
    NSString *result = nil;
    while (fgets(line, sizeof(line), f)) {
        if (strstr(line, "[GameISO]")) { inSection = true; continue; }
        if (line[0] == '[') { inSection = false; continue; }
        if (inSection && strstr(line, "BootISO")) {
            char *eq = strchr(line, '=');
            if (eq) {
                eq++;
                while (*eq == ' ') eq++;
                // Remove trailing newline
                char *nl = strchr(eq, '\n'); if (nl) *nl = 0;
                char *cr = strchr(eq, '\r'); if (cr) *cr = 0;
                if (strlen(eq) > 0) result = [NSString stringWithUTF8String:eq];
            }
        }
    }
    fclose(f);
    return result;
}

+ (nonnull NSString *)isoDirectory {
    NSString *docsPath = [NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES) firstObject];
    NSString *isoDir = [docsPath stringByAppendingPathComponent:@"iso"];
    [[NSFileManager defaultManager] createDirectoryAtPath:isoDir withIntermediateDirectories:YES attributes:nil error:nil];
    return isoDir;
}

+ (nonnull NSString *)documentsDirectory {
    return [NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES) firstObject];
}

+ (nonnull NSArray<NSString *> *)availableISOs {
    NSFileManager *fm = [NSFileManager defaultManager];
    NSMutableSet *seen = [NSMutableSet set];
    NSMutableArray *isos = [NSMutableArray array];

    // Helper block: scan a directory for ISO files
    void (^scanDir)(NSString *) = ^(NSString *dir) {
        NSArray *files = [fm contentsOfDirectoryAtPath:dir error:nil];
        for (NSString *file in files) {
            if ([seen containsObject:file]) continue;
            NSString *ext = file.pathExtension.lowercaseString;
            if ([ext isEqualToString:@"iso"] || [ext isEqualToString:@"img"] || [ext isEqualToString:@"chd"] || [ext isEqualToString:@"elf"]) {
                [isos addObject:file];
                [seen addObject:file];
            } else if ([ext isEqualToString:@"bin"]) {
// .bin > 50MB treated as game image
                NSString *fullPath = [dir stringByAppendingPathComponent:file];
                NSDictionary *attrs = [fm attributesOfItemAtPath:fullPath error:nil];
                if ([attrs fileSize] > 50 * 1024 * 1024) {
                    [isos addObject:file];
                    [seen addObject:file];
                }
            }
        }
    };

    // Scan Documents/iso/ first, then Documents/ root
    scanDir([self isoDirectory]);
    NSString *docsPath = [NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES) firstObject];
    scanDir(docsPath);

    return isos;
}

// Toggle overlay visibility via position (None vs TopRight).
// Individual OSD flags are controlled by preset in SettingsStore, not here.
+ (void)setPerformanceOverlayVisible:(BOOL)visible {
    if (visible) {
        GSConfig.OsdPerformancePos = EmuConfig.GS.OsdPerformancePos;
        // If user had None in config, default to TopRight
        if (GSConfig.OsdPerformancePos == OsdOverlayPos::None)
            GSConfig.OsdPerformancePos = OsdOverlayPos::TopRight;
    } else {
        GSConfig.OsdPerformancePos = OsdOverlayPos::None;
    }
}

+ (BOOL)isPerformanceOverlayVisible {
    return GSConfig.OsdPerformancePos != OsdOverlayPos::None;
}

// Apply OSD preset — sets ALL GSConfig flags to match the preset
+ (void)applyOsdPreset:(int)preset {
    // Clear everything first
    GSConfig.OsdShowFPS = false;
    GSConfig.OsdShowSpeed = false;
    GSConfig.OsdShowVPS = false;
    GSConfig.OsdShowCPU = false;
    GSConfig.OsdShowGPU = false;
    GSConfig.OsdShowResolution = false;
    GSConfig.OsdShowGSStats = false;
    GSConfig.OsdShowFrameTimes = false;
    GSConfig.OsdShowVersion = false;
    GSConfig.OsdShowHardwareInfo = false;

    switch (preset) {
    case 1: // simple: FPS + CPU usage
        GSConfig.OsdShowFPS = true;
        GSConfig.OsdShowCPU = true;
        break;
    case 2: // detail: simple + speed + resolution
        GSConfig.OsdShowFPS = true;
        GSConfig.OsdShowSpeed = true;
        GSConfig.OsdShowCPU = true;
        GSConfig.OsdShowResolution = true;
        break;
    case 3: // full: detail + frame times
        GSConfig.OsdShowFPS = true;
        GSConfig.OsdShowSpeed = true;
        GSConfig.OsdShowCPU = true;
        GSConfig.OsdShowResolution = true;
        GSConfig.OsdShowFrameTimes = true;
        break;
    default: // 0 = off
        break;
    }
}

// ============================================================
// ISO / BIOS / Settings management
// ============================================================

#pragma mark - ISO boot

+ (void)bootISO:(nonnull NSString *)isoName {
    if (!g_p44_settings_interface) return;
    g_p44_settings_interface->SetStringValue("GameISO", "BootISO", isoName.UTF8String);
    g_p44_settings_interface->Save();
    NSLog(@"bootISO: set BootISO=%@", isoName);
}

#pragma mark - BIOS management

+ (nonnull NSString *)biosDirectory {
    NSString *docsPath = [NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES) firstObject];
    NSString *biosDir = [docsPath stringByAppendingPathComponent:@"bios"];
    [[NSFileManager defaultManager] createDirectoryAtPath:biosDir withIntermediateDirectories:YES attributes:nil error:nil];
    return biosDir;
}

+ (nonnull NSArray<NSString *> *)availableBIOSes {
    NSFileManager *fm = [NSFileManager defaultManager];
    NSMutableSet *seen = [NSMutableSet set];
    NSMutableArray *bioses = [NSMutableArray array];

    // Helper block: scan directory for BIOS files (>= 1MB .bin/.rom)
    void (^scanDir)(NSString *) = ^(NSString *dir) {
        NSArray *files = [fm contentsOfDirectoryAtPath:dir error:nil];
        for (NSString *file in files) {
            if ([seen containsObject:file]) continue;
            NSString *ext = file.pathExtension.lowercaseString;
            if ([ext isEqualToString:@"bin"] || [ext isEqualToString:@"rom"]) {
                NSString *fullPath = [dir stringByAppendingPathComponent:file];
                NSDictionary *attrs = [fm attributesOfItemAtPath:fullPath error:nil];
// BIOS files are >= 1MB and <= 50MB
                unsigned long long sz = [attrs fileSize];
                if (sz >= 1024 * 1024 && sz <= 50 * 1024 * 1024) {
                    [bioses addObject:file];
                    [seen addObject:file];
                }
            }
        }
    };

    scanDir([self biosDirectory]);
    return bioses;
}

+ (nonnull NSString *)defaultBIOSName {
    if (!g_p44_settings_interface) return @"";
    std::string val = g_p44_settings_interface->GetStringValue("Filenames", "BIOS", "");
    return [NSString stringWithUTF8String:val.c_str()];
}

+ (void)setDefaultBIOS:(nonnull NSString *)biosName {
    if (!g_p44_settings_interface) return;
    g_p44_settings_interface->SetStringValue("Filenames", "BIOS", biosName.UTF8String);
    g_p44_settings_interface->Save();
    EmuConfig.BaseFilenames.Bios = biosName.UTF8String;
    NSLog(@"setDefaultBIOS: %@", biosName);
}

#pragma mark - Favorites

+ (BOOL)isFavorite:(nonnull NSString *)isoName {
    if (!g_p44_settings_interface) return NO;
    return g_p44_settings_interface->GetBoolValue("Favorites", isoName.UTF8String, false);
}

+ (void)setFavorite:(nonnull NSString *)isoName favorite:(BOOL)favorite {
    if (!g_p44_settings_interface) return;
    g_p44_settings_interface->SetBoolValue("Favorites", isoName.UTF8String, favorite);
    g_p44_settings_interface->Save();
}

#pragma mark - INI generic getter/setter

+ (int)getINIInt:(nonnull NSString *)section key:(nonnull NSString *)key defaultValue:(int)def {
    if (!g_p44_settings_interface) return def;
    return g_p44_settings_interface->GetIntValue(section.UTF8String, key.UTF8String, def);
}

+ (BOOL)getINIBool:(nonnull NSString *)section key:(nonnull NSString *)key defaultValue:(BOOL)def {
    if (!g_p44_settings_interface) return def;
    return g_p44_settings_interface->GetBoolValue(section.UTF8String, key.UTF8String, def);
}

+ (float)getINIFloat:(nonnull NSString *)section key:(nonnull NSString *)key defaultValue:(float)def {
    if (!g_p44_settings_interface) return def;
    return g_p44_settings_interface->GetFloatValue(section.UTF8String, key.UTF8String, def);
}

+ (nonnull NSString *)getINIString:(nonnull NSString *)section key:(nonnull NSString *)key defaultValue:(nonnull NSString *)def {
    if (!g_p44_settings_interface) return def;
    std::string val = g_p44_settings_interface->GetStringValue(section.UTF8String, key.UTF8String, def.UTF8String);
    return [NSString stringWithUTF8String:val.c_str()];
}

+ (void)setINIInt:(nonnull NSString *)section key:(nonnull NSString *)key value:(int)value {
    if (!g_p44_settings_interface) return;
    g_p44_settings_interface->SetIntValue(section.UTF8String, key.UTF8String, value);
    g_p44_settings_interface->Save();
}

+ (void)setINIBool:(nonnull NSString *)section key:(nonnull NSString *)key value:(BOOL)value {
    if (!g_p44_settings_interface) return;
    g_p44_settings_interface->SetBoolValue(section.UTF8String, key.UTF8String, value);
    g_p44_settings_interface->Save();
}

+ (void)setINIFloat:(nonnull NSString *)section key:(nonnull NSString *)key value:(float)value {
    if (!g_p44_settings_interface) return;
    g_p44_settings_interface->SetFloatValue(section.UTF8String, key.UTF8String, value);
    g_p44_settings_interface->Save();
}

+ (void)setINIString:(nonnull NSString *)section key:(nonnull NSString *)key value:(nonnull NSString *)value {
    if (!g_p44_settings_interface) return;
    g_p44_settings_interface->SetStringValue(section.UTF8String, key.UTF8String, value.UTF8String);
    g_p44_settings_interface->Save();
}

#pragma mark - VM lifecycle

+ (BOOL)isVMRunning {
    VMState st = VMManager::GetState();
    return st == VMState::Running || st == VMState::Paused;
}

+ (BOOL)hasBIOS {
    if (EmuConfig.BaseFilenames.Bios.empty()) return NO;
    std::string fullPath = Path::Combine(EmuFolders::Bios, EmuConfig.BaseFilenames.Bios);
    return FileSystem::FileExists(fullPath.c_str());
}

+ (void)requestVMBoot {
    // Post notification that ios_main.mm will observe to start VM
    [[NSNotificationCenter defaultCenter] postNotificationName:@"iPSX2RequestVMBoot" object:nil];
}

+ (void)requestVMShutdown {
    [[NSNotificationCenter defaultCenter] postNotificationName:@"iPSX2RequestVMShutdown" object:nil];
}

// Gamepad button mapping
extern std::atomic<bool> s_captureMode;
extern std::atomic<int>  s_capturedButton;
extern int s_buttonMap[16];

+ (void)startButtonCapture {
    s_capturedButton.store(-1);
    s_captureMode.store(true);
}

+ (void)stopButtonCapture {
    s_captureMode.store(false);
}

// Poll SDL gamepad from main thread (for settings screen when VM is not running)
+ (void)pollGamepadForCapture {
    if (!s_captureMode.load()) return;
    SDL_UpdateGamepads();
    // Keep gamepad open across polls to avoid open/close overhead
    static SDL_Gamepad* s_settingsGP = nullptr;
    if (!s_settingsGP) {
        int count = 0;
        SDL_JoystickID* ids = SDL_GetGamepads(&count);
        if (ids && count > 0) s_settingsGP = SDL_OpenGamepad(ids[0]);
        SDL_free(ids);
    }
    if (!s_settingsGP) return;
    if (!SDL_GamepadConnected(s_settingsGP)) {
        SDL_CloseGamepad(s_settingsGP);
        s_settingsGP = nullptr;
        return;
    }
    // SDL_PumpEvents required for GCController input to be processed
    SDL_PumpEvents();
    SDL_UpdateGamepads();
    for (int b = 0; b < SDL_GAMEPAD_BUTTON_COUNT; b++) {
        if (SDL_GetGamepadButton(s_settingsGP, (SDL_GamepadButton)b)) {
            s_capturedButton.store(b);
            break;
        }
    }
}

+ (int)capturedButton {
    return s_capturedButton.exchange(-1);
}

+ (void)setButtonMapping:(int)ps2Index toSDLButton:(int)sdlButton {
    if (ps2Index >= 0 && ps2Index < 16) {
        s_buttonMap[ps2Index] = sdlButton;
        // Persist to INI
        if (g_p44_settings_interface) {
            char key[32];
            snprintf(key, sizeof(key), "Button%d", ps2Index);
            g_p44_settings_interface->SetIntValue("iPSX2/GamepadMapping", key, sdlButton);
            g_p44_settings_interface->Save();
        }
    }
}

+ (int)getButtonMapping:(int)ps2Index {
    if (ps2Index >= 0 && ps2Index < 16) return s_buttonMap[ps2Index];
    return -1;
}

+ (void)resetButtonMappings {
    static const int defMap[16] = {
        SDL_GAMEPAD_BUTTON_DPAD_UP, SDL_GAMEPAD_BUTTON_DPAD_DOWN,
        SDL_GAMEPAD_BUTTON_DPAD_LEFT, SDL_GAMEPAD_BUTTON_DPAD_RIGHT,
        SDL_GAMEPAD_BUTTON_SOUTH, SDL_GAMEPAD_BUTTON_EAST,
        SDL_GAMEPAD_BUTTON_WEST, SDL_GAMEPAD_BUTTON_NORTH,
        SDL_GAMEPAD_BUTTON_LEFT_SHOULDER, SDL_GAMEPAD_BUTTON_RIGHT_SHOULDER,
        -1, -1,
        SDL_GAMEPAD_BUTTON_START, SDL_GAMEPAD_BUTTON_BACK,
        SDL_GAMEPAD_BUTTON_LEFT_STICK, SDL_GAMEPAD_BUTTON_RIGHT_STICK,
    };
    for (int i = 0; i < 16; i++) s_buttonMap[i] = defMap[i];
    if (g_p44_settings_interface) {
        g_p44_settings_interface->RemoveSection("iPSX2/GamepadMapping");
        g_p44_settings_interface->Save();
    }
}

@end
