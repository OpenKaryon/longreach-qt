#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2026 OpenKaryon
# Focused SDK integration: no GUI galleries or security test runners.
set -euo pipefail

qt=/opt/qt6-linux-amd64-llvm
source=/src/scripts/tests/qt6-linux-amd64-llvm
"$CXX" --version | head -1 | grep -F '21.1.8'
test "$("$qt/bin/qtpaths" --qt-version)" = 6.8.5
"$CXX" --version > /out/compiler-version.txt
/opt/llvm-21/bin/ld.lld --version > /out/linker-version.txt
"$qt/bin/qtpaths" --query > /out/qtpaths.txt
cp "$qt/share/longreach/config.summary" /out/qt-config.summary
cp "$qt/share/longreach/CMakeCache.txt" /out/qt-CMakeCache.txt
find "$qt/lib" -maxdepth 1 -name '*.a' | sort > /out/qt-static-libraries.txt
for standard in 17 20 23; do
    required=OFF
    if [ "$standard" = 23 ]; then required=ON; fi
    "$qt/bin/qt-cmake" -S "$source" -B "/tmp/modern-$standard" -G Ninja \
        -DCMAKE_BUILD_TYPE=Release -DCMAKE_CXX_STANDARD="$standard" \
        -DSMOKE_REQUIRE_CXX23="$required" -DCMAKE_PREFIX_PATH="$qt" \
        -DCMAKE_EXE_LINKER_FLAGS=-no-pie -DCMAKE_CXX_FLAGS= -DCMAKE_EXPORT_COMPILE_COMMANDS=ON
    cmake --build "/tmp/modern-$standard" --parallel 2
    binary="/out/modern-cxx$standard"
    cp "/tmp/modern-$standard/modern-only" "$binary"
    timeout 60 "$binary" | tee "$binary.log"
    python3 /src/scripts/build/qt5-lucid/max-glibc.py "$binary" 2.17
    readelf -d "$binary" > "$binary.dependencies.log"
    if grep -E 'NEEDED.*lib(c\+\+|stdc\+\+|gcc_s|unwind|LLVM|clang)' "$binary.dependencies.log"; then
        echo 'Unexpected shared C++ runtime dependency' >&2
        exit 1
    fi
done
python3 /src/scripts/tests/require-modern-cpp.py /out/modern-cxx23.log
cp /tmp/modern-23/compile_commands.json /out/modern-cxx23-compile_commands.json
if grep -F -- '-fexperimental-library' /out/modern-cxx23-compile_commands.json; then
    echo 'The LLVM 21 required run must use ordinary libc++' >&2
    exit 1
fi

# qmake consumers select the same compiler/runtime wrappers explicitly.
mkdir /tmp/modern-qmake
cat > /tmp/modern-qmake/modern.pro <<'EOF'
TEMPLATE = app
TARGET = modern-qmake-cxx23
CONFIG += console release c++23
CONFIG -= app_bundle
QT = core
QMAKE_CXXFLAGS += -std=c++23
QMAKE_LFLAGS += -no-pie
DEFINES += SMOKE_REQUIRE_CXX23=1
INCLUDEPATH += /src/tests/common
SOURCES += /src/tests/qt-selftest/checks_modern_cpp.cpp /src/scripts/tests/qt6-linux-amd64-llvm/modern-only.cpp
EOF
(
    cd /tmp/modern-qmake
    "$qt/bin/qmake" modern.pro "QMAKE_CC=$CC" "QMAKE_CXX=$CXX" "QMAKE_LINK=$CXX" \
        'QMAKE_AR=/opt/llvm-21/bin/llvm-ar cqs' 'QMAKE_RANLIB=/opt/llvm-21/bin/llvm-ranlib'
    make -j2
)
cp /tmp/modern-qmake/modern-qmake-cxx23 /out/modern-qmake-cxx23
timeout 60 /out/modern-qmake-cxx23 | tee /out/modern-qmake-cxx23.log
python3 /src/scripts/tests/require-modern-cpp.py /out/modern-qmake-cxx23.log
python3 /src/scripts/build/qt5-lucid/max-glibc.py /out/modern-qmake-cxx23 2.17
readelf -d /out/modern-qmake-cxx23 > /out/modern-qmake-cxx23.dependencies.log
if grep -E 'NEEDED.*lib(c\+\+|stdc\+\+|gcc_s|unwind|LLVM|clang)' /out/modern-qmake-cxx23.dependencies.log; then
    echo 'Unexpected shared C++ runtime dependency' >&2
    exit 1
fi

cp -r /src/tests /tmp/qt-smoke-src
"$qt/bin/qt-cmake" -S /tmp/qt-smoke-src -B /tmp/qt-smoke-required -G Ninja \
    -DCMAKE_BUILD_TYPE=Release -DCMAKE_CXX_STANDARD=23 -DSMOKE_REQUIRE_CXX23=ON \
    -DCMAKE_PREFIX_PATH="$qt" -DCMAKE_EXE_LINKER_FLAGS=-no-pie -DCMAKE_CXX_FLAGS= \
    -DSMOKE_LICENSE_PROFILE=gpl-enabled \
    -DOPENSSL_ROOT_DIR=/opt/openssl-3 -DOPENSSL_USE_STATIC_LIBS=ON
cmake --build /tmp/qt-smoke-required --target qt-selftest --parallel 4
cp /tmp/qt-smoke-required/qt-selftest/qt-selftest /out/qt-selftest-required
xvfb-run -a -s '-screen 0 1280x1024x24' env QT_QPA_PLATFORM=offscreen \
    timeout 60 /out/qt-selftest-required --modern-cpp > /out/qt-selftest-required.log 2>&1
cat /out/qt-selftest-required.log
python3 /src/scripts/tests/require-modern-cpp.py /out/qt-selftest-required.log
python3 /src/scripts/build/qt5-lucid/max-glibc.py /out/qt-selftest-required 2.17
readelf -d /out/qt-selftest-required > /out/qt-selftest-required.dependencies.log
if grep -E 'NEEDED.*lib(c\+\+|stdc\+\+|gcc_s|unwind|LLVM|clang)' /out/qt-selftest-required.dependencies.log; then
    echo 'Unexpected shared C++ runtime dependency' >&2
    exit 1
fi

# Ordinary Qt API integration, separate from the exact modern-only contract.
xvfb-run -a -s '-screen 0 1280x1024x24' env QT_QPA_PLATFORM=offscreen \
    timeout 180 /out/qt-selftest-required --selftest > /out/qt-selftest-console.log 2>&1
cat /out/qt-selftest-console.log
python3 /src/scripts/tests/require-modern-cpp.py --allow-other-checks /out/qt-selftest-console.log
