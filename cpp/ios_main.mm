
// Set SDL_MAIN_HANDLED to prevent SDL from redefining main()
#define SDL_MAIN_HANDLED

#include <SDL3/SDL.h>
#include <SDL3/SDL_main.h>
#include <SDL3/SDL_metal.h>

// SwiftUI integration — import auto-generated Swift header
#if __has_include("iPSX2-Swift.h")
#import "iPSX2-Swift.h"
#define iPSX2_HAS_SWIFTUI 1
#else
#define iPSX2_HAS_SWIFTUI 0
#endif
#import <SwiftUI/SwiftUI.h>

// ... other includes ...
#include <unistd.h>
#include <cstdlib>
#include <string>
#include <iostream>

#include "common/ProgressCallback.h"
#include "pcsx2/Input/InputManager.h"
#include "pcsx2/SIO/Pad/Pad.h"
#include "pcsx2/SIO/Pad/PadDualshock2.h"
#include "pcsx2/Counters.h" // g_FrameCount
#include "pcsx2/Achievements.h"
#include "pcsx2/CDVD/CDVDdiscReader.h"
#include "common/Console.h"
#include "common/FileSystem.h"
#include "common/Path.h"
#include "pcsx2/VMManager.h"
#include "pcsx2/ImGui/ImGuiManager.h"
#include "pcsx2/Config.h"
#include "pcsx2/CDVD/CDVD.h"
#include "pcsx2/CDVD/CDVDcommon.h"

#include "pcsx2/DEV9/pcap_io.h"
#include "pcsx2/DEV9/net.h"

#include "pcsx2/Host.h"
#include "pcsx2/Host/AudioStreamTypes.h"

#include "common/WindowInfo.h"
#include "common/HTTPDownloader.h"
#include <thread>
#include <mutex>
#include <condition_variable>
#include <atomic>
#include <optional>
#include <sys/stat.h> // For mkdir

struct rc_client_event_t;
struct rc_client_t;

// iOS specific headers
#import <UIKit/UIKit.h>
#include <mach-o/dyld.h>
#include "common/Darwin/DarwinMisc.h" // For iPSX2_CRASH_DIAG
#include "3rdparty/simpleini/include/SimpleIni.h"
#include "pcsx2/INISettingsInterface.h"

// Global Log View
static UITextView* g_logView = nil;

// Game render view — frame-based layout, portrait=50% / landscape=full safe area
// Game render view with CAMetalLayer as backing layer (like MTKView)
// Game render view — backing layer (CAMetalLayer), manual landscape toggle
#include "pcsx2/MTGS.h"
extern void GSResizeDisplayWindow(int width, int height, float scale);

@interface iPSX2GameView : UIView
@end
@implementation iPSX2GameView
+ (Class)layerClass { return [CAMetalLayer class]; }
- (void)layoutSubviews {
    [super layoutSubviews];
    // Frame is set by SwiftUI — only update Metal drawable size
    CGFloat scale = self.contentScaleFactor;
    CAMetalLayer *mtl = (CAMetalLayer *)self.layer;
    mtl.drawableSize = CGSizeMake(self.bounds.size.width * scale,
                                   self.bounds.size.height * scale);
    int w = (int)(self.bounds.size.width * scale);
    int h = (int)(self.bounds.size.height * scale);
    float s = (float)scale;
    MTGS::RunOnGSThread([w, h, s]() {
        GSResizeDisplayWindow(w, h, s);
    });
}
@end
iPSX2GameView* g_gameRenderView = nil;  // non-static: accessed from iPSX2Bridge.mm

// Touch pad state
std::atomic<bool> g_touchPadState[64] = {};

// Persistent VM thread lifecycle
static std::atomic<bool> s_vmThreadActive{false};   // true while VM is executing
static std::atomic<bool> s_requestVMStop{false};    // signal VM to stop from UI
static std::atomic<bool> s_requestVMBoot{false};    // signal VM thread to boot
static std::mutex s_vmMutex;
static std::condition_variable s_vmCV;
static std::atomic<bool> s_vmThreadCreated{false};
static std::atomic<bool> s_requestAppExit{false};
std::mutex g_settingsMutex;

extern "C" bool VMController_IsStopRequested() {
    return s_requestVMStop.load();
}

@interface VMController : NSObject
+ (instancetype)sharedInstance;
- (BOOL)isVMRunning;
- (BOOL)isVMThreadActive;
- (void)requestVMBoot;
- (void)requestVMShutdown;
- (void)startVMThread;
@end

@implementation VMController

+ (instancetype)sharedInstance {
    static VMController *shared = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        shared = [[self alloc] init];
    });
    return shared;
}

- (BOOL)isVMRunning {
    return s_vmThreadActive.load();
}

- (BOOL)isVMThreadActive {
    return s_vmThreadActive.load();
}

- (void)requestVMBoot {
    [[NSNotificationCenter defaultCenter] postNotificationName:@"iPSX2RequestVMBoot" object:nil];
}

- (void)requestVMShutdown {
    s_requestVMStop.store(true);
    [[NSNotificationCenter defaultCenter] postNotificationName:@"iPSX2RequestVMShutdown" object:nil];
}

