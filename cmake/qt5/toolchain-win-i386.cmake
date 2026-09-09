# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2026 OpenKaryon
#
# CMake toolchain for the Windows i386 target (MinGW-w64, GCC).
#
# qmake took all of this from the mkspec and -device-option CROSS_COMPILE.
# CMake has no equivalent, so the same facts are restated here: this is what
# `-xplatform win32-g++ -device-option CROSS_COMPILE=i686-w64-mingw32-` in
# docker/windows/i386/Dockerfile means, expressed for CMake.
#
# Setting CMAKE_SYSTEM_NAME is what makes this a cross build as far as CMake is
# concerned, and it is also what makes WIN32 true - which tests/cmake/SmokeApp.cmake
# keys the -fno-ipa-ra workaround off. Do not drop it.

set(CMAKE_SYSTEM_NAME Windows)
set(CMAKE_SYSTEM_PROCESSOR i686)

set(SMOKE_TOOLCHAIN_PREFIX i686-w64-mingw32)

set(CMAKE_C_COMPILER   ${SMOKE_TOOLCHAIN_PREFIX}-gcc)
set(CMAKE_CXX_COMPILER ${SMOKE_TOOLCHAIN_PREFIX}-g++)
set(CMAKE_RC_COMPILER  ${SMOKE_TOOLCHAIN_PREFIX}-windres)

# Libraries and headers from the cross root, the installed Qt and OpenSSL
# (libQt5Network.prl names -lssl -lcrypto, which Qt5NetworkConfig.cmake
# resolves with find_library()); programs (moc, rcc, uic) from the host.
set(CMAKE_FIND_ROOT_PATH
    /usr/${SMOKE_TOOLCHAIN_PREFIX}
    /usr/local/Qt-5.15
    /opt/openssl-3)

# OpenSSL installs into lib64/, which a cross find_library() may not search.
list(APPEND CMAKE_LIBRARY_PATH /opt/openssl-3/lib64 /opt/openssl-3/lib)
set(CMAKE_FIND_ROOT_PATH_MODE_PROGRAM NEVER)
set(CMAKE_FIND_ROOT_PATH_MODE_LIBRARY ONLY)
set(CMAKE_FIND_ROOT_PATH_MODE_INCLUDE ONLY)
set(CMAKE_FIND_ROOT_PATH_MODE_PACKAGE ONLY)
