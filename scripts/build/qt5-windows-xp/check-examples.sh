#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2026 OpenKaryon
set -euo pipefail

export SMOKE_QT_PREFIX="${QT_INSTALL_DIR:?}"
export SMOKE_CMAKE_TOOLCHAIN=/opt/llvm-runtime-xp/toolchain.cmake
export SMOKE_OPENSSL_PREFIX=/opt/openssl-3
export SMOKE_REQUIRE_CXX23=1

case "${XP_ARCH:?}" in
    i386) machine=I386; minor=1 ;;
    amd64) machine=AMD64; minor=2 ;;
esac

out=/opt/qt-smoke-bin
cp -a /src/tests /tmp/qt-smoke-tests
bash /tmp/build-tests.sh /tmp/qt-smoke-tests "$out"

while IFS= read -r app; do
    case "$app" in ''|\#*) continue ;; esac
    binary="$out/$app.exe"
    test -f "$binary"
    pe=$(llvm-readobj --file-headers --coff-imports "$binary")
    grep -Fq "Machine: IMAGE_FILE_MACHINE_$machine" <<< "$pe"
    grep -Fq 'MajorSubsystemVersion: 5' <<< "$pe"
    grep -Fq "MinorSubsystemVersion: $minor" <<< "$pe"
    grep -Fiq 'Name: msvcr100.dll' <<< "$pe"
    if grep -Eiq 'Name: (msvcrt|libc\+\+|libstdc\+\+|libgcc_s[^.]*|libwinpthread[^.]*|libunwind)\.dll' <<< "$pe"; then
        echo "Unexpected runtime DLL for $app" >&2
        exit 1
    fi
done < /src/tests/expected-apps.txt
