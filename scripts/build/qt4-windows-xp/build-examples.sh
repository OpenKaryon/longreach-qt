#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2026 OpenKaryon
set -euo pipefail

sdk=${QT_INSTALL_DIR:?}
jobs=${PARALLEL_JOBS:-3}
out=/opt/qt4-smoke-bin
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
bash /src/scripts/build/qt4-tests.sh "$sdk" /src/tests "$out" "$jobs" -spec "$QMAKESPEC" -unix
cd "$work"
"$sdk/bin/qmake" -spec "$QMAKESPEC" -unix /src/tests/qt-selftest/qt-selftest.pro \
    -after 'QMAKE_CXXFLAGS+=-std=c++23' 'DEFINES+=SMOKE_REQUIRE_CXX23'
make -j"$jobs"
install -m755 release/qt-selftest.exe "$out/qt-selftest-cxx23.exe"

for binary in "$out"/*.exe /opt/llvm-runtime-xp/share/cxx23-probe.exe; do
    pe=$(llvm-readobj --file-headers --coff-imports "$binary")
    grep -Fq 'Machine: IMAGE_FILE_MACHINE_AMD64' <<< "$pe"
    grep -Fq 'MajorSubsystemVersion: 5' <<< "$pe"
    grep -Fq 'MinorSubsystemVersion: 2' <<< "$pe"
    grep -Fiq 'Name: msvcr100.dll' <<< "$pe"
    if grep -Eiq 'Name: (msvcrt|libc\+\+|libstdc\+\+|libgcc[^.]*|libwinpthread[^.]*|libunwind|ucrtbase|api-ms-win-crt[^.]*)\.dll' <<< "$pe"; then
        echo "Unexpected runtime DLL for $binary" >&2
        exit 1
    fi
done