- (void)startVMThread {
    std::unique_lock<std::mutex> lk(s_vmMutex);

    if (s_vmThreadActive.load()) {
        Console.WriteLn("[VM] startVMThread: VM already active, ignoring");
        return;
    }

    s_requestVMBoot.store(true);
    s_requestVMStop.store(false);

    if (s_vmThreadCreated.exchange(true)) {
        // Thread already exists — wake it
        Console.WriteLn("[VM] startVMThread: signaling existing VM thread");
        lk.unlock();
        s_vmCV.notify_one();
        return;
    }

    // First call: create thread while still holding the lock so the new
    // thread blocks on s_vmCV.wait() before we release.
    Console.WriteLn("[VM] Creating persistent VM thread...");

    std::thread vmThread([]() {
        // === ONE-TIME INIT (runs once per app lifetime) ===
        Console.WriteLn("[VM] VM Thread: CPUThreadInitialize (once)...");
        if (!VMManager::Internal::CPUThreadInitialize()) {
            Console.Error("VM Thread: CPUThreadInitialize failed.");
            s_vmThreadCreated.store(false);
            return;
        }

        // Set ImGui font path (once)
        std::string fontPath = Path::Combine(EmuFolders::Resources, "fonts/Roboto-Regular.ttf");
        ImGuiManager::SetFontPathAndRange(std::move(fontPath), {});

        // === PERSISTENT BOOT LOOP ===
        bool auto_boot_first = (getenv("iPSX2_AUTO_BOOT") && atoi(getenv("iPSX2_AUTO_BOOT")) == 1)
                            || (getenv("iPSX2_BOOT_ELF") != nullptr);
        while (true) {
            if (s_requestAppExit.load()) break;
            // Wait for boot signal (or auto-boot on first iteration)
            {
                std::unique_lock<std::mutex> lk(s_vmMutex);
                if (auto_boot_first) {
                    Console.WriteLn("[AutoBoot] @@AUTO_BOOT@@ skipping UI wait, auto-boot enabled");
                    auto_boot_first = false;
                } else {
                    Console.WriteLn("[VM] VM Thread: waiting for boot request...");
                    s_vmCV.wait(lk, [] { return s_requestVMBoot.load(); });
                }
                s_requestVMBoot.store(false);
            }

            Console.WriteLn("[VM] VM Thread: boot signal received, preparing boot params...");
            s_vmThreadActive.store(true);

            // --- Build boot parameters from INI ---
            VMBootParameters boot_params;
            boot_params.fast_boot = false;
            {
                std::string isoDir = EmuFolders::DataRoot + "/iso";
                std::string defaultISO = "";
                // Access global settings interface for configuration
                extern INISettingsInterface* g_p44_settings_interface;
                extern std::mutex g_settingsMutex;
                std::string isoFilename = "";
                bool fastBoot = false;
                {
                    std::lock_guard<std::mutex> lk(g_settingsMutex);
                    if (g_p44_settings_interface) {
                        isoFilename = g_p44_settings_interface->GetStringValue("GameISO", "BootISO", defaultISO.c_str());
                        fastBoot = g_p44_settings_interface->GetBoolValue("GameISO", "FastBoot", false);
                        g_p44_settings_interface->SetStringValue("GameISO", "BootISO", isoFilename.c_str());
                        g_p44_settings_interface->SetBoolValue("GameISO", "FastBoot", fastBoot);
                        g_p44_settings_interface->Save();
                    }
                }
                std::string isoPath = isoDir + "/" + isoFilename;
                // Fallback: check Documents/ root if not found in iso/
                if (!isoFilename.empty() && !FileSystem::FileExists(isoPath.c_str())) {
                    std::string rootPath = EmuFolders::DataRoot + "/" + isoFilename;
                    if (FileSystem::FileExists(rootPath.c_str())) {
                        isoPath = rootPath;
                        Console.WriteLn("ISO found in Documents/ root: %s", isoPath.c_str());
                    }
                }
                if (!isoFilename.empty() && FileSystem::FileExists(isoPath.c_str())) {
                    std::string suffix = isoFilename.size() >= 4 ? isoFilename.substr(isoFilename.size() - 4) : "";
                    std::transform(suffix.begin(), suffix.end(), suffix.begin(), ::tolower);
                    bool isElf = (suffix == ".elf");
                    if (isElf) {
                        boot_params.elf_override = isoPath;
                        boot_params.source_type = CDVD_SourceType::NoDisc;
                        boot_params.fast_boot = true;
                        Console.WriteLn("@@ISO_BOOT@@ path=%s fast_boot=1 mode=ELF (INI: %s)", isoPath.c_str(), isoFilename.c_str());
                    } else {
                        boot_params.filename = isoPath;
                        boot_params.source_type = CDVD_SourceType::Iso;
                        boot_params.fast_boot = fastBoot;
                        Console.WriteLn("@@ISO_BOOT@@ path=%s fast_boot=%d (INI: %s)", isoPath.c_str(), fastBoot ? 1 : 0, isoFilename.c_str());
                    }
                } else {
                    Console.WriteLn("@@ISO_BOOT@@ no ISO='%s', falling back to BIOS only", isoFilename.c_str());
                }
            }

            if (getenv("iPSX2_AUTO_BOOT_BIOS")) {
                Console.WriteLn("@@AUTO_BOOT_BIOS@@ enabled=1 action=triggered");
                boot_params.fast_boot = false;
            }
            // ps2autotests: boot ELF directly via env var
            if (const char* testElf = getenv("iPSX2_BOOT_ELF")) {
                boot_params.elf_override = testElf;
                boot_params.source_type = CDVD_SourceType::NoDisc;
                boot_params.fast_boot = true;
                Console.WriteLn("@@BOOT_ELF@@ elf=%s", testElf);
            }

            // BIOS sanity check
            if (EmuConfig.BaseFilenames.Bios.empty() || !FileSystem::FileExists(Path::Combine(EmuFolders::Bios, EmuConfig.BaseFilenames.Bios).c_str())) {
                Console.Error("CRITICAL: BIOS verification failed inside VM thread.");
                Host::ReportErrorAsync("BIOS Error", "Validation failed.");
                s_vmThreadActive.store(false);
                dispatch_async(dispatch_get_main_queue(), ^{
                    [[NSNotificationCenter defaultCenter] postNotificationName:@"iPSX2VMDidShutdown" object:nil];
                });
                continue; // back to wait loop
            }

            // --- Initialize & Execute VM ---
            if (VMManager::Initialize(boot_params)) {
                Console.WriteLn("[VM] VM initialized successfully");
                VMManager::SetState(VMState::Running);

                while (true) {
                    if (VMController_IsStopRequested()) {
                        Console.WriteLn("[VM] VM Thread: stop requested from UI.");
                        break;
                    }
                    VMState state = VMManager::GetState();
                    if (state == VMState::Stopping || state == VMState::Shutdown) {
                        Console.WriteLn("[VM] VM Thread: shutdown signal received.");
                        break;
                    } else if (state == VMState::Running) {
                        VMManager::Execute();
                    } else {
                        std::this_thread::sleep_for(std::chrono::milliseconds(10));
                    }
                }

                Console.WriteLn("[VM] VM Thread: shutting down VM...");
                VMManager::Shutdown(false);
            } else {
                Console.Error("VM Thread: VMManager::Initialize failed!");
                Host::ReportErrorAsync("Startup Error", "VM Initialization Failed.");
            }

            // --- Post-shutdown: reset state, notify UI ---
            s_vmThreadActive.store(false);
            s_requestVMStop.store(false);
            Console.WriteLn("[VM] VM Thread: shutdown complete, posting notification");
            dispatch_async(dispatch_get_main_queue(), ^{
                [[NSNotificationCenter defaultCenter] postNotificationName:@"iPSX2VMDidShutdown" object:nil];
            });
        } // end while(true) boot loop

        VMManager::Internal::CPUThreadShutdown();
        Console.WriteLn("[VM] VM Thread: CPUThreadShutdown called, thread exiting.");
    });
    vmThread.detach();
}

@end

// Gamepad button mapping
#include "GamepadMapper.h"

std::atomic<bool> GamepadMapper::captureMode{false};
std::atomic<int>  GamepadMapper::capturedButton{-1};
int GamepadMapper::buttonMap[16] = {
    SDL_GAMEPAD_BUTTON_DPAD_UP,        // 0  PAD_UP
    SDL_GAMEPAD_BUTTON_DPAD_DOWN,      // 1  PAD_DOWN
    SDL_GAMEPAD_BUTTON_DPAD_LEFT,      // 2  PAD_LEFT
    SDL_GAMEPAD_BUTTON_DPAD_RIGHT,     // 3  PAD_RIGHT
    SDL_GAMEPAD_BUTTON_SOUTH,          // 4  PAD_CROSS
    SDL_GAMEPAD_BUTTON_EAST,           // 5  PAD_CIRCLE
    SDL_GAMEPAD_BUTTON_WEST,           // 6  PAD_SQUARE
    SDL_GAMEPAD_BUTTON_NORTH,          // 7  PAD_TRIANGLE
    SDL_GAMEPAD_BUTTON_LEFT_SHOULDER,  // 8  PAD_L1
    SDL_GAMEPAD_BUTTON_RIGHT_SHOULDER, // 9  PAD_R1
    -1,                                // 10 PAD_L2 (analog trigger)
    -1,                                // 11 PAD_R2 (analog trigger)
    SDL_GAMEPAD_BUTTON_START,          // 12 PAD_START
    SDL_GAMEPAD_BUTTON_BACK,           // 13 PAD_SELECT
    SDL_GAMEPAD_BUTTON_LEFT_STICK,     // 14 PAD_L3
    SDL_GAMEPAD_BUTTON_RIGHT_STICK,    // 15 PAD_R3
};
const int s_defaultMap[16] = {
    SDL_GAMEPAD_BUTTON_DPAD_UP, SDL_GAMEPAD_BUTTON_DPAD_DOWN,
    SDL_GAMEPAD_BUTTON_DPAD_LEFT, SDL_GAMEPAD_BUTTON_DPAD_RIGHT,
    SDL_GAMEPAD_BUTTON_SOUTH, SDL_GAMEPAD_BUTTON_EAST,
    SDL_GAMEPAD_BUTTON_WEST, SDL_GAMEPAD_BUTTON_NORTH,
    SDL_GAMEPAD_BUTTON_LEFT_SHOULDER, SDL_GAMEPAD_BUTTON_RIGHT_SHOULDER,
    -1, -1,
    SDL_GAMEPAD_BUTTON_START, SDL_GAMEPAD_BUTTON_BACK,
    SDL_GAMEPAD_BUTTON_LEFT_STICK, SDL_GAMEPAD_BUTTON_RIGHT_STICK,
};

void GamepadMapper::ResetToDefaults() {
    for (int i = 0; i < 16; i++) buttonMap[i] = s_defaultMap[i];
}

void GamepadMapper::SetMapping(int ps2Index, int sdlButton) {
    if (ps2Index >= 0 && ps2Index < 16) {
        buttonMap[ps2Index] = sdlButton;
    }
}

int GamepadMapper::GetMapping(int ps2Index) {
    if (ps2Index >= 0 && ps2Index < 16) return buttonMap[ps2Index];
    return -1;
}


// View controller references for background color switching
static UIViewController* __unsafe_unretained s_menuVC = nil;
static UIViewController* __unsafe_unretained s_rootVC = nil;

// Helper to log to screen (thread safe)
void LogToScreen(const char* str) {
    if (!str) return;
    NSString *msg = [NSString stringWithUTF8String:str];
    dispatch_async(dispatch_get_main_queue(), ^{
        if (g_logView) {
            g_logView.text = [g_logView.text stringByAppendingString:msg];
            if (g_logView.text.length > 20000) {
                 g_logView.text = [g_logView.text substringFromIndex:g_logView.text.length - 20000];
            }
            [g_logView scrollRangeToVisible:NSMakeRange(g_logView.text.length, 0)];
        }
    });
}

// ... Host Stubs (Keep existing ones) ...

// We need to forward declare the Host stubs here or ensure they are present.
// For brevity, I will include the critical parts and stubs.

// -- Host Implementation Start --

namespace Host
{
    SDL_Window* g_sdl_window = nullptr;
    static SDL_Gamepad* s_gamepad = nullptr;

    void RequestShutdown() {
        SDL_Event event;
        event.type = SDL_EVENT_QUIT;
        SDL_PushEvent(&event);
    }
    
