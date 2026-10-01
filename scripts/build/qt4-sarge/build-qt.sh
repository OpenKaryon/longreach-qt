#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2026 OpenKaryon
set -euo pipefail
source "$(dirname "$0")/arch.sh"
jobs=${SARGE_JOBS:-6}
export PATH=/work/toolchain/bin:$PATH
root=/work/sysroot
python /scripts/relativize-sysroot.py
# glibc 2.3 headers use GNU89 C inline semantics, predating GCC's GNU11 default.
if ! grep -q fgnu89-inline /work/toolchain/bin/sarge-gcc; then
    sed -i 's|exec /usr/bin/gcc |exec /usr/bin/gcc -std=gnu89 -fgnu89-inline |' /work/toolchain/bin/sarge-gcc
fi
if [ ! -f /work/openssl-1.0.2u/lib/libssl.a ]; then
    cd /work
    test -d openssl-source || { mkdir openssl-source; tar -xzf /archives/openssl-1.0.2u.tar.gz --strip-components=1 -C openssl-source; }
    cd openssl-source
    ./Configure "$SARGE_OPENSSL_TARGET" --prefix=/work/openssl-1.0.2u no-shared no-capieng
    make clean
    make -j "$jobs" CC=sarge-gcc
    make install_sw
fi
if [ ! -f /work/qt-source/configure ]; then
    mkdir -p /work/qt-source
    tar -xzf /archives/qt-everywhere-opensource-src-4.8.7.tar.gz --strip-components=1 -C /work/qt-source
    cd /work/qt-source
    # OpenSSL 1.0.2u here; the 1.1 API port in all/01 is guarded on the version.
    for p in /patches/all/*.patch /patches/linux/*.patch; do patch -p1 < "$p"; done
    rm -f .sarge-configured
fi
cd /work/qt-source
mkdir -p "mkspecs/$SARGE_SPEC"
cp mkspecs/linux-g++/qplatformdefs.h "mkspecs/$SARGE_SPEC/"
cat > "mkspecs/$SARGE_SPEC/qmake.conf" <<'EOF'
include(../linux-g++/qmake.conf)
QMAKE_CC = /work/toolchain/bin/sarge-gcc
QMAKE_CXX = /work/toolchain/bin/sarge-g++
QMAKE_LINK = $$QMAKE_CXX
QMAKE_LINK_SHLIB = $$QMAKE_CXX
QMAKE_INCDIR_X11 = /work/sysroot/usr/X11R6/include
QMAKE_LIBDIR_X11 = /work/sysroot/usr/X11R6/lib
QMAKE_INCDIR_OPENGL = /work/sysroot/usr/X11R6/include
QMAKE_LIBDIR_OPENGL = /work/sysroot/usr/X11R6/lib
QMAKE_INCDIR_FREETYPE = /work/sysroot/usr/include/freetype2
QMAKE_INCDIR_FONTCONFIG = /work/sysroot/usr/include
QMAKE_LIBDIR += /work/sysroot/usr/lib
QMAKE_LFLAGS += -static-libgcc -static-libstdc++
DEFINES += QT_NO_LINUX_FUTEX
EOF
if ! grep -q "QT_ARCH = $SARGE_QT_ARCH" mkspecs/qconfig.pri 2>/dev/null; then rm -f .sarge-configured; fi
if [ ! -f /work/qt-source/.sarge-configured ]; then
    OPENSSL_LIBS='-L/work/openssl-1.0.2u/lib -lssl -lcrypto -ldl -pthread' \
    ./configure -prefix /work/sdk -opensource -confirm-license -release -static -no-rpath \
        -platform linux-g++ -xplatform "$SARGE_SPEC" -arch "$SARGE_QT_ARCH" -host-arch "$SARGE_QT_ARCH" \
        -openssl-linked -I/work/openssl-1.0.2u/include -L/work/openssl-1.0.2u/lib \
        -I/work/sysroot/usr/include/freetype2 \
        -nomake demos -nomake examples -nomake docs -nomake translations -nomake tests \
        -no-webkit -no-phonon -no-phonon-backend -no-glib -no-gtkstyle \
        -no-dbus -no-cups -no-nis -no-icu -no-pch -no-separate-debug-info -no-openvg \
        -no-sql-mysql -no-sql-psql -no-sql-odbc -qt-sql-sqlite \
        -qt-zlib -qt-libpng -qt-libjpeg -qt-libtiff -qt-libmng -qt-freetype -fontconfig \
        -opengl desktop -qt3support -xmlpatterns -script -scripttools -svg -declarative \
        -multimedia -audio-backend -accessibility -stl -exceptions -largefile
    grep -q openssl-linked mkspecs/qconfig.pri
    touch .sarge-configured
fi
make -j "$jobs"
make install
cd /work/qt-source/tools/designer/src/uitools
/work/sdk/bin/qmake -spec "/work/sdk/mkspecs/$SARGE_SPEC" uitools.pro
make -j "$jobs"
make install
