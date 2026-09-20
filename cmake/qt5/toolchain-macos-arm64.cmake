# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2026 OpenKaryon
#
# CMake toolchain for the macOS ARM64 target (osxcross + Clang).
#
# The Qt 5 counterpart of `-xplatform macx-clang -device-option
# CROSS_COMPILE="$(cat /opt/osxcross-prefix)"` in docker/macos/arm64/Dockerfile.
#
# The compiler prefix is not a constant. osxcross names its wrappers after the
# Darwin version of whichever SDK was unpacked - arm64-apple-darwin20.4- for
# the SDK this kit pins today - and the image writes the resolved prefix to
# /opt/osxcross-prefix rather than hardcoding it anywhere. Reading that file is
# what keeps this toolchain working across an SDK bump, exactly as the configure
# line does.
#
# Setting CMAKE_SYSTEM_NAME to Darwin is what makes CMake's APPLE true, which
# the suite uses to skip the archive-group flags that Apple's ld64 does not
# understand. See tests/CMakeLists.txt.

set(CMAKE_SYSTEM_NAME Darwin)
set(CMAKE_SYSTEM_PROCESSOR arm64)

if(NOT EXISTS /opt/osxcross-prefix)
    message(FATAL_ERROR
        "/opt/osxcross-prefix is missing - this toolchain only works inside the "
        "macOS build image, which writes it when osxcross is built.")
endif()
file(READ /opt/osxcross-prefix SMOKE_OSXCROSS_PREFIX)
string(STRIP "${SMOKE_OSXCROSS_PREFIX}" SMOKE_OSXCROSS_PREFIX)

set(CMAKE_C_COMPILER   ${SMOKE_OSXCROSS_PREFIX}clang)
set(CMAKE_CXX_COMPILER ${SMOKE_OSXCROSS_PREFIX}clang++)
set(CMAKE_AR           ${SMOKE_OSXCROSS_PREFIX}ar)
set(CMAKE_RANLIB       ${SMOKE_OSXCROSS_PREFIX}ranlib)
set(CMAKE_INSTALL_NAME_TOOL ${SMOKE_OSXCROSS_PREFIX}install_name_tool)

# macOS 11.0, where Apple silicon starts.
set(CMAKE_OSX_DEPLOYMENT_TARGET "11.0")

# No implicit dylibs, as patches/qt5/macos/24 does for qmake.
string(APPEND CMAKE_EXE_LINKER_FLAGS_INIT " -Wl,-no_implicit_dylibs")
string(APPEND CMAKE_SHARED_LINKER_FLAGS_INIT " -Wl,-no_implicit_dylibs")
string(APPEND CMAKE_MODULE_LINKER_FLAGS_INIT " -Wl,-no_implicit_dylibs")

# The SDK, where the frameworks are: without it Qt5CoreConfig.cmake cannot
# resolve the -framework entries in libQt5Core.prl. Found, not hardcoded.
file(GLOB SMOKE_OSX_SDKS /usr/local/osxcross/SDK/MacOSX*.sdk)
list(SORT SMOKE_OSX_SDKS)
list(REVERSE SMOKE_OSX_SDKS)
list(GET SMOKE_OSX_SDKS 0 CMAKE_OSX_SYSROOT)
if(NOT EXISTS "${CMAKE_OSX_SYSROOT}")
    message(FATAL_ERROR "no macOS SDK under /usr/local/osxcross/SDK")
endif()

set(CMAKE_FIND_ROOT_PATH
    ${CMAKE_OSX_SYSROOT}
    /usr/local/osxcross
    /usr/local/Qt-5.15)

set(CMAKE_FIND_ROOT_PATH_MODE_PROGRAM NEVER)
set(CMAKE_FIND_ROOT_PATH_MODE_LIBRARY ONLY)
set(CMAKE_FIND_ROOT_PATH_MODE_INCLUDE ONLY)
set(CMAKE_FIND_ROOT_PATH_MODE_PACKAGE ONLY)
