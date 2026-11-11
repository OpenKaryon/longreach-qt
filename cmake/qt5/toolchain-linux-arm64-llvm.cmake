# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2026 OpenKaryon

set(CMAKE_SYSTEM_NAME Linux)
set(CMAKE_SYSTEM_PROCESSOR aarch64)
set(CMAKE_SYSROOT /work/sysroot)
set(CMAKE_C_COMPILER /opt/qt5-llvm/bin/target-cc)
set(CMAKE_CXX_COMPILER /opt/qt5-llvm/bin/target-cxx)
set(CMAKE_AR /opt/llvm-21/bin/llvm-ar)
set(CMAKE_RANLIB /opt/llvm-21/bin/llvm-ranlib)
set(CMAKE_EXE_LINKER_FLAGS_INIT -no-pie)
list(APPEND CMAKE_LIBRARY_PATH
    /work/sysroot/usr/local/lib
    /work/sysroot/usr/lib/aarch64-linux-gnu
    /work/sysroot/usr/lib
    /work/sysroot/lib/aarch64-linux-gnu
)
