# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2026 OpenKaryon
#
# CMake toolchain file for Qt 6 for Linux arm64: RHEL/CentOS 7 aarch64
# (glibc 2.17) from an x86_64 host. The compilers are the wrappers of
# scripts/build/qt6-linux-arm64 (Debian's aarch64 GCC 11, the CentOS 7 sysroot
# and Developer Toolset 10's C++ library).

set(CMAKE_SYSTEM_NAME Linux)
set(CMAKE_SYSTEM_PROCESSOR aarch64)

set(CMAKE_SYSROOT /opt/sysroot-arm64)

set(CMAKE_C_COMPILER /opt/cross/bin/aarch64-centos7-gcc)
set(CMAKE_CXX_COMPILER /opt/cross/bin/aarch64-centos7-g++)

set(TOOLCHAIN_PREFIX aarch64-linux-gnu)
set(CMAKE_AR ${TOOLCHAIN_PREFIX}-ar)
set(CMAKE_RANLIB ${TOOLCHAIN_PREFIX}-ranlib)
set(CMAKE_STRIP ${TOOLCHAIN_PREFIX}-strip)
set(CMAKE_NM ${TOOLCHAIN_PREFIX}-nm)
set(CMAKE_OBJCOPY ${TOOLCHAIN_PREFIX}-objcopy)
set(CMAKE_OBJDUMP ${TOOLCHAIN_PREFIX}-objdump)
set(CMAKE_LINKER ${TOOLCHAIN_PREFIX}-ld)

# pkg-config reads the sysroot's .pc files, the Wayland stubs' first.
set(ENV{PKG_CONFIG_PATH} "")
set(ENV{PKG_CONFIG_LIBDIR} "${CMAKE_SYSROOT}/usr/local/lib/pkgconfig:${CMAKE_SYSROOT}/usr/lib64/pkgconfig:${CMAKE_SYSROOT}/usr/share/pkgconfig")
set(ENV{PKG_CONFIG_SYSROOT_DIR} "${CMAKE_SYSROOT}")

set(CMAKE_FIND_ROOT_PATH ${CMAKE_SYSROOT} /opt/qt6-linux-arm64 /opt/openssl-3)
set(CMAKE_FIND_ROOT_PATH_MODE_PROGRAM NEVER)
set(CMAKE_FIND_ROOT_PATH_MODE_LIBRARY ONLY)
set(CMAKE_FIND_ROOT_PATH_MODE_INCLUDE ONLY)
set(CMAKE_FIND_ROOT_PATH_MODE_PACKAGE ONLY)

# The scanner that writes code for RHEL 7's libwayland (see its wrapper).
set(WaylandScanner_EXECUTABLE /opt/cross/bin/wayland-scanner CACHE FILEPATH "")

set(QT_FORCE_FIND_TOOLS ON)
