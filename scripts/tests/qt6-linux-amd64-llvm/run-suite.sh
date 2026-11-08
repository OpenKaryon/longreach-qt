#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2026 OpenKaryon
set -eu

cp -r /src/tests /tmp/qt-smoke-src
/opt/qt6-linux-amd64-llvm/bin/qt-cmake -S /tmp/qt-smoke-src -B /tmp/qt-smoke -G Ninja \
    -DCMAKE_BUILD_TYPE=Release -DCMAKE_CXX_STANDARD=23 \
    -DCMAKE_PREFIX_PATH=/opt/qt6-linux-amd64-llvm \
    -DCMAKE_EXE_LINKER_FLAGS=-no-pie \
    -DSMOKE_LICENSE_PROFILE=gpl-enabled \
    -DOPENSSL_ROOT_DIR=/opt/openssl-3 -DOPENSSL_USE_STATIC_LIBS=ON
cmake --build /tmp/qt-smoke --parallel 4
find /tmp/qt-smoke -maxdepth 2 -type f -executable \
    ! -path '*/CMakeFiles/*' ! -name '*.so' -exec cp {} /out/ \;
cd /out
for app in $(sed -e '/^#/d' -e '/^$/d' /src/tests/expected-apps.txt); do
    test -x "$app"
    python3 /src/scripts/build/qt5-lucid/max-glibc.py "$app" 2.17
done
xvfb-run -a -s '-screen 0 1280x1024x24' env QT_QPA_PLATFORM=offscreen ./smoke-runner

modern_source=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
for standard in 17 20 23; do
    /opt/qt6-linux-amd64-llvm/bin/qt-cmake -S "$modern_source" \
        -B "/tmp/modern-$standard" -G Ninja \
        -DCMAKE_BUILD_TYPE=Release -DCMAKE_CXX_STANDARD="$standard" \
        -DCMAKE_PREFIX_PATH=/opt/qt6-linux-amd64-llvm \
        -DCMAKE_EXE_LINKER_FLAGS=-no-pie
    cmake --build "/tmp/modern-$standard" --parallel 2
    "/tmp/modern-$standard/modern-only" > "/out/modern-cxx$standard.log"
done
cp /tmp/modern-23/modern-only /out/modern-cxx23
python3 /src/scripts/build/qt5-lucid/max-glibc.py /out/modern-cxx23 2.17
readelf -d /out/modern-cxx23 | grep NEEDED
if readelf -d /out/modern-cxx23 | grep -E 'libstdc\+\+|libc\+\+|libLLVM|libclang'; then
    echo 'Unexpected runtime dependency' >&2
    exit 1
fi

# Separate libc++ experimental run: preserve the ordinary binaries and logs.
# Test the complete console self-test with exactly the same Qt SDK.
/opt/qt6-linux-amd64-llvm/bin/qt-cmake -S /tmp/qt-smoke-src \
    -B /tmp/qt-smoke-experimental -G Ninja \
    -DCMAKE_BUILD_TYPE=Release -DCMAKE_CXX_STANDARD=23 \
    -DCMAKE_PREFIX_PATH=/opt/qt6-linux-amd64-llvm \
    -DCMAKE_CXX_FLAGS=-fexperimental-library \
    '-DCMAKE_EXE_LINKER_FLAGS=-no-pie -fexperimental-library' \
    -DSMOKE_LICENSE_PROFILE=gpl-enabled \
    -DOPENSSL_ROOT_DIR=/opt/openssl-3 -DOPENSSL_USE_STATIC_LIBS=ON
cmake --build /tmp/qt-smoke-experimental --target qt-selftest --parallel 4
cp /tmp/qt-smoke-experimental/qt-selftest/qt-selftest /out/qt-selftest-experimental
xvfb-run -a -s '-screen 0 1280x1024x24' env QT_QPA_PLATFORM=offscreen \
    /out/qt-selftest-experimental --selftest > /out/qt-selftest-experimental.log 2>&1

require_cpp_threads() {
    grep -Fx 'PASS: C++20 std::jthread' "$1"
    grep -Fx 'PASS: C++20 std::stop_token and callbacks' "$1"
}
require_cpp_threads /out/qt-selftest-experimental.log
python3 /src/scripts/build/qt5-lucid/max-glibc.py /out/qt-selftest-experimental 2.17

# A QtCore-only binary also permits a stock-userland runtime check.
/opt/qt6-linux-amd64-llvm/bin/qt-cmake -S "$modern_source" \
    -B /tmp/modern-experimental -G Ninja \
    -DCMAKE_BUILD_TYPE=Release -DCMAKE_CXX_STANDARD=23 \
    -DCMAKE_PREFIX_PATH=/opt/qt6-linux-amd64-llvm \
    -DCMAKE_CXX_FLAGS=-fexperimental-library \
    '-DCMAKE_EXE_LINKER_FLAGS=-no-pie -fexperimental-library'
cmake --build /tmp/modern-experimental --parallel 2
cp /tmp/modern-experimental/modern-only /out/modern-cxx23-experimental
/out/modern-cxx23-experimental > /out/modern-cxx23-experimental.log
require_cpp_threads /out/modern-cxx23-experimental.log
python3 /src/scripts/build/qt5-lucid/max-glibc.py /out/modern-cxx23-experimental 2.17
readelf -d /out/modern-cxx23-experimental | grep NEEDED
if readelf -d /out/modern-cxx23-experimental | grep -E 'libstdc\+\+|libc\+\+|libLLVM|libclang'; then
    echo 'Unexpected experimental runtime dependency' >&2
    exit 1
fi
