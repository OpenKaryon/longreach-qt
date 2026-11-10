#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2026 OpenKaryon
set -euo pipefail
target=${1:?target required}
test "$target" = linux-arm64
prefix=/opt/qt6-linux-arm64-llvm
source=/src/scripts/tests/qt6-llvm-sdk
"$CXX" --version > /out/target-compiler-version.txt
/opt/llvm-21/bin/ld.lld --version > /out/linker-version.txt
grep -F '21.1.8' /out/target-compiler-version.txt
grep -F '21.1.8' /out/linker-version.txt
cp "$prefix/share/longreach/config.summary" /out/qt-config.summary
cp "$prefix/share/longreach/CMakeCache.txt" /out/qt-CMakeCache.txt
find "$prefix/lib" -maxdepth 1 -name '*.a' | sort > /out/qt-static-libraries.txt
run_target() {
    timeout 90 env -u LD_LIBRARY_PATH qemu-aarch64-static -L /opt/sysroot-arm64 "$@"
}
for standard in 17 20 23; do
    required=OFF
    if [ "$standard" = 23 ]; then required=ON; fi
    cmake -S "$source" -B "/tmp/modern-$standard" -G Ninja \
        -DCMAKE_TOOLCHAIN_FILE=/opt/longreach-llvm/cmake/toolchain.cmake \
        -DQT_HOST_PATH=/opt/qt6-host-llvm21 -DCMAKE_PREFIX_PATH="$prefix" \
        -DCMAKE_BUILD_TYPE=Release -DCMAKE_CXX_STANDARD="$standard" \
        -DSMOKE_REQUIRE_CXX23="$required" -DCMAKE_EXE_LINKER_FLAGS=-no-pie \
        -DCMAKE_CXX_FLAGS= -DCMAKE_EXPORT_COMPILE_COMMANDS=ON
    cmake --build "/tmp/modern-$standard" --parallel 2
    binary="/out/modern-cxx$standard"
    cp "/tmp/modern-$standard/modern-only" "$binary"
    run_target "$binary" | tee "$binary.log"
    python3 /src/scripts/build/qt5-lucid/max-glibc.py "$binary" 2.17
    readelf -d "$binary" > "$binary.dependencies.log"
    if grep -E 'NEEDED.*lib(c\+\+|stdc\+\+|gcc_s|unwind|LLVM|clang)' "$binary.dependencies.log"; then
        echo 'Unexpected shared C++ runtime dependency' >&2; exit 1
    fi
done
python3 /src/scripts/tests/require-modern-cpp.py /out/modern-cxx23.log
cp /tmp/modern-23/compile_commands.json /out/modern-cxx23-compile_commands.json
if grep -F -- '-fexperimental-library' /out/modern-cxx23-compile_commands.json; then exit 1; fi

cp -r /src/tests /tmp/qt-smoke-src
cmake -S /tmp/qt-smoke-src -B /tmp/qt-smoke-required -G Ninja \
    -DCMAKE_TOOLCHAIN_FILE=/opt/longreach-llvm/cmake/toolchain.cmake \
    -DQT_HOST_PATH=/opt/qt6-host-llvm21 -DCMAKE_PREFIX_PATH="$prefix" \
    -DCMAKE_BUILD_TYPE=Release -DCMAKE_CXX_STANDARD=23 -DSMOKE_REQUIRE_CXX23=ON \
    -DCMAKE_EXE_LINKER_FLAGS=-no-pie -DCMAKE_CXX_FLAGS= \
    -DSMOKE_LICENSE_PROFILE=gpl-enabled -DOPENSSL_ROOT_DIR=/opt/openssl-3 -DOPENSSL_USE_STATIC_LIBS=ON
cmake --build /tmp/qt-smoke-required --target qt-selftest --parallel 4
cp /tmp/qt-smoke-required/qt-selftest/qt-selftest /out/qt-selftest-required
QT_QPA_PLATFORM=offscreen run_target /out/qt-selftest-required --modern-cpp > /out/qt-selftest-required.log 2>&1
cat /out/qt-selftest-required.log
python3 /src/scripts/tests/require-modern-cpp.py /out/qt-selftest-required.log
python3 /src/scripts/build/qt5-lucid/max-glibc.py /out/qt-selftest-required 2.17
readelf -d /out/qt-selftest-required > /out/qt-selftest-required.dependencies.log
if grep -E 'NEEDED.*lib(c\+\+|stdc\+\+|gcc_s|unwind|LLVM|clang)' /out/qt-selftest-required.dependencies.log; then
    echo 'Unexpected shared C++ runtime dependency' >&2; exit 1
fi
