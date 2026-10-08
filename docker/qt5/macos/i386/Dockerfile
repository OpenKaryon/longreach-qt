# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2026 OpenKaryon
#
# Qt 5.15, static, for 32-bit Intel Macs from Mac OS X 10.6 (the last system of
# the 2006 Core Duo Macs); 64-bit Macs run the binaries up to 10.14.
#
# Built on the amd64 image's toolchain stage at 10.6 (BASE_IMAGE), plus the i386
# compiler drivers of scripts/build/qt5-macos/build-i386-toolchain.sh, which
# link against the i386 libraries of the 10.7 SDK. Qt itself is the amd64 build
# with -arch i386; patches/qt5/macos 43-47 handle the 32-bit Objective-C
# runtime.

ARG BASE_IMAGE="qt5-macos-toolchain-10.6"

# ---------------------------------------------------------------------------
# toolchain: the amd64 toolchain plus the i386 drivers.
# ---------------------------------------------------------------------------
FROM ${BASE_IMAGE} AS toolchain

ARG DOWNLOAD_DIR="downloads"
ARG LLVM_SRC="llvm-project-14.0.6.src.tar.xz"
# The 10.7 SDK, of which only the i386 libraries are used (QT5_MACOS_I386_LINK_SDK).
ARG I386_LINK_SDK="MacOSX10.7.sdk.tar.xz"
ARG PARALLEL_JOBS=""

COPY ${DOWNLOAD_DIR}/${LLVM_SRC} /opt/staging/${LLVM_SRC}
COPY ${DOWNLOAD_DIR}/${I386_LINK_SDK} /opt/staging/${I386_LINK_SDK}
COPY scripts/build/qt5-macos /tmp/qt5-macos
RUN \
    set -eux && \
    PARALLEL_JOBS="$PARALLEL_JOBS" bash /tmp/qt5-macos/build-i386-toolchain.sh \
        /opt/staging/$LLVM_SRC /opt/staging/$I386_LINK_SDK && \
    rm -rf /opt/staging /tmp/qt5-macos && \
    exit 0

# ---------------------------------------------------------------------------
# builder: unpack, patch, configure, build and install Qt.
# ---------------------------------------------------------------------------
FROM toolchain AS builder

ARG QT_FULL_VERSION="5.15.19"
ARG QT_DISTRO="qt-everywhere-opensource-src-${QT_FULL_VERSION}.tar.xz"
ARG DOWNLOAD_DIR="downloads"
ARG QT_SRC_DIR="qt-everywhere-src-${QT_FULL_VERSION}"
ARG PARALLEL_JOBS=""
ARG OPENSSL_VERSION="3.5.7"
ARG OPENSSL_DISTRO="openssl-${OPENSSL_VERSION}.tar.gz"

COPY patches/qt5/all /tmp/patches/all
COPY patches/qt5/macos /tmp/patches/macos
COPY ${DOWNLOAD_DIR}/${QT_DISTRO} /opt/${QT_DISTRO}
COPY ${DOWNLOAD_DIR}/${OPENSSL_DISTRO} /opt/${OPENSSL_DISTRO}
COPY scripts/build/openssl.sh /tmp/build-openssl.sh

# As in the amd64 image below 10.11 (see its builder stage for each option).
RUN \
    set -eux && \
    prefix=i386-apple-darwin10- && \
    mkdir -p /opt/openssl-3 && \
    CC=${prefix}clang CXX=${prefix}clang++ AR=${prefix}ar RANLIB=${prefix}ranlib \
        MACOSX_DEPLOYMENT_TARGET=10.6 \
        bash /tmp/build-openssl.sh /opt/$OPENSSL_DISTRO darwin-i386-cc /opt/openssl-3 \
        no-async no-shared no-tests && \
    rm -f /opt/$OPENSSL_DISTRO && \
    cd /opt && \
    tar -xJf $QT_DISTRO && \
    mv $QT_SRC_DIR Qt-5.15 && \
    rm -f $QT_DISTRO && \
    cd /opt/Qt-5.15/ && \
    for p in /tmp/patches/all/*.patch /tmp/patches/macos/*.patch; do echo "applying $p"; git apply "$p"; done && \
    sed -i "s|^QMAKE_MACOSX_DEPLOYMENT_TARGET = .*|QMAKE_MACOSX_DEPLOYMENT_TARGET = 10.6|" \
        qtbase/mkspecs/common/macx.conf && \
    grep -q "^QMAKE_MACOSX_DEPLOYMENT_TARGET = 10.6\$" qtbase/mkspecs/common/macx.conf && \
    MACOSX_DEPLOYMENT_TARGET=10.6 ./configure -v -prefix "/usr/local/Qt-5.15" \
        -xplatform macx-clang -device-option CROSS_COMPILE=$prefix QMAKE_APPLE_DEVICE_ARCHS=i386 \
        -no-avx -c++std c++14 -static -optimize-size -release -opensource -confirm-license \
        -nomake examples -nomake tests -nomake tools -no-cups -dbus-runtime -gif -no-iconv \
        -no-icu -opengl desktop -openssl-linked -no-securetransport OPENSSL_PATH=/opt/openssl-3 \
        "OPENSSL_LIBS=-L/opt/openssl-3/lib -lssl -lcrypto" -no-openvg -no-pch -sql-sqlite -qt-sqlite -ssl \
        -make libs -qt-harfbuzz -qt-libjpeg -qt-libpng -qt-pcre -qt-zlib -skip wayland -skip qtwebengine && \
    MACOSX_DEPLOYMENT_TARGET=10.6 make -j "${PARALLEL_JOBS:-$(nproc)}" && \
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

ENV PATH="/usr/local/Qt-5.15/bin:$PATH"

# CMake for the tests/ suite; see the amd64 Dockerfile.
ARG CMAKE_VERSION="3.28.6"
COPY scripts/build/cmake.sh /tmp/build-cmake.sh
RUN bash /tmp/build-cmake.sh "${CMAKE_VERSION}" /opt/cmake

ENV PATH="/opt/cmake/bin:${PATH}"

COPY tests /tmp/qt-smoke-tests
COPY cmake/qt5 /tmp/qt-smoke-cmake
COPY scripts/build/tests.sh /tmp/build-tests.sh

RUN SMOKE_OPENSSL_PREFIX=/opt/openssl-3 \
    SMOKE_CMAKE_TOOLCHAIN=/tmp/qt-smoke-cmake/toolchain-macos-i386.cmake \
    bash /tmp/build-tests.sh /tmp/qt-smoke-tests /opt/qt-smoke-bin

ENTRYPOINT ["/bin/bash", "-l", "-c"]