    // ... [Include all other Host stubs from previous ios_main.mm] ...
    // Note: I will paste the stubs in the actual write call to ensure compilation.
    

    
    void RunOnMainThread(std::function<void()> func, bool wait) {
        if (wait) {
            dispatch_sync(dispatch_get_main_queue(), ^{ func(); });
        } else {
            dispatch_async(dispatch_get_main_queue(), ^{ func(); });
        }
    }

    // Only needed stubs for linking
    // GetHTTPUserAgent removed (duplicate)
    bool CopyTextToClipboard(const std::string_view text) { return false; }
    void OnOSDMessage(const std::string&, float, u32) {}
    void ReportError(const char*, const char*) {}
    bool ConfirmAction(const char*, const char*, const char*) { return true; }
    std::optional<std::string> OpenFileSelectionDialog(const char*, const char*, const char*, const char*) { return std::nullopt; }
    std::optional<std::string> OpenDirectorySelectionDialog(const char*, const char*) { return std::nullopt; }
    void SysLog(const char* fmt, ...) {
        va_list args;
        va_start(args, fmt);
        vprintf(fmt, args);
        va_end(args);
    }
    void LoadSettings(SettingsInterface&, std::unique_lock<std::mutex>&) {} 
    void RequestResetSettings(bool) {} 
    const char* GetTranslatedStringImpl(const char* key) { return key; }
    u32 GetDisplayRefreshRate() { return 60; }
    std::optional<WindowInfo> AcquireRenderWindow(bool recreate_window) {
        Console.WriteLn("Host::AcquireRenderWindow(recreate=%d) called.", recreate_window);
        if (!g_sdl_window) {
            Console.Error("Host::AcquireRenderWindow: g_sdl_window is NULL");
            return std::nullopt;
        }
        
        __block WindowInfo wi = {};
        wi.type = WindowInfo::Type::iOS;
        
        // SDL calls that interact with UIKit must run on the main thread
        dispatch_sync(dispatch_get_main_queue(), ^{
            // SDL3 properties for UIKit
            SDL_PropertiesID props = SDL_GetWindowProperties(g_sdl_window);
            UIWindow* window = (__bridge UIWindow*)SDL_GetPointerProperty(props, SDL_PROP_WINDOW_UIKIT_WINDOW_POINTER, NULL);
            
            if (window) {
// Use dedicated game render view if available (sized for portrait)
                 if (g_gameRenderView) {
                     wi.window_handle = (__bridge void*)g_gameRenderView;
                 } else {
                     wi.window_handle = (__bridge void*)[window rootViewController].view;
                 }
            }

            if (!wi.window_handle) {
                 Console.Error("Host::AcquireRenderWindow: Failed to get UIKit View (UIWindow=%p)", window);
                 // Last resort: some older SDL versions might put the view in the window property or vice versa
                 if (!wi.window_handle) wi.window_handle = (__bridge void*)window;
            }

// Get render size from the actual render view
            UIView* renderView = (__bridge UIView*)wi.window_handle;
            CGFloat scale = renderView.contentScaleFactor;
            wi.surface_width = static_cast<u32>(renderView.bounds.size.width * scale);
            wi.surface_height = static_cast<u32>(renderView.bounds.size.height * scale);
            // [BLACK-SCREEN-FIX] If the view hasn't been laid out yet (CGRectZero), fall back to
            // screen native bounds. AttachSurfaceOnMainThread uses surface_width/height to set
            // CAMetalLayer.drawableSize; a zero size makes nextDrawable return nil permanently
            // because ResizeWindow early-returns when m_layer is null (device not yet created),
            // so the zero gets "baked in" by AttachSurfaceOnMainThread. layoutSubviews will call
            // GSResizeDisplayWindow with the correct size once the view is in the hierarchy.
            if (wi.surface_width == 0 || wi.surface_height == 0) {
                CGRect nativeBounds = [UIScreen mainScreen].nativeBounds;
                wi.surface_width = static_cast<u32>(nativeBounds.size.width);
                wi.surface_height = static_cast<u32>(nativeBounds.size.height);
                Console.WriteLn("Host::AcquireRenderWindow: View not yet laid out; using screen native bounds %ux%u",
                    wi.surface_width, wi.surface_height);
            }
            wi.surface_scale = SDL_GetWindowDisplayScale(g_sdl_window);
            
            SDL_DisplayID display = SDL_GetDisplayForWindow(g_sdl_window);
            const SDL_DisplayMode* mode = SDL_GetCurrentDisplayMode(display);
            if (mode)
                wi.surface_refresh_rate = mode->refresh_rate;
            else
                wi.surface_refresh_rate = 60.0f;
        });
            
        Console.WriteLn("Host::AcquireRenderWindow: Returning WindowInfo (Type=%d, View=%p, Size=%ux%u, Scale=%.2f)", 
            (int)wi.type, wi.window_handle, wi.surface_width, wi.surface_height, wi.surface_scale);

        return wi;
    }
    void ReleaseRenderWindow() {}
    bool InNoGUIMode() { return false; }
    void OnVMPaused() {}
    void OnVMResumed() {}
    void OnVMStarted() {}
    void OnVMStarting() {}
    void EndTextInput() {}
    bool IsFullscreen() { return true; }
    void SetMouseMode(bool, bool) {}
    void OnGameChanged(const std::string&, const std::string&, const std::string&, const std::string&, unsigned int, unsigned int) {}
    void OnVMDestroyed() {}
    void SetFullscreen(bool) {}
    void BeginTextInput() {}
    bool ConfirmMessage(std::string_view, std::string_view) { return true; }
    void RunOnCPUThread(std::function<void()>, bool) {}
    void ReportInfoAsync(std::string_view, std::string_view) {}
    void ReportErrorAsync(std::string_view title, std::string_view msg) {
        Console.Error("Host::ReportErrorAsync: %s - %s", std::string(title).c_str(), std::string(msg).c_str());
        NSString *nsTitle = [NSString stringWithUTF8String:std::string(title).c_str()];
        NSString *nsMsg = [NSString stringWithUTF8String:std::string(msg).c_str()];
        
        dispatch_async(dispatch_get_main_queue(), ^{
            // Re-read on main thread — s_rootVC is only ever set on main thread.
            UIViewController* vc = s_rootVC;
            if (!vc) return;
            UIAlertController *alert = [UIAlertController alertControllerWithTitle:nsTitle
                                                                           message:nsMsg
                                                                    preferredStyle:UIAlertControllerStyleAlert];
            [alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
            [vc presentViewController:alert animated:YES completion:nil];
        });
    }
    void OnSaveStateSaved(std::string_view) {}
    void OnSaveStateLoaded(std::string_view, bool) {}
    void BeginPresentFrame() {}
    void OnSaveStateLoading(std::string_view) {}
    bool LocaleCircleConfirm() { return false; }

    void RefreshGameListAsync(bool) {}
    bool RequestResetSettings(bool, bool, bool, bool, bool) { return true; }
    void CancelGameListRefresh() {}
    void RequestVMShutdown(bool, bool, bool) {}
    void RequestExitBigPicture() {}
    void OnInputDeviceConnected(std::string_view, std::string_view) {}
    void RequestExitApplication(bool) {}
    void CheckForSettingsChanges(const Pcsx2Config&) {}
    void OnAchievementsRefreshed() {}
    void PumpMessagesOnCPUThread()
    {
// Check for VM shutdown request (safe: runs on CPU thread)
        if (VMController_IsStopRequested()) {
            Console.WriteLn("[UI] PumpMessages: setting VM state to Stopping");
            VMManager::SetState(VMState::Stopping);
            return;
        }

        PadBase* pad = Pad::GetPad(0, 0);
        if (!pad) return;

#if TARGET_OS_SIMULATOR
        const bool* keys = SDL_GetKeyboardState(nullptr);
        if (!keys) return;

        static const struct { SDL_Scancode sc; u32 idx; } mapping[] = {
            { SDL_SCANCODE_UP,     PadDualshock2::Inputs::PAD_UP },
            { SDL_SCANCODE_DOWN,   PadDualshock2::Inputs::PAD_DOWN },
            { SDL_SCANCODE_LEFT,   PadDualshock2::Inputs::PAD_LEFT },
            { SDL_SCANCODE_RIGHT,  PadDualshock2::Inputs::PAD_RIGHT },
            { SDL_SCANCODE_Z,      PadDualshock2::Inputs::PAD_CIRCLE },
            { SDL_SCANCODE_X,      PadDualshock2::Inputs::PAD_CROSS },
            { SDL_SCANCODE_A,      PadDualshock2::Inputs::PAD_SQUARE },
            { SDL_SCANCODE_S,      PadDualshock2::Inputs::PAD_TRIANGLE },
            { SDL_SCANCODE_Q,      PadDualshock2::Inputs::PAD_L1 },
            { SDL_SCANCODE_W,      PadDualshock2::Inputs::PAD_R1 },
            { SDL_SCANCODE_1,      PadDualshock2::Inputs::PAD_L2 },
            { SDL_SCANCODE_2,      PadDualshock2::Inputs::PAD_R2 },
            { SDL_SCANCODE_RETURN, PadDualshock2::Inputs::PAD_START },
            { SDL_SCANCODE_SPACE,  PadDualshock2::Inputs::PAD_SELECT },
        };

        // Merge keyboard + touch input: only override with keyboard if
        // touch is not currently pressing the same button.
        for (const auto& m : mapping) {
            if (keys[m.sc])
                pad->Set(m.idx, 1.0f);
            else if (!g_touchPadState[m.idx])
                pad->Set(m.idx, 0.0f);
            // If touch is holding the button (g_touchPadState), don't reset it
        }
#endif // TARGET_OS_SIMULATOR — keyboard mapping

        // MFi / External gamepad support via SDL3
        {
            // Auto-detect: open first available gamepad if not already open
            if (!s_gamepad) {
                int count = 0;
                SDL_JoystickID* ids = SDL_GetGamepads(&count);
                if (ids && count > 0) {
                    s_gamepad = SDL_OpenGamepad(ids[0]);
                    if (s_gamepad)
                        Console.WriteLn("[Files] MFi gamepad connected: %s", SDL_GetGamepadName(s_gamepad));
                }
                SDL_free(ids);
            }
            // Handle disconnect
            if (s_gamepad && !SDL_GamepadConnected(s_gamepad)) {
                Console.WriteLn("[Files] MFi gamepad disconnected");
                SDL_CloseGamepad(s_gamepad);
                s_gamepad = nullptr;
            }
            if (s_gamepad) {
                SDL_UpdateGamepads();
                // Capture mode: detect any pressed button for remapping UI
                if (GamepadMapper::captureMode.load()) {
                    for (int b = 0; b < SDL_GAMEPAD_BUTTON_COUNT; b++) {
                        if (SDL_GetGamepadButton(s_gamepad, (SDL_GamepadButton)b)) {
                            GamepadMapper::capturedButton.store(b);
                            break;
                        }
                    }
                }
// Use configurable mapping table
                static const u32 ps2Buttons[] = {
                    PadDualshock2::Inputs::PAD_UP, PadDualshock2::Inputs::PAD_DOWN,
                    PadDualshock2::Inputs::PAD_LEFT, PadDualshock2::Inputs::PAD_RIGHT,
                    PadDualshock2::Inputs::PAD_CROSS, PadDualshock2::Inputs::PAD_CIRCLE,
                    PadDualshock2::Inputs::PAD_SQUARE, PadDualshock2::Inputs::PAD_TRIANGLE,
                    PadDualshock2::Inputs::PAD_L1, PadDualshock2::Inputs::PAD_R1,
                    0, 0, // L2/R2 handled as analog
                    PadDualshock2::Inputs::PAD_START, PadDualshock2::Inputs::PAD_SELECT,
                    PadDualshock2::Inputs::PAD_L3, PadDualshock2::Inputs::PAD_R3,
                };
                for (int i = 0; i < 16; i++) {
                    int sdlBtn = GamepadMapper::GetMapping(i);
                    if (sdlBtn < 0) continue; // analog trigger
                    bool pressed = SDL_GetGamepadButton(s_gamepad, (SDL_GamepadButton)sdlBtn);
                    if (pressed)
                        pad->Set(ps2Buttons[i], 1.0f);
                    else if (!g_touchPadState[ps2Buttons[i]])
                        pad->Set(ps2Buttons[i], 0.0f);
                }
                // L2/R2 triggers (analog)
                float l2 = SDL_GetGamepadAxis(s_gamepad, SDL_GAMEPAD_AXIS_LEFT_TRIGGER) / 32767.0f;
                float r2 = SDL_GetGamepadAxis(s_gamepad, SDL_GAMEPAD_AXIS_RIGHT_TRIGGER) / 32767.0f;
                if (l2 > 0.1f || !g_touchPadState[PadDualshock2::Inputs::PAD_L2])
                    pad->Set(PadDualshock2::Inputs::PAD_L2, l2 > 0.1f ? l2 : 0.0f);
                if (r2 > 0.1f || !g_touchPadState[PadDualshock2::Inputs::PAD_R2])
                    pad->Set(PadDualshock2::Inputs::PAD_R2, r2 > 0.1f ? r2 : 0.0f);
                // Analog sticks
                auto axis = [&](SDL_GamepadAxis a) -> float {
                    float v = SDL_GetGamepadAxis(s_gamepad, a) / 32767.0f;
                    return (v > 0.15f || v < -0.15f) ? v : 0.0f; // deadzone
                };
                float lx = axis(SDL_GAMEPAD_AXIS_LEFTX);
                float ly = axis(SDL_GAMEPAD_AXIS_LEFTY);
                float rx = axis(SDL_GAMEPAD_AXIS_RIGHTX);
                float ry = axis(SDL_GAMEPAD_AXIS_RIGHTY);
                pad->Set(PadDualshock2::Inputs::PAD_L_RIGHT, lx > 0 ? lx : 0.0f);
                pad->Set(PadDualshock2::Inputs::PAD_L_LEFT,  lx < 0 ? -lx : 0.0f);
                pad->Set(PadDualshock2::Inputs::PAD_L_DOWN,  ly > 0 ? ly : 0.0f);
                pad->Set(PadDualshock2::Inputs::PAD_L_UP,    ly < 0 ? -ly : 0.0f);
                pad->Set(PadDualshock2::Inputs::PAD_R_RIGHT, rx > 0 ? rx : 0.0f);
                pad->Set(PadDualshock2::Inputs::PAD_R_LEFT,  rx < 0 ? -rx : 0.0f);
                pad->Set(PadDualshock2::Inputs::PAD_R_DOWN,  ry > 0 ? ry : 0.0f);
                pad->Set(PadDualshock2::Inputs::PAD_R_UP,    ry < 0 ? -ry : 0.0f);
            }
        }
    }
    std::string TranslatePluralToString(const char*, const char*, const char*, int) { return ""; }
    void CommitBaseSettingChanges() {}
    void OnInputDeviceDisconnected(InputBindingKey, std::string_view) {}
    void OpenHostFileSelectorAsync(std::string_view, bool, std::function<void(const std::string&)>, std::vector<std::string>, std::string_view) {}
    std::unique_ptr<ProgressCallback> CreateHostProgressCallback() { return nullptr; }
    void OnAchievementsLoginSuccess(char const*, u32, u32, u32) {}
    void OnPerformanceMetricsUpdated() {}
    void OnAchievementsLoginRequested(Achievements::LoginRequestReason) {}
    bool ShouldPreferHostFileSelector() { return false; }
    void OnCoverDownloaderOpenRequested() {}
    void OnCreateMemoryCardOpenRequested() {}
    void OnAchievementsHardcoreModeChanged(bool) {}
    void OpenURL(std::string_view) {}
}

namespace Host::Internal
{
    s32 GetTranslatedStringImpl(const std::string_view, const std::string_view, char*, size_t) { return 0; }
}

// Called from iPSX2Bridge to toggle SDL fullscreen (controls status bar visibility)
extern "C" void iPSX2_SetSDLFullscreen(bool enabled) {
    if (Host::g_sdl_window)
        SDL_SetWindowFullscreen(Host::g_sdl_window, enabled);
}

// Returns the gamepad handle opened by PumpMessagesOnCPUThread (or nullptr if none).
// Bridge uses this for capture-mode polling to avoid a duplicate open.
extern "C" SDL_Gamepad* iPSX2_GetActiveGamepad() {
    return Host::s_gamepad;
}

namespace Common {
    bool PlaySoundAsync(const char*) { return false; }
}

// IOCtlSrc Stubs
IOCtlSrc::IOCtlSrc(std::string filename) : m_filename(std::move(filename)) {}
IOCtlSrc::~IOCtlSrc() {}
bool IOCtlSrc::Reopen(Error*) { return false; }
u32 IOCtlSrc::GetSectorCount() const { return 0; }
const std::vector<toc_entry>& IOCtlSrc::ReadTOC() const { static std::vector<toc_entry> empty; return empty; }
bool IOCtlSrc::ReadSectors2048(u32, u32, u8*) const { return false; }
bool IOCtlSrc::ReadSectors2352(u32, u32, u8*) const { return false; }
bool IOCtlSrc::ReadTrackSubQ(cdvdSubQ*) const { return false; }
u32 IOCtlSrc::GetLayerBreakAddress() const { return 0; }
s32 IOCtlSrc::GetMediaType() const { return 0; }
void IOCtlSrc::SetSpindleSpeed(bool) const {}
bool IOCtlSrc::DiscReady() { return false; }

// ... InputManager Stubs ...
namespace InputManager {
    void Initialize() {}
    void Shutdown() {}
    void Update() {}
    void SetRumble(int, u8, u8) {}
    const char* ConvertHostKeyboardCodeToIcon(unsigned int) { return ""; }
    std::optional<std::string> ConvertHostKeyboardCodeToString(unsigned int) { return std::nullopt; }
    std::optional<unsigned int> ConvertHostKeyboardStringToCode(std::string_view) { return std::nullopt; }
}

// ... HTTP Stubs ...
std::unique_ptr<HTTPDownloader> HTTPDownloader::Create(std::string user_agent) { return nullptr; }

// Global stubs for DISCopen
void GetValidDrive(std::string&) {  }
std::vector<std::string> GetOpticalDriveList() { return {}; }

namespace FileSystem {
    int OpenFDFileContent(const char*) { return -1; } // Added overload
    bool OpenFDFileContent(const std::string&, int, s64, s64) { return false; }
    std::string GetValidDrive(const std::string&) { return ""; }
    std::vector<std::string> GetOpticalDriveList() { return {}; }
}


// ... IOCtlSrc Stub Removed ...

// ... CocoaTools Stub ...
namespace CocoaTools {
    void InhibitAppNap(const std::string&) {}
    void UninhibitAppNap() {}
    std::string GetBundlePath() { return [[NSBundle mainBundle].bundlePath UTF8String]; }
    
