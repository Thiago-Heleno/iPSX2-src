# Setting it to a range tells it that it supports the features on the newer
# versions as well, avoiding setting policies.
cmake_minimum_required(VERSION 3.16...3.25)

# Enabling this cmake policy gets rid of warnings regarding LTO.
cmake_policy(SET CMP0069 NEW)
set(CMAKE_POLICY_DEFAULT_CMP0069 NEW)

if(${CMAKE_SOURCE_DIR} STREQUAL ${CMAKE_BINARY_DIR})
	message(FATAL_ERROR "PCSX2 does not support in-tree builds.  Please make a build directory that is not the PCSX2 source directory and generate your CMake project there using either `cmake -B build_directory` or by running cmake from the build directory.")
endif()

# Skip compiler checks to avoid freeze on Simulator environment
set(CMAKE_C_COMPILER_WORKS 1)
set(CMAKE_CXX_COMPILER_WORKS 1)

# Real device vs Simulator build
option(iPSX2_REAL_DEVICE "Build for real iOS device (iphoneos SDK)" OFF)
if(iPSX2_REAL_DEVICE)
    set(CMAKE_OSX_SYSROOT "iphoneos")
else()
    set(CMAKE_OSX_SYSROOT "iphonesimulator")
endif()
set(CMAKE_OSX_ARCHITECTURES "arm64")

# Version (single source of truth)
set(IPSX2_VERSION_MAJOR 0)
set(IPSX2_VERSION_MINOR 1)
set(IPSX2_VERSION_PATCH 2)
set(IPSX2_VERSION "${IPSX2_VERSION_MAJOR}.${IPSX2_VERSION_MINOR}.${IPSX2_VERSION_PATCH}")
set(IPSX2_BUILD_NUMBER 2)

# Project Name
project(iPSX2 VERSION ${IPSX2_VERSION} LANGUAGES C CXX)

# Code signing setup
if(CMAKE_GENERATOR STREQUAL "Xcode")
    if(NOT iPSX2_REAL_DEVICE)
        # Simulator: ad-hoc signing
        set(CMAKE_XCODE_ATTRIBUTE_CODE_SIGNING_REQUIRED "NO")
        set(CMAKE_XCODE_ATTRIBUTE_CODE_SIGN_IDENTITY "")
    else()
        # Real device: skip signing entirely (Sideloadly will re-sign the IPA)
        set(CMAKE_XCODE_ATTRIBUTE_CODE_SIGNING_REQUIRED "NO")
        set(CMAKE_XCODE_ATTRIBUTE_CODE_SIGNING_ALLOWED "NO")
        set(CMAKE_XCODE_ATTRIBUTE_CODE_SIGN_IDENTITY "")
    endif()
endif()

if(CMAKE_SYSTEM_NAME STREQUAL "iOS")
	add_compile_definitions(_M_ARM64=1)
    set(_M_ARM64 TRUE)
    set(_M_X86 FALSE)
    set(CMAKE_HOST_SYSTEM_PROCESSOR "arm64")

    set(_M_ARM64 TRUE)
    set(_M_X86 FALSE)
    set(CMAKE_HOST_SYSTEM_PROCESSOR "arm64")

endif()

# Variable to check that people use the good file
set(TOP_CMAKE_WAS_SOURCED TRUE)

# set module path
set(CMAKE_MODULE_PATH ${CMAKE_SOURCE_DIR}/../../cmake)

# Write binaries to the bin directory under the build directory.
# This makes it simple to run development builds directly out of the build directory.
if (UNIX AND NOT APPLE)
	set(CMAKE_RUNTIME_OUTPUT_DIRECTORY "${CMAKE_CURRENT_BINARY_DIR}/bin")
	set(CMAKE_LIBRARY_OUTPUT_DIRECTORY "${CMAKE_CURRENT_BINARY_DIR}/bin")
endif()

# include some generic functions to ensure correctness of the env
include(Pcsx2Utils)

check_no_parenthesis_in_path()
detect_operating_system()
detect_compiler()

#-------------------------------------------------------------------------------
# Include specific module
include(BuildParameters)
include(SearchForStuff)

option(USE_DISCORD_SDK "Enable Discord SDK / Discord Rich Presence support" OFF)

if(ANDROID)
	if(USE_DISCORD_SDK)
		find_package(discord_partner_sdk CONFIG)
	endif()
	# Link all native binaries with 16KB page support for newer devices.
	add_link_options(-Wl,-z,max-page-size=16384)
	# Belt-and-suspenders: ensure every shared/module target inherits the flag.
	set(CMAKE_SHARED_LINKER_FLAGS "${CMAKE_SHARED_LINKER_FLAGS} -Wl,-z,max-page-size=16384")
	set(CMAKE_MODULE_LINKER_FLAGS "${CMAKE_MODULE_LINKER_FLAGS} -Wl,-z,max-page-size=16384")
