#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2026 OpenKaryon
set -euo pipefail
jobs=${TIGER_JOBS:-6}
sdk=/opt/qt4-tiger
target_arch=${TIGER_ARCH:-i386}
qmake_spec=${TIGER_SPEC:-macx-tiger-clang}
qt_arch=$target_arch
case "$target_arch" in ppc|ppc64) qt_arch=powerpc;; esac
source=/work/qt-source
mkdir -p "$source"
# The tree lives in a cache mount, which outlasts --no-cache. It is reused
# only while it was made from this archive and exactly these patches; with
# one removed, renamed or changed it starts again, since a patch no longer
# here would otherwise stay applied.
tree_key=$( { echo qt-everywhere-opensource-src-4.8.7.tar.gz;
              cd /patches && sha256sum all/*.patch macos/*.patch; } | sha256sum | cut -d" " -f1)
if [ -f "$source/configure" ] && [ "$(cat "$source/.kit-tree-key" 2>/dev/null || true)" != "$tree_key" ]; then
    echo "build-qt.sh: the patches changed since this tree was made; starting from a clean tree"
    find "$source" -mindepth 1 -delete
fi
if [ ! -f "$source/configure" ]; then
    tar -xzf /archives/qt-everywhere-opensource-src-4.8.7.tar.gz --strip-components=1 -C "$source"
    printf '%s\n' "$tree_key" > "$source/.kit-tree-key"
fi
cd "$source"
apply_patch() {
    local patch_file=$1 key previous
    key=${patch_file#/patches/}
    previous="$source/.kit-applied/$key"
    if [ -f "$previous" ] && cmp -s "$previous" "$patch_file"; then return; fi
    if [ -f "$previous" ]; then patch -R -p1 < "$previous"; fi
    patch -p1 < "$patch_file"
    mkdir -p "$(dirname "$previous")"
    cp "$patch_file" "$previous"
}
for p in /patches/all/*.patch /patches/macos/*.patch; do apply_patch "$p"; done
mkdir -p "mkspecs/$qmake_spec"
cp mkspecs/macx-g++/qplatformdefs.h "mkspecs/$qmake_spec/"
cp /scripts/qmake.conf "mkspecs/$qmake_spec/"
if [ "$qt_arch" = powerpc ]; then
    config_key=$( { sha256sum /scripts/build-qt.sh /scripts/qmake.conf;
                    printf '%s\n' "$target_arch" "$qmake_spec" "${TIGER_CACHE_KEY:-}"; } | sha256sum)
    if [ -f Makefile ] && [ "$(cat .qtkit-ppc-config 2>/dev/null || true)" != "$config_key" ]; then
        make clean > /tmp/qt4-ppc-clean.log
    fi
    printf '%s\n' "$config_key" > .qtkit-ppc-config
fi
# Qt itself uses C++98. Host generators stay Linux.
OPENSSL_LIBS='-L/opt/openssl-tiger/lib -lssl -lcrypto' \
./configure -v -prefix "$sdk" -opensource -confirm-license -release -static \
    -platform linux-g++ -xplatform "$qmake_spec" -arch "$target_arch" -host-arch x86_64 \
    -carbon -no-framework -no-dwarf2 -no-pch -no-separate-debug-info \
    -openssl-linked -I/opt/openssl-tiger/include -L/opt/openssl-tiger/lib \
    -nomake demos -nomake examples -nomake docs -nomake translations -nomake tests \
    -no-webkit -no-phonon -no-phonon-backend -no-dbus -no-cups -no-nis -no-icu \
    -no-glib -no-gtkstyle -no-openvg -no-sql-mysql -no-sql-psql -no-sql-odbc \
    -plugin-sql-sqlite -qt-zlib -qt-libpng -qt-libjpeg -qt-libtiff -qt-libmng \
    -opengl desktop -qt3support -xmlpatterns -script -scripttools -svg -declarative \
    -multimedia -audio-backend -accessibility -stl -exceptions -largefile
grep -q "QT_ARCH = $qt_arch" mkspecs/qconfig.pri
grep -q openssl-linked mkspecs/qconfig.pri
if [ "$qt_arch" = powerpc ]; then
    # GCC ICEs can leave a 152-byte Mach-O header which make considers current.
    # Remove those incomplete cached objects before retrying with a fixed GCC.
    find "$source" -type f -name '*.o' -size -256c -delete
fi
make -j "$jobs"
make install
cp "$source/LICENSE.LGPLv21" "$source/LICENSE.LGPLv3" "$source/LGPL_EXCEPTION.txt" /opt/qt4-licenses/
cp /work/openssl-source/LICENSE /opt/qt4-licenses/OPENSSL-LICENSE.txt
cd tools/designer/src/uitools
"$sdk/bin/qmake" -spec "$sdk/mkspecs/$qmake_spec" uitools.pro
make -j "$jobs"
make install
