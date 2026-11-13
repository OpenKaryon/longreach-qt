#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2026 OpenKaryon
set -euo pipefail

source=/build/qt-everywhere-src-5.15.19
archive=/src/qt.tar.xz
prefix=${QT_INSTALL_DIR:?}
echo "173c2326dae138bbb0d98921e9d911e55c00163d93a6db29f294b5e19ff306ae  $archive" | sha256sum -c -
mkdir -p /build/qt
tar -xJf "$archive" -C /build --exclude='*/qtwebengine/*'
for patch in /src/patches/qt5/{all,windows,windows-xp-llvm}/*.patch /src/qml-x86.patch /src/mapbox-clang21.patch; do
    (cd "$source" && git apply "$patch")
done

cd /build/qt
"$source/configure" -v -opensource -confirm-license -prefix "$prefix" \
    -platform linux-g++ -xplatform win32-clang-g++ \
    -device-option CROSS_COMPILE="/opt/llvm-runtime-xp/bin/${XP_CROSS:?}-" \
    OPENSSL_PATH=/opt/openssl-3 \
    OPENSSL_LIBS="-L/opt/openssl-3/${XP_OPENSSL_LIBDIR:?} -lssl -lcrypto -lcrypt32 -lws2_32 -lgdi32 -luser32 -ladvapi32" \
    -no-avx -c++std c++14 -static -static-runtime -optimize-size -release \
    -nomake examples -nomake tests -nomake tools -skip qtwebengine \
    -no-angle -no-cups -no-dbus -no-fontconfig -gif -no-iconv -no-icu -opengl desktop \
    -openssl-linked -no-openvg -no-pch -sql-sqlite -qt-sqlite -ssl \
    -make libs -qt-freetype -qt-harfbuzz -qt-libjpeg -qt-libpng -qt-pcre -qt-zlib
make -j"${PARALLEL_JOBS:-4}"
make install
install -m 644 config.summary "$prefix/qt-config.summary"
test -f "$prefix/plugins/geoservices/libqtgeoservices_mapboxgl.a"
test "$("$prefix/bin/qmake" -query QT_VERSION)" = 5.15.19
