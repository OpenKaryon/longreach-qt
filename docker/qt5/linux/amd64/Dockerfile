# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2026 OpenKaryon
#
# Qt 5.15 for Linux amd64 from Ubuntu 10.04 Lucid (glibc 2.11, libxcb 1.5,
# libX11 1.3): make qt5-linux-amd64. docker/qt5/linux/i386 is the same build
# for i386; LUCID_ARCH picks the packages, LUCID_PLATFORM the build image whose
# GCC decides the target.
#
#   toolchain   Ubuntu 16.04's GCC 5.4 with the pinned Lucid headers and
#               libraries (scripts/fetch/locks/qt5-lucid-<arch>-packages.json),
#               libstdc++ rebuilt against glibc 2.11
#   xdeps       the static X client libraries the xcb plugin needs over Lucid's
#               libxcb 1.5 (scripts/build/qt5-lucid/build-xdeps.sh)
#   builder     OpenSSL 3 and Qt with the linux-lucid-g++ mkspec and the
#               run-time fallbacks of patches/qt5/linux
#   final       the SDK plus the tests/ suite
#
# 64-bit glibc 2.11 needs the vsyscall page, which Docker Desktop's WSL2 kernel
# lacks: run the binaries on Lucid or a newer distribution.

# ---------------------------------------------------------------------------
ARG LUCID_PLATFORM=amd64
FROM --platform=linux/${LUCID_PLATFORM} ubuntu:16.04 AS toolchain
ARG LUCID_ARCH=amd64
ARG PARALLEL_JOBS=6
ENV LUCID_JOBS=${PARALLEL_JOBS} DEBIAN_FRONTEND=noninteractive
RUN apt-get update && apt-get install -y --no-install-recommends \
        build-essential python3 xz-utils file ca-certificates && \
    rm -rf /var/lib/apt/lists/*
COPY downloads/ubuntu-lucid-${LUCID_ARCH} /packages
COPY downloads/gcc-5.5.0.tar.xz /archives/
COPY scripts/build/qt5-lucid /scripts
RUN bash /scripts/prepare.sh && rm -rf /work/gcc-source /work/cxx-build
ENV PATH="/work/toolchain/bin:${PATH}"
LABEL org.openkaryon.longreach-qt.platform="ubuntu-lucid-${LUCID_ARCH}" \
      org.openkaryon.longreach-qt.glibc="2.11"

# ---------------------------------------------------------------------------
FROM toolchain AS xdeps
ARG PARALLEL_JOBS=6
ENV LUCID_JOBS=${PARALLEL_JOBS}
RUN apt-get update && apt-get install -y --no-install-recommends \
        pkg-config python bison flex bzip2 libwayland-dev libasound2-dev libpulse-dev \
        libglib2.0-dev libspeechd-dev libbluetooth-dev libgstreamer1.0-dev \
        libgstreamer-plugins-base1.0-dev && rm -rf /var/lib/apt/lists/*
COPY downloads/lucid-xsrc /xsrc
COPY scripts/build/qt5-lucid/build-xdeps.sh scripts/build/qt5-lucid/xcb-lucid-compat.c scripts/build/qt5-lucid/x11-xcb-stub.c /scripts/
RUN bash /scripts/build-xdeps.sh && rm -rf /work/xsrc
# Wayland, ALSA, PulseAudio, speech-dispatcher, BlueZ and GStreamer without
# depending on them at run time: dlopen stubs (build-optional-dlopen.sh).
COPY scripts/build/dlopen /scripts/dlopen
RUN bash /scripts/build-optional-dlopen.sh

# ---------------------------------------------------------------------------
FROM xdeps AS builder

ARG PARALLEL_JOBS=6
ARG LICENSE_PROFILE="gpl-enabled"
ARG QT_FULL_VERSION="5.15.19"
ARG QT_DISTRO="qt-everywhere-opensource-src-${QT_FULL_VERSION}.tar.xz"
ARG QT_SRC_DIR="qt-everywhere-src-${QT_FULL_VERSION}"
ARG OPENSSL_VERSION="3.5.7"
ARG OPENSSL_DISTRO="openssl-${OPENSSL_VERSION}.tar.gz"

RUN apt-get update && apt-get install -y --no-install-recommends perl git && \
    rm -rf /var/lib/apt/lists/*

COPY downloads/${QT_DISTRO} /opt/${QT_DISTRO}
COPY downloads/${OPENSSL_DISTRO} /opt/${OPENSSL_DISTRO}
COPY patches/qt5/all /tmp/patches/all
COPY patches/qt5/linux /tmp/patches/linux
COPY scripts/build/qt5-lucid/mkspecs/linux-lucid-g++ /tmp/linux-lucid-g++
COPY scripts/build/openssl.sh /tmp/build-openssl.sh
COPY scripts/build/license-configure-args.sh /tmp/license-configure-args.sh

ENV PKG_CONFIG_SYSROOT_DIR=/work/sysroot \
    PKG_CONFIG_LIBDIR=/work/sysroot/usr/local/lib/pkgconfig:/work/sysroot/usr/local/share/pkgconfig:/work/sysroot/usr/lib/pkgconfig:/work/sysroot/usr/share/pkgconfig

RUN set -eux; cd /opt; \
    CC=lucid-gcc PARALLEL_JOBS="$PARALLEL_JOBS" bash /tmp/build-openssl.sh /opt/$OPENSSL_DISTRO "$(case "$(gcc -dumpmachine)" in x86_64*) echo linux-x86_64;; *) echo linux-elf;; esac)" /opt/openssl-3 \
        no-async no-shared no-tests > /tmp/openssl.log 2>&1 || { tail -40 /tmp/openssl.log; exit 1; }; \
    tar -xJf $QT_DISTRO; mv $QT_SRC_DIR Qt-5.15; rm -f $QT_DISTRO; cd /opt/Qt-5.15; \
    for p in /tmp/patches/all/*.patch /tmp/patches/linux/*.patch; do echo "applying $p"; git apply "$p"; done; \
    cp -r /tmp/linux-lucid-g++ qtbase/mkspecs/; \
    ./configure -v -platform linux-lucid-g++ -prefix /usr/local/Qt-5.15 -pkg-config \
        OPENSSL_PATH=/opt/openssl-3 \
        OPENSSL_LIBS="-L/opt/openssl-3/lib64 -L/opt/openssl-3/lib -lssl -lcrypto -ldl -pthread" \
        -no-avx -c++std c++14 -static -optimize-size -release -opensource -confirm-license \
        -xcb -bundled-xcb-xinput -xkbcommon -fontconfig -system-freetype \
        -nomake examples -nomake tests -nomake tools \
        -no-cups -dbus-runtime -alsa -pulseaudio -gstreamer 1.0 -speechd -gif -no-iconv -no-icu -no-glib -opengl desktop -openssl-linked -no-openvg -no-pch \
        -sql-sqlite -qt-sqlite -ssl -no-libudev -no-libinput -no-mtdev -no-tslib \
        -make libs -qt-harfbuzz -qt-libjpeg -qt-libpng -qt-pcre -qt-zlib \
        -skip qtwebengine \
        $(/tmp/license-configure-args.sh qt5 "$LICENSE_PROFILE") > /tmp/configure.log 2>&1 \
        || { tail -80 /tmp/configure.log; exit 1; }; \
    grep -E "XCB|Xlib|GLX|OpenGL|xkbcommon|Fontconfig|FreeType|OpenSSL|Wayland|ALSA|PulseAudio|GStreamer|Speech|BlueZ" /tmp/configure.log | head -60; \
    make -j "$PARALLEL_JOBS" > /tmp/make.log 2>&1 || { grep -n -E "error|undefined reference" /tmp/make.log | head -60; exit 1; }; \
    make install > /dev/null; \
    du -sh /usr/local/Qt-5.15

# ---------------------------------------------------------------------------
FROM xdeps
ARG PARALLEL_JOBS=6
ARG LICENSE_PROFILE="gpl-enabled"
COPY --from=builder /usr/local/Qt-5.15 /usr/local/Qt-5.15
COPY --from=builder /opt/openssl-3 /opt/openssl-3
ENV PATH="/usr/local/Qt-5.15/bin:${PATH}" \
    PKG_CONFIG_SYSROOT_DIR=/work/sysroot \
    PKG_CONFIG_LIBDIR=/work/sysroot/usr/local/lib/pkgconfig:/work/sysroot/usr/local/share/pkgconfig:/work/sysroot/usr/lib/pkgconfig:/work/sysroot/usr/share/pkgconfig

# CMake for the tests/ suite (Qt 5.15's static plugin import needs 3.15+).
ARG CMAKE_VERSION="3.28.6"
RUN apt-get update && apt-get install -y --no-install-recommends wget ca-certificates libssl-dev && \
    rm -rf /var/lib/apt/lists/*
COPY scripts/build/cmake.sh /tmp/build-cmake.sh
RUN bash /tmp/build-cmake.sh "${CMAKE_VERSION}" /opt/cmake
ENV PATH="/opt/cmake/bin:${PATH}"

COPY cmake/qt5/toolchain-linux-amd64.cmake /opt/toolchain-lucid.cmake
COPY tests /tmp/qt-smoke-tests
COPY scripts/build/tests.sh /tmp/build-tests.sh
RUN SMOKE_CMAKE_TOOLCHAIN=/opt/toolchain-lucid.cmake SMOKE_OPENSSL_PREFIX=/opt/openssl-3 \
    SMOKE_LICENSE_PROFILE="$LICENSE_PROFILE" bash /tmp/build-tests.sh /tmp/qt-smoke-tests /opt/qt-smoke-bin
ENTRYPOINT ["/bin/bash", "-l", "-c"]
