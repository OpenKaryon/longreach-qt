#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2026 OpenKaryon
set -euo pipefail

jobs=${PARALLEL_JOBS:-4}
prefix=/opt/qt6-linux-amd64-llvm
build=/opt/qt-build-llvm
test "${LLVM_ROOT:?}" = /opt/llvm-21
"$CXX" --version | head -1 | grep -F '21.1.8'
mkdir -p "$build"
cd "$build"
/opt/qt-everywhere-src-6.8.5/configure \
    -opensource -confirm-license -prefix "$prefix" \
    -release -optimize-size -static \
    -qt-zlib -qt-pcre -qt-libpng -qt-libjpeg -qt-freetype -qt-harfbuzz \
    -nomake examples -nomake tests -skip qtwebengine -skip qtwebview \
    -openssl-linked \
    -- -DCMAKE_BUILD_TYPE=Release -DCMAKE_DISABLE_PRECOMPILE_HEADERS=ON \
       -DCMAKE_JOB_POOLS=link_pool=1 -DCMAKE_JOB_POOL_LINK=link_pool \
       -DOPENSSL_ROOT_DIR=/opt/openssl-3 -DOPENSSL_USE_STATIC_LIBS=ON
cmake --build . --parallel "$jobs"
cmake --install .
if grep -rIl '/usr/lib64/libwayland' "$prefix/lib/cmake"; then
    echo 'Qt links libwayland instead of the pinned dlopen stubs' >&2
    exit 1
fi
mkdir -p "$prefix/lib" "$prefix/share/longreach"
ln -sfn /usr/share/fonts/dejavu "$prefix/lib/fonts"
cp config.summary "$prefix/share/longreach/config.summary"
cp CMakeCache.txt "$prefix/share/longreach/CMakeCache.txt"
"$prefix/bin/qtpaths" --qt-version
