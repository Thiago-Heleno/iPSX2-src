# SearchForStuff.cmake — locate required libraries and frameworks for iPSX2

include(CheckIncludeFile)
include(CheckIncludeFiles)
include(CheckLibraryExists)
include(CMakePushCheckState)

# ── Apple / iOS frameworks (always present on the platform) ──────────────────
if(APPLE)
    find_library(FOUNDATION_LIBRARY   Foundation   REQUIRED)
    find_library(COREFOUNDATION_LIB   CoreFoundation REQUIRED)
    find_library(CORETEXT_LIB         CoreText     REQUIRED)
    find_library(COREGRAPHICS_LIB     CoreGraphics REQUIRED)
    find_library(METAL_LIB            Metal        REQUIRED)
    find_library(METALKIT_LIB         MetalKit     REQUIRED)
    find_library(QUARTZCORE_LIB       QuartzCore   REQUIRED)

    if(CMAKE_SYSTEM_NAME STREQUAL "iOS")
        find_library(UIKIT_LIB        UIKit        REQUIRED)
    else()
        find_library(APPKIT_LIB       AppKit       REQUIRED)
    endif()
endif()

# ── SDL3 (vendored inside cpp/3rdparty/SDL3) ──────────────────────────────────
# The SDL3 CMakeLists is added as a subdirectory by the pcsx2 sub-build.
# If it hasn't been added yet, add it here so find_package works.
if(NOT TARGET SDL3::SDL3)
    if(EXISTS "${CMAKE_CURRENT_LIST_DIR}/../cpp/3rdparty/SDL3/CMakeLists.txt")
        add_subdirectory(
            "${CMAKE_CURRENT_LIST_DIR}/../cpp/3rdparty/SDL3"
            "${CMAKE_BINARY_DIR}/3rdparty/SDL3"
            EXCLUDE_FROM_ALL
        )
    else()
        # CI: SDL3 excluded from repo — use a stub so configure succeeds.
        # The actual SDL3 target is provided by the pcsx2 subdirectory.
        message(STATUS "SDL3 vendored source not found; expecting it via pcsx2 subdirectory.")
    endif()
endif()

# ── zlib (system) ─────────────────────────────────────────────────────────────
find_package(ZLIB QUIET)
if(NOT ZLIB_FOUND)
    message(STATUS "zlib not found via find_package; linker will resolve it from the SDK.")
endif()

message(STATUS "SearchForStuff: dependency search complete.")