    void* CreateMetalLayer(WindowInfo* wi) {
        if (!Host::g_sdl_window) return nullptr;
        
        // Return existing layer if we already have it
        if (wi->surface_handle) {
            return SDL_Metal_GetLayer((SDL_MetalView)wi->surface_handle);
        }
        
        // Create the Metal view
        SDL_MetalView view = SDL_Metal_CreateView(Host::g_sdl_window);
        if (!view) {
            Console.Error("SDL_Metal_CreateView failed: %s", SDL_GetError());
            return nullptr;
        }
        
        void* layer = SDL_Metal_GetLayer(view);
        wi->surface_handle = view; // Store view handle to destroy later
        Console.WriteLn("Created Metal Layer: %p from View: %p", layer, view);
        return layer;
    }
    
    void DestroyMetalLayer(WindowInfo* wi) {
        if (wi->surface_handle) {
            Console.WriteLn("Destroying Metal View: %p", wi->surface_handle);
            SDL_Metal_DestroyView((SDL_MetalView)wi->surface_handle);
            wi->surface_handle = nullptr;
        }
    }
}

// ... AudioStream Stub ...
#include "pcsx2/Host/AudioStream.h"
std::unique_ptr<AudioStream> AudioStream::CreateOboeAudioStream(unsigned int, AudioStreamParameters const&, bool, Error*) { return nullptr; }

// ... PCAP Stub ...
PCAPAdapter::PCAPAdapter() {}
PCAPAdapter::~PCAPAdapter() {}
bool PCAPAdapter::blocks() { return false; }
bool PCAPAdapter::isInitialised() { return false; }
bool PCAPAdapter::recv(NetPacket*) { return false; }
bool PCAPAdapter::send(NetPacket*) { return false; }
void PCAPAdapter::reloadSettings() {}
std::vector<AdapterEntry> PCAPAdapter::GetAdapters() { return {}; }
AdapterOptions PCAPAdapter::GetAdapterOptions() { return {}; }
bool PCAPAdapter::InitPCAP(const std::string&, bool) { return false; }
bool PCAPAdapter::SetMACSwitchedFilter(PacketReader::MAC_Address) { return false; }
void PCAPAdapter::SetMACBridgedRecv(NetPacket*) {}
void PCAPAdapter::SetMACBridgedSend(NetPacket*) {}
void PCAPAdapter::HandleFrameCheckSequence(NetPacket*) {}
bool PCAPAdapter::ValidateEtherFrame(NetPacket*) { return false; }


// ... FileSystem Stub ...
// Duplicate FileSystem block removed

// -- End Host Stubs --

// Settings Interface
static INISettingsInterface* s_settings_interface = nullptr;
// Expose to iPSX2Bridge.mm via extern
INISettingsInterface* g_p44_settings_interface = nullptr;

//
// -- IOS AppDelegate & SceneDelegate --
//

@interface PCSX2SceneDelegate : UIResponder <UIWindowSceneDelegate, UIDocumentPickerDelegate>
@property (strong, nonatomic) UIWindow *window;
@property (strong, nonatomic) UIButton *startBiosButton;
@end

@implementation PCSX2SceneDelegate

- (void)scene:(UIScene *)scene willConnectToSession:(UISceneSession *)session options:(UISceneConnectionOptions *)connectionOptions {
    if (![scene isKindOfClass:[UIWindowScene class]]) return;
    
    UIWindowScene *windowScene = (UIWindowScene *)scene;
    
    // --- SDL Initialization ---
    static bool s_initialized = false;
    if (!s_initialized) {
        SDL_SetMainReady();
        if (SDL_Init(SDL_INIT_VIDEO | SDL_INIT_AUDIO | SDL_INIT_GAMEPAD) < 0) {
            NSLog(@"SDL_Init failed: %s", SDL_GetError());
            return;
        }
        s_initialized = true;
    }
    
    // --- Setup PCSX2 Environment ---
    // (Moved to AppDelegate)
    // We still need local variables if used below, but EmuFolders are global.
    NSArray *paths = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES);
    NSString *documentsDirectory = [paths objectAtIndex:0];
    std::string dataRoot = [documentsDirectory UTF8String];
    
