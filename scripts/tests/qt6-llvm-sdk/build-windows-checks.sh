#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2026 OpenKaryon
set -euo pipefail
target=${1:?target required}
case "$target" in
    windows-amd64) machine=IMAGE_FILE_MACHINE_AMD64 ;;
    windows-arm64) machine=IMAGE_FILE_MACHINE_ARM64 ;;
    *) exit 2 ;;
esac
prefix=/opt/qt6-$target-llvm
source=/src/scripts/tests/qt6-llvm-sdk
for standard in 17 20 23; do
    required=OFF
    if [ "$standard" = 23 ]; then required=ON; fi
    cmake -S "$source" -B "/tmp/modern-$standard" -G Ninja \
        -DCMAKE_TOOLCHAIN_FILE=/opt/longreach-llvm/cmake/toolchain.cmake \
        -DQT_HOST_PATH=/opt/qt6-host-llvm21 -DCMAKE_PREFIX_PATH="$prefix" \
        -DCMAKE_BUILD_TYPE=Release -DCMAKE_CXX_STANDARD="$standard" \
        -DSMOKE_REQUIRE_CXX23="$required" -DCMAKE_CXX_FLAGS= \
        -DCMAKE_EXPORT_COMPILE_COMMANDS=ON
    cmake --build "/tmp/modern-$standard" --parallel 2
    binary="/out/modern-cxx$standard.exe"
    cp "/tmp/modern-$standard/modern-only.exe" "$binary"
    /opt/llvm-21/bin/llvm-readobj --file-headers "$binary" > "$binary.headers.log"
    grep -F "Machine: $machine " "$binary.headers.log"
    /opt/llvm-21/bin/llvm-objdump -p "$binary" > "$binary.dependencies.log"
    if grep -Ei 'DLL Name: *(Qt6|libc\+\+|libstdc\+\+|libunwind|libgcc|libwinpthread)' "$binary.dependencies.log"; then
        echo 'Unexpected shared Qt/C++ runtime dependency' >&2
        exit 1
    fi
    if [ "$target" = windows-amd64 ]; then
        PATH=/opt/llvm-21/bin:$PATH bash /src/scripts/audit/qt6-win7-audit.sh "$binary"
    else
        awk '$1=="MajorSubsystemVersion" { major=$2 } $1=="MinorSubsystemVersion" { minor=$2 }
             END { exit !(major==10 && minor==0 && major!="" && minor!="") }' "$binary.dependencies.log"
    fi
done
cp /tmp/modern-23/compile_commands.json /out/modern-cxx23-compile_commands.json
if grep -F -- '-fexperimental-library' /out/modern-cxx23-compile_commands.json; then exit 1; fi
cp "$prefix/share/longreach/config.summary" /out/qt-config.summary
cp "$prefix/share/longreach/CMakeCache.txt" /out/qt-CMakeCache.txt
find "$prefix/lib" -maxdepth 1 -name '*.a' | sort > /out/qt-static-libraries.txt
