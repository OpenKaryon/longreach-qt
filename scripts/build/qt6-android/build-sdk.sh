#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-or-later

set -euo pipefail
source=/work/api21/qt-src
build=/work/api21/qt-sdk-build
prefix=/opt/qt6-android-armeabi-v7a-llvm
phase=${1:-all}
archive=/repo/downloads/qt-everywhere-src-6.8.5.tar.xz
echo 'c0537548bb3871cbb3cac85fb55813430d45ac4d5d4daa64bdf41f3c2ae65ff9  '"$archive" | sha256sum -c -
if [[ ! -f "$source/configure" ]]; then
    mkdir -p "$source"
    tar -xJf "$archive" --strip-components=1 -C "$source" --exclude='*/qtwebengine/*'
fi
python3 /repo/scripts/build/qt6-android/apply-qt-patches.py /repo "$source" "$archive"
export JAVA_HOME=/usr/lib/jvm/java-17-openjdk-amd64
export PATH="$JAVA_HOME/bin:$PATH"
export LANG=C.UTF-8
export LC_ALL=C.UTF-8
unset PKG_CONFIG_SYSROOT_DIR PKG_CONFIG_PATH
export PKG_CONFIG_LIBDIR=/opt/openssl-api21/lib/pkgconfig
if [[ "$phase" != build ]]; then
cmake -S "$source" -B "$build" -G Ninja \
    -DCMAKE_TOOLCHAIN_FILE=/opt/longreach-android-api21/toolchain.cmake \
    -DQT_HOST_PATH=/opt/qt6-host-llvm21 -DCMAKE_INSTALL_PREFIX="$prefix" \
    -DCMAKE_BUILD_TYPE=Release -DCMAKE_CXX_STANDARD=17 \
    -DCMAKE_C_FLAGS=-DANDROID -DCMAKE_CXX_FLAGS=-DANDROID -DCMAKE_ASM_FLAGS=-DANDROID \
    -DBUILD_SHARED_LIBS=ON -DQT_BUILD_TESTS=OFF -DQT_BUILD_EXAMPLES=OFF \
    -DBUILD_qtwebengine=OFF -DBUILD_qtwayland=OFF \
    -DQT_FEATURE_dbus=OFF -DQT_FEATURE_glib=OFF -DQT_FEATURE_icu=OFF \
    -DQT_FEATURE_iconv=OFF -DINPUT_opengl=es2 -DQT_FEATURE_vulkan=OFF \
    -DINPUT_zlib=qt -DINPUT_pcre=qt -DINPUT_libpng=qt -DINPUT_libjpeg=qt \
    -DINPUT_freetype=qt -DINPUT_harfbuzz=qt -DINPUT_sqlite=qt \
    -DINPUT_openssl=linked -DOPENSSL_ROOT_DIR=/opt/openssl-api21 -DOPENSSL_USE_STATIC_LIBS=ON \
    -DCMAKE_PREFIX_PATH=/opt/openssl-api21 -DCMAKE_DISABLE_PRECOMPILE_HEADERS=ON \
    -DCMAKE_DISABLE_FIND_PACKAGE_Clang=ON \
    -DCMAKE_JOB_POOLS=link_pool=1 -DCMAKE_JOB_POOL_LINK=link_pool \
    -DQT_QMAKE_TARGET_MKSPEC=android-clang -DQT_QMAKE_DEVICE_OPTIONS=ANDROID_PLATFORM=android-21
fi
if [[ "$phase" == configure ]]; then
    exit 0
fi
cmake --build "$build" --parallel "${PARALLEL_JOBS:-2}"
cmake --install "$build"
mkdir -p /out
cp "$build/config.summary" /out/qt-sdk-config.summary
find "$prefix/lib" -maxdepth 1 -type f -name 'libQt6*.so' -printf '%f\n' | sort > /out/sdk-modules.txt
