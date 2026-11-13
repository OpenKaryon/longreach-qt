#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2026 OpenKaryon
set -euo pipefail

export SMOKE_QT_PREFIX="${QT_INSTALL_DIR:?}"
export SMOKE_CMAKE_TOOLCHAIN=/opt/longreach-llvm/cmake/toolchain.cmake
export SMOKE_REQUIRE_CXX23=1
out=/opt/qt-smoke-bin
cp -a /src/tests /tmp/qt-smoke-tests
bash /tmp/build-tests.sh /tmp/qt-smoke-tests "$out"

while IFS= read -r app; do
    case "$app" in ''|\#*) continue ;; esac
    pe=$(llvm-readobj --file-headers --coff-imports "$out/$app.exe")
    grep -Fq 'Machine: IMAGE_FILE_MACHINE_ARM64' <<< "$pe"
    grep -Fq 'MajorSubsystemVersion: 10' <<< "$pe"
    grep -Fq 'MinorSubsystemVersion: 0' <<< "$pe"
    if grep -Eiq 'Name: (libc\+\+|libstdc\+\+|libgcc_s[^.]*|libwinpthread[^.]*|libunwind)\.dll' <<< "$pe"; then
        echo "Unexpected runtime DLL for $app" >&2
        exit 1
    fi
done < /src/tests/expected-apps.txt
