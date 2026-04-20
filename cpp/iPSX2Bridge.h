// iPSX2Bridge.h — ObjC bridge for C++ emulator control
// SPDX-License-Identifier: GPL-3.0+

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

typedef NS_ENUM(NSInteger, iPSX2EmulatorState) {
    iPSX2EmulatorStateStopped = 0,
    iPSX2EmulatorStateRunning,
    iPSX2EmulatorStatePaused,
    iPSX2EmulatorStateSaving,
    iPSX2EmulatorStateSuspended,
};

typedef NS_ENUM(NSInteger, iPSX2CoreType) {
    iPSX2CoreTypeJIT = 0,
    iPSX2CoreTypeInterpreter = 1,
};

typedef NS_ENUM(NSInteger, iPSX2PadButton) {
    iPSX2PadButtonUp = 0,
    iPSX2PadButtonDown,
    iPSX2PadButtonLeft,
    iPSX2PadButtonRight,
    iPSX2PadButtonCross,
    iPSX2PadButtonCircle,
    iPSX2PadButtonSquare,
    iPSX2PadButtonTriangle,
    iPSX2PadButtonL1,
    iPSX2PadButtonR1,
    iPSX2PadButtonL2,
    iPSX2PadButtonR2,
    iPSX2PadButtonStart,
    iPSX2PadButtonSelect,
    iPSX2PadButtonL3,
    iPSX2PadButtonR3,
};

@interface iPSX2Bridge : NSObject

// Game render view (for UIViewRepresentable)
+ (nonnull UIView *)gameRenderView;

// Lifecycle
+ (void)saveNVRAM;
+ (void)saveMemoryCards;
+ (void)saveAllState;  // NVM + MC
+ (BOOL)isRunning;

// NVM status
+ (nullable NSDate *)lastNVMSaveDate;
+ (nullable NSString *)nvmFilePath;
+ (BOOL)nvmFileExists;

// Pad input
+ (void)setPadButton:(iPSX2PadButton)button pressed:(BOOL)pressed;
+ (void)setLeftStickX:(float)x Y:(float)y;
+ (void)setRightStickX:(float)x Y:(float)y;

// VM control
+ (void)requestVMStop;
+ (void)setFullScreen:(BOOL)enabled;

// Info
+ (nonnull NSString *)biosName;
+ (nonnull NSString *)buildVersion;

// OSD overlay
+ (void)setPerformanceOverlayVisible:(BOOL)visible;
+ (BOOL)isPerformanceOverlayVisible;
+ (void)applyOsdPreset:(int)preset;  // 0=off, 1=simple, 2=detail, 3=full

// ISO management
+ (nullable NSString *)currentISOPath;
+ (nonnull NSString *)isoDirectory;
+ (nonnull NSString *)documentsDirectory;
+ (nonnull NSArray<NSString *> *)availableISOs;

// [P44] ISO boot
+ (void)bootISO:(nonnull NSString *)isoName;

// [P44] BIOS management
+ (nonnull NSString *)biosDirectory;
+ (nonnull NSArray<NSString *> *)availableBIOSes;
+ (nonnull NSString *)defaultBIOSName;
+ (void)setDefaultBIOS:(nonnull NSString *)biosName;

// [P44] Favorites
+ (BOOL)isFavorite:(nonnull NSString *)isoName;
+ (void)setFavorite:(nonnull NSString *)isoName favorite:(BOOL)favorite;

// [P44] INI generic getter/setter
+ (int)getINIInt:(nonnull NSString *)section key:(nonnull NSString *)key defaultValue:(int)def;
+ (BOOL)getINIBool:(nonnull NSString *)section key:(nonnull NSString *)key defaultValue:(BOOL)def;
+ (float)getINIFloat:(nonnull NSString *)section key:(nonnull NSString *)key defaultValue:(float)def;
+ (nonnull NSString *)getINIString:(nonnull NSString *)section key:(nonnull NSString *)key defaultValue:(nonnull NSString *)def;
+ (void)setINIInt:(nonnull NSString *)section key:(nonnull NSString *)key value:(int)value;
+ (void)setINIBool:(nonnull NSString *)section key:(nonnull NSString *)key value:(BOOL)value;
+ (void)setINIFloat:(nonnull NSString *)section key:(nonnull NSString *)key value:(float)value;
+ (void)setINIString:(nonnull NSString *)section key:(nonnull NSString *)key value:(nonnull NSString *)value;

// [P44] VM lifecycle for menu flow
+ (BOOL)isVMRunning;
+ (BOOL)hasBIOS;
+ (void)requestVMBoot;
+ (void)requestVMShutdown;

// [P53] Gamepad button mapping
+ (void)startButtonCapture;
+ (void)stopButtonCapture;
+ (void)pollGamepadForCapture;  // call from main thread when VM is not running
+ (int)capturedButton;  // returns SDL_GamepadButton or -1
+ (void)setButtonMapping:(int)ps2Index toSDLButton:(int)sdlButton;
+ (int)getButtonMapping:(int)ps2Index;
+ (void)resetButtonMappings;

@end
