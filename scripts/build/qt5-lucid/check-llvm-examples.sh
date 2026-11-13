#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2026 OpenKaryon
set -euo pipefail

export SMOKE_QT_PREFIX="${QT_INSTALL_DIR:?}"
export SMOKE_CMAKE_TOOLCHAIN=/opt/llvm-runtime-lucid/toolchain.cmake
export SMOKE_OPENSSL_PREFIX=/opt/openssl-lucid
export SMOKE_REQUIRE_CXX23=1
export CMAKE_GENERATOR=Ninja

case "${LUCID_ARCH:?}" in
    amd64) machine='Advanced Micro Devices X86-64' ;;
    i386) machine='Intel 80386' ;;
    *) exit 2 ;;
esac

out=/opt/qt-smoke-bin
cp -a /src/tests /tmp/qt-smoke-tests
bash /tmp/build-tests.sh /tmp/qt-smoke-tests "$out"
while read -r app; do
    case "$app" in ''|\#*) continue ;; esac
    binary="$out/$app"
    test -x "$binary"
    python3 /tmp/max-glibc.py "$binary" 2.11
    readelf -h "$binary" | grep -F "$machine"
    needed=$(readelf -d "$binary")
    if grep -E 'NEEDED.*lib(Qt5|c\+\+|stdc\+\+|gcc_s|unwind)' <<< "$needed"; then
        exit 1
    fi
done < /src/tests/expected-apps.txt
