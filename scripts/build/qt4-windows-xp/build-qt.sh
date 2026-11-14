#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2026 OpenKaryon
set -euo pipefail
export PATH=/opt/llvm-runtime-xp/bin:/opt/llvm-21/bin:/usr/bin:/bin
unset CC CXX
mkdir -p /out
src=/work/qt4-xp-src
jobs=${PARALLEL_JOBS:-3}
prefix=/opt/qt4-win-amd64-llvm
trip=/opt/llvm-runtime-xp/bin/x86_64-w64-mingw32
mkdir -p "$src"
archive=/src/qt.tar.gz
echo "e2882295097e47fe089f8ac741a95fef47e0a73a3f3cdf21b56990638f626ea0  $archive" | sha256sum -c -
tar -xzf "$archive" --strip-components=1 -C "$src"
cd "$src"
for patch in /src/patches/qt4/{all,windows}/*.patch; do
    patch --quiet -p1 --fuzz=0 < "$patch"
done
patch --quiet -p1 --fuzz=0 < /src/patches/qt4/linux-sarge-llvm/01-xmlpatterns-color-mask.patch
patch --quiet -p2 --fuzz=0 < /src/patches/qt5/windows-xp-llvm/01-qtscript-win32-clock.patch
patch --quiet -p1 --fuzz=0 < /src/patches/qt4/linux-sarge-llvm/02-widget-style-optimization.patch
patch --quiet -p1 --fuzz=0 < /src/patches/qt4/windows-xp-llvm/01-javascriptcore-jmp-buffer-alignment.patch

mkdir -p mkspecs/linux-longreach-host mkspecs/win32-g++-longreach-xp
cp mkspecs/linux-g++/qplatformdefs.h mkspecs/linux-longreach-host/
cp mkspecs/win32-g++/qplatformdefs.h mkspecs/win32-g++-longreach-xp/
cat > mkspecs/linux-longreach-host/qmake.conf <<'EOF'
include(../linux-g++/qmake.conf)
QMAKE_CC = /opt/llvm-21/bin/clang
QMAKE_CXX = /opt/llvm-21/bin/clang++
QMAKE_CXXFLAGS += -std=gnu++98
QMAKE_LINK = /opt/llvm-21/bin/clang++
EOF
cat > mkspecs/win32-g++-longreach-xp/qmake.conf <<EOF
include(../win32-g++/qmake.conf)
QMAKE_CC = $trip-clang
QMAKE_CXX = $trip-clang++ -std=gnu++98 -D__STDC_CONSTANT_MACROS -D__STDC_LIMIT_MACROS
QMAKE_LINK = $trip-clang++
QMAKE_LINK_SHLIB = $trip-clang++
# Pass objects directly because LLD does not read the GNU ld INPUT script.
QMAKE_LINK_OBJECT_MAX = 10000
QMAKE_LIB = $trip-ar -ru
QMAKE_RC = $trip-windres
QMAKE_STRIP = $trip-strip
QMAKE_LFLAGS -= -static-libgcc -static-libstdc++
QMAKE_LFLAGS_APP -= -static-libgcc -static-libstdc++
EOF
OPENSSL_LIBS="-L/opt/openssl-3/lib64 -lssl -lcrypto -lcrypt32 -lws2_32 -lgdi32 -luser32 -ladvapi32" \
./configure -v -prefix "$prefix" -opensource -confirm-license -release -static \
    -platform linux-longreach-host -xplatform win32-g++-longreach-xp -arch x86_64 -host-arch x86_64 -little-endian \
    -openssl-linked -I/opt/openssl-3/include -L/opt/openssl-3/lib64 \
    -nomake demos -nomake examples -nomake docs -nomake translations -nomake tests \
    -no-webkit -no-phonon -no-phonon-backend -no-glib -no-gtkstyle \
    -no-dbus -no-cups -no-icu -no-pch -no-freetype -no-separate-debug-info -no-openvg \
    -no-sql-mysql -no-sql-psql -no-sql-odbc -qt-sql-sqlite \
    -qt-zlib -qt-libpng -qt-libjpeg -qt-libtiff -qt-libmng \
    -opengl desktop -qt3support -xmlpatterns -script -scripttools -svg -declarative \
    -no-javascript-jit -multimedia -audio-backend -accessibility -stl -exceptions -largefile \
    > /out/configure.log 2>&1 || { tail -55 /out/configure.log; exit 1; }
grep -q openssl-linked mkspecs/qconfig.pri
sed -i 's/^#define QT_POINTER_SIZE 4$/#define QT_POINTER_SIZE 8/' src/corelib/global/qconfig.h
grep -q '^#define QT_POINTER_SIZE 8$' src/corelib/global/qconfig.h

make -j"$jobs" > /out/build.log 2>&1 || { grep -E 'error:|undefined symbol|Error [0-9]' /out/build.log | tail -30; exit 1; }
make install > /out/install.log 2>&1
"$prefix/bin/qmake" -v
