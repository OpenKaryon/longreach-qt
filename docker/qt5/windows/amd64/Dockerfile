# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2026 OpenKaryon
#
# Qt 5.15, static, for Windows x86_64 from XP x64 and Server 2003, with
# MinGW-w64. Ubuntu 18.04: GCC 7.3 builds Qt 5.15, and its MinGW-w64 runtime v5
# imports nothing XP lacks (v7 in 20.04 pulls Vista-only CRT imports).
#
#   toolchain  the MinGW cross-compiler
#   builder    patch, configure, build, install
#   final      the toolchain plus the installed SDK and the tests/ suite
#
# -no-dbus stays: this configuration is the one validated on real XP hardware.

# ---------------------------------------------------------------------------
# toolchain: the MinGW cross-compiler, shared by builder and final.
# ---------------------------------------------------------------------------
FROM --platform=linux/amd64 ubuntu:18.04 AS toolchain

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

ARG QT_FULL_VERSION="5.15.19"
ARG QT_DISTRO="qt-everywhere-opensource-src-${QT_FULL_VERSION}.tar.xz"
ARG OPENSSL_VERSION="3.5.7"
ARG OPENSSL_DISTRO="openssl-${OPENSSL_VERSION}.tar.gz"
ARG DOWNLOAD_DIR="downloads"
ARG QT_SRC_DIR="qt-everywhere-src-${QT_FULL_VERSION}"
ARG QT_OPENGL_CONFIG="-opengl desktop"
ARG PARALLEL_JOBS=""

# patches/qt5/all for every Qt 5 target, patches/qt5/windows for Windows.
COPY patches/qt5/all /tmp/patches/all
COPY patches/qt5/windows /tmp/patches/windows
COPY ${DOWNLOAD_DIR}/${QT_DISTRO} /opt/${QT_DISTRO}
COPY ${DOWNLOAD_DIR}/${OPENSSL_DISTRO} /opt/${OPENSSL_DISTRO}
COPY scripts/build/openssl.sh /tmp/build-openssl.sh

RUN \
    set -eux && \
    cd /opt && \
    bash /tmp/build-openssl.sh /opt/$OPENSSL_DISTRO mingw64 /opt/openssl-3 \
        no-async no-shared no-tests --cross-compile-prefix=x86_64-w64-mingw32- -D_WIN32_WINNT=0x0501 && \
    tar -xJf $QT_DISTRO && \
    mv $QT_SRC_DIR Qt-5.15 && \
    rm -f $QT_DISTRO && \
    cd /opt/Qt-5.15/ && \
    for p in /tmp/patches/all/*.patch /tmp/patches/windows/*.patch; do echo "applying $p"; git apply "$p"; done && \
    ./configure -v -prefix "/usr/local/Qt-5.15" \
    OPENSSL_PATH=/opt/openssl-3 \
    OPENSSL_LIBS="-L/opt/openssl-3/lib64 -lssl -lcrypto -lcrypt32 -lws2_32 -lgdi32 -luser32 -ladvapi32" \
    -xplatform win32-g++ -device-option CROSS_COMPILE=x86_64-w64-mingw32- \
    -no-avx -c++std c++14 -static -static-runtime -optimize-size -release -opensource -confirm-license \
    -nomake examples -nomake tests -nomake tools -skip qtwebengine -no-angle -no-cups -no-dbus -no-fontconfig -gif -no-iconv \
    -no-icu $QT_OPENGL_CONFIG -openssl-linked -no-openvg -no-pch -sql-sqlite -qt-sqlite -ssl \
    -make libs -qt-freetype -qt-harfbuzz -qt-libjpeg -qt-libpng -qt-pcre -qt-zlib && \
    make -j "${PARALLEL_JOBS:-$(nproc)}" && \
    make install && \
    echo "SDK prefix to be shipped:" && du -sh /usr/local/Qt-5.15 && \
    exit 0

# ---------------------------------------------------------------------------
# final: the toolchain stage plus the installed SDK, with tests/ built
# against it.
# ---------------------------------------------------------------------------
FROM toolchain

ARG PARALLEL_JOBS=""

COPY --from=builder /usr/local/Qt-5.15 /usr/local/Qt-5.15
COPY --from=builder /opt/openssl-3 /opt/openssl-3

ENV PATH="${PATH}:/usr/local/Qt-5.15/bin"

# CMake for tests/ (Qt 5.15's static plugin import needs 3.15+; 18.04 has
# 3.10), installed here so the builder's cache stays valid.
ARG CMAKE_VERSION="3.28.6"
COPY scripts/build/cmake.sh /tmp/build-cmake.sh
RUN bash /tmp/build-cmake.sh "${CMAKE_VERSION}" /opt/cmake

ENV PATH="/opt/cmake/bin:${PATH}"

COPY tests /tmp/qt-smoke-tests
COPY cmake/qt5 /tmp/qt-smoke-cmake
COPY scripts/build/tests.sh /tmp/build-tests.sh

# Building the suite against the installed SDK alone proves it self-contained.
RUN SMOKE_CMAKE_TOOLCHAIN=/tmp/qt-smoke-cmake/toolchain-win-amd64.cmake \
    bash /tmp/build-tests.sh /tmp/qt-smoke-tests /opt/qt-smoke-bin

ENTRYPOINT ["/bin/bash", "-l", "-c"]
