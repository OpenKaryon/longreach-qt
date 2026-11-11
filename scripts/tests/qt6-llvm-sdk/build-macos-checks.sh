#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2026 OpenKaryon
set -euo pipefail
target=${1:?target required}
case "$target" in
    macos-amd64) arch=x86_64; cpu=0x01000007; minimum=10.13 ;;
    macos-arm64) arch=arm64; cpu=0x0100000c; minimum=11.0 ;;
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
    binary="/out/modern-cxx$standard"
    cp "/tmp/modern-$standard/modern-only" "$binary"
    python3 - "$binary" "$cpu" <<'PY'
import struct, sys
with open(sys.argv[1], 'rb') as binary:
    magic, machine = struct.unpack('<II', binary.read(8))
assert magic == 0xfeedfacf and machine == int(sys.argv[2], 16), (magic, machine)
PY
    MACHO_AUDIT_ARCH="$arch" bash /src/scripts/audit/qt6-macos-audit.sh "$minimum" "$binary"
    /opt/llvm-21/bin/llvm-objdump --macho --dylibs-used "$binary" > "$binary.dependencies.log"
    if grep -E 'lib(c\+\+|stdc\+\+|unwind|gcc_s).*\.dylib|Qt[^/]*\.framework' "$binary.dependencies.log"; then
        echo 'Unexpected shared Qt/C++ runtime dependency' >&2
        exit 1
    fi
done
cp /tmp/modern-23/compile_commands.json /out/modern-cxx23-compile_commands.json
if grep -F -- '-fexperimental-library' /out/modern-cxx23-compile_commands.json; then exit 1; fi
cp "$prefix/share/longreach/config.summary" /out/qt-config.summary
cp "$prefix/share/longreach/CMakeCache.txt" /out/qt-CMakeCache.txt
find "$prefix/lib" -maxdepth 1 -name '*.a' | sort > /out/qt-static-libraries.txt
