# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2026 OpenKaryon
#
# Qt 5.15 for Linux arm64 from Ubuntu 14.04 (glibc 2.19), cross-built the way
# the Lucid builds are: make qt5-linux-arm64.
#
#   sysroot     the Ubuntu 14.04 arm64 packages of
#               scripts/build/qt5-linux-arm64/packages.txt, unpacked
#   toolchain   Ubuntu 16.04's aarch64 GCC 5 pointed at the sysroot, the
#               Lucid build's static X libraries (libxcb 1.11 extensions,
#               xcb-util, xkbcommon) and the optional libraries as dlopen
#               stubs (build-optional-dlopen.sh)
#   builder     OpenSSL 3 and Qt with the linux-trusty-aarch64-g++ mkspec
#   final       the SDK plus the tests/ suite

# ---------------------------------------------------------------------------

# Base images are pinned by digest; BASE_REGISTRY is where they are pulled
# from (the OpenKaryonLab copy, or docker.io/library: docs/sources.md).
ARG BASE_REGISTRY=ghcr.io/openkaryonlab
FROM ${BASE_REGISTRY}/ubuntu:14.04@sha256:64483f3496c1373bfd55348e88694d1c4d0c9b660dee6bfef5e12f43b9933b30 AS sysroot
COPY scripts/build/qt5-linux-arm64/packages.txt /tmp/packages.txt
# The arm64 packages come from ports.ubuntu.com, verified by apt; the
# architecture-independent ones (protocol headers) from the amd64 archive.
RUN set -eux; \
    dpkg --add-architecture arm64; \
    sed -i 's/^deb /deb [arch=amd64] /' /etc/apt/sources.list; \
    for pocket in trusty trusty-updates trusty-security; do \
        echo "deb [arch=arm64] http://ports.ubuntu.com/ubuntu-ports $pocket main universe" >> /etc/apt/sources.list; \
    done; \
    apt-get update; \
    mkdir -p /debs /sysroot; cd /debs; \
    for p in $(grep -v '^#' /tmp/packages.txt); do \
        if apt-cache show --no-all-versions "$p" | grep -q '^Architecture: all'; then echo "$p"; else echo "$p:arm64"; fi; \
    done > /tmp/download.txt; \
    apt-get download $(cat /tmp/download.txt); \
    for deb in *.deb; do dpkg-deb -x "$deb" /sysroot; done; \
    ls /debs | wc -l

