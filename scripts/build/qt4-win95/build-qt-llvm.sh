#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2026 OpenKaryon
set -euo pipefail
export PATH=/opt/llvm-runtime-win95/bin:/opt/llvm-21/bin:/usr/bin:/bin
unset CC CXX
mkdir -p /out
src=/work/qt4-win95-src
jobs=${PARALLEL_JOBS:-3}
prefix=/opt/qt4-win-i386-llvm
trip=/opt/llvm-runtime-win95/bin/i686-w64-mingw32
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
patch --quiet -p1 --fuzz=0 < /src/patches/qt4/windows-95-llvm/01-win32-crt-time.patch

mkdir -p mkspecs/linux-longreach-host mkspecs/win32-g++-longreach-win95
cp mkspecs/linux-g++/qplatformdefs.h mkspecs/linux-longreach-host/
cp mkspecs/win32-g++/qplatformdefs.h mkspecs/win32-g++-longreach-win95/
# This MinGW sysroot declares EXTENDED_NAME_FORMAT even at WINVER 0x0400.
sed -i '/^#if !defined(_WIN32_WINNT) || (_WIN32_WINNT-0 < 0x0500)/,/^#endif/d' \
    mkspecs/win32-g++-longreach-win95/qplatformdefs.h
cat > mkspecs/linux-longreach-host/qmake.conf <<'EOF'
include(../linux-g++/qmake.conf)
QMAKE_CC = /opt/llvm-21/bin/clang
QMAKE_CXX = /opt/llvm-21/bin/clang++
QMAKE_CXXFLAGS += -std=gnu++98
QMAKE_LINK = /opt/llvm-21/bin/clang++
EOF
cat > mkspecs/win32-g++-longreach-win95/qmake.conf <<EOF
include(../win32-g++/qmake.conf)
QMAKE_CC = $trip-clang -D__USE_MINGW_ANSI_STDIO=0
QMAKE_CXX = $trip-clang++ -std=gnu++98 -D__STDC_CONSTANT_MACROS -D__STDC_LIMIT_MACROS
QMAKE_LINK = $trip-clang++
QMAKE_LINK_SHLIB = $trip-clang++
QMAKE_LINK_C = $trip-clang
# Pass objects directly because LLD does not read the GNU ld INPUT script.
QMAKE_LINK_OBJECT_MAX = 10000
QMAKE_LIB = /opt/llvm-21/bin/llvm-ar -ru
QMAKE_RC = /opt/llvm-runtime-win95/bin/i686-w64-mingw32-windres
QMAKE_STRIP = /opt/llvm-21/bin/llvm-strip
QMAKE_OBJCOPY = /opt/llvm-21/bin/llvm-objcopy
QMAKE_LFLAGS -= -static-libgcc -static-libstdc++
QMAKE_LFLAGS_APP -= -static-libgcc -static-libstdc++
QMAKE_CXXFLAGS_EXCEPTIONS_ON -= -mthreads
QMAKE_LFLAGS_EXCEPTIONS_ON -= -mthreads
EOF
OPENSSL_LIBS="-L/opt/openssl-1.0.2u/lib -lssl -lcrypto -lws2_32 -lgdi32 -ladvapi32" \
./configure -v -prefix "$prefix" -opensource -confirm-license -release -static \
    -platform linux-longreach-host -xplatform win32-g++-longreach-win95 -arch i386 -host-arch x86_64 -little-endian \
    -no-mmx -no-3dnow -no-sse -no-sse2 -no-sse3 -no-ssse3 -no-sse4.1 -no-sse4.2 -no-avx \
    -openssl-linked -I/opt/openssl-1.0.2u/include -L/opt/openssl-1.0.2u/lib \
    -nomake demos -nomake examples -nomake docs -nomake translations -nomake tests \
    -no-webkit -no-phonon -no-phonon-backend -no-glib -no-gtkstyle \
    -no-dbus -no-cups -no-icu -no-pch -no-freetype -no-fontconfig -no-separate-debug-info -no-openvg \
    -no-sql-mysql -no-sql-psql -no-sql-odbc -qt-sql-sqlite \
    -qt-zlib -qt-libpng -qt-libjpeg -qt-libtiff -qt-libmng \
    -opengl desktop -qt3support -xmlpatterns -script -scripttools -svg -declarative \
    -no-javascript-jit -multimedia -audio-backend -accessibility -stl -exceptions -largefile -D QT_NO_DIRECTWRITE \
    > /out/sdk-configure.log 2>&1 || { tail -55 /out/sdk-configure.log; exit 1; }
grep -q openssl-linked mkspecs/qconfig.pri
grep -q '^#define QT_POINTER_SIZE 4$' src/corelib/global/qconfig.h

make -j"$jobs" > /out/sdk-build.log 2>&1 || { grep -E 'error:|undefined symbol|Error [0-9]' /out/sdk-build.log | tail -30; exit 1; }
make install > /out/sdk-install.log 2>&1
"$prefix/bin/qmake" -v