    // Re-ensure EmuFolders (idempotent)
    EmuFolders::DataRoot = dataRoot;
    EmuFolders::Bios = dataRoot + "/bios";
    // ...
    
    Console.WriteLn("PCSX2 iOS: Initializing logic in SceneDelegate...");
    
    // Settings Initialization
    if (!s_settings_interface) {
        std::string iniPath = dataRoot + "/PCSX2-iOS.ini";
        s_settings_interface = new INISettingsInterface(iniPath);
        if (!static_cast<INISettingsInterface*>(s_settings_interface)->Load()) {
            Console.WriteLn("Creating new config at %s", iniPath.c_str());
            
            // [iPSX2] Standard Defaults: JIT Enabled (if supported), EE/IOP/VU Recompilers ON
            s_settings_interface->SetIntValue("EmuCore/CPU", "CoreType", 0); // Recompiler
            s_settings_interface->SetBoolValue("EmuCore/CPU", "UseArm64Dynarec", false);
            s_settings_interface->SetBoolValue("EmuCore/CPU/Recompiler", "EnableEE", true);
            s_settings_interface->SetBoolValue("EmuCore/CPU/Recompiler", "EnableIOP", true);
            s_settings_interface->SetBoolValue("EmuCore/CPU/Recompiler", "EnableVU0", true);
            s_settings_interface->SetBoolValue("EmuCore/CPU/Recompiler", "EnableVU1", true);
            s_settings_interface->SetBoolValue("EmuCore/CPU", "EnableSparseMemory", true);
            s_settings_interface->SetBoolValue("EmuCore/CPU", "ExtraMemory", false);

            // Audio
            s_settings_interface->SetStringValue("SPU2/Output", "Backend", "SDL");

            // GS — use PCSX2 defaults; pcrtc_offsets controlled per-game via game database
            s_settings_interface->SetIntValue("EmuCore/GS", "VsyncQueueSize", 2);

            // Speedhacks
            s_settings_interface->SetBoolValue("EmuCore/Speedhacks", "MTVU", false);
            
            Console.WriteLn("@@CFG_DEFAULTS@@ created=1 CoreType=0 UseArm64Dynarec=false EnableEE=1");
            s_settings_interface->Save();
        }
        Host::Internal::SetBaseSettingsLayer(s_settings_interface);
        g_p44_settings_interface = s_settings_interface; // expose to Bridge
// Load gamepad button mapping from INI
        for (int i = 0; i < 16; i++) {
            char key[32]; snprintf(key, sizeof(key), "Button%d", i);
            int val = s_settings_interface->GetIntValue("iPSX2/GamepadMapping", key, s_defaultMap[i]);
            GamepadMapper::buttonMap[i] = val;
        }
    }
    // One-time migration for existing INI (runs once, then conditions are false)
    if (!s_settings_interface->ContainsValue("SPU2/Output", "Backend")) {
        s_settings_interface->SetStringValue("SPU2/Output", "Backend", "SDL");
    }
    if (!s_settings_interface->ContainsValue("EmuCore/CPU", "ExtraMemory")) {
        s_settings_interface->SetBoolValue("EmuCore/CPU", "ExtraMemory", false);
    }

    s_settings_interface->Save();
    [self checkAndConfigureBIOS];

