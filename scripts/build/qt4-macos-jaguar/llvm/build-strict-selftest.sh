#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2026 OpenKaryon
set -euo pipefail

sdk=/opt/qt4-jaguar
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
cd "$work"
"$sdk/bin/qmake" -spec "$sdk/mkspecs/macx-jaguar-g++" /input/qt-selftest/qt-selftest.pro \
    'CONFIG+=app_bundle' 'CONFIG-=console' 'DEFINES+=SMOKE_STATIC_QSQLITE' \
    "LIBS+=-L$sdk/plugins/sqldrivers -lqsqlite" \
    -after 'QMAKE_CXXFLAGS+=-std=c++23 -Wno-register' 'DEFINES+=SMOKE_REQUIRE_CXX23'
make -j "${JAGUAR_JOBS:-3}" >/out/qt-strict-build.log 2>&1 || { tail -40 /out/qt-strict-build.log; exit 1; }
executable=qt-selftest
if [ -f qt-selftest.app/Contents/MacOS/qt-selftest ]; then
    executable=qt-selftest.app/Contents/MacOS/qt-selftest
fi
cp "$executable" /out/qt-selftest-jaguar-strict
python3 /scripts/check-imports.py /out/qt-selftest-jaguar-strict /out/imports/qt-selftest-jaguar-strict.txt
