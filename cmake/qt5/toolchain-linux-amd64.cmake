# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2026 OpenKaryon
#
# Ubuntu 10.04 Lucid, amd64: the kit's lucid-gcc/lucid-g++ wrappers point
# Ubuntu 16.04's GCC at the pinned Lucid sysroot (/work/sysroot) and the
# static libstdc++ rebuilt against its glibc 2.11. Qt's CMake packages carry
# absolute paths into that sysroot, so only the compilers and the library
# search path need setting. The binaries do not run in the build container
# (see docker/qt5/linux/amd64/Dockerfile), hence the explicit
# cross-compiling flag.
set(CMAKE_SYSTEM_NAME Linux)
# The compiler's own target, not uname: the i386 image runs on a 64-bit kernel.
execute_process(COMMAND gcc -dumpmachine OUTPUT_VARIABLE SMOKE_LUCID_TRIPLE OUTPUT_STRIP_TRAILING_WHITESPACE)
string(REGEX REPLACE "-.*" "" SMOKE_LUCID_CPU "${SMOKE_LUCID_TRIPLE}")
set(CMAKE_SYSTEM_PROCESSOR ${SMOKE_LUCID_CPU})
set(CMAKE_CROSSCOMPILING ON)
set(CMAKE_C_COMPILER /work/toolchain/bin/lucid-gcc)
set(CMAKE_CXX_COMPILER /work/toolchain/bin/lucid-g++)
set(CMAKE_EXE_LINKER_FLAGS_INIT "-static-libgcc -static-libstdc++")
list(APPEND CMAKE_LIBRARY_PATH /work/sysroot/usr/local/lib /work/sysroot/usr/lib /work/sysroot/lib)
list(APPEND CMAKE_INCLUDE_PATH /work/sysroot/usr/local/include /work/sysroot/usr/include)
