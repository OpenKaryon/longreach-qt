#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2026 OpenKaryon
set -euo pipefail
export PATH=/opt/llvm-21/bin:/usr/local/bin:/usr/bin:/bin
unset CC CXX PKG_CONFIG_SYSROOT_DIR PKG_CONFIG_LIBDIR
sdk=/opt/qt4-sarge-llvm-sdk
spec=linux-sarge-llvm
jobs=${PARALLEL_JOBS:-3}
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
mkdir -p /out/bin
bash /src/scripts/build/qt4-tests.sh "$sdk" /src/tests /out/bin "$jobs" -spec "$spec"
cd "$work"
"$sdk/bin/qmake" -spec "$spec" /src/tests/qt-selftest/qt-selftest.pro \
    -after 'QMAKE_CXXFLAGS+=-std=c++23' 'DEFINES+=SMOKE_REQUIRE_CXX23'
make -j"$jobs"
install -m 755 qt-selftest /out/bin/qt-selftest-cxx23
