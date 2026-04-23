#pragma once
#include <atomic>

struct GamepadMapper {
    static std::atomic<bool> captureMode;
    static std::atomic<int> capturedButton;
    static int buttonMap[16];
    
    static void ResetToDefaults();
    static void SetMapping(int ps2Index, int sdlButton);
    static int GetMapping(int ps2Index);
};