# ---------------------------------------------------------------------------
FROM ${BASE_REGISTRY}/ubuntu:16.04@sha256:1f1a2d56de1d604801a9671f301190704c25d604a416f59e03c04f5c6ffee0d6 AS toolchain
ARG PARALLEL_JOBS=6
ENV JOBS=${PARALLEL_JOBS} DEBIAN_FRONTEND=noninteractive
# The -dev packages give the headers and the function names of the optional
# libraries; nothing of the build image's own architecture is linked.
RUN apt-get update && apt-get install -y --no-install-recommends \
        g++-5-aarch64-linux-gnu binutils-aarch64-linux-gnu build-essential \
        python python3 perl git bison flex pkg-config xz-utils bzip2 autotools-dev file ca-certificates \
        libwayland-dev libasound2-dev libpulse-dev libglib2.0-dev libspeechd-dev libbluetooth-dev \
        libgstreamer1.0-dev libgstreamer-plugins-base1.0-dev && \
    rm -rf /var/lib/apt/lists/*
COPY --from=sysroot /sysroot /work/sysroot
COPY scripts/build/qt5-linux-arm64/gcc /work/toolchain/bin/aarch64-trusty-gcc
COPY scripts/build/qt5-linux-arm64/g++ /work/toolchain/bin/aarch64-trusty-g++
RUN chmod +x /work/toolchain/bin/*
ENV PATH="/work/toolchain/bin:${PATH}"
COPY scripts/build/qt5-lucid/relativize-sysroot.py scripts/build/qt5-lucid/max-glibc.py \
     scripts/build/qt5-lucid/probe.cpp scripts/build/qt5-linux-arm64/prepare.sh /scripts/
RUN bash /scripts/prepare.sh
# Qt 5.15 needs libxcb 1.11 and xkbcommon 0.5; 14.04 has 1.10 and 0.4.1. The
# Lucid build's static X libraries fill the gap the same way.
COPY downloads/lucid-xsrc /xsrc
COPY scripts/build/qt5-lucid/build-xdeps.sh scripts/build/qt5-lucid/xcb-lucid-compat.c \
     scripts/build/qt5-lucid/x11-xcb-stub.c /scripts/
RUN XDEPS_CC=aarch64-trusty-gcc XDEPS_CXX=aarch64-trusty-g++ AR=aarch64-linux-gnu-ar LUCID_JOBS=$JOBS \
    bash /scripts/build-xdeps.sh && rm -rf /work/xsrc
# Wayland, ALSA, PulseAudio, speech-dispatcher, BlueZ and GStreamer without
# depending on them at run time: dlopen stubs (build-optional-dlopen.sh).
COPY scripts/build/dlopen /scripts/dlopen
COPY scripts/build/qt5-lucid/build-optional-dlopen.sh scripts/build/qt5-lucid/speechd-missing.c \
     scripts/build/qt5-lucid/gstreamer-init.c /scripts/
RUN CC=aarch64-trusty-gcc NM=aarch64-linux-gnu-nm AR=aarch64-linux-gnu-ar bash /scripts/build-optional-dlopen.sh
# Qt's CMake packages resolve each -l with find_library over the -L
# directories in the order Qt recorded them, the sysroot's own before
# /usr/local, so 14.04's development links (libxcb-icccm.so and the like)
# would win over the static libraries above. They go; only those are linked.
RUN for a in /work/sysroot/usr/local/lib/lib*.a; do \
        n=$(basename "$a" .a); rm -fv "/work/sysroot/usr/lib/aarch64-linux-gnu/$n.so" "/work/sysroot/usr/lib/$n.so"; \
    done
LABEL org.openkaryon.longreach-qt.platform="ubuntu-trusty-arm64" \
      org.openkaryon.longreach-qt.glibc="2.19"

# ---------------------------------------------------------------------------
FROM toolchain AS builder

ARG PARALLEL_JOBS=6
ARG LICENSE_PROFILE="gpl-enabled"
ARG QT_FULL_VERSION="5.15.19"
ARG QT_DISTRO="qt-everywhere-opensource-src-${QT_FULL_VERSION}.tar.xz"
ARG QT_SRC_DIR="qt-everywhere-src-${QT_FULL_VERSION}"
ARG OPENSSL_VERSION="3.5.7"
ARG OPENSSL_DISTRO="openssl-${OPENSSL_VERSION}.tar.gz"

COPY downloads/${QT_DISTRO} /opt/${QT_DISTRO}
COPY downloads/${OPENSSL_DISTRO} /opt/${OPENSSL_DISTRO}
COPY patches/qt5/all /tmp/patches/all
COPY patches/qt5/linux /tmp/patches/linux
COPY scripts/build/qt5-linux-arm64/mkspecs/linux-trusty-aarch64-g++ /tmp/linux-trusty-aarch64-g++
COPY scripts/build/openssl.sh /tmp/build-openssl.sh
COPY scripts/build/license-configure-args.sh /tmp/license-configure-args.sh

ENV PKG_CONFIG_SYSROOT_DIR=/work/sysroot \
    PKG_CONFIG_LIBDIR=/work/sysroot/usr/local/lib/pkgconfig:/work/sysroot/usr/local/share/pkgconfig:/work/sysroot/usr/lib/aarch64-linux-gnu/pkgconfig:/work/sysroot/usr/lib/pkgconfig:/work/sysroot/usr/share/pkgconfig

RUN set -eux; cd /opt; \
    CC=aarch64-trusty-gcc AR=aarch64-linux-gnu-ar RANLIB=aarch64-linux-gnu-ranlib PARALLEL_JOBS="$PARALLEL_JOBS" \
        bash /tmp/build-openssl.sh /opt/$OPENSSL_DISTRO linux-aarch64 /opt/openssl-3 \
        no-async no-shared no-tests > /tmp/openssl.log 2>&1 || { tail -40 /tmp/openssl.log; exit 1; }; \
    tar -xJf $QT_DISTRO; mv $QT_SRC_DIR Qt-5.15; rm -f $QT_DISTRO; cd /opt/Qt-5.15; \
    for p in /tmp/patches/all/*.patch /tmp/patches/linux/*.patch; do echo "applying $p"; git apply "$p"; done; \
    cp -r /tmp/linux-trusty-aarch64-g++ qtbase/mkspecs/; \
    ./configure -v -xplatform linux-trusty-aarch64-g++ -prefix /usr/local/Qt-5.15 -pkg-config \
        OPENSSL_PATH=/opt/openssl-3 \
        OPENSSL_LIBS="-L/opt/openssl-3/lib -lssl -lcrypto -ldl -pthread" \
        -c++std c++14 -static -optimize-size -release -opensource -confirm-license \
        -xcb -bundled-xcb-xinput -xkbcommon -fontconfig -system-freetype \
        -nomake examples -nomake tests -nomake tools \
        -no-cups -dbus-runtime -alsa -pulseaudio -gstreamer 1.0 -speechd -gif -no-iconv -no-icu -no-glib \
        -opengl desktop -openssl-linked -no-openvg -no-pch \
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
FROM toolchain
ARG PARALLEL_JOBS=6
ARG LICENSE_PROFILE="gpl-enabled"
COPY --from=builder /usr/local/Qt-5.15 /usr/local/Qt-5.15
COPY --from=builder /opt/openssl-3 /opt/openssl-3
ENV PATH="/usr/local/Qt-5.15/bin:${PATH}" \
    PKG_CONFIG_SYSROOT_DIR=/work/sysroot \
    PKG_CONFIG_LIBDIR=/work/sysroot/usr/local/lib/pkgconfig:/work/sysroot/usr/local/share/pkgconfig:/work/sysroot/usr/lib/aarch64-linux-gnu/pkgconfig:/work/sysroot/usr/lib/pkgconfig:/work/sysroot/usr/share/pkgconfig

# CMake for the tests/ suite (Qt 5.15's static plugin import needs 3.15+).
ARG CMAKE_VERSION="3.28.6"
RUN apt-get update && apt-get install -y --no-install-recommends wget ca-certificates libssl-dev && \
    rm -rf /var/lib/apt/lists/*
# From the OpenKaryonLab copy (make passes LONGREACH_MIRROR; cmake.sh has the default).
ARG LONGREACH_MIRROR
COPY scripts/build/cmake.sh /tmp/build-cmake.sh
RUN bash /tmp/build-cmake.sh "${CMAKE_VERSION}" /opt/cmake
ENV PATH="/opt/cmake/bin:${PATH}"

COPY cmake/qt5/toolchain-linux-arm64.cmake /opt/toolchain-trusty-arm64.cmake
COPY tests /tmp/qt-smoke-tests
COPY scripts/build/tests.sh /tmp/build-tests.sh
RUN SMOKE_CMAKE_TOOLCHAIN=/opt/toolchain-trusty-arm64.cmake SMOKE_OPENSSL_PREFIX=/opt/openssl-3 \
    SMOKE_LICENSE_PROFILE="$LICENSE_PROFILE" bash /tmp/build-tests.sh /tmp/qt-smoke-tests /opt/qt-smoke-bin
# No binary may need a shared library that the static ones replace.
RUN needed=$(for f in /opt/qt-smoke-bin/*; do aarch64-linux-gnu-readelf -d "$f" 2>/dev/null; done | \
        sed -n 's/.*(NEEDED).*\[\(lib[^.]*\)\.so.*/\1/p' | sort -u); \
    for n in $needed; do \
        if [ -f "/work/sysroot/usr/local/lib/$n.a" ]; then echo "linked shared $n" >&2; exit 1; fi; \
    done; echo "needed: $needed" | tr '\n' ' '
ENTRYPOINT ["/bin/bash", "-l", "-c"]
