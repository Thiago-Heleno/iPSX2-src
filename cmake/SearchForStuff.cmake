# SearchForStuff.cmake — locate required libraries and frameworks for iPSX2

include(CheckIncludeFile)
include(CheckIncludeFiles)
include(CheckLibraryExists)
include(CMakePushCheckState)

# Path helper for vendored dependencies located under cpp/3rdparty.
set(IPSX2_CPP_ROOT "${CMAKE_CURRENT_LIST_DIR}/../cpp")

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
if(NOT TARGET SDL3::SDL3)
    message(STATUS "SDL3 target not found (vendored or package). iOS build will skip direct SDL3 linking.")
endif()

# ── fmt (vendored inside cpp/3rdparty/fmt) ─────────────────────────────────────
if(NOT TARGET fmt::fmt)
    ipsx2_add_vendored_subdirectory("3rdparty/fmt" "3rdparty/fmt")
endif()
if(NOT TARGET fmt::fmt)
    find_package(fmt QUIET CONFIG)
endif()
if(NOT TARGET fmt::fmt)
    message(FATAL_ERROR "fmt target not found. Provide cpp/3rdparty/fmt or install a CMake package exposing fmt::fmt.")
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
if(NOT ANDROID AND NOT TARGET WebP::libwebp)
    message(FATAL_ERROR "WebP target not found. Provide cpp/3rdparty/libwebp or install a CMake package exposing WebP::libwebp/WebP::webp.")
endif()

# ── zlib (system) ─────────────────────────────────────────────────────────────
find_package(ZLIB QUIET)
if(NOT ZLIB_FOUND)
    message(STATUS "zlib not found via find_package; linker will resolve it from the SDK.")
endif()

message(STATUS "SearchForStuff: dependency search complete.")
