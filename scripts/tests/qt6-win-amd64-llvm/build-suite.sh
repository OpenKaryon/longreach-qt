#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2026 OpenKaryon
set -eu

cp -r /src/tests /tmp/qt-smoke-src
cmake_args=(
    -G Ninja -DCMAKE_BUILD_TYPE=Release -DCMAKE_CXX_STANDARD=23
    -DCMAKE_TOOLCHAIN_FILE=/opt/qt6-amd64/lib/cmake/Qt6/qt.toolchain.cmake
    -DQT_HOST_PATH=/opt/qt6-host -DSMOKE_LICENSE_PROFILE=gpl-enabled
)
/opt/qt6-amd64/bin/qt-cmake -S /tmp/qt-smoke-src -B /tmp/ordinary "${cmake_args[@]}"
cmake --build /tmp/ordinary --parallel 4
find /tmp/ordinary -type f -name '*.exe' ! -name a.exe -exec cp {} /out/ \;
while read -r app; do
    case "$app" in
        ''|'#'*) continue ;;
    esac
    test -f "/out/$app.exe"
done < /src/tests/expected-apps.txt

/opt/qt6-amd64/bin/qt-cmake -S /tmp/qt-smoke-src -B /tmp/experimental \
    "${cmake_args[@]}" -DCMAKE_CXX_FLAGS=-fexperimental-library \
    -DCMAKE_EXE_LINKER_FLAGS=-fexperimental-library
cmake --build /tmp/experimental --target qt-selftest --parallel 4
cp /tmp/experimental/qt-selftest/qt-selftest.exe /out/qt-selftest-experimental.exe

modern_source=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
for mode in ordinary experimental; do
    extra_args=()
    if [ "$mode" = experimental ]; then
        extra_args=(-DCMAKE_CXX_FLAGS=-fexperimental-library
                    '-DCMAKE_EXE_LINKER_FLAGS=-static -fexperimental-library')
    else
        extra_args=(-DCMAKE_EXE_LINKER_FLAGS=-static)
    fi
    /opt/qt6-amd64/bin/qt-cmake -S "$modern_source" -B "/tmp/modern-$mode" \
        "${cmake_args[@]}" "${extra_args[@]}"
    cmake --build "/tmp/modern-$mode" --parallel 2
    cp "/tmp/modern-$mode/modern-only.exe" "/out/modern-cxx23-$mode.exe"
done
bash /src/scripts/audit/qt6-win7-audit.sh /out/*.exe
