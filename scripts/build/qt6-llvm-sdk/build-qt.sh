#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2026 OpenKaryon
set -euo pipefail
target=${1:?target required}
test "$target" = linux-arm64
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
for patch in /src/patches/qt6/all/*.patch; do
    receipt="$receipts/$(basename "$patch")"
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

prefix=/opt/qt6-linux-arm64-llvm
mkdir -p /build/qt
cd /build/qt
"$source/configure" -opensource -confirm-license -prefix "$prefix" \
    -qt-host-path /opt/qt6-host-llvm21 -release -optimize-size -static \
    -qt-zlib -qt-pcre -qt-libpng -qt-libjpeg -qt-freetype -qt-harfbuzz \
    -nomake examples -nomake tests -skip qtwebengine -skip qtwebview -openssl-linked \
    -- -DCMAKE_TOOLCHAIN_FILE=/opt/longreach-llvm/cmake/toolchain.cmake \
       -DCMAKE_BUILD_TYPE=Release -DCMAKE_DISABLE_PRECOMPILE_HEADERS=ON \
       -DCMAKE_JOB_POOLS=link_pool=1 -DCMAKE_JOB_POOL_LINK=link_pool \
       -DOPENSSL_ROOT_DIR=/opt/openssl-3 -DOPENSSL_USE_STATIC_LIBS=ON
cmake --build . --parallel "${PARALLEL_JOBS:-4}"
cmake --install .
if grep -rIl 'usr/lib64/libwayland' "$prefix/lib/cmake"; then exit 1; fi
mkdir -p "$prefix/share/longreach"
cp config.summary CMakeCache.txt "$prefix/share/longreach/"
