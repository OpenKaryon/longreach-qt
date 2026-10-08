# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2026 OpenKaryon
#
# CMake toolchain for the macOS i386 target (Mac OS X 10.6, 32-bit Intel).
#
# The counterpart of `-device-option CROSS_COMPILE=i386-apple-darwin10-
# QMAKE_APPLE_DEVICE_ARCHS=i386` in docker/qt5/macos/i386/Dockerfile. The
# compiler drivers are the wrappers scripts/build/qt5-macos/build-i386-toolchain.sh
# installs: they compile against the same SDK as the x86_64 target and link
# against the i386 libraries of the 10.7 SDK, so this file only names them and
# otherwise matches toolchain-macos-amd64.cmake.

set(CMAKE_SYSTEM_NAME Darwin)
set(CMAKE_SYSTEM_PROCESSOR i386)
set(CMAKE_OSX_ARCHITECTURES i386)

set(SMOKE_PREFIX i386-apple-darwin10-)
set(CMAKE_C_COMPILER   /usr/local/osxcross/bin/${SMOKE_PREFIX}clang)
set(CMAKE_CXX_COMPILER /usr/local/osxcross/bin/${SMOKE_PREFIX}clang++)
set(CMAKE_AR           /usr/local/osxcross/bin/${SMOKE_PREFIX}ar)
set(CMAKE_RANLIB       /usr/local/osxcross/bin/${SMOKE_PREFIX}ranlib)
set(CMAKE_INSTALL_NAME_TOOL /usr/local/osxcross/bin/${SMOKE_PREFIX}install_name_tool)
if(NOT EXISTS "${CMAKE_CXX_COMPILER}")
    message(FATAL_ERROR "${CMAKE_CXX_COMPILER} is missing - this toolchain only works "
                        "inside the macOS i386 build image.")
endif()

if(DEFINED ENV{SMOKE_QT_PREFIX})
    set(SMOKE_QT_PREFIX "$ENV{SMOKE_QT_PREFIX}")
else()
    set(SMOKE_QT_PREFIX /usr/local/Qt-5.15)
endif()

# The deployment target Qt was built for, from the installed macx.conf.
file(STRINGS ${SMOKE_QT_PREFIX}/mkspecs/common/macx.conf SMOKE_MACOS_TARGET
     REGEX "^QMAKE_MACOSX_DEPLOYMENT_TARGET *=")
string(REGEX REPLACE "^.*= *" "" SMOKE_MACOS_TARGET "${SMOKE_MACOS_TARGET}")
if(NOT SMOKE_MACOS_TARGET)
    message(FATAL_ERROR "no QMAKE_MACOSX_DEPLOYMENT_TARGET in the installed macx.conf")
endif()
set(CMAKE_OSX_DEPLOYMENT_TARGET "${SMOKE_MACOS_TARGET}")

# As for x86_64 (patches/qt5/macos/24-no-implicit-dylibs.patch).
string(APPEND CMAKE_EXE_LINKER_FLAGS_INIT " -Wl,-no_implicit_dylibs")
string(APPEND CMAKE_SHARED_LINKER_FLAGS_INIT " -Wl,-no_implicit_dylibs")
string(APPEND CMAKE_MODULE_LINKER_FLAGS_INIT " -Wl,-no_implicit_dylibs")

# The SDK Qt was configured against (see toolchain-macos-amd64.cmake for why
# the sysroot must be set at all). The wrappers link against the 10.7 SDK.
file(GLOB SMOKE_OSX_SDKS /usr/local/osxcross/SDK/MacOSX1[1-9]*.sdk)
list(SORT SMOKE_OSX_SDKS)
list(REVERSE SMOKE_OSX_SDKS)
list(GET SMOKE_OSX_SDKS 0 CMAKE_OSX_SYSROOT)
if(NOT EXISTS "${CMAKE_OSX_SYSROOT}")
    message(FATAL_ERROR "no macOS SDK under /usr/local/osxcross/SDK")
endif()

if(DEFINED ENV{SMOKE_OPENSSL_PREFIX})
    set(SMOKE_OPENSSL "$ENV{SMOKE_OPENSSL_PREFIX}")
else()
    set(SMOKE_OPENSSL /opt/openssl-3)
endif()

set(CMAKE_FIND_ROOT_PATH
    ${CMAKE_OSX_SYSROOT}
    /usr/local/osxcross
    ${SMOKE_QT_PREFIX}
    ${SMOKE_OPENSSL})
list(APPEND CMAKE_LIBRARY_PATH ${SMOKE_OPENSSL}/lib)

set(CMAKE_FIND_ROOT_PATH_MODE_PROGRAM NEVER)
set(CMAKE_FIND_ROOT_PATH_MODE_LIBRARY ONLY)
set(CMAKE_FIND_ROOT_PATH_MODE_INCLUDE ONLY)
set(CMAKE_FIND_ROOT_PATH_MODE_PACKAGE ONLY)
