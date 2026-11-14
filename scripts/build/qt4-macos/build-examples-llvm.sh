#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2026 OpenKaryon
set -euo pipefail
export TIGER_SPEC=macx-tiger-llvm
export TIGER_JOBS=${TIGER_JOBS:-3}
bash /scripts/build-examples.sh
sdk=/opt/qt4-tiger
mkdir -p /work/strict
cd /work/strict
"$sdk/bin/qmake" -spec "$sdk/mkspecs/$TIGER_SPEC" /input/qt-selftest/qt-selftest.pro \
    'CONFIG+=app_bundle' 'CONFIG-=console' 'DEFINES+=SMOKE_STATIC_QSQLITE' \
    "LIBS+=-L$sdk/plugins/sqldrivers -lqsqlite" \
    -after 'QMAKE_CXXFLAGS+=-std=c++23' 'DEFINES+=SMOKE_REQUIRE_CXX23'
make -j "$TIGER_JOBS"
bundle=qt-selftest.app
mkdir -p "$bundle/Contents/MacOS" "$bundle/Contents/Resources"
if [ ! -f "$bundle/Contents/MacOS/qt-selftest" ]; then
    cp qt-selftest "$bundle/Contents/MacOS/"
fi
TARGET_NAME=qt-selftest BUNDLE="$bundle" python3 /scripts/write-bundle.py
python3 - <<'PY'
import json
from pathlib import Path
import runpy
inspect = runpy.run_path("/scripts/audit-macho.py")["inspect"]
binary = Path("qt-selftest.app/Contents/MacOS/qt-selftest")
Path("/out/macho-audit-strict.json").write_text(json.dumps(inspect(binary, "i386"), indent=2) + "\n")
PY
tar -czf /out/qt4-tiger-i386-strict.tar.gz "$bundle"
