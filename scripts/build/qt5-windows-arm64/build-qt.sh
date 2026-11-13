#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2026 OpenKaryon
set -euo pipefail

source=/build/qt-everywhere-src-5.15.19
archive=/src/qt.tar.xz
prefix=${QT_INSTALL_DIR:?}
echo "173c2326dae138bbb0d98921e9d911e55c00163d93a6db29f294b5e19ff306ae  $archive" | sha256sum -c -
clang --version | grep -E '^clang version 21\.1\.8([[:space:]]|$)'
mkdir -p /build/qt
tar -xJf "$archive" -C /build --exclude='*/qtwebengine/*'
for patch in /src/patches/{all,windows}/*.patch; do
    (cd "$source" && git apply "$patch")
done

cd /build/qt
# Preserve the baseline ARM64 module set and its Schannel backend.
"$source/configure" -opensource -confirm-license -prefix "$prefix" \
    -platform linux-g++ -xplatform win32-clang-g++ \
    -device-option CROSS_COMPILE=/opt/longreach-llvm/bin/aarch64-w64-mingw32- \
    -c++std c++14 -static -static-runtime -optimize-size -release \
    -nomake examples -nomake tests -nomake tools -skip qtwebengine \
    -no-angle -no-cups -no-dbus -no-fontconfig -gif -no-iconv -no-icu -opengl desktop \
    -no-openssl -schannel -no-openvg -no-pch -sql-sqlite -qt-sqlite -ssl \
    -no-d3d12 -no-feature-geoservices_mapboxgl \
    -make libs -qt-freetype -qt-harfbuzz -qt-libjpeg -qt-libpng -qt-pcre -qt-zlib
make -j"${PARALLEL_JOBS:-3}"
make install
install -m 644 config.summary "$prefix/qt-config.summary"
test "$("$prefix/bin/qmake" -query QT_VERSION)" = 5.15.19
