# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2026 OpenKaryon

set(CMAKE_SYSTEM_NAME Linux)
if("$ENV{LUCID_ARCH}" STREQUAL "i386")
    set(CMAKE_SYSTEM_PROCESSOR i686)
else()
    set(CMAKE_SYSTEM_PROCESSOR x86_64)
endif()
set(CMAKE_SYSROOT /opt/sysroot-lucid)
set(CMAKE_C_COMPILER /opt/llvm-runtime-lucid/bin/target-cc)
set(CMAKE_CXX_COMPILER /opt/llvm-runtime-lucid/bin/target-cxx)
set(CMAKE_AR /opt/llvm-21/bin/llvm-ar)
set(CMAKE_RANLIB /opt/llvm-21/bin/llvm-ranlib)
set(CMAKE_EXE_LINKER_FLAGS_INIT -no-pie)
list(APPEND CMAKE_LIBRARY_PATH /opt/sysroot-lucid/usr/local/lib /opt/sysroot-lucid/usr/lib /opt/sysroot-lucid/lib)
