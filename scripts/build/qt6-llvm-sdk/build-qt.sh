#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2026 OpenKaryon
set -euo pipefail
target=${1:?target required}
patches=(/src/patches/qt6/all/*.patch)
platform_args=(-openssl-linked)
platform_cmake=(-DOPENSSL_ROOT_DIR=/opt/openssl-3 -DOPENSSL_USE_STATIC_LIBS=ON)
case "$target" in
    linux-arm64) ;;
    windows-amd64|windows-arm64)
        patches+=(/src/patches/qt6/windows/*.patch)
        processor=x86_64
        if [ "$target" = windows-arm64 ]; then processor=aarch64; fi
        platform_args=(-strip -platform linux-g++ -xplatform win32-clang-g++
            -device-option "CROSS_COMPILE=$processor-w64-mingw32-"
            -no-vulkan -no-dbus -skip qtwayland -skip qtactiveqt)
        platform_cmake=(-DCMAKE_EXPORT_COMPILE_COMMANDS=ON)
        ;;
    macos-amd64|macos-arm64)
        patches+=(/src/patches/qt6/macos/*.patch)
        platform_args=(-strip -no-vulkan -no-dbus -no-cups -skip qtwayland)
        platform_cmake=(-DQT_FORCE_WARN_APPLE_SDK_AND_XCODE_CHECK=ON
            -DQT_CREATE_VERSIONED_HARD_LINK=OFF -DCMAKE_EXPORT_COMPILE_COMMANDS=ON)
        ;;
    *) exit 2 ;;
esac
archive=/src/downloads/qt-everywhere-src-6.8.5.tar.xz
echo 'c0537548bb3871cbb3cac85fb55813430d45ac4d5d4daa64bdf41f3c2ae65ff9  '"$archive" | sha256sum -c -
source=/build/qt-everywhere-src-6.8.5
# A receipt per patch allows an interrupted build to accept additional patches
# without silently reusing an old source tree. Changed applied patches require
# a fresh source volume rather than assuming their old contents still match.
receipts="$source/.longreach-patch-receipts"
if [ ! -f "$source/.longreach-extracted" ] && [ ! -f "$source/.longreach-patched" ]; then
    tar -xJf "$archive" -C /build --exclude='*/qtwebengine/*' --exclude='*/qtwebview/*'
    touch "$source/.longreach-extracted"
fi
if [ -f "$source/.longreach-patched" ] && [ ! -d "$receipts" ]; then
    # The original SDK helper applied common patches 01..28 before this marker.
    mkdir -p "$receipts"
    for patch in /src/patches/qt6/all/*.patch; do
        case "$(basename "$patch")" in
            0[1-9]-*|1[0-9]-*|2[0-8]-*) sha256sum "$patch" | cut -d' ' -f1 > "$receipts/$(basename "$patch")" ;;
        esac
    done
fi
mkdir -p "$receipts"
for patch in "${patches[@]}"; do
    group=$(basename "$(dirname "$patch")")
    receipt="$receipts/$(basename "$patch")"
    if [ "$group" != all ]; then receipt="$receipts/$group-$(basename "$patch")"; fi
    signature=$(sha256sum "$patch" | cut -d' ' -f1)
    if [ -f "$receipt" ]; then
        if [ "$(cat "$receipt")" != "$signature" ]; then
            echo "An applied patch changed: $(basename "$patch"); use a fresh source volume" >&2
            exit 1
        fi
        continue
    fi
    if ! (cd "$source" && git apply --reverse --check "$patch") 2>/dev/null; then
        (cd "$source" && git apply "$patch")
    fi
    printf '%s\n' "$signature" > "$receipt"
done
touch "$source/.longreach-patched"

prefix=/opt/qt6-$target-llvm
mkdir -p /build/qt
cd /build/qt
"$source/configure" -opensource -confirm-license -prefix "$prefix" \
    -qt-host-path /opt/qt6-host-llvm21 -release -optimize-size -static \
    -qt-zlib -qt-pcre -qt-libpng -qt-libjpeg -qt-freetype -qt-harfbuzz \
    -nomake examples -nomake tests -skip qtwebengine -skip qtwebview "${platform_args[@]}" \
    -- -DCMAKE_TOOLCHAIN_FILE=/opt/longreach-llvm/cmake/toolchain.cmake \
       -DCMAKE_BUILD_TYPE=Release -DCMAKE_DISABLE_PRECOMPILE_HEADERS=ON \
       -DCMAKE_JOB_POOLS=link_pool=1 -DCMAKE_JOB_POOL_LINK=link_pool \
       "${platform_cmake[@]}"
if [ "$target" = windows-amd64 ]; then
    cmake --build . --target QWindowsMediaPlugin --parallel "${PARALLEL_JOBS:-4}"
fi
cmake --build . --parallel "${PARALLEL_JOBS:-4}"
cmake --install .
if [ "$target" = linux-arm64 ] && grep -rIl 'usr/lib64/libwayland' "$prefix/lib/cmake"; then exit 1; fi
mkdir -p "$prefix/share/longreach"
cp config.summary CMakeCache.txt "$prefix/share/longreach/"
