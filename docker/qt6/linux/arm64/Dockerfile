# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2026 OpenKaryon
#
# Qt 6.8.4 for Linux arm64 from RHEL/CentOS 7 aarch64 (glibc 2.17), the floor
# of the amd64 build. Cross-built on Debian 12 with its aarch64 GCC 11 against
# a sysroot of CentOS 7.9 aarch64 packages (scripts/build/rpm-sysroot.py) and
# Developer Toolset 10's C++ library, linked as Developer Toolset links it:
# RHEL 7's libstdc++.so.6 plus the newer parts statically. The host tools come
# from the qt6-host image. As for amd64, the result needs only RHEL 7's own
# libraries: OpenSSL and xcb-util-cursor are static, D-Bus is loaded at run
# time, and Wayland is linked through dlopen stubs.

ARG QT_VERSION=6.8.4
ARG QT_ARCHIVE=qt-everywhere-src-${QT_VERSION}.tar.xz
ARG PARALLEL_JOBS=""
# The host Qt image by its tag, which carries the licence profile.
ARG QT6_HOST_IMAGE=qt6-host

FROM ${QT6_HOST_IMAGE} AS host-qt

# ---------------------------------------------------------------------------
# toolchain: the cross-compiler, the CentOS 7 aarch64 sysroot and the host Qt
# ---------------------------------------------------------------------------

FROM debian:12 AS toolchain

ENV DEBIAN_FRONTEND=noninteractive

