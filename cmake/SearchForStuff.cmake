# SearchForStuff.cmake — locate required libraries and frameworks for iPSX2

include(CheckIncludeFile)
include(CheckIncludeFiles)
include(CheckLibraryExists)
include(CMakePushCheckState)

# Path helper for vendored dependencies located under cpp/3rdparty.
set(IPSX2_CPP_ROOT "${CMAKE_CURRENT_LIST_DIR}/../cpp")
set(IPSX2_MISSING_TARGET_HINTS "")

function(ipsx2_add_vendored_subdirectory rel_path build_subdir)
    set(_src "${IPSX2_CPP_ROOT}/${rel_path}")
    if(EXISTS "${_src}/CMakeLists.txt")
        add_subdirectory(
            "${_src}"
            "${CMAKE_BINARY_DIR}/${build_subdir}"
            EXCLUDE_FROM_ALL
        )
    endif()
endfunction()

macro(ipsx2_require_target target hint)
    if(NOT TARGET ${target})
        list(APPEND IPSX2_MISSING_TARGET_HINTS "${target} (${hint})")
    endif()
endmacro()

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
if(NOT TARGET SDL3::SDL3)
    ipsx2_add_vendored_subdirectory("3rdparty/SDL3" "3rdparty/SDL3")
endif()
if(NOT TARGET SDL3::SDL3)
    find_package(SDL3 QUIET CONFIG)
endif()

# ── fmt (vendored inside cpp/3rdparty/fmt) ─────────────────────────────────────
if(NOT TARGET fmt::fmt)
    ipsx2_add_vendored_subdirectory("3rdparty/fmt" "3rdparty/fmt")
endif()
if(NOT TARGET fmt::fmt)
    find_package(fmt QUIET CONFIG)
endif()

# ── rapidyaml (vendored inside cpp/3rdparty/rapidyaml) ────────────────────────
if(NOT TARGET rapidyaml::rapidyaml)
    ipsx2_add_vendored_subdirectory("3rdparty/rapidyaml" "3rdparty/rapidyaml")
endif()
if(NOT TARGET rapidyaml::rapidyaml)
    find_package(rapidyaml QUIET CONFIG)
endif()

# ── zlib baseline for dependencies requiring ZLIB::ZLIB ───────────────────────
if(NOT TARGET ZLIB::ZLIB)
    find_package(ZLIB QUIET)
endif()
if(CMAKE_SYSTEM_NAME STREQUAL "iOS" AND NOT TARGET ZLIB::ZLIB)
    # iOS SDK always provides libz; create a target-compatible shim.
    add_library(ZLIB::ZLIB INTERFACE IMPORTED)
    set_target_properties(ZLIB::ZLIB PROPERTIES INTERFACE_LINK_LIBRARIES "z")
    message(STATUS "ZLIB::ZLIB not found via find_package; using iOS SDK libz shim.")
endif()

# ── Core libraries for common/pcsx2 targets ───────────────────────────────────
if(NOT TARGET Zstd::Zstd)
    ipsx2_add_vendored_subdirectory("3rdparty/zstd" "3rdparty/zstd")
endif()

if(NOT TARGET LZMA::LZMA)
    ipsx2_add_vendored_subdirectory("3rdparty/lzma" "3rdparty/lzma")
endif()

if(NOT TARGET LZ4::LZ4)
    ipsx2_add_vendored_subdirectory("3rdparty/lz4" "3rdparty/lz4")
endif()

if(NOT TARGET SoundTouch::SoundTouch)
    ipsx2_add_vendored_subdirectory("3rdparty/soundtouch" "3rdparty/soundtouch")
endif()

if(NOT TARGET fast_float)
    ipsx2_add_vendored_subdirectory("3rdparty/fast_float" "3rdparty/fast_float")
endif()

if(NOT TARGET vixl)
    ipsx2_add_vendored_subdirectory("3rdparty/vixl" "3rdparty/vixl")
endif()

if(NOT TARGET imgui)
    ipsx2_add_vendored_subdirectory("3rdparty/imgui" "3rdparty/imgui")
endif()

if(NOT TARGET simpleini)
    ipsx2_add_vendored_subdirectory("3rdparty/simpleini" "3rdparty/simpleini")
endif()

if(NOT TARGET ccc)
    ipsx2_add_vendored_subdirectory("3rdparty/ccc" "3rdparty/ccc")
endif()

if(NOT TARGET demanglegnu)
    ipsx2_add_vendored_subdirectory("3rdparty/demangler" "3rdparty/demangler")
endif()

if(NOT TARGET freesurround)
    ipsx2_add_vendored_subdirectory("3rdparty/freesurround" "3rdparty/freesurround")
endif()

if(NOT TARGET cpuinfo)
    ipsx2_add_vendored_subdirectory("3rdparty/cpuinfo" "3rdparty/cpuinfo")
endif()
if(NOT TARGET cpuinfo)
    if(TARGET cpuinfo::cpuinfo)
        add_library(cpuinfo INTERFACE IMPORTED)
        set_target_properties(cpuinfo PROPERTIES INTERFACE_LINK_LIBRARIES "cpuinfo::cpuinfo")
    endif()
endif()

if(NOT TARGET cubeb)
    ipsx2_add_vendored_subdirectory("3rdparty/cubeb" "3rdparty/cubeb")
endif()

if(NOT TARGET rcheevos)
    ipsx2_add_vendored_subdirectory("3rdparty/rcheevos" "3rdparty/rcheevos")
endif()

