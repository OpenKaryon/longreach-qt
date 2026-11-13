# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2026 OpenKaryon
set(CMAKE_SYSTEM_NAME Windows)
set(CMAKE_SYSTEM_VERSION 5.2)
set(CMAKE_SYSTEM_PROCESSOR x86_64)
set(CMAKE_SYSROOT /opt/sysroot-xp)

set(QT5_XP_TOOLS /opt/llvm-runtime-xp/bin/x86_64-w64-mingw32)
set(CMAKE_C_COMPILER "${QT5_XP_TOOLS}-clang")
set(CMAKE_CXX_COMPILER "${QT5_XP_TOOLS}-clang++")
set(CMAKE_RC_COMPILER "${QT5_XP_TOOLS}-windres")
set(CMAKE_C_COMPILER_TARGET x86_64-w64-windows-gnu)
set(CMAKE_CXX_COMPILER_TARGET x86_64-w64-windows-gnu)

set(CMAKE_FIND_ROOT_PATH
    ${CMAKE_SYSROOT}
    /opt/llvm-runtime-xp
    /opt/qt5-win-amd64-llvm
    /opt/openssl-3)
list(APPEND CMAKE_LIBRARY_PATH /opt/openssl-3/lib64 /opt/openssl-3/lib)
set(CMAKE_FIND_ROOT_PATH_MODE_PROGRAM NEVER)
set(CMAKE_FIND_ROOT_PATH_MODE_LIBRARY ONLY)
set(CMAKE_FIND_ROOT_PATH_MODE_INCLUDE ONLY)
set(CMAKE_FIND_ROOT_PATH_MODE_PACKAGE ONLY)
