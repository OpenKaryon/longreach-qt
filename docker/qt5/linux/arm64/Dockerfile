# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2026 OpenKaryon
#
# Qt 5.15, static, for Linux arm64 from Ubuntu 16.04, built natively under
# emulation.
#
#   toolchain  compilers and system dependencies
#   builder    patch, configure, build, install
#   final      the toolchain plus the installed SDK and the tests/ suite

# ---------------------------------------------------------------------------
# toolchain: compilers and system dependencies, shared by builder and final.
# ---------------------------------------------------------------------------
FROM --platform=linux/arm64 ubuntu:16.04 AS toolchain

# Mesa GL and GLU back -opengl desktop (Qt3D, DataVisualization, Quick3D,
# QtOpenGL); libvulkan-dev is headers only. libdbus-1-3 is the runtime that
# -dbus-runtime loads: without it the iio-sensor-proxy sensor plugin crashes
# in QSensor::start(). Wayland 1.12 is enough for qtwayland 5.15, which carries
# its own protocol files.
RUN \
    set -eux && \
    export DEBIAN_FRONTEND=noninteractive && \
    apt -y update && \
    apt -y upgrade && \
    apt -y install \
        build-essential python perl git wget nano ca-certificates xz-utils \
        libfontconfig1-dev libfreetype6-dev libxrender-dev libxcb-render0-dev libxcb-render-util0-dev \
        libxcb-shape0-dev libxcb-randr0-dev libxcb-xfixes0-dev libxcb-sync-dev libxcb-shm0-dev \
        libxcb-icccm4-dev libxcb-keysyms1-dev libxcb-image0-dev libxkbcommon-dev libxkbcommon-x11-dev \
        libxext-dev libx11-dev libxcb1-dev libx11-xcb-dev \
        libgl1-mesa-dev libglu1-mesa-dev libvulkan-dev libdbus-1-3 \
        libwayland-dev libegl1-mesa-dev && \
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
ARG PARALLEL_JOBS=""

# patches/qt5/all for every Qt 5 target, patches/qt5/linux for Linux.
COPY patches/qt5/all /tmp/patches/all
COPY patches/qt5/linux /tmp/patches/linux
COPY ${DOWNLOAD_DIR}/${QT_DISTRO} /opt/${QT_DISTRO}
COPY ${DOWNLOAD_DIR}/${OPENSSL_DISTRO} /opt/${OPENSSL_DISTRO}
COPY scripts/build/openssl.sh /tmp/build-openssl.sh

RUN \
    set -eux && \
    cd /opt && \
    bash /tmp/build-openssl.sh /opt/$OPENSSL_DISTRO linux-aarch64 /opt/openssl-3 no-async no-shared no-tests && \
    tar -xJf $QT_DISTRO && \
    mv $QT_SRC_DIR Qt-5.15 && \
    rm -f $QT_DISTRO && \
    cd /opt/Qt-5.15/ && \
    for p in /tmp/patches/all/*.patch /tmp/patches/linux/*.patch; do echo "applying $p"; git apply "$p"; done && \
    ./configure -v -prefix "/usr/local/Qt-5.15" \
    OPENSSL_PATH=/opt/openssl-3 \
    OPENSSL_LIBS="-L/opt/openssl-3/lib -lssl -lcrypto -ldl -pthread" \
    -no-avx -c++std c++14 -static -optimize-size -release -opensource -confirm-license \
    -fontconfig -system-freetype -bundled-xcb-xinput -nomake examples -nomake tests -nomake tools \
    -no-cups -dbus-runtime -gif -no-iconv -no-icu -opengl desktop -openssl-linked -no-openvg -no-pch -sql-sqlite -qt-sqlite -ssl \
    -make libs -qt-harfbuzz -qt-libjpeg -qt-libpng -qt-pcre -qt-zlib -skip qtwebengine && \
    make -j "${PARALLEL_JOBS:-$(nproc)}" && \
    make install && \
    echo "SDK prefix to be shipped:" && du -sh /usr/local/Qt-5.15 && \
    exit 0

# ---------------------------------------------------------------------------
# final: the shipped SDK - the toolchain stage plus the `make install` output,
# with the tests/ suite built against it.
# ---------------------------------------------------------------------------
FROM toolchain

ARG PARALLEL_JOBS=""

COPY --from=builder /usr/local/Qt-5.15 /usr/local/Qt-5.15
COPY --from=builder /opt/openssl-3 /opt/openssl-3

ENV PATH="${PATH}:/usr/local/Qt-5.15/bin"

# CMake for tests/ (Qt 5.15's static plugin import needs 3.15+), installed
# here so the builder's cache stays valid.
ARG CMAKE_VERSION="3.28.6"
COPY scripts/build/cmake.sh /tmp/build-cmake.sh
RUN bash /tmp/build-cmake.sh "${CMAKE_VERSION}" /opt/cmake

ENV PATH="/opt/cmake/bin:${PATH}"

COPY tests /tmp/qt-smoke-tests
COPY scripts/build/tests.sh /tmp/build-tests.sh

# Building the suite against the installed SDK alone proves it self-contained.
# It runs in the container too, offscreen:
#   docker run --rm qt5-linux-arm64-gpl-enabled \
#       'cd /opt/qt-smoke-bin && QT_QPA_PLATFORM=offscreen ./smoke-runner'
RUN SMOKE_OPENSSL_PREFIX=/opt/openssl-3 \
    bash /tmp/build-tests.sh /tmp/qt-smoke-tests /opt/qt-smoke-bin

ENTRYPOINT ["/bin/bash", "-l", "-c"]
