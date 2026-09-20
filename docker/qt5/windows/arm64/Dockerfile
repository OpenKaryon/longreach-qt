# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2026 OpenKaryon
#
# Qt 5.15, static, for Windows on ARM64 (from Windows 10), cross-built with
# LLVM-MinGW. The x86 patches apply; their XP branches always find the newer
# API here.
#
#   toolchain  LLVM-MinGW and what Qt's configure needs
#   builder    patch, configure, build, install
#   final      the toolchain plus the installed SDK and the tests/ suite

# ---------------------------------------------------------------------------
# toolchain: LLVM-MinGW, shared by the builder and the final image.
# The whole toolchain is one tarball, so the base only supplies python, perl
# and a shell (the x86 images pin 18.04 for MinGW-w64 runtime v5 instead).
# ---------------------------------------------------------------------------
FROM --platform=linux/amd64 debian:12 AS toolchain

# LLVM-MinGW: clang plus the aarch64 mingw-w64 headers and import libraries,
# from the build context (make download-llvm-mingw). Another release:
#     make qt5-win-arm64 LLVM_MINGW_VERSION=... LLVM_MINGW_ARCHIVE=... LLVM_MINGW_SHA256=...
ARG LLVM_MINGW_ARCHIVE="llvm-mingw-20241217-ucrt-ubuntu-20.04-x86_64.tar.xz"
ARG LLVM_MINGW_SHA256="cfe4aac3d245a77d8cd0c41bdcd7971b1002c771d3bba2ac39702733b0fb0c12"
ARG DOWNLOAD_DIR="downloads"

# Every LLVM-MinGW release carries the aarch64 triple.
ARG TARGET_PREFIX="aarch64-w64-mingw32-"

RUN \
    set -eux && \
    export DEBIAN_FRONTEND=noninteractive && \
    apt-get -y update && \
    apt-get -y upgrade && \
    apt-get -y install \
        build-essential python3 python-is-python3 perl git wget ca-certificates \
        xz-utils file && \
    apt-get -y autoremove && \
    apt-get -y autoclean && \
    apt-get -y clean && \
    rm -rf /var/lib/apt/lists/* && \
    exit 0

COPY ${DOWNLOAD_DIR}/${LLVM_MINGW_ARCHIVE} /tmp/${LLVM_MINGW_ARCHIVE}

# The checksum is checked where the file is used and coreutils exist.
RUN \
    set -eux && \
    echo "${LLVM_MINGW_SHA256}  /tmp/${LLVM_MINGW_ARCHIVE}" | sha256sum -c - && \
    mkdir -p /opt/llvm-mingw && \
    tar -C /opt/llvm-mingw --strip-components=1 -xf /tmp/${LLVM_MINGW_ARCHIVE} && \
    ln -sf libsecur32.a /opt/llvm-mingw/aarch64-w64-mingw32/lib/libSecur32.a && \
    ln -sf libcrypt32.a /opt/llvm-mingw/aarch64-w64-mingw32/lib/libCrypt32.a && \
    rm -f /tmp/${LLVM_MINGW_ARCHIVE} && \
    exit 0
ENV PATH="/opt/llvm-mingw/bin:$PATH"

# The toolchain must produce ARM64 PE before Qt is built with it.
RUN \
    set -eux && \
    printf '#include <windows.h>\nint main() { return GetTickCount() ? 0 : 1; }\n' > /tmp/probe.cpp && \
    "${TARGET_PREFIX}clang++" -O2 -static /tmp/probe.cpp -o /tmp/probe.exe && \
    file /tmp/probe.exe && \
    file /tmp/probe.exe | grep -q Aarch64 && \
    rm -f /tmp/probe.cpp /tmp/probe.exe && \
    exit 0

# ---------------------------------------------------------------------------
# builder: unpack, patch, configure, build and install Qt.
# ---------------------------------------------------------------------------
FROM toolchain AS builder

ARG QT_FULL_VERSION="5.15.19"
ARG QT_DISTRO="qt-everywhere-opensource-src-${QT_FULL_VERSION}.tar.xz"
ARG DOWNLOAD_DIR="downloads"
ARG QT_SRC_DIR="qt-everywhere-src-${QT_FULL_VERSION}"
ARG QT_OPENGL_CONFIG="-opengl desktop"
ARG PARALLEL_JOBS=""
# ARGs do not cross FROM.
ARG TARGET_PREFIX

# patches/qt5/all for every Qt 5 target, patches/qt5/windows for Windows.
COPY patches/qt5/all /tmp/patches/all
COPY patches/qt5/windows /tmp/patches/windows
COPY ${DOWNLOAD_DIR}/${QT_DISTRO} /opt/${QT_DISTRO}

# win32-clang-g++ takes the toolchain from CROSS_COMPILE, so it serves aarch64
# as is; there is no x86 to give -no-avx to. The module set is the x86 one.
#
# -no-d3d12: LLVM-MinGW ships d3d12.h, so Qt Quick's D3D12 backend would be
# built, and its shaders need Microsoft's fxc.
#
# -no-feature-geoservices_mapboxgl: the boost 1.65 and rapidjson 1.1 vendored
# in QtLocation's mapbox-gl-native do not compile with clang 19 (both fixed in
# later versions of those libraries); the other geoservices plugins are built.
RUN \
    set -eux && \
    cd /opt && \
    tar -xJf $QT_DISTRO && \
    mv $QT_SRC_DIR Qt-5.15 && \
    rm -f $QT_DISTRO && \
    cd /opt/Qt-5.15/ && \
    for p in /tmp/patches/all/*.patch /tmp/patches/windows/*.patch; do echo "applying $p"; git apply "$p"; done && \
    ./configure -v -prefix "/usr/local/Qt-5.15" \
    -xplatform win32-clang-g++ -device-option CROSS_COMPILE="$TARGET_PREFIX" \
    -c++std c++14 -static -static-runtime -optimize-size -release -opensource -confirm-license \
    -nomake examples -nomake tests -nomake tools -skip qtwebengine -no-angle -no-cups -no-dbus -no-fontconfig -gif -no-iconv \
    -no-icu $QT_OPENGL_CONFIG -no-openssl -schannel -no-openvg -no-pch -sql-sqlite -qt-sqlite -ssl \
    -no-d3d12 -no-feature-geoservices_mapboxgl \
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

ENV PATH="/usr/local/Qt-5.15/bin:$PATH"

# CMake for tests/ (Qt 5.15's static plugin import needs 3.15+), installed
# here so the builder's cache stays valid.
ARG CMAKE_VERSION="3.28.6"
COPY scripts/build/cmake.sh /tmp/build-cmake.sh
RUN bash /tmp/build-cmake.sh "${CMAKE_VERSION}" /opt/cmake

ENV PATH="/opt/cmake/bin:${PATH}"

COPY tests /tmp/qt-smoke-tests
COPY cmake/qt5 /tmp/qt-smoke-cmake
COPY scripts/build/tests.sh /tmp/build-tests.sh

# Building the suite against the installed SDK alone proves it self-contained;
# running it needs an ARM64 Windows machine.
RUN SMOKE_CMAKE_TOOLCHAIN=/tmp/qt-smoke-cmake/toolchain-win-arm64.cmake \
    bash /tmp/build-tests.sh /tmp/qt-smoke-tests /opt/qt-smoke-bin

ENTRYPOINT ["/bin/bash", "-l", "-c"]