# qemu-user-static runs the sysroot's wayland-scanner (see its wrapper); the
# libraries after it are what the host tools (qsb and the rest) load.
RUN apt-get update && apt-get install -y --no-install-recommends \
        g++-11-aarch64-linux-gnu binutils-aarch64-linux-gnu \
        cmake ninja-build make m4 perl python3 pkg-config file xz-utils git \
        rpm2cpio cpio qemu-user-static binutils ca-certificates \
        libfontconfig1 libfreetype6 libpng16-16 zlib1g libbrotli1 libglib2.0-0 libdbus-1-3 \
        libx11-6 libx11-xcb1 libxcb1 libxcb-cursor0 libxcb-icccm4 libxcb-image0 libxcb-keysyms1 \
        libxcb-randr0 libxcb-render-util0 libxcb-render0 libxcb-shape0 libxcb-shm0 libxcb-sync1 \
        libxcb-xfixes0 libxcb-xkb1 libxkbcommon0 libxkbcommon-x11-0 \
        libwayland-client0 libwayland-cursor0 libwayland-server0 && \
    rm -rf /var/lib/apt/lists/*

ENV SYSROOT=/opt/sysroot-arm64
COPY scripts/build/rpm-sysroot.py scripts/build/qt6-linux-arm64/packages.txt /tmp/sysroot/
RUN base=http://vault.centos.org/altarch/7.9.2009 && \
    python3 /tmp/sysroot/rpm-sysroot.py --dest ${SYSROOT} --arch aarch64 --merged-usr \
        --repo $base/os/aarch64 --repo $base/updates/aarch64 --repo $base/sclo/aarch64/rh \
        $(grep -v '^#' /tmp/sysroot/packages.txt) > /tmp/sysroot/installed.txt && \
    wc -l < /tmp/sysroot/installed.txt && rm -rf /tmp/sysroot

COPY scripts/build/qt6-linux-arm64/gcc /opt/cross/bin/aarch64-centos7-gcc
COPY scripts/build/qt6-linux-arm64/g++ /opt/cross/bin/aarch64-centos7-g++
COPY scripts/build/qt6-linux-arm64/wayland-scanner /opt/cross/bin/wayland-scanner
RUN chmod +x /opt/cross/bin/*
ENV PATH="/opt/cross/bin:${PATH}"

# The toolchain must produce nothing that needs a glibc newer than RHEL 7's.
COPY scripts/build/qt5-lucid/probe.cpp scripts/build/qt5-lucid/max-glibc.py /tmp/probe/
RUN aarch64-centos7-g++ -std=c++17 -O2 -pthread /tmp/probe/probe.cpp -o /tmp/probe/probe && \
    python3 /tmp/probe/max-glibc.py /tmp/probe/probe 2.17 && rm -rf /tmp/probe

COPY --from=host-qt /opt/qt6-host /opt/qt6-host

# ---------------------------------------------------------------------------
# deps: what Qt links statically, and the Wayland stubs
# ---------------------------------------------------------------------------

FROM toolchain AS deps
ARG PARALLEL_JOBS

# Static OpenSSL 3.
ARG OPENSSL_VERSION=3.5.7
COPY downloads/openssl-${OPENSSL_VERSION}.tar.gz /tmp/openssl.tar.gz
COPY scripts/build/openssl.sh /tmp/build-openssl.sh
RUN CC=aarch64-centos7-gcc AR=aarch64-linux-gnu-ar RANLIB=aarch64-linux-gnu-ranlib \
    PARALLEL_JOBS="${PARALLEL_JOBS:-$(nproc)}" bash /tmp/build-openssl.sh /tmp/openssl.tar.gz linux-aarch64 \
        /opt/openssl-3 no-async no-shared no-tests && \
    rm /tmp/openssl.tar.gz /tmp/build-openssl.sh

# Static xcb-util-cursor (not in RHEL 7), into the sysroot.
COPY downloads/xcb-util-cursor-0.1.5.tar.xz /tmp/xcb-util-cursor.tar.xz
RUN set -eux && \
    echo '0caf99b0d60970f81ce41c7ba694e5eaaf833227bb2cbcdb2f6dc9666a663c57  /tmp/xcb-util-cursor.tar.xz' | sha256sum -c - && \
    mkdir /tmp/xcb-cursor && tar -xJf /tmp/xcb-util-cursor.tar.xz -C /tmp/xcb-cursor --strip-components=1 && \
    cd /tmp/xcb-cursor && \
    PKG_CONFIG_LIBDIR=${SYSROOT}/usr/lib64/pkgconfig:${SYSROOT}/usr/share/pkgconfig PKG_CONFIG_SYSROOT_DIR=${SYSROOT} \
        ./configure --host=aarch64-linux-gnu CC=aarch64-centos7-gcc --prefix=/usr --libdir=/usr/lib64 \
        --disable-shared --enable-static --with-pic && \
    make -j "${PARALLEL_JOBS:-$(nproc)}" && make install DESTDIR=${SYSROOT} && \
    test -f ${SYSROOT}/usr/lib64/libxcb-cursor.a && \
    rm -rf /tmp/xcb-cursor /tmp/xcb-util-cursor.tar.xz

# Wayland without libwayland at link time: dlopen stubs
# (scripts/build/dlopen/wayland.sh), so that the binaries also start where it
# is not installed, as on a RHEL 7 server.
COPY scripts/build/dlopen /tmp/dlopen
RUN CC=aarch64-centos7-gcc NM=aarch64-linux-gnu-nm AR=aarch64-linux-gnu-ar \
    WAYLAND_LIBDIR=${SYSROOT}/usr/lib64 WAYLAND_EGL=${SYSROOT}/usr/lib64/libwayland-egl.so.1 \
    WAYLAND_INCLUDEDIR=${SYSROOT}/usr/include WAYLAND_XML=${SYSROOT}/usr/share/wayland/wayland.xml \
    WAYLAND_SCANNER=/opt/cross/bin/wayland-scanner \
    WAYLAND_VERSION="$(PKG_CONFIG_LIBDIR=${SYSROOT}/usr/lib64/pkgconfig pkg-config --modversion wayland-client)" \
    WAYLAND_EGL_VERSION="$(PKG_CONFIG_LIBDIR=${SYSROOT}/usr/lib64/pkgconfig pkg-config --modversion wayland-egl)" \
        bash /tmp/dlopen/wayland.sh ${SYSROOT}/usr/local /usr/local && \
    rm -rf /tmp/dlopen

# ---------------------------------------------------------------------------
# builder: Qt
# ---------------------------------------------------------------------------

FROM deps AS builder
ARG QT_VERSION
ARG QT_ARCHIVE
ARG PARALLEL_JOBS
ARG LICENSE_PROFILE="gpl-enabled"

COPY downloads/${QT_ARCHIVE} /tmp/qt-src.tar.xz
RUN tar -xJf /tmp/qt-src.tar.xz -C /opt \
        --exclude="qt-everywhere-src-${QT_VERSION}/qtwebengine/*" \
        --exclude="qt-everywhere-src-${QT_VERSION}/qtwebview/*" && \
    rm /tmp/qt-src.tar.xz

COPY patches/qt6/all /tmp/patches-qt6-all
COPY scripts/build/license-configure-args.sh /tmp/license-configure-args.sh
RUN cd /opt/qt-everywhere-src-${QT_VERSION} && \
    for p in /tmp/patches-qt6-all/*.patch; do git apply "$p"; done

COPY cmake/qt6/qt-toolchain-linux-arm64.cmake /workspace/qt-build/toolchain.cmake

# The module set of the amd64 build: not built are qtwebengine and qtwebview
# (Chromium).
RUN mkdir -p /opt/qt-build && cd /opt/qt-build && \
    /opt/qt-everywhere-src-${QT_VERSION}/configure \
        -opensource -confirm-license \
        -prefix /opt/qt6-linux-arm64 \
        -qt-host-path /opt/qt6-host \
        -release -optimize-size -static \
        -qt-zlib -qt-pcre -qt-libpng -qt-libjpeg -qt-freetype -qt-harfbuzz \
        -nomake examples -nomake tests \
        -skip qtwebengine -skip qtwebview \
        -openssl-linked \
        $(/tmp/license-configure-args.sh qt6 "$LICENSE_PROFILE") \
        -- -DCMAKE_TOOLCHAIN_FILE=/workspace/qt-build/toolchain.cmake \
           -DCMAKE_BUILD_TYPE=Release -DCMAKE_DISABLE_PRECOMPILE_HEADERS=ON \
           -DOPENSSL_ROOT_DIR=/opt/openssl-3 -DOPENSSL_USE_STATIC_LIBS=ON && \
    cmake --build . --parallel "${PARALLEL_JOBS:-$(nproc)}" && \
    cmake --install . && \
    cd / && rm -rf /opt/qt-build && \
    if grep -rIl 'usr/lib64/libwayland' /opt/qt6-linux-arm64/lib/cmake; then \
        echo "Qt links libwayland instead of the stubs" >&2; exit 1; fi

# ---------------------------------------------------------------------------
# final: the toolchain, the sysroot, the host tools and the SDK
# ---------------------------------------------------------------------------

FROM deps

COPY --from=builder /opt/qt6-linux-arm64 /opt/qt6-linux-arm64
COPY --from=builder /workspace/qt-build/toolchain.cmake /workspace/qt-build/toolchain.cmake

ENV QT_INSTALL_DIR=/opt/qt6-linux-arm64
ENV PATH="${QT_INSTALL_DIR}/bin:${PATH}"

WORKDIR /workspace

CMD ["bash", "-c", "echo 'Qt 6 for Linux arm64 (RHEL/CentOS 7 aarch64)'; echo 'Qt: /opt/qt6-linux-arm64'; echo 'Sysroot: /opt/sysroot-arm64'"]
