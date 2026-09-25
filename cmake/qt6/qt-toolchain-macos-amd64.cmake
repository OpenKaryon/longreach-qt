# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2026 OpenKaryon
#
# qt-toolchain-macos-amd64.cmake

# Target: macOS x86_64
set(CMAKE_SYSTEM_NAME Darwin)
set(CMAKE_SYSTEM_PROCESSOR x86_64)

if (NOT DEFINED OSXCROSS_ROOT)
    if (DEFINED ENV{OSXCROSS_ROOT})
        set(OSXCROSS_ROOT "$ENV{OSXCROSS_ROOT}")
    else()
        set(OSXCROSS_ROOT "/opt/osxcross")
    endif()
endif()

# osxcross names its wrappers after the SDK's Darwin version. Discover the
# actual wrapper so switching SDKs does not leave a stale Darwin 23 compiler.
file(GLOB _OSXCROSS_C_COMPILERS
    "${OSXCROSS_ROOT}/target/bin/x86_64-apple-darwin*-clang")
# The osxcross CMake launcher also matches the glob, but it is a command
# launcher and cannot compile a C source passed with -c.
list(FILTER _OSXCROSS_C_COMPILERS EXCLUDE REGEX "-cmake-clang$")
list(SORT _OSXCROSS_C_COMPILERS)
if (NOT _OSXCROSS_C_COMPILERS)
    message(FATAL_ERROR "osxcross x86_64 clang wrapper not found")
endif()
list(GET _OSXCROSS_C_COMPILERS -1 _OSXCROSS_C_COMPILER)
if (NOT CMAKE_C_COMPILER)
    set(CMAKE_C_COMPILER "${_OSXCROSS_C_COMPILER}")
endif()
if (NOT CMAKE_CXX_COMPILER)
    set(CMAKE_CXX_COMPILER "${_OSXCROSS_C_COMPILER}++")
endif()
get_filename_component(_OSXCROSS_COMPILER_NAME "${_OSXCROSS_C_COMPILER}" NAME)
string(REGEX REPLACE "-clang$" "" _OSXCROSS_TARGET "${_OSXCROSS_COMPILER_NAME}")
set(CMAKE_C_COMPILER_TARGET "${_OSXCROSS_TARGET}")
set(CMAKE_CXX_COMPILER_TARGET "${_OSXCROSS_TARGET}")

if (NOT DEFINED OSXCROSS_SDK_VERSION)
    if (DEFINED ENV{OSXCROSS_SDK_VERSION})
        set(OSXCROSS_SDK_VERSION "$ENV{OSXCROSS_SDK_VERSION}" CACHE STRING "macOS SDK version used by osxcross")
    else()
        set(OSXCROSS_SDK_VERSION "14.0" CACHE STRING "macOS SDK version used by osxcross")
    endif()
endif()

# The SDK in osxcross' usual locations.
set(_CANDIDATE_SYSROOTS
    "${OSXCROSS_ROOT}/SDK/MacOSX${OSXCROSS_SDK_VERSION}.sdk"
    "${OSXCROSS_ROOT}/SDK/MacOSX.sdk"
    "${OSXCROSS_ROOT}/target/SDK/MacOSX${OSXCROSS_SDK_VERSION}.sdk"
    "${OSXCROSS_ROOT}/target/SDK/MacOSX.sdk"
)

foreach(_sr ${_CANDIDATE_SYSROOTS})
    if (EXISTS "${_sr}")
        set(CMAKE_OSX_SYSROOT "${_sr}" CACHE PATH "macOS SDK sysroot" FORCE)
        break()
    endif()
endforeach()

if (NOT CMAKE_OSX_SYSROOT)
    message(WARNING
        "osxcross: could not find SDK under "
        "${OSXCROSS_ROOT}/SDK or ${OSXCROSS_ROOT}/target/SDK; "
        "continuing without explicit CMAKE_OSX_SYSROOT"
    )
endif()

# Architecture and minimum macOS version
set(CMAKE_OSX_ARCHITECTURES "x86_64" CACHE STRING "" FORCE)
if (NOT CMAKE_OSX_DEPLOYMENT_TARGET)
    if (DEFINED ENV{MACOSX_DEPLOYMENT_TARGET})
        set(CMAKE_OSX_DEPLOYMENT_TARGET "$ENV{MACOSX_DEPLOYMENT_TARGET}" CACHE STRING "macOS deployment target")
    else()
        set(CMAKE_OSX_DEPLOYMENT_TARGET "10.13" CACHE STRING "macOS deployment target")
    endif()
endif()

set(CMAKE_FIND_ROOT_PATH
    "${OSXCROSS_ROOT}/target"
    ${CMAKE_OSX_SYSROOT}
)

set(CMAKE_FIND_ROOT_PATH_MODE_PROGRAM NEVER)
set(CMAKE_FIND_ROOT_PATH_MODE_LIBRARY ONLY)
set(CMAKE_FIND_ROOT_PATH_MODE_INCLUDE ONLY)
set(CMAKE_FIND_ROOT_PATH_MODE_PACKAGE ONLY)

# GUI applications are built as .app bundles (without console window)
set(CMAKE_MACOSX_BUNDLE TRUE)
