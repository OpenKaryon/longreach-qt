# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2026 OpenKaryon
#
# Ubuntu 14.04 arm64 from an x86_64 host: the kit's aarch64-trusty-gcc/-g++
# wrappers point Ubuntu 16.04's aarch64 GCC 5 at the 14.04 sysroot
# (/work/sysroot). Qt's CMake packages carry absolute paths into that
# sysroot, so only the compilers and the library search path need setting.
set(CMAKE_SYSTEM_NAME Linux)
set(CMAKE_SYSTEM_PROCESSOR aarch64)
set(CMAKE_CROSSCOMPILING ON)
set(CMAKE_C_COMPILER /work/toolchain/bin/aarch64-trusty-gcc)
set(CMAKE_CXX_COMPILER /work/toolchain/bin/aarch64-trusty-g++)
set(CMAKE_AR /usr/bin/aarch64-linux-gnu-ar)
set(CMAKE_RANLIB /usr/bin/aarch64-linux-gnu-ranlib)
set(CMAKE_EXE_LINKER_FLAGS_INIT "-static-libgcc -static-libstdc++")
list(APPEND CMAKE_LIBRARY_PATH /work/sysroot/usr/local/lib /work/sysroot/usr/lib/aarch64-linux-gnu
     /work/sysroot/usr/lib /work/sysroot/lib/aarch64-linux-gnu)
list(APPEND CMAKE_INCLUDE_PATH /work/sysroot/usr/local/include /work/sysroot/usr/include)
