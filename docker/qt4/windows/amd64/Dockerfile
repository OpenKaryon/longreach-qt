# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2026 OpenKaryon
#
# Qt 4.8.7, static, for Windows x86_64 with MinGW-w64, from XP x64 and Server
# 2003 (the first 64-bit Windows; no backport needed). Ubuntu 16.04: gcc 5
# defaults to the C++98 dialect Qt 4.8.7 was written for.
#
#   toolchain  the MinGW cross-compiler
#   builder    OpenSSL 3, then Qt: patch, configure, build, install
#   final      the toolchain plus the installed SDK

# ---------------------------------------------------------------------------
# toolchain: the MinGW cross-compiler, shared by builder and final.
# ---------------------------------------------------------------------------
FROM --platform=linux/amd64 ubuntu:16.04 AS toolchain

# The posix threading alternative, as in the Qt 5 Windows images.
RUN \
    set -eux && \
    export DEBIAN_FRONTEND=noninteractive && \
    apt -y update && \
    apt -y upgrade && \
    apt -y install \
        build-essential python perl git wget nano ca-certificates xz-utils \
        binutils-mingw-w64-x86-64 mingw-w64-x86-64-dev g++-mingw-w64-x86-64 gcc-mingw-w64-x86-64 && \
    update-alternatives --set x86_64-w64-mingw32-gcc /usr/bin/x86_64-w64-mingw32-gcc-posix && \
    update-alternatives --set x86_64-w64-mingw32-g++ /usr/bin/x86_64-w64-mingw32-g++-posix && \
    apt -y autoremove && \
    apt -y autoclean && \
    apt -y clean && \
    rm -rf /var/lib/apt/lists/* && \
    exit 0

# ---------------------------------------------------------------------------
# builder: unpack, patch, configure, build and install Qt.
# ---------------------------------------------------------------------------
FROM toolchain AS builder

ARG QT4_VERSION="4.8.7"
ARG QT4_DISTRO="qt-everywhere-opensource-src-${QT4_VERSION}.tar.gz"
# OpenSSL 3, which patches/qt4/all/01-openssl-1.1-api.patch makes Qt 4 accept.
ARG OPENSSL_VERSION="3.5.7"
ARG OPENSSL_DISTRO="openssl-${OPENSSL_VERSION}.tar.gz"
ARG DOWNLOAD_DIR="downloads"
ARG QT4_SRC_DIR="qt-everywhere-opensource-src-${QT4_VERSION}"
ARG PARALLEL_JOBS=""

COPY patches/qt4 /tmp/patches/qt4
COPY ${DOWNLOAD_DIR}/${QT4_DISTRO} /opt/${QT4_DISTRO}
COPY ${DOWNLOAD_DIR}/${OPENSSL_DISTRO} /opt/${OPENSSL_DISTRO}
COPY scripts/build/openssl.sh /tmp/build-openssl.sh

# Qt 4.8.7's own cross invocation (-xplatform win32-g++ with CROSS_COMPILE):
# configure builds moc, rcc and uic with the host g++, so no host-tools pass is
# needed. The disabled features are the Linux list minus the X11 ones; Windows
# uses GDI fonts, so no fontconfig or FreeType. 0x0502 is XP x64 and Server
# 2003, the first 64-bit Windows.
#
# OPENSSL_LIBS reaches Qt 4's configure through the environment; as an
# argument it is ignored silently, hence the check after configure.
RUN \
    set -eux && \
    cd /opt && \
    bash /tmp/build-openssl.sh /opt/$OPENSSL_DISTRO mingw64 /opt/openssl-3 \
        no-shared no-tests --cross-compile-prefix=x86_64-w64-mingw32- -D_WIN32_WINNT=0x0502 && \
    tar -xzf $QT4_DISTRO && \
    mv $QT4_SRC_DIR Qt-4.8 && \
    rm -f $QT4_DISTRO && \
    cd /opt/Qt-4.8/ && \
    for p in /tmp/patches/qt4/all/*.patch /tmp/patches/qt4/windows/*.patch; do echo "applying $p"; patch -p1 < "$p"; done && \
    OPENSSL_LIBS="-L/opt/openssl-3/lib64 -L/opt/openssl-3/lib -lssl -lcrypto -lcrypt32 -lws2_32 -lgdi32 -luser32 -ladvapi32" \
    ./configure -prefix "/usr/local/Qt-4.8" \
    -opensource -confirm-license -release -static \
    -platform linux-g++ \
    -xplatform win32-g++ -device-option CROSS_COMPILE=x86_64-w64-mingw32- \
    -openssl-linked -I/opt/openssl-3/include -L/opt/openssl-3/lib64 -L/opt/openssl-3/lib \
    -nomake demos -nomake examples -nomake docs -nomake translations -nomake tests \
    -no-webkit -no-phonon -no-phonon-backend -no-glib -no-gtkstyle \
    -no-dbus -no-cups -no-icu -no-pch -no-separate-debug-info -no-openvg \
    -no-sql-mysql -no-sql-psql -no-sql-odbc -qt-sql-sqlite \
    -qt-zlib -qt-libpng -qt-libjpeg -qt-libtiff -qt-libmng \
    -opengl desktop -qt3support -xmlpatterns -script -scripttools -svg -declarative \
    -multimedia -audio-backend -accessibility -stl -exceptions -largefile && \
    grep -q "openssl-linked" mkspecs/qconfig.pri || \
        { echo "configure did not enable linked OpenSSL - check OPENSSL_LIBS" >&2; exit 1; } && \
    make -j "${PARALLEL_JOBS:-$(nproc)}" && \
    make install && \
    echo "SDK prefix to be shipped:" && du -sh /usr/local/Qt-4.8 && \
    exit 0

# ---------------------------------------------------------------------------
# final: the toolchain stage plus the installed SDK, with the test suite built
# against it.
# ---------------------------------------------------------------------------
FROM toolchain

ARG PARALLEL_JOBS=""

COPY --from=builder /usr/local/Qt-4.8 /usr/local/Qt-4.8
# libQtNetwork.prl names -lssl -lcrypto and their -L path, so OpenSSL travels too.
COPY --from=builder /opt/openssl-3 /opt/openssl-3

ENV PATH="/usr/local/Qt-4.8/bin:${PATH}"

COPY tests /tmp/qt4-smoke-tests
# qt4-tests.sh finds the dependency check beside itself; here it proves the
# static libgcc and libstdc++ reached the link.
COPY scripts/build/qt4-tests.sh scripts/audit/qt4-check-deps.sh /tmp/qt4-build/

# Building the suite against the installed SDK alone proves it self-contained,
# and exercises the Linux qmake and moc of this cross SDK. The executables
# in /opt/qt4-smoke-bin run on Windows (make qt4-extract-tests).
RUN bash /tmp/qt4-build/qt4-tests.sh /usr/local/Qt-4.8 /tmp/qt4-smoke-tests /opt/qt4-smoke-bin "$(nproc)" \
        -spec /usr/local/Qt-4.8/mkspecs/win32-g++ -unix && \
    for f in /opt/qt4-smoke-bin/*; do bash /tmp/qt4-build/qt4-check-deps.sh "$f"; done

ENTRYPOINT ["/bin/bash", "-l", "-c"]