    // GS Renderer: Metal fixed on iOS. Only override if not already Metal.
#if DEBUG
    if (const char* null_gs_env = getenv("iPSX2_NULL_GS"); null_gs_env && atoi(null_gs_env)) {
        EmuConfig.GS.Renderer = GSRendererType::Null;
        Console.WriteLn("@@CFG@@ GS Renderer: Null (DEBUG)");
    } else
#endif
    {
        EmuConfig.GS.Renderer = GSRendererType::Metal;
    }
    s_settings_interface->Save();

    VMManager::Internal::LoadStartupSettings();
    VMManager::ApplySettings();
    
    // --- Create SDL Window ---
    Host::g_sdl_window = SDL_CreateWindow("PCSX2 iOS", 1280, 720, SDL_WINDOW_METAL | SDL_WINDOW_RESIZABLE);
    if (!Host::g_sdl_window) {
        Console.Error("Failed to create SDL window: %s", SDL_GetError());
        return;
    }
    
    // --- Attach UIWindow ---
    UIWindow *uiWindow = (__bridge UIWindow*)SDL_GetPointerProperty(SDL_GetWindowProperties(Host::g_sdl_window), SDL_PROP_WINDOW_UIKIT_WINDOW_POINTER, NULL);
    if (uiWindow) {
        Console.WriteLn("Attaching UIWindow to Scene...");
        uiWindow.windowScene = windowScene;
        self.window = uiWindow;
        self.window.backgroundColor = [UIColor systemGroupedBackgroundColor];
        [self.window makeKeyAndVisible];

// Create game render view — SwiftUI MetalGameView (UIViewRepresentable) manages placement
        g_gameRenderView = [[iPSX2GameView alloc] initWithFrame:CGRectZero];
        g_gameRenderView.backgroundColor = [UIColor blackColor];
        g_gameRenderView.clipsToBounds = YES;
        // Do NOT addSubview here — SwiftUI's MetalGameView handles view hierarchy
        Console.WriteLn("[Layout] Game render view created (SwiftUI-managed)");
        
// Debug-only UI elements
#if DEBUG
        if (rootVC) {
            g_logView = [[UITextView alloc] initWithFrame:CGRectMake(10, 50, 600, 300)];
            g_logView.backgroundColor = [UIColor colorWithWhite:0.0 alpha:0.5];
            g_logView.textColor = [UIColor whiteColor];
            g_logView.font = [UIFont fontWithName:@"Courier" size:10];
            g_logView.editable = NO;
            g_logView.hidden = YES;
            [rootVC.view addSubview:g_logView];
        }
#endif
    }
    
    // --- [UI] Startup Logic: Show menu first, boot on user action ---
#if iPSX2_HAS_SWIFTUI
    {
        UIViewController *rootVC = self.window.rootViewController;
        if (rootVC) {
            rootVC.view.backgroundColor = [UIColor systemGroupedBackgroundColor];

            UIViewController *menuVC = [SwiftUIHost createMenuController];
            menuVC.view.translatesAutoresizingMaskIntoConstraints = NO;
            menuVC.view.userInteractionEnabled = YES;
// Keep hosting controller always clear — SwiftUI RootView handles its own background
            menuVC.view.backgroundColor = [UIColor clearColor];
            [rootVC.view addSubview:menuVC.view];
            [NSLayoutConstraint activateConstraints:@[
                [menuVC.view.topAnchor constraintEqualToAnchor:rootVC.view.topAnchor],
                [menuVC.view.bottomAnchor constraintEqualToAnchor:rootVC.view.bottomAnchor],
                [menuVC.view.leadingAnchor constraintEqualToAnchor:rootVC.view.leadingAnchor],
                [menuVC.view.trailingAnchor constraintEqualToAnchor:rootVC.view.trailingAnchor],
            ]];
            [rootVC addChildViewController:menuVC];
            [menuVC didMoveToParentViewController:rootVC];
            s_menuVC = menuVC;
            s_rootVC = rootVC;

            if (g_logView) {
                g_logView.hidden = YES;
                g_logView.userInteractionEnabled = NO;
            }
            Console.WriteLn("[UI] SwiftUI menu attached (screen: %.0fx%.0f)",
                rootVC.view.bounds.size.width, rootVC.view.bounds.size.height);

}
    }

    // Listen for VM boot request from SwiftUI
    // queue:nil = synchronous delivery, so background colors are set BEFORE
    // SwiftUI re-renders the game overlay (avoids gray flash)
    [[NSNotificationCenter defaultCenter] addObserverForName:@"iPSX2RequestVMBoot"
                                                      object:nil
                                                       queue:nil
                                                  usingBlock:^(NSNotification * _Nonnull note) {
        Console.WriteLn("[UI] VM boot requested from UI (rootVC=%p)", s_rootVC);
        if (s_rootVC) s_rootVC.view.backgroundColor = [UIColor blackColor];
#if TARGET_OS_SIMULATOR
        [[VMController sharedInstance] startVMThread];
#else
        [self checkJITAndStartVM];
#endif
    }];

    [[NSNotificationCenter defaultCenter] addObserverForName:@"iPSX2RequestVMShutdown"
                                                      object:nil
                                                       queue:nil
                                                  usingBlock:^(NSNotification * _Nonnull note) {
        Console.WriteLn("[UI] VM shutdown requested from UI");
        [[VMController sharedInstance] requestVMShutdown];
    }];

    // iPSX2VMDidShutdown / iPSX2ReturnToMenu: no rootVC background change needed.
    // SwiftUI RootView handles menu background via Color(systemGroupedBackground).ignoresSafeArea().
    // rootVC stays black after first boot — eliminates white flash during VM restart.

    [[NSNotificationCenter defaultCenter] addObserverForName:@"iPSX2VMDidShutdown"
                                                      object:nil
                                                       queue:nil
                                                  usingBlock:^(NSNotification * _Nonnull note) {
        // No rootVC background change — SwiftUI handles menu bg
    }];

    [[NSNotificationCenter defaultCenter] addObserverForName:@"iPSX2ReturnToMenu"
                                                      object:nil
                                                       queue:nil
                                                  usingBlock:^(NSNotification * _Nonnull note) {
        // No rootVC background change — SwiftUI handles menu bg
    }];

    [[NSNotificationCenter defaultCenter] addObserverForName:@"iPSX2EnterGameScreen"
                                                      object:nil
                                                       queue:nil
                                                  usingBlock:^(NSNotification * _Nonnull note) {
        if (s_rootVC) s_rootVC.view.backgroundColor = [UIColor blackColor];
    }];

// Auto-boot — debug/simulator only
#if DEBUG || TARGET_OS_SIMULATOR
    if (getenv("iPSX2_AUTO_BOOT") && atoi(getenv("iPSX2_AUTO_BOOT")) == 1) {
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            Console.WriteLn("[AutoBoot] @@AUTO_BOOT@@ posting iPSX2RequestVMBoot + AutoBootDidStart");
            [[NSNotificationCenter defaultCenter] postNotificationName:@"iPSX2RequestVMBoot" object:nil];
            [[NSNotificationCenter defaultCenter] postNotificationName:@"iPSX2AutoBootDidStart" object:nil];
        });
    }
#endif // DEBUG || TARGET_OS_SIMULATOR — AUTO_BOOT
    // ps2autotests: auto-boot VM when ELF env var is set (always enabled)
    if (getenv("iPSX2_BOOT_ELF")) {
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(2.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            [[NSNotificationCenter defaultCenter] postNotificationName:@"iPSX2RequestVMBoot" object:nil];
        });
    }
#else
    // Fallback: no SwiftUI — auto-boot like before
    if (!EmuConfig.BaseFilenames.Bios.empty() && FileSystem::FileExists(Path::Combine(EmuFolders::Bios, EmuConfig.BaseFilenames.Bios).c_str())) {
#if TARGET_OS_SIMULATOR
        [[VMController sharedInstance] startVMThread];
#else
        [self checkJITAndStartVM];
#endif
    } else {
        Console.Warning("No valid BIOS found. Showing selection UI.");
        if (self.startBiosButton) {
            self.startBiosButton.hidden = NO;
            [self.window bringSubviewToFront:self.startBiosButton];
        }
    }
#endif
}