endif()

# Must be done after SearchForStuff
get_git_version_info()
write_svnrev_h()

# make common
add_subdirectory(common)

# make pcsx2
add_subdirectory(pcsx2)
#add_subdirectory(pcsx2-qt)

# Updater is Windows only for now.
if (WIN32)
	add_subdirectory(updater)
endif()

## tests
#if(ENABLE_TESTS)
#	add_subdirectory(3rdparty/googletest)
#	add_subdirectory(tests/ctest)
#endif()

# gsrunner
if(ENABLE_GSRUNNER)
	if (NOT WIN32)
		message(WARNING "GSRunner is only supported on Windows and may not build on your system")
	endif()
	add_subdirectory(pcsx2-gsrunner)
endif()

#-------------------------------------------------------------------------------
if(NOT IS_SUPPORTED_COMPILER)
	message(WARNING "
*************** UNSUPPORTED CONFIGURATION ***************
You are not compiling PCSX2 with a supported compiler.
It may not even build successfully.
PCSX2 only supports the Clang and MSVC compilers.
No support will be provided, continue at your own risk.
*********************************************************")
endif()

#if(_M_ARM64)
#	message(WARNING "
#*************** UNSUPPORTED CONFIGURATION ***************
#
#Apple Silicon support in PCSX2 is INCOMPLETE. There are
#currently no EE/VU/IOP recompilers, and games will run
#VERY slow. There is no date for completion yet, you
#should set -DCMAKE_OSX_ARCHITECTURES=x86_64 for now,
#unless you want to work on the recompilers.
#
#We also ask that you read https://dont-ship.it/.
#
#*********************************************************")
#endif()

if(CMAKE_SYSTEM_NAME STREQUAL "iOS")
    enable_language(Swift)

    # Swift source files
    set(SWIFT_SOURCES
        ${CMAKE_SOURCE_DIR}/../swift/Views/RootView.swift
        ${CMAKE_SOURCE_DIR}/../swift/Views/GameListView.swift
        ${CMAKE_SOURCE_DIR}/../swift/Views/BIOSListView.swift
        ${CMAKE_SOURCE_DIR}/../swift/Views/HelpView.swift
        ${CMAKE_SOURCE_DIR}/../swift/Views/GameScreenView.swift
        ${CMAKE_SOURCE_DIR}/../swift/Views/MetalGameView.swift
        ${CMAKE_SOURCE_DIR}/../swift/Views/EmulatorView.swift
        ${CMAKE_SOURCE_DIR}/../swift/Views/VirtualControllerView.swift
        ${CMAKE_SOURCE_DIR}/../swift/Views/LicenseView.swift
        ${CMAKE_SOURCE_DIR}/../swift/Views/Settings/SettingsRootView.swift
        ${CMAKE_SOURCE_DIR}/../swift/Views/Settings/EmulatorSettingsView.swift
        ${CMAKE_SOURCE_DIR}/../swift/Views/Settings/GraphicsSettingsView.swift
        ${CMAKE_SOURCE_DIR}/../swift/Views/Settings/OverlaySettingsView.swift
        ${CMAKE_SOURCE_DIR}/../swift/Views/Settings/GamepadSettingsView.swift
        ${CMAKE_SOURCE_DIR}/../swift/Views/Settings/VirtualPadSettingsView.swift
        ${CMAKE_SOURCE_DIR}/../swift/Views/Settings/PadLayoutEditView.swift
        ${CMAKE_SOURCE_DIR}/../swift/Models/PadLayoutStore.swift
        ${CMAKE_SOURCE_DIR}/../swift/Models/EmulatorBridge.swift
        ${CMAKE_SOURCE_DIR}/../swift/Models/SwiftUIHost.swift
        ${CMAKE_SOURCE_DIR}/../swift/Models/AppState.swift
        ${CMAKE_SOURCE_DIR}/../swift/Models/SettingsStore.swift
        ${CMAKE_SOURCE_DIR}/../swift/Models/FileImportHandler.swift
    )

    # Generate Info.plist with version from CMake
    configure_file("${CMAKE_SOURCE_DIR}/Info.plist.in" "${CMAKE_BINARY_DIR}/Info.plist" @ONLY)

    add_executable(iPSX2 ios_main.mm iPSX2Bridge.mm ${SWIFT_SOURCES})
    set_target_properties(iPSX2 PROPERTIES
        MACOSX_BUNDLE TRUE
        MACOSX_BUNDLE_GUI_IDENTIFIER "com.otti83.iPSX2"
        MACOSX_BUNDLE_BUNDLE_NAME "iPSX2"
        MACOSX_BUNDLE_BUNDLE_VERSION "${IPSX2_BUILD_NUMBER}"
        MACOSX_BUNDLE_SHORT_VERSION_STRING "${IPSX2_VERSION}"
        MACOSX_BUNDLE_INFO_PLIST "${CMAKE_BINARY_DIR}/Info.plist"
        MACOSX_BUNDLE_EXECUTABLE_NAME "iPSX2"
        XCODE_ATTRIBUTE_PRODUCT_BUNDLE_IDENTIFIER "com.otti83.iPSX2"
        XCODE_ATTRIBUTE_TARGETED_DEVICE_FAMILY "1,2" # 1=iPhone, 2=iPad
        XCODE_ATTRIBUTE_IPHONEOS_DEPLOYMENT_TARGET "18.0"
        XCODE_ATTRIBUTE_SDKROOT "${CMAKE_OSX_SYSROOT}"
        XCODE_ATTRIBUTE_CODE_SIGNING_REQUIRED "NO"
        XCODE_ATTRIBUTE_CODE_SIGN_STYLE "Manual"
        XCODE_ATTRIBUTE_CODE_SIGN_IDENTITY ""
        XCODE_ATTRIBUTE_DEVELOPMENT_TEAM ""
        XCODE_ATTRIBUTE_PROVISIONING_PROFILE_SPECIFIER ""
        XCODE_ATTRIBUTE_CODE_SIGN_ENTITLEMENTS "${CMAKE_SOURCE_DIR}/Entitlements.plist"
        XCODE_ATTRIBUTE_SWIFT_OBJC_BRIDGING_HEADER "${CMAKE_SOURCE_DIR}/iPSX2-Bridging-Header.h"
        XCODE_ATTRIBUTE_SWIFT_VERSION "6.0"
        XCODE_ATTRIBUTE_CLANG_ENABLE_MODULES "YES"
        XCODE_ATTRIBUTE_ASSETCATALOG_COMPILER_APPICON_NAME "AppIcon"
    )
    # [P53] Asset catalog (app icon + splash image)
    set(ASSET_CATALOG "${CMAKE_SOURCE_DIR}/../assets/Assets.xcassets")
    target_sources(iPSX2 PRIVATE "${ASSET_CATALOG}")
    set_source_files_properties("${ASSET_CATALOG}" PROPERTIES MACOSX_PACKAGE_LOCATION Resources)
    target_link_libraries(iPSX2 PRIVATE PCSX2 SDL3::SDL3)
    # Swift runtime link paths for device builds
    set_target_properties(iPSX2 PROPERTIES
        XCODE_ATTRIBUTE_LD_RUNPATH_SEARCH_PATHS "@executable_path/Frameworks /usr/lib/swift"
        XCODE_ATTRIBUTE_LIBRARY_SEARCH_PATHS "$(inherited) $(TOOLCHAIN_DIR)/usr/lib/swift/$(PLATFORM_NAME) /usr/lib/swift"
    )
    # Exclude -pipe and other C++ flags from Swift compilation
    set_target_properties(iPSX2 PROPERTIES
        XCODE_ATTRIBUTE_OTHER_SWIFT_FLAGS ""
    )
    # Remove -pipe from Swift by adding it only to C/CXX
    target_compile_options(iPSX2 PRIVATE $<$<COMPILE_LANGUAGE:C,CXX,OBJC,OBJCXX>:-pipe>)
    
    # Needs to link SDL3? PCSX2 links it, so transitive linking should work if PUBLIC/INTERFACE used.
    # PCSX2 uses PRIVATE link for SDL3? 
    # Let's check. If PRIVATE, we might need to link SDL3 again or make PCSX2 link PUBLIC.
    # For now assume it works or we link SDL3::SDL3.
    # We need headers.
    target_link_libraries(iPSX2 PRIVATE "-framework UIKit" "-framework Metal" "-framework MetalKit" "-framework QuartzCore" "-framework CoreText" "-framework CoreGraphics")
	# Git short hash for BUILD_ID
	execute_process(
		COMMAND git rev-parse --short HEAD
		WORKING_DIRECTORY "${CMAKE_SOURCE_DIR}"
		OUTPUT_VARIABLE iPSX2_GIT_HASH
		OUTPUT_STRIP_TRAILING_WHITESPACE
		ERROR_QUIET
	)
	if(NOT iPSX2_GIT_HASH)
		set(iPSX2_GIT_HASH "unknown")
	endif()
	target_compile_definitions(iPSX2 PRIVATE PCSX2_NO_PCAP=1 iPSX2_GIT_HASH="${iPSX2_GIT_HASH}" IPSX2_VERSION_STR="${IPSX2_VERSION}")
    target_include_directories(iPSX2 PRIVATE
        ${CMAKE_SOURCE_DIR}
        ${CMAKE_SOURCE_DIR}/common
        ${CMAKE_SOURCE_DIR}/pcsx2
        ${CMAKE_SOURCE_DIR}/pcsx2/GS/Renderers/Metal
        ${CMAKE_SOURCE_DIR}/3rdparty/SDL3/include
        ${CMAKE_SOURCE_DIR}/3rdparty/fmt/include
        ${CMAKE_SOURCE_DIR}/3rdparty/fast_float/include
        ${CMAKE_SOURCE_DIR}/3rdparty/vixl/include
        ${CMAKE_SOURCE_DIR}/3rdparty/include
        ${CMAKE_SOURCE_DIR}/3rdparty/vulkan/include
        ${CMAKE_SOURCE_DIR}/3rdparty/glslang/glslang
        ${CMAKE_SOURCE_DIR}/3rdparty/glslang/include
        ${CMAKE_BINARY_DIR}/common/include
        ${CMAKE_BINARY_DIR}/pcsx2
        ${CMAKE_SOURCE_DIR}/3rdparty/simpleini/include
        ${CMAKE_SOURCE_DIR}/3rdparty/imgui/include
        ${CMAKE_SOURCE_DIR}/3rdparty/rapidyaml/include
        ${CMAKE_SOURCE_DIR}/3rdparty/cpuinfo/include
        ${CMAKE_SOURCE_DIR}/3rdparty/libchdr/include
        ${CMAKE_SOURCE_DIR}/3rdparty/libzip/lib
        ${CMAKE_BINARY_DIR}/3rdparty/libzip
        ${CMAKE_SOURCE_DIR}/3rdparty/cubeb/include
        ${CMAKE_SOURCE_DIR}/3rdparty/rcheevos/include
        ${CMAKE_SOURCE_DIR}/3rdparty/freesurround/include
        ${CMAKE_SOURCE_DIR}/3rdparty/freetype/include
        ${CMAKE_SOURCE_DIR}/3rdparty/plutosvg1/source
        ${CMAKE_SOURCE_DIR}/3rdparty/plutosvg1/plutovg/include
        ${CMAKE_BINARY_DIR}/3rdparty/freetype/include
        ${CMAKE_SOURCE_DIR}/3rdparty/soundtouch/soundtouch
        ${CMAKE_SOURCE_DIR}/3rdparty/lz4/lz4/lib
        ${CMAKE_SOURCE_DIR}/3rdparty/lzma/include
        ${CMAKE_SOURCE_DIR}/3rdparty/zstd/zstd/lib
        ${CMAKE_SOURCE_DIR}/3rdparty/demangler/include
        ${CMAKE_SOURCE_DIR}/3rdparty/ccc/src
        ${CMAKE_BINARY_DIR}/3rdparty/SDL3/include-revision
    )
    
    set_target_properties(iPSX2 PROPERTIES
        XCODE_ATTRIBUTE_MTL_HEADER_SEARCH_PATHS "${CMAKE_SOURCE_DIR}/pcsx2/GS/Renderers/Metal ${CMAKE_SOURCE_DIR}/../assets"
    )

    # Add Metal shaders directly to the app target to ensure they are compiled into default.metallib
    file(GLOB METAL_SHADERS "${CMAKE_SOURCE_DIR}/pcsx2/GS/Renderers/Metal/*.metal")
    message(STATUS "Found Metal Shaders: ${METAL_SHADERS}")
    
    # Add Fonts to resources
    file(GLOB FONTS "${CMAKE_SOURCE_DIR}/../assets/resources/fonts/*.ttf" "${CMAKE_SOURCE_DIR}/../assets/resources/fonts/*.otf")
    message(STATUS "Found Fonts: ${FONTS}")

    target_sources(iPSX2 PRIVATE ${METAL_SHADERS} ${FONTS})
    
    # Ensure Metal is compiled for Simulator
    set_source_files_properties(${METAL_SHADERS} PROPERTIES 
        XCODE_EXPLICIT_FILE_TYPE "sourcecode.metal"
        MACOSX_PACKAGE_LOCATION Resources
    )
    
    # Consolidate font resources into the "fonts" subdirectory of the bundle resources
    set_source_files_properties(${FONTS} PROPERTIES
        MACOSX_PACKAGE_LOCATION Resources/fonts
    )

    # Metal debug info: only for Debug builds
    set_target_properties(iPSX2 PROPERTIES
        XCODE_ATTRIBUTE_MTL_ENABLE_DEBUG_INFO "$<IF:$<CONFIG:Debug>,INCLUDE_SOURCE,>"
    )
    
    
    # Bundle resources, shaders, etc.
    # setup_main_executable(iPSX2)
    
    # Override the executable name directly in properties again to be absolutely sure
    set_target_properties(iPSX2 PROPERTIES
        MACOSX_BUNDLE_EXECUTABLE_NAME "iPSX2"
        OUTPUT_NAME "iPSX2"
    )
endif()
