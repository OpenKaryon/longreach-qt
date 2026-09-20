# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2026 OpenKaryon
#
# CMake toolchain for the Windows ARM64 target (LLVM-MinGW, clang).
#
# The Qt 5 counterpart of `-xplatform win32-clang-g++ -device-option
# CROSS_COMPILE=aarch64-w64-mingw32-` in docker/windows/arm64/Dockerfile.
#
# Unlike the other two Windows targets this one is clang, not GCC, and that has
# one consequence worth stating: clang has no -fipa-ra, so the miscompile
# workaround the GCC targets need does not apply and is not set. See
# tests/cmake/SmokeApp.cmake, which keys that flag off the compiler id rather
# than off the platform for exactly this reason.
#
# Setting CMAKE_SYSTEM_NAME is what makes this a cross build as far as CMake is
# concerned, and it is also what makes WIN32 true, which the suite uses to
# decide on -static. Do not drop it.

set(CMAKE_SYSTEM_NAME Windows)
set(CMAKE_SYSTEM_PROCESSOR aarch64)

set(SMOKE_TOOLCHAIN_PREFIX aarch64-w64-mingw32)

set(CMAKE_C_COMPILER   ${SMOKE_TOOLCHAIN_PREFIX}-clang)
set(CMAKE_CXX_COMPILER ${SMOKE_TOOLCHAIN_PREFIX}-clang++)
set(CMAKE_RC_COMPILER  ${SMOKE_TOOLCHAIN_PREFIX}-windres)

# LLVM-MinGW keeps its target sysroot inside the toolchain rather than under
# /usr, which is why this differs from the GCC targets.
set(CMAKE_FIND_ROOT_PATH
    /opt/llvm-mingw/${SMOKE_TOOLCHAIN_PREFIX}
    /usr/local/Qt-5.15)

set(CMAKE_FIND_ROOT_PATH_MODE_PROGRAM NEVER)
set(CMAKE_FIND_ROOT_PATH_MODE_LIBRARY ONLY)
set(CMAKE_FIND_ROOT_PATH_MODE_INCLUDE ONLY)
set(CMAKE_FIND_ROOT_PATH_MODE_PACKAGE ONLY)
