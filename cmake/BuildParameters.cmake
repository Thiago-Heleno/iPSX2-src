# BuildParameters.cmake — compiler flags and feature options for iPSX2

# ── C++ standard ──────────────────────────────────────────────────────────────
set(CMAKE_CXX_STANDARD 20)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_CXX_EXTENSIONS OFF)

set(CMAKE_C_STANDARD 11)
set(CMAKE_C_STANDARD_REQUIRED ON)

# ── iOS / ARM64 platform flags ────────────────────────────────────────────────
if(CMAKE_SYSTEM_NAME STREQUAL "iOS")
    # Silence warnings that pollute the build log on ARM64 iOS
    add_compile_options(
        -Wno-deprecated-declarations
        -Wno-unused-parameter
        -Wno-missing-field-initializers
    )

    # Enable NEON for ARM64 — required by VIF unpack and GS vector paths
    add_compile_options(-march=armv8-a+simd)

    # Hide symbols by default; only export what's explicitly marked
    set(CMAKE_C_VISIBILITY_PRESET   hidden)
    set(CMAKE_CXX_VISIBILITY_PRESET hidden)
    set(CMAKE_VISIBILITY_INLINES_HIDDEN ON)

    # Ensure __POSIX__ is defined globally so that POSIX-guarded includes
    # (e.g. socket headers in DEV9) work even before Pcsx2Defs.h is included.
    add_compile_definitions(__POSIX__=1)
endif()

# ── Optimisation and debug info ───────────────────────────────────────────────
if(CMAKE_BUILD_TYPE STREQUAL "Release" OR CMAKE_BUILD_TYPE STREQUAL "RelWithDebInfo")
    add_compile_options(-O2)
endif()

# ── Feature options ───────────────────────────────────────────────────────────
option(ENABLE_TESTS    "Build unit tests"        OFF)
option(ENABLE_GSRUNNER "Build GS standalone runner" OFF)
option(PCSX2_CORE      "Build as library (core)" OFF)
