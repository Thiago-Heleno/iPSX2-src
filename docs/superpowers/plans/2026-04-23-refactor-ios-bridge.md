# iOS Bridge & Main Refactor Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Clean up the iOS port's global state, memory semantics, and hacky workarounds (BIOS nav, incomplete Host stubs) to ensure long-term stability and maintainability.

**Architecture:** We will encapsulate the VM threading and UI state into proper Objective-C/C++ classes, remove `__unsafe_unretained` pointers to prevent crashes, delete the fragile BIOS navigation hack, and properly implement asynchronous UI error reporting.

**Tech Stack:** Objective-C++, C++, UIKit, SDL3

---

### Task 1: Fix View Controller Memory Management

**Files:**
- Modify: `cpp/ios_main.mm`

- [ ] **Step 1: Replace `__unsafe_unretained` with `__weak`**

In `cpp/ios_main.mm`, find the global variables for the view controllers and change their memory semantics to prevent dangling pointers.

```objc
// Replace:
// static UIViewController* __unsafe_unretained s_menuVC = nil;
// static UIViewController* __unsafe_unretained s_rootVC = nil;

// With:
static UIViewController* __weak s_menuVC = nil;
static UIViewController* __weak s_rootVC = nil;
```

- [ ] **Step 2: Commit**

```bash
git add cpp/ios_main.mm
git commit -m "fix(ios): replace __unsafe_unretained with __weak for view controllers"
```

### Task 2: Implement Proper UI Error Reporting

**Files:**
- Modify: `cpp/ios_main.mm`

- [ ] **Step 1: Update `Host::ReportErrorAsync` to show an alert**

Currently, `ReportErrorAsync` only logs to the console. It must show a user-visible alert since it's an asynchronous error reporting function.

```cpp
    void ReportErrorAsync(std::string_view title, std::string_view msg) {
        Console.Error("Host::ReportErrorAsync: %s - %s", std::string(title).c_str(), std::string(msg).c_str());
        NSString *nsTitle = [NSString stringWithUTF8String:std::string(title).c_str()];
        NSString *nsMsg = [NSString stringWithUTF8String:std::string(msg).c_str()];
        
        dispatch_async(dispatch_get_main_queue(), ^{
            if (s_rootVC) {
                UIAlertController *alert = [UIAlertController alertControllerWithTitle:nsTitle
                                                                               message:nsMsg
                                                                        preferredStyle:UIAlertControllerStyleAlert];
                [alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
                [s_rootVC presentViewController:alert animated:YES completion:nil];
            }
        });
    }
```

- [ ] **Step 2: Commit**

```bash
git add cpp/ios_main.mm
git commit -m "feat(ios): implement proper UIAlertController in Host::ReportErrorAsync"
```

### Task 3: Remove the Fragile BIOS Navigation Hack

**Files:**
- Modify: `cpp/ios_main.mm`

- [ ] **Step 1: Delete the `iPSX2_BIOS_NAV` block**

In `cpp/ios_main.mm`, inside `PumpMessagesOnCPUThread`, delete the entire `#if DEBUG` block that implements the BIOS navigation hack using hardcoded frame counts.

```cpp
        // Remove this entire block:
        // // [BIOS_NAV] Auto-navigate BIOS — debug only
        // #if DEBUG
        // if (const char* nav = getenv("iPSX2_BIOS_NAV"); nav && atoi(nav))
        // {
        //     unsigned int fc = ::g_FrameCount;
        // ...
        //     for (auto cp : cps) {
        //         if (fc == cp) {
        //             Console.WriteLn(Color_Yellow, "[BIOS_NAV] checkpoint f=%u", fc);
        //         }
        //     }
        // }
        // #endif // DEBUG — BIOS_NAV
```

- [ ] **Step 2: Commit**

```bash
git add cpp/ios_main.mm
git commit -m "chore(ios): remove fragile frame-counted BIOS navigation hack"
```

### Task 4: Encapsulate Global VM State

**Files:**
- Modify: `cpp/ios_main.mm`
- Modify: `cpp/iPSX2Bridge.mm`
- Modify: `cpp/iPSX2Bridge.h`

- [ ] **Step 1: Define `VMController` interface**

In `cpp/iPSX2Bridge.h`, declare an interface to manage VM state instead of relying purely on extern atomics scattered across files.

```objc
// Add to cpp/iPSX2Bridge.h:
@interface VMController : NSObject
+ (instancetype)sharedInstance;
- (void)startVMThread;
- (void)requestVMBoot;
- (void)requestVMShutdown;
@property (nonatomic, readonly) BOOL isVMRunning;
@property (nonatomic, readonly) BOOL isVMThreadActive;
@end
```

- [ ] **Step 2: Migrate state from globals to `VMController`**

Move `s_vmThreadActive`, `s_requestVMStop`, `s_requestVMBoot`, `s_vmMutex`, `s_vmCV`, and `s_vmThreadCreated` into static members inside `VMController` implementation in `cpp/ios_main.mm` or `cpp/iPSX2Bridge.mm`. Update `[self startVMThread]` calls to use `[[VMController sharedInstance] startVMThread]`. Update `requestVMBoot` and `requestVMShutdown` to use this class.

- [ ] **Step 3: Update `PumpMessagesOnCPUThread`**

Update the shutdown check in `PumpMessagesOnCPUThread` to use the new encapsulated state instead of the raw extern `s_requestVMStop`.

- [ ] **Step 4: Commit**

```bash
git add cpp/ios_main.mm cpp/iPSX2Bridge.mm cpp/iPSX2Bridge.h
git commit -m "refactor(ios): encapsulate VM thread state into VMController"
```

### Task 5: Encapsulate Gamepad Mapping State

**Files:**
- Modify: `cpp/ios_main.mm`
- Modify: `cpp/iPSX2Bridge.mm`

- [ ] **Step 1: Create an `InputMapper` struct/class**

Instead of using `extern int s_buttonMap[16];` and `extern std::atomic<bool> s_captureMode;`, create a clean C++ struct in a new header or top of `ios_main.mm` to hold the mapping configuration. Provide explicit getter/setter methods.

```cpp
struct GamepadMapper {
    static std::atomic<bool> captureMode;
    static std::atomic<int> capturedButton;
    static int buttonMap[16];
    
    static void ResetToDefaults();
    static void SetMapping(int ps2Index, int sdlButton);
    static int GetMapping(int ps2Index);
};
```

- [ ] **Step 2: Update `iPSX2Bridge` methods**

Update the Objective-C bridge methods (`setButtonMapping:toSDLButton:`, `getButtonMapping:`, etc.) to call the new `GamepadMapper` methods instead of modifying the extern arrays directly.

- [ ] **Step 3: Commit**

```bash
git add cpp/ios_main.mm cpp/iPSX2Bridge.mm
git commit -m "refactor(ios): encapsulate gamepad mappings into GamepadMapper struct"
```