if(NOT TARGET libchdr)
    ipsx2_add_vendored_subdirectory("3rdparty/libchdr" "3rdparty/libchdr")
endif()

if(NOT TARGET libzip::zip)
    ipsx2_add_vendored_subdirectory("3rdparty/libzip" "3rdparty/libzip")
endif()
if(NOT TARGET libzip::zip)
    find_package(libzip QUIET CONFIG)
endif()

# ── WebP (vendored inside cpp/3rdparty/libwebp) ────────────────────────────────
if(NOT TARGET WebP::libwebp)
    # We only need the core library in this project.
    set(WEBP_BUILD_ANIM_UTILS OFF CACHE BOOL "" FORCE)
    set(WEBP_BUILD_CWEBP OFF CACHE BOOL "" FORCE)
    set(WEBP_BUILD_DWEBP OFF CACHE BOOL "" FORCE)
    set(WEBP_BUILD_GIF2WEBP OFF CACHE BOOL "" FORCE)
    set(WEBP_BUILD_IMG2WEBP OFF CACHE BOOL "" FORCE)
    set(WEBP_BUILD_VWEBP OFF CACHE BOOL "" FORCE)
    set(WEBP_BUILD_WEBPINFO OFF CACHE BOOL "" FORCE)
    set(WEBP_BUILD_LIBWEBPMUX OFF CACHE BOOL "" FORCE)
    set(WEBP_BUILD_WEBPMUX OFF CACHE BOOL "" FORCE)
    set(WEBP_BUILD_EXTRAS OFF CACHE BOOL "" FORCE)
    set(WEBP_BUILD_FUZZTEST OFF CACHE BOOL "" FORCE)
    ipsx2_add_vendored_subdirectory("3rdparty/libwebp" "3rdparty/libwebp")
endif()
if(NOT TARGET WebP::libwebp)
    find_package(WebP QUIET CONFIG)
endif()
if(NOT TARGET WebP::libwebp)
    if(TARGET webp)
        add_library(WebP::libwebp ALIAS webp)
    elseif(TARGET WebP::webp)
        add_library(WebP::libwebp INTERFACE IMPORTED)
        set_target_properties(WebP::libwebp PROPERTIES INTERFACE_LINK_LIBRARIES "WebP::webp")
    endif()
endif()

# ── Aggregate checks: report all missing targets at once ──────────────────────
ipsx2_require_target("fmt::fmt" "provide cpp/3rdparty/fmt or a package exposing fmt::fmt")
ipsx2_require_target("rapidyaml::rapidyaml" "provide cpp/3rdparty/rapidyaml or a package exposing rapidyaml::rapidyaml")
ipsx2_require_target("Zstd::Zstd" "provide cpp/3rdparty/zstd")
ipsx2_require_target("LZMA::LZMA" "provide cpp/3rdparty/lzma")
ipsx2_require_target("LZ4::LZ4" "provide cpp/3rdparty/lz4")
ipsx2_require_target("SoundTouch::SoundTouch" "provide cpp/3rdparty/soundtouch")
ipsx2_require_target("fast_float" "provide cpp/3rdparty/fast_float")
ipsx2_require_target("vixl" "provide cpp/3rdparty/vixl")
ipsx2_require_target("imgui" "provide cpp/3rdparty/imgui")
ipsx2_require_target("simpleini" "provide cpp/3rdparty/simpleini")
ipsx2_require_target("ccc" "provide cpp/3rdparty/ccc")
ipsx2_require_target("demanglegnu" "provide cpp/3rdparty/demangler")
ipsx2_require_target("freesurround" "provide cpp/3rdparty/freesurround")
ipsx2_require_target("cpuinfo" "provide cpp/3rdparty/cpuinfo")
ipsx2_require_target("cubeb" "provide cpp/3rdparty/cubeb")
ipsx2_require_target("rcheevos" "provide cpp/3rdparty/rcheevos")
ipsx2_require_target("libchdr" "provide cpp/3rdparty/libchdr")
ipsx2_require_target("libzip::zip" "provide cpp/3rdparty/libzip or a package exposing libzip::zip")
ipsx2_require_target("ZLIB::ZLIB" "install zlib package or provide SDK/system libz target")

if(NOT ANDROID)
    ipsx2_require_target("WebP::libwebp" "provide cpp/3rdparty/libwebp or a package exposing WebP::libwebp/WebP::webp")
endif()

if(CMAKE_SYSTEM_NAME STREQUAL "iOS")
    if(NOT TARGET SDL3::SDL3)
        message(STATUS "SDL3 target not found (vendored or package). iOS build will skip direct SDL3 linking.")
    endif()
else()
    ipsx2_require_target("SDL3::SDL3" "provide cpp/3rdparty/SDL3 or a package exposing SDL3::SDL3")
endif()

if(NOT TARGET ZLIB::ZLIB AND NOT CMAKE_SYSTEM_NAME STREQUAL "iOS")
    message(STATUS "zlib not found via find_package; linker will resolve it from the SDK.")
endif()

if(IPSX2_MISSING_TARGET_HINTS)
    string(JOIN "\n  - " IPSX2_MISSING_TARGETS_JOINED ${IPSX2_MISSING_TARGET_HINTS})
    message(FATAL_ERROR
        "SearchForStuff: missing required CMake targets:\n"
        "  - ${IPSX2_MISSING_TARGETS_JOINED}\n"
        "Resolve the targets above and re-run CMake."
    )
endif()

message(STATUS "SearchForStuff: dependency search complete.")