- (void)checkAndConfigureBIOS {
    std::string dataRoot = EmuFolders::DataRoot;
    std::string biosDir = dataRoot + "/bios";
    
    // 0. [iPSX2] Check Env Var Override (iPSX2_BIOS_PATH)
    const char* envBios = getenv("iPSX2_BIOS_PATH");
    // Simulator: use iPSX2_BIOS_PATH env var or auto-scan Documents/bios/
    // Real device: BIOS must be placed in Documents/bios/ via Files app
    Console.WriteLn("@@BIOS_DIR@@ path=\"%s\"", biosDir.c_str());
    
    if (envBios) {
        bool exists = FileSystem::FileExists(envBios);
        Console.WriteLn("@@BIOS_ENV@@ exists=%d", exists ? 1 : 0);
        
        if (exists) {
            // Copy to EmuFolders::Bios to ensure sandbox compliance
            struct stat st = {0};
            if (stat(biosDir.c_str(), &st) == -1) mkdir(biosDir.c_str(), 0755);
            
            std::string fileName(Path::GetFileName(envBios));
            std::string destPath = Path::Combine(biosDir, fileName);
            
            // Only copy if source != dest
            if (std::string(envBios) != destPath) {
                FILE *src = fopen(envBios, "rb");
                FILE *dst = fopen(destPath.c_str(), "wb");
                bool copyOk = true;
                if (src && dst) {
                    char buffer[4096];
                    size_t bytes;
                    while ((bytes = fread(buffer, 1, 4096, src)) > 0) {
                        if (fwrite(buffer, 1, bytes, dst) != bytes) { copyOk = false; break; }
                    }
                    fclose(src); fclose(dst);
                    if (!copyOk) {
                        Console.Error("[BIOS] Copy failed (disk full?): %s -> %s", envBios, destPath.c_str());
                        std::remove(destPath.c_str());
                    } else {
                        Console.WriteLn("Copied env-var BIOS to: %s", destPath.c_str());
                    }
                } else {
                    Console.Error("Failed to copy env-var BIOS. src=%p dst=%p", src, dst);
                    if (src) fclose(src);
                    if (dst) fclose(dst);
                }
            }
            
            EmuConfig.BaseFilenames.Bios = fileName;
            if (s_settings_interface) {
                s_settings_interface->SetStringValue("Filenames", "BIOS", EmuConfig.BaseFilenames.Bios.c_str());
                s_settings_interface->Save();
            }
            Console.WriteLn("@@BIOS_PICK@@ result=\"%s\" source=env", EmuConfig.BaseFilenames.Bios.c_str());
            return;
        }
    } else {
        Console.WriteLn("@@BIOS_ENV@@ exists=0");
    }

    // 1. Check existing config
    if (!EmuConfig.BaseFilenames.Bios.empty() && FileSystem::FileExists(Path::Combine(EmuFolders::Bios, EmuConfig.BaseFilenames.Bios).c_str())) {
        Console.WriteLn("@@BIOS_PICK@@ result=\"%s\" source=config", EmuConfig.BaseFilenames.Bios.c_str());
        return;
    }

    // 1b. Auto-move BIOS files from Documents/ root to bios/ subfolder
    {
        FileSystem::FindResultsArray rootResults;
        if (FileSystem::FindFiles(dataRoot.c_str(), "*", FILESYSTEM_FIND_FILES, &rootResults)) {
            for (const auto& fd : rootResults) {
                if (fd.Size >= 1024*1024 && fd.Size <= 50*1024*1024) {
                    std::string fn = std::string(Path::GetFileName(fd.FileName));
                    std::string ext = fn.size() >= 4 ? fn.substr(fn.size() - 4) : "";
                    std::transform(ext.begin(), ext.end(), ext.begin(), ::tolower);
                    if (ext == ".bin" || ext == ".rom") {
                        std::string src = Path::Combine(dataRoot, fn);
                        std::string dst = Path::Combine(biosDir, fn);
                        if (!FileSystem::FileExists(dst.c_str())) {
                            if (rename(src.c_str(), dst.c_str()) == 0)
                                Console.WriteLn("[Files] Moved BIOS to bios/: %s", fn.c_str());
                            else
                                Console.WriteLn("[Files] Failed to move BIOS: %s (errno=%d)", fn.c_str(), errno);
                        }
                    }
                }
            }
        }
    }

    // 2. Scan Documents/bios
    FileSystem::FindResultsArray results;
    int foundCount = 0;
    if (FileSystem::FindFiles(biosDir.c_str(), "*", FILESYSTEM_FIND_FILES, &results)) {
        for (const auto& fd : results) {
            foundCount++;
            if (fd.Size >= 1024*1024 && (fd.FileName.find(".bin") != std::string::npos || fd.FileName.find(".BIN") != std::string::npos)) {
                // Found a candidate
                std::string currentName = std::string(Path::GetFileName(fd.FileName));
                EmuConfig.BaseFilenames.Bios = currentName;
                Console.WriteLn("Auto-detected BIOS (name only): %s", EmuConfig.BaseFilenames.Bios.c_str());
                if (s_settings_interface) {
                    s_settings_interface->SetStringValue("Filenames", "BIOS", EmuConfig.BaseFilenames.Bios.c_str());
                    s_settings_interface->Save();
                }
                Console.WriteLn("@@BIOS_PICK@@ result=\"%s\" source=scan", EmuConfig.BaseFilenames.Bios.c_str());
                return;
            }
        }
    }
    Console.WriteLn("@@BIOS_SCAN@@ found=%d", foundCount);
    Console.WriteLn("@@BIOS_PICK@@ result=\"(none)\" source=none");

    // 3. Check Bundle Resources (Fallback)
    NSString *resourcePath = [[NSBundle mainBundle] resourcePath];
    std::string bundleDir = [resourcePath UTF8String];
    FileSystem::FindResultsArray bundleResults;

    // [iPSX2] Support "BiosFiles" folder reference
    std::string bfDir = bundleDir + "/BiosFiles";
    if (FileSystem::FindFiles(bfDir.c_str(), "*", FILESYSTEM_FIND_FILES, &bundleResults)) {
        for (const auto& fd : bundleResults) {
             if (fd.Size >= 1024*1024 && (fd.FileName.find(".bin") != std::string::npos || fd.FileName.find(".BIN") != std::string::npos)) {
                 Console.WriteLn("Found BIOS in BiosFiles: %s", fd.FileName.c_str());
                 struct stat st = {0};
                 if (stat(biosDir.c_str(), &st) == -1) mkdir(biosDir.c_str(), 0755);

                 std::string src = bfDir + "/" + fd.FileName;
                 std::string dst = biosDir + "/" + fd.FileName;
                 FILE *s=fopen(src.c_str(),"rb"), *d=fopen(dst.c_str(),"wb");
                 bool copyOk2 = true;
                 if (s && d) {
                     char b[4096]; size_t n;
                     while ((n = fread(b, 1, 4096, s)) > 0) {
                         if (fwrite(b, 1, n, d) != n) { copyOk2 = false; break; }
                     }
                 }
                 if (s) fclose(s);
                 if (d) fclose(d);
                 if (!copyOk2) {
                     Console.Error("[BIOS] BiosFiles bundle copy failed");
                     continue;
                 }
                 EmuConfig.BaseFilenames.Bios = fd.FileName;
                 return;
             }
        }
    }
    if (FileSystem::FindFiles(bundleDir.c_str(), "*", FILESYSTEM_FIND_FILES, &bundleResults)) {
        for (const auto& fd : bundleResults) {
             if (fd.Size >= 1024*1024 && (fd.FileName.find(".bin") != std::string::npos || fd.FileName.find(".BIN") != std::string::npos)) {
                 Console.WriteLn("Found BIOS in Bundle: %s. Copying...", fd.FileName.c_str());
                 std::string srcPath = bundleDir + "/" + fd.FileName;
                 std::string destPath = biosDir + "/" + fd.FileName;
                 
                 struct stat st = {0};
                 if (stat(biosDir.c_str(), &st) == -1) mkdir(biosDir.c_str(), 0755);

                 FILE *src = fopen(srcPath.c_str(), "rb");
                 FILE *dst = fopen(destPath.c_str(), "wb");
                 bool copyOk3 = true;
                 if (src && dst) {
                     char buffer[4096];
                     size_t bytes;
                     while ((bytes = fread(buffer, 1, 4096, src)) > 0) {
                         if (fwrite(buffer, 1, bytes, dst) != bytes) { copyOk3 = false; break; }
                     }
                 }
                 if (src) fclose(src);
                 if (dst) fclose(dst);
                 if (copyOk3 && src && dst) {
                     EmuConfig.BaseFilenames.Bios = fd.FileName;
                     Console.WriteLn("Copy and set successful.");
                     return;
                 } else if (!copyOk3) {
                     Console.Error("[BIOS] Bundle copy failed (disk full?)");
                     std::remove(destPath.c_str());
                 }
             }
        }
    }
    
    Console.Warning("No BIOS found automatically.");
    EmuConfig.BaseFilenames.Bios.clear();
}

- (void)showBiosPicker {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
    UIDocumentPickerViewController *documentPicker = [[UIDocumentPickerViewController alloc] initWithDocumentTypes:@[@"public.data"] inMode:UIDocumentPickerModeImport];
#pragma clang diagnostic pop
    documentPicker.delegate = self;
    documentPicker.allowsMultipleSelection = NO;
    [self.window.rootViewController presentViewController:documentPicker animated:YES completion:nil];
}

