#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2026 OpenKaryon

set -euo pipefail

source=/build/qt-everywhere-src-5.15.19
archive=/src/qt.tar.xz
prefix=${QT_INSTALL_DIR:?}
echo "173c2326dae138bbb0d98921e9d911e55c00163d93a6db29f294b5e19ff306ae  $archive" | sha256sum -c -
wayland-scanner --version

mkdir -p /build/qt
tar -xJf "$archive" -C /build --exclude='*/qtwebengine/*'
for patch in /src/patches/qt5/{all,linux,linux-lucid-llvm}/*.patch /src/mapbox-clang21.patch; do
    (cd "$source" && git apply "$patch")
done
spec="$source/qtbase/mkspecs/linux-lucid-clang"
mkdir "$spec"
cp /src/qt5-lucid/mkspecs/linux-lucid-clang/qmake.conf "$spec/"
cp /src/qt5-lucid/mkspecs/linux-lucid-g++/qplatformdefs.h "$spec/"

cd /build/qt
"$source/configure" -opensource -confirm-license -prefix "$prefix" \
    -platform linux-g++ -xplatform linux-lucid-clang -pkg-config \
    OPENSSL_PATH=/opt/openssl-lucid OPENSSL_LIBS="-L/opt/openssl-lucid/lib64 -L/opt/openssl-lucid/lib -lssl -lcrypto -ldl -pthread" \
    -no-avx -c++std c++14 -static -optimize-size -release \
    -xcb -bundled-xcb-xinput -xkbcommon -fontconfig -system-freetype \
    -nomake examples -nomake tests -nomake tools \
    -no-cups -dbus-runtime -alsa -pulseaudio -gstreamer 1.0 -speechd -gif -no-iconv -no-icu -no-glib \
    -opengl desktop -openssl-linked -no-openvg -no-pch \
    -sql-sqlite -qt-sqlite -ssl -no-libudev -no-libinput -no-mtdev -no-tslib \
    -make libs -qt-harfbuzz -qt-libjpeg -qt-libpng -qt-pcre -qt-zlib -skip qtwebengine

grep -E '^Qt Wayland Client \.+ yes$' config.summary
grep -E '^Qt Wayland Compositor \.+ yes$' config.summary
make -j"${PARALLEL_JOBS:-4}"
make install
install -m 644 config.summary "$prefix/qt-config.summary"
for module in Core Widgets WaylandClient WaylandCompositor; do
    test -f "$prefix/lib/libQt5$module.a"
done
test -f "$prefix/plugins/geoservices/libqtgeoservices_mapboxgl.a"
for importer in assimp uip; do
    test -f "$prefix/plugins/assetimporters/lib$importer.a"
done
for tool in balsam meshdebug; do
    test -x "$prefix/bin/$tool"
done
test "$("$prefix/bin/qmake" -query QT_VERSION)" = 5.15.19
