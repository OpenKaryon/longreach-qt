#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-or-later

set -euo pipefail
repo=${REPO_ROOT:-/repo}
source=/work/qt5-sdk-src
build=/work/qt5-android-build
prefix=/opt/qt5-android-armeabi-v7a-llvm
phase=${1:-all}

echo '173c2326dae138bbb0d98921e9d911e55c00163d93a6db29f294b5e19ff306ae  '"$repo/downloads/qt-everywhere-opensource-src-5.15.19.tar.xz" | sha256sum -c -
if [[ ! -f "$source/configure" ]]; then
    mkdir -p "$source"
    tar -xJf "$repo/downloads/qt-everywhere-opensource-src-5.15.19.tar.xz" \
        --strip-components=1 -C "$source" --exclude='*/qtwebengine/*'
fi
python3 "$repo/scripts/build/qt5-android/apply-qt-patches.py" "$repo" "$source" \
    "$repo/downloads/qt-everywhere-opensource-src-5.15.19.tar.xz"

mkdir -p /work/host-bin "$build" "$source/qtbase/mkspecs/android-longreach-clang"
ln -sf /usr/bin/clang-21 /work/host-bin/clang
ln -sf /usr/bin/clang++-21 /work/host-bin/clang++
spec="$source/qtbase/mkspecs/android-longreach-clang"
if ! cmp -s "$repo/scripts/build/qt5-android/mkspec/qmake.conf" "$spec/qmake.conf"; then
    cp "$repo/scripts/build/qt5-android/mkspec/qmake.conf" "$spec/qmake.conf"
fi
if ! cmp -s "$source/qtbase/mkspecs/android-clang/qplatformdefs.h" "$spec/qplatformdefs.h"; then
    cp "$source/qtbase/mkspecs/android-clang/qplatformdefs.h" "$spec/qplatformdefs.h"
fi

export JAVA_HOME=/usr/lib/jvm/java-17-openjdk-amd64
export PATH="/work/host-bin:$JAVA_HOME/bin:$PATH"
export ANDROID_NDK_ROOT=/opt/longreach-android/ndk
export ANDROID_SDK_ROOT=${ANDROID_SDK_ROOT:-/work/android-sdk}
# Target dependencies use their own /opt prefixes, outside the Bionic sysroot.
unset PKG_CONFIG_SYSROOT_DIR
export PKG_CONFIG_LIBDIR=/opt/openssl-api10/lib/pkgconfig
cd "$build"
if [[ ! -f .longreach-configured ]]; then
    "$source/configure" -opensource -confirm-license -release -shared -optimize-size \
        -prefix "$prefix" -platform linux-clang -xplatform android-longreach-clang \
        -android-abis armeabi-v7a -android-ndk "$ANDROID_NDK_ROOT" \
        -android-ndk-host linux-x86_64 -android-ndk-platform android-10 \
        -android-sdk "$ANDROID_SDK_ROOT" -android-javac-source 8 -android-javac-target 8 \
        -c++std c++17 -opengl es2 -no-pch -no-dbus -no-glib -no-icu -no-iconv \
        -qt-freetype -qt-harfbuzz -qt-libpng -qt-libjpeg -qt-pcre -qt-zlib \
        -sql-sqlite -qt-sqlite -openssl-linked \
        OPENSSL_PATH=/opt/openssl-api10 \
        OPENSSL_LIBS="-L/opt/openssl-api10/lib -lssl -lcrypto -ldl" \
        -nomake tests -nomake examples -skip qtwebengine
    touch .longreach-configured
fi
if [[ "$phase" == base ]]; then
    make --output-sync=target -j"${PARALLEL_JOBS:-2}" module-qtbase
    make -C qtbase install
else
    make --output-sync=target -j"${PARALLEL_JOBS:-2}"
    make install
fi
cp config.summary "$prefix/qt-config.summary"
"$prefix/bin/qmake" -query QT_VERSION