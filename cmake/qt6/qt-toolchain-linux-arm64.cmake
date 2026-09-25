# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2026 OpenKaryon
#
# CMake toolchain file for Qt 6 cross-compilation
# Target: Linux ARM64 (aarch64-linux-gnu)
# Host: Linux x86_64
# Toolchain: GCC cross-compiler with ARM64 sysroot (Debian multiarch)

set(CMAKE_SYSTEM_NAME Linux)
set(CMAKE_SYSTEM_PROCESSOR aarch64)

set(TOOLCHAIN_PREFIX aarch64-linux-gnu)

# Sysroot path - contains ARM64 libraries and headers
set(CMAKE_SYSROOT /opt/sysroot-arm64)

set(CMAKE_C_COMPILER ${TOOLCHAIN_PREFIX}-gcc)
set(CMAKE_CXX_COMPILER ${TOOLCHAIN_PREFIX}-g++)

set(CMAKE_AR ${TOOLCHAIN_PREFIX}-ar)
set(CMAKE_RANLIB ${TOOLCHAIN_PREFIX}-ranlib)
set(CMAKE_STRIP ${TOOLCHAIN_PREFIX}-strip)
set(CMAKE_NM ${TOOLCHAIN_PREFIX}-nm)
set(CMAKE_OBJCOPY ${TOOLCHAIN_PREFIX}-objcopy)
set(CMAKE_OBJDUMP ${TOOLCHAIN_PREFIX}-objdump)
set(CMAKE_LINKER ${TOOLCHAIN_PREFIX}-ld)

# PKG_CONFIG for cross-compilation
set(ENV{PKG_CONFIG_PATH} "")
set(ENV{PKG_CONFIG_LIBDIR} "${CMAKE_SYSROOT}/usr/lib/aarch64-linux-gnu/pkgconfig:${CMAKE_SYSROOT}/usr/share/pkgconfig")
set(ENV{PKG_CONFIG_SYSROOT_DIR} "${CMAKE_SYSROOT}")

set(CMAKE_FIND_ROOT_PATH ${CMAKE_SYSROOT} /opt/qt6-linux-arm64)
set(CMAKE_FIND_ROOT_PATH_MODE_PROGRAM NEVER)
set(CMAKE_FIND_ROOT_PATH_MODE_LIBRARY ONLY)
set(CMAKE_FIND_ROOT_PATH_MODE_INCLUDE ONLY)
set(CMAKE_FIND_ROOT_PATH_MODE_PACKAGE ONLY)

# Compiler flags for ARM64
set(QT_COMPILER_FLAGS "-march=armv8-a --sysroot=${CMAKE_SYSROOT}")
set(QT_COMPILER_FLAGS_RELEASE "-O2 -DNDEBUG")
set(QT_LINKER_FLAGS "-static-libgcc -static-libstdc++ --sysroot=${CMAKE_SYSROOT}")

set(CMAKE_C_FLAGS "${CMAKE_C_FLAGS} ${QT_COMPILER_FLAGS}")
set(CMAKE_CXX_FLAGS "${CMAKE_CXX_FLAGS} ${QT_COMPILER_FLAGS}")
set(CMAKE_C_FLAGS_RELEASE "${QT_COMPILER_FLAGS_RELEASE}")
set(CMAKE_CXX_FLAGS_RELEASE "${QT_COMPILER_FLAGS_RELEASE}")
set(CMAKE_SHARED_LINKER_FLAGS "${CMAKE_SHARED_LINKER_FLAGS} ${QT_LINKER_FLAGS}")
set(CMAKE_EXE_LINKER_FLAGS "${CMAKE_EXE_LINKER_FLAGS} ${QT_LINKER_FLAGS}")

# Disable checks that fail during cross-compilation
set(CMAKE_CROSSCOMPILING_EMULATOR "")
set(QT_FORCE_FIND_TOOLS ON)
