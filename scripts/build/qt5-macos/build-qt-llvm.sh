#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2026 OpenKaryon
set -euo pipefail

arch=${1:?Target architecture required}
case "$arch" in
    i386)
        prefix=i386-apple-darwin10-
        ;;
    x86_64|arm64)
        prefix=$(cat /opt/osxcross-prefix)
        ;;
    *)
        echo "Unsupported macOS architecture: $arch" >&2
        exit 2
        ;;
esac

patches=(/src/patches/{all,macos,macos-llvm}/*.patch)
toolchain=(usr/local/osxcross opt/llvm-21/bin opt/llvm-21/lib/clang/21)
if [ "$arch" = arm64 ]; then
    minimum=11.0
    tls=(-no-openssl -securetransport)
    patches+=(/src/patches/arm64-llvm/*.patch)
else
    minimum=10.6
    tls=(-openssl-linked -no-securetransport OPENSSL_PATH=/opt/openssl-3
         'OPENSSL_LIBS=-L/opt/openssl-3/lib -lssl -lcrypto')
    patches+=(/src/qml-x86.patch /src/mapbox.patch)
    toolchain+=(opt/openssl-3)
fi

archive=/src/qt.tar.xz
install_dir=/usr/local/Qt-5.15
echo "173c2326dae138bbb0d98921e9d911e55c00163d93a6db29f294b5e19ff306ae  $archive" | sha256sum -c -
# Hash the installed SDK, wrappers, linker and runtime together. Include paths,
# modes and symlink targets, but ignore timestamps and ownership from image builds.
toolchain_hash=$(tar -C / --sort=name --mtime=@0 --owner=0 --group=0 --numeric-owner \
    -cf - "${toolchain[@]}" | sha256sum)
inputs=$(sha256sum "$archive" "$0" "${patches[@]}")
fingerprint=$(printf '%s\n' "$arch" "$prefix" "$inputs" "$toolchain_hash" | sha256sum)
build="/work/${fingerprint%% *}"
source="$build/qt"
mkdir -p "$build"
if [ ! -f "$source/qtbase/mkspecs/common/macx.conf" ]; then
    staging=$(mktemp -d "$build/qt.XXXXXX")
    trap 'rm -rf "$staging"' EXIT
    tar -xJf "$archive" -C "$staging" --strip-components=1
    (
        cd "$staging"
        for patch in "${patches[@]}"; do git apply "$patch"; done
        sed -i "s/^QMAKE_MACOSX_DEPLOYMENT_TARGET = .*/QMAKE_MACOSX_DEPLOYMENT_TARGET = $minimum/" qtbase/mkspecs/common/macx.conf
        grep -Fxq "QMAKE_MACOSX_DEPLOYMENT_TARGET = $minimum" qtbase/mkspecs/common/macx.conf
    )
    mv "$staging" "$source"
    trap - EXIT
fi

export MACOSX_DEPLOYMENT_TARGET="$minimum"
cd "$source"
if [ ! -f .longreach-configured ]; then
    ./configure -v -prefix "$install_dir" \
        -xplatform macx-clang -device-option CROSS_COMPILE="$prefix" QMAKE_APPLE_DEVICE_ARCHS="$arch" \
        -no-avx -c++std c++14 -static -optimize-size -release -opensource -confirm-license \
        -nomake examples -nomake tests -nomake tools -no-cups -dbus-runtime -gif -no-iconv \
        -no-icu -opengl desktop "${tls[@]}" -no-openvg -no-pch -sql-sqlite -qt-sqlite -ssl \
        -make libs -qt-harfbuzz -qt-libjpeg -qt-libpng -qt-pcre -qt-zlib -skip wayland -skip qtwebengine
    touch .longreach-configured
fi

if ! make -s -j"${PARALLEL_JOBS:-3}" > "$build/make.log" 2>&1; then
    grep -E 'error:|Undefined symbols|Error [1-9]' "$build/make.log" | tail -n 25 || true
    tail -n 30 "$build/make.log"
    exit 1
fi
make -s install
install -m 644 config.summary "$install_dir/qt-config.summary"
test "$("$install_dir/bin/qmake" -query QT_VERSION)" = 5.15.19
