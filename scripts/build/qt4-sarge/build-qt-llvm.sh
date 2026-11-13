#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2026 OpenKaryon
set -euo pipefail
runtime=/work/sarge-llvm/runtimes/linux-sarge-i386
prefix=/opt/qt4-sarge-llvm-sdk
source=/work/qt4-sarge-llvm-sdk-src
spec=linux-sarge-llvm
archive=/src/qt.tar.gz
jobs=${PARALLEL_JOBS:-3}
echo "e2882295097e47fe089f8ac741a95fef47e0a73a3f3cdf21b56990638f626ea0  $archive" | sha256sum -c -
export PATH=/opt/llvm-21/bin:/usr/local/bin:/usr/bin:/bin
unset CC CXX PKG_CONFIG_SYSROOT_DIR PKG_CONFIG_LIBDIR
mkdir -p "$source"
tar -xzf "$archive" --strip-components=1 -C "$source"
cd "$source"
for patch in /src/patches/qt4/{all,linux,linux-sarge-llvm}/*.patch; do
    patch -p1 --fuzz=0 < "$patch"
done
mkdir -p "mkspecs/$spec" mkspecs/linux-longreach-host
cp mkspecs/linux-g++/qplatformdefs.h "mkspecs/$spec/"
cp mkspecs/linux-g++/qplatformdefs.h mkspecs/linux-longreach-host/
cat > mkspecs/linux-longreach-host/qmake.conf <<'EOF'
include(../linux-g++/qmake.conf)
QMAKE_CC = /opt/llvm-21/bin/clang
QMAKE_CXX = /opt/llvm-21/bin/clang++
QMAKE_CXXFLAGS += -std=gnu++98
QMAKE_LINK = /opt/llvm-21/bin/clang++
EOF
cat > "mkspecs/$spec/qmake.conf" <<EOF
include(../linux-g++/qmake.conf)
QMAKE_CC = $runtime/bin/clang-c -fgnu89-inline
QMAKE_CXX = $runtime/bin/clang-cxx -std=gnu++98
QMAKE_LINK = $runtime/bin/clang-cxx
QMAKE_LINK_SHLIB = $runtime/bin/clang-cxx
QMAKE_AR = /opt/llvm-21/bin/llvm-ar cqs
QMAKE_RANLIB = /opt/llvm-21/bin/llvm-ranlib
QMAKE_INCDIR_X11 = /opt/sysroot-sarge/usr/X11R6/include
QMAKE_LIBDIR_X11 = /opt/sysroot-sarge/usr/X11R6/lib
QMAKE_INCDIR_OPENGL = /opt/sysroot-sarge/usr/X11R6/include
QMAKE_LIBDIR_OPENGL = /opt/sysroot-sarge/usr/X11R6/lib
QMAKE_INCDIR_FREETYPE = /opt/sysroot-sarge/usr/include/freetype2
QMAKE_INCDIR_FONTCONFIG = /opt/sysroot-sarge/usr/include
QMAKE_LIBDIR += /opt/sysroot-sarge/usr/lib
QMAKE_LFLAGS += -Wl,-rpath-link,/opt/sysroot-sarge/usr/X11R6/lib
DEFINES += QT_NO_LINUX_FUTEX
EOF
OPENSSL_LIBS='-L/opt/sarge-openssl/lib -lssl -lcrypto -ldl -pthread' \
./configure -prefix "$prefix" -opensource -confirm-license -release -static -no-rpath \
    -platform linux-longreach-host -xplatform "$spec" -arch i386 -host-arch x86_64 \
    -openssl-linked -I/opt/sarge-openssl/include -L/opt/sarge-openssl/lib \
    -I/opt/sysroot-sarge/usr/include/freetype2 \
    -nomake demos -nomake examples -nomake docs -nomake translations -nomake tests \
    -no-webkit -no-phonon -no-phonon-backend -no-glib -no-gtkstyle \
    -no-dbus -no-cups -no-nis -no-icu -no-pch -no-separate-debug-info -no-openvg \
    -no-mmx -no-3dnow -no-sse -no-sse2 -no-sse3 -no-ssse3 -no-sse4.1 -no-sse4.2 -no-avx \
    -no-sql-mysql -no-sql-psql -no-sql-odbc -qt-sql-sqlite \
    -qt-zlib -qt-libpng -qt-libjpeg -qt-libtiff -qt-libmng -qt-freetype -fontconfig \
    -opengl desktop -qt3support -xmlpatterns -script -scripttools -svg -declarative \
    -no-javascript-jit -multimedia -audio-backend -accessibility -stl -exceptions -largefile
grep -q openssl-linked mkspecs/qconfig.pri
make -j"$jobs"
make install
cd tools/designer/src/uitools
"$prefix/bin/qmake" -spec "$spec" uitools.pro
make -j"$jobs"
make install
"$prefix/bin/qmake" -v