- (void)documentPicker:(UIDocumentPickerViewController *)controller didPickDocumentsAtURLs:(NSArray<NSURL *> *)urls {
    if (urls.count == 0) return;
    
    NSURL *url = urls.firstObject;
    Console.WriteLn("User picked file: %s", [[url path] UTF8String]);
    
    // Copy to Documents/bios
    std::string biosDir = EmuFolders::DataRoot + "/bios";
    struct stat st = {0};
    if (stat(biosDir.c_str(), &st) == -1) mkdir(biosDir.c_str(), 0755);
    
    NSString *destPath = [NSString stringWithFormat:@"%s/%@", biosDir.c_str(), [url lastPathComponent]];
    NSError *error = nil;
    
    // Remove if exists
    [[NSFileManager defaultManager] removeItemAtPath:destPath error:nil];
    
    if ([[NSFileManager defaultManager] copyItemAtURL:url toURL:[NSURL fileURLWithPath:destPath] error:&error]) {
        Console.WriteLn("Imported BIOS to: %s", [destPath UTF8String]);
        
        std::string fileName = [[destPath lastPathComponent] UTF8String];
        EmuConfig.BaseFilenames.Bios = fileName;
        
        // Hide button and start VM
        dispatch_async(dispatch_get_main_queue(), ^{
            self.startBiosButton.hidden = YES;
        });
        
#if TARGET_OS_SIMULATOR
        [[VMController sharedInstance] startVMThread];
#else
        [self checkJITAndStartVM];
#endif

    } else {
        Console.Error("Failed to import BIOS: %s", [[error localizedDescription] UTF8String]);
        Host::ReportErrorAsync("Import Failed", [[error localizedDescription] UTF8String]);
    }
}

// JIT availability check for real device — fallback to Interpreter if JIT unavailable
// CS_DEBUGGED check only (DolphiniOS approach) — no blocking, runs on main thread
- (void)checkJITAndStartVM {
#if !TARGET_OS_SIMULATOR
    if (DarwinMisc::IsJITAvailable()) {
        Console.WriteLn("@@JIT_GATE@@ JIT available — starting VM in JIT mode");
        [[VMController sharedInstance] startVMThread];
        return;
    }

    Console.Warning("@@JIT_GATE@@ JIT NOT available — falling back to Interpreter mode");
    DarwinMisc::iPSX2_FORCE_EE_INTERP = 1;
    Console.WriteLn("@@JIT_GATE@@ iPSX2_FORCE_EE_INTERP forced to 1");
    [[VMController sharedInstance] startVMThread];
#else
    [[VMController sharedInstance] startVMThread];
#endif
}



- (void)sceneDidDisconnect:(UIScene *)scene {
    s_menuVC = nil;
    s_rootVC = nil;
}

- (void)sceneDidBecomeActive:(UIScene *)scene {
}

- (void)sceneWillResignActive:(UIScene *)scene {
// NVM save when app loses focus
    extern void cdvdSaveNVRAM();
    cdvdSaveNVRAM();
}

- (void)sceneWillEnterForeground:(UIScene *)scene {
}

- (void)sceneDidEnterBackground:(UIScene *)scene {
// Save NVM + memory cards when app goes to background.
    // Without this, BIOS settings (language/date) are lost on every restart
    // because cdvdSaveNVRAM() is only called at VM shutdown, which never
    // happens when iOS terminates the app via SIGTERM.
    extern void cdvdSaveNVRAM();
    cdvdSaveNVRAM();
    Console.WriteLn("[NVM] NVM saved on sceneDidEnterBackground");
}

@end


@interface PCSX2AppDelegate : UIResponder <UIApplicationDelegate>
@end

@implementation PCSX2AppDelegate

- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)launchOptions {
    // Override point for customization after application launch.
    
    // --- Setup PCSX2 Environment (Moved from SceneDelegate) ---
    NSArray *paths = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES);
    NSString *documentsDirectory = [paths objectAtIndex:0];
    NSString *resourcePath = [[NSBundle mainBundle] resourcePath];
    
    std::string dataRoot = [documentsDirectory UTF8String];
    EmuFolders::DataRoot = dataRoot;
    EmuFolders::AppRoot = [resourcePath UTF8String];
    EmuFolders::Resources = [resourcePath UTF8String];
    EmuFolders::Bios = dataRoot + "/bios";
    // ... [Init other folders if needed, but DataRoot is key] ...
    EmuFolders::Logs = dataRoot + "/logs";

    // --- Unified Logging Redirection ---
    // Force stderr and stdout to pcsx2_log.txt
    std::string logPath = dataRoot + "/pcsx2_log.txt";
    
    // Redirect stderr to file
    if (freopen(logPath.c_str(), "w", stderr) == NULL) { // "w" clears old logs
        printf("Reopen stderr failed\n");
    }
    
    // Redirect stdout to stderr
    if (dup2(fileno(stderr), fileno(stdout)) == -1) {
        fprintf(stderr, "Redirection of stdout failed\n");
    }
    
    // Disable buffering
    setvbuf(stderr, NULL, _IONBF, 0);
    setvbuf(stdout, NULL, _IONBF, 0);
    
    // [iPSX2] Register File Descriptor for Signal Handler
    // We use the raw file descriptor of stderr (which is now our log file)
    DarwinMisc::SetCrashLogFD(fileno(stderr));
    
    // Log Proof Tag
    fprintf(stderr, "@@LOG_SINK@@ unified=1 path=%s pid=%d\n", logPath.c_str(), getpid());
    NSString* bundleID = [[NSBundle mainBundle] bundleIdentifier];
    fprintf(stderr, "@@BUNDLE_ID@@ %s\n", bundleID ? [bundleID UTF8String] : "(null)");
    fprintf(stderr, "@@BUILD_ID@@ %s_%s_%s\n", iPSX2_GIT_HASH, __DATE__, __TIME__);
    
    // [iPSX2] Unification Validation
    // @@BIOS_GATE@@ build_id=2026-01-14_13-30-00 bundle=(from_nsbundle)
    NSString* bID = [[NSBundle mainBundle] bundleIdentifier];
    const char* cBundle = bID ? [bID UTF8String] : "(null)";
    fprintf(stderr, "@@BIOS_GATE@@ build_id=2026-01-17_PROBE bundle=%s\n", cBundle);
    fprintf(stderr, "@@LOG_UNIFIED@@ pcsx2_log.txt includes emulog output; emulog.txt disabled=1\n");
    
// DYLD Map — debug builds only
#if DEBUG
    {
        fprintf(stderr, "@@CFG@@ iPSX2_CRASH_DIAG=1 (DYLD Dump Enabled)\n");
        uint32_t count = _dyld_image_count();
        for (uint32_t i = 0; i < count; i++) {
            const char* name = _dyld_get_image_name(i);
            intptr_t slide = _dyld_get_image_vmaddr_slide(i);
            const struct mach_header* hdr = _dyld_get_image_header(i);
            fprintf(stderr, "@@DYLD_MAP@@ idx=%u addr=%p slide=%p path=%s\n", i, hdr, (void*)slide, name);
        }
    }
#endif
    fflush(stderr);

    // Enable PCSX2 Console Output only (std::cout/cerr will now go to file)
    Log::SetConsoleOutputLevel(LOGLEVEL::LOGLEVEL_INFO);
    
    Console.WriteLn("PCSX2 iOS: AppDelegate didFinishLaunching.");
    
    return YES;
}

- (UISceneConfiguration *)application:(UIApplication *)application configurationForConnectingSceneSession:(UISceneSession *)connectingSceneSession options:(UISceneConnectionOptions *)options {
    // Called when a new scene session is being created.
    // Use this method to select a configuration to create the new scene with.
    UISceneConfiguration *config = [[UISceneConfiguration alloc] initWithName:@"Default Configuration" sessionRole:connectingSceneSession.role];
    config.delegateClass = [PCSX2SceneDelegate class];
    return config;
}

- (void)application:(UIApplication *)application didDiscardSceneSessions:(NSSet<UISceneSession *> *)sceneSessions {
}

- (void)applicationWillTerminate:(UIApplication *)application {
    Console.WriteLn("[App] applicationWillTerminate: signaling VM thread to exit");
    s_requestVMStop.store(true);
    s_requestAppExit.store(true);
    s_vmCV.notify_all();
    std::this_thread::sleep_for(std::chrono::milliseconds(500));
}

@end


//
// -- Main Entry Point --
//

// Signal Handler removed to allow PCSX2's internal handlers to work
#import <UIKit/UIKit.h>
#include <mach-o/dyld.h>
#include <cstdio>

int main(int argc, char * argv[]) {
    // InstallSignalHandler(); // Removed
    
    @autoreleasepool {
        // SDL_MAIN_HANDLED is set, so we use standard main()
        return UIApplicationMain(argc, argv, nil, NSStringFromClass([PCSX2AppDelegate class]));
    }
}
