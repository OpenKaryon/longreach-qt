# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2026 OpenKaryon
#
# Qt 6.8.4 for Linux amd64 from RHEL/CentOS 7.6 (glibc 2.17), built on CentOS 7
# from the vault.centos.org archive with Developer Toolset's GCC 11, which links
# the newer parts of libstdc++ statically: the result needs only RHEL 7's own
# libraries. xcb-util-cursor (not in RHEL 7) is built statically too.

# Base images are pinned by digest; BASE_REGISTRY is where they are pulled
# from (the OpenKaryonLab copy, or docker.io/library: docs/sources.md).
ARG BASE_REGISTRY=ghcr.io/openkaryonlab
FROM ${BASE_REGISTRY}/centos:7.9.2009@sha256:be65f488b7764ad3638f236b7b515b3678369a5124c47b8d32916d6487418ea4

ARG PARALLEL_JOBS=8
ARG QT_VERSION=6.8.4
ARG QT_ARCHIVE=qt-everywhere-src-${QT_VERSION}.tar.xz
ARG LICENSE_PROFILE="gpl-enabled"

RUN set -eux; \
    sed -i -e 's|^mirrorlist=|#mirrorlist=|' \
           -e 's|^#baseurl=http://mirror.centos.org/centos/\$releasever|baseurl=http://vault.centos.org/7.9.2009|' \
        /etc/yum.repos.d/CentOS-*.repo; \
    yum -y install centos-release-scl-rh; \
    sed -i -e 's|^mirrorlist=|#mirrorlist=|' \
           -e 's|^#\?baseurl=http://mirror.centos.org/centos/7/sclo/\$basearch/rh/|baseurl=http://vault.centos.org/7.9.2009/sclo/$basearch/rh/|' \
        /etc/yum.repos.d/CentOS-SCLo-scl-rh.repo; \
    yum -y install \
        devtoolset-11-gcc devtoolset-11-gcc-c++ devtoolset-11-binutils devtoolset-11-make \
        git perl perl-IPC-Cmd perl-Data-Dumper perl-Time-Piece python3 which xz wget \
        ca-certificates m4 pkgconfig \
        mesa-libGL-devel mesa-libEGL-devel fontconfig-devel freetype-devel \
        libX11-devel libXext-devel libXfixes-devel libXi-devel libXrender-devel \
        libxcb-devel xcb-util-devel xcb-util-image-devel xcb-util-keysyms-devel \
        xcb-util-renderutil-devel xcb-util-wm-devel \
        libxkbcommon-devel libxkbcommon-x11-devel wayland-devel mesa-libwayland-egl-devel \
        dejavu-sans-fonts xorg-x11-server-Xvfb xorg-x11-xauth; \
    yum clean all; \
    rm -rf /var/cache/yum
ENV PATH="/opt/rh/devtoolset-11/root/usr/bin:${PATH}" \
    LD_LIBRARY_PATH="/opt/rh/devtoolset-11/root/usr/lib64:/opt/rh/devtoolset-11/root/usr/lib" \
    CC=gcc CXX=g++

# CMake from Kitware's release binaries, which run on glibc 2.17; checked
# against the SHA256 from cmake-3.27.9-SHA-256.txt, kept here. From the
# OpenKaryonLab copy (Kitware's release is on GitHub too).
ARG CMAKE_VERSION=3.27.9
ARG CMAKE_SHA256=72b01478eeb312bf1a0136208957784fe55a7b587f8d9f9142a7fc9b0b9e9a28
ARG LONGREACH_MIRROR=https://github.com/OpenKaryonLab/longreach-qt-sources/releases/download/sources/
RUN set -eu; \
    archive="cmake-${CMAKE_VERSION}-linux-x86_64.tar.gz"; \
    for try in 1 2 3 4 5; do \
        wget -q "${LONGREACH_MIRROR%/}/${archive}" -O "/tmp/${archive}" && break; \
        [ "$try" -lt 5 ] || exit 1; sleep 30; \
    done; \
    echo "${CMAKE_SHA256}  /tmp/${archive}" | sha256sum -c -; \
    tar -xzf "/tmp/${archive}" -C /opt; \
    rm "/tmp/${archive}"
ENV PATH="/opt/cmake-${CMAKE_VERSION}-linux-x86_64/bin:${PATH}"

# Ninja, for Qt and for the tests/ suite (the smoke macro uses -G Ninja).
COPY downloads/ninja-1.12.1.tar.gz /tmp/ninja.tar.gz
RUN set -eux && \
    echo '821bdff48a3f683bc4bb3b6f0b5fe7b2d647cf65d52aeb63328c91a6c6df285a  /tmp/ninja.tar.gz' | sha256sum -c - && \
    mkdir /tmp/ninja && tar -xzf /tmp/ninja.tar.gz -C /tmp/ninja --strip-components=1 && \
    cd /tmp/ninja && cmake -S . -B build -DCMAKE_BUILD_TYPE=Release -DBUILD_TESTING=OFF && \
    cmake --build build --parallel "${PARALLEL_JOBS}" && install -m 755 build/ninja /usr/local/bin/ninja && \
    rm -rf /tmp/ninja /tmp/ninja.tar.gz

# Static xcb-util-cursor, see the header.
COPY downloads/xcb-util-cursor-0.1.5.tar.xz /tmp/xcb-util-cursor.tar.xz
RUN set -eux && \
    echo '0caf99b0d60970f81ce41c7ba694e5eaaf833227bb2cbcdb2f6dc9666a663c57  /tmp/xcb-util-cursor.tar.xz' | sha256sum -c - && \
    mkdir /tmp/xcb-cursor && tar -xJf /tmp/xcb-util-cursor.tar.xz -C /tmp/xcb-cursor --strip-components=1 && \
    cd /tmp/xcb-cursor && ./configure --prefix=/usr --libdir=/usr/lib64 --disable-shared --enable-static --with-pic && \
    make -j "${PARALLEL_JOBS}" && make install && \
    test -f /usr/lib64/libxcb-cursor.a && \
    rm -rf /tmp/xcb-cursor /tmp/xcb-util-cursor.tar.xz

# Static OpenSSL 3.
ARG OPENSSL_VERSION=3.5.7
COPY downloads/openssl-${OPENSSL_VERSION}.tar.gz /tmp/openssl.tar.gz
COPY scripts/build/openssl.sh /tmp/build-openssl.sh
RUN PARALLEL_JOBS="${PARALLEL_JOBS}" bash /tmp/build-openssl.sh /tmp/openssl.tar.gz linux-x86_64 \
        /opt/openssl-3 no-async no-shared no-tests && \
    rm /tmp/openssl.tar.gz /tmp/build-openssl.sh

# Wayland without libwayland at link time: dlopen stubs
# (scripts/build/dlopen/wayland.sh), so that the binaries also start where it
# is not installed, as on a RHEL 7 server.
COPY scripts/build/dlopen /tmp/dlopen
RUN WAYLAND_LIBDIR=/usr/lib64 WAYLAND_EGL=/usr/lib64/libwayland-egl.so.1 \
    WAYLAND_VERSION="$(pkg-config --modversion wayland-client)" \
    WAYLAND_EGL_VERSION="$(pkg-config --modversion wayland-egl)" \
        bash /tmp/dlopen/wayland.sh /opt/wayland-dlopen /opt/wayland-dlopen && \
    rm -rf /tmp/dlopen
ENV PKG_CONFIG_PATH=/opt/wayland-dlopen/lib/pkgconfig

COPY downloads/${QT_ARCHIVE} /tmp/qt-src.tar.xz
RUN tar -xJf /tmp/qt-src.tar.xz -C /opt && rm /tmp/qt-src.tar.xz

COPY patches/qt6/all /tmp/patches-qt6-all
COPY scripts/build/license-configure-args.sh /tmp/license-configure-args.sh
RUN cd /opt/qt-everywhere-src-${QT_VERSION} && \
    for p in /tmp/patches-qt6-all/*.patch; do git apply "$p" || exit 1; done

RUN mkdir -p /opt/qt-build && \
    cd /opt/qt-build && \
    /opt/qt-everywhere-src-${QT_VERSION}/configure \
        -opensource -confirm-license \
        -prefix /opt/qt6-linux-amd64 \
        -release -optimize-size -static \
        -qt-zlib -qt-pcre -qt-libpng -qt-libjpeg -qt-freetype -qt-harfbuzz \
        -nomake examples -nomake tests \
        -skip qtwebengine -skip qtwebview \
        -openssl-linked \
        $(/tmp/license-configure-args.sh qt6 "$LICENSE_PROFILE") \
        -- -DCMAKE_BUILD_TYPE=Release -DCMAKE_DISABLE_PRECOMPILE_HEADERS=ON \
           -DOPENSSL_ROOT_DIR=/opt/openssl-3 -DOPENSSL_USE_STATIC_LIBS=ON && \
    cmake --build . --parallel "${PARALLEL_JOBS}" && \
    cmake --install . && \
    cd / && rm -rf /opt/qt-build && \
    if grep -rIl '/usr/lib64/libwayland' /opt/qt6-linux-amd64/lib/cmake; then \
        echo "Qt links libwayland instead of the stubs" >&2; exit 1; fi

RUN mkdir -p /opt/qt6-linux-amd64/lib && ln -s /usr/share/fonts/dejavu /opt/qt6-linux-amd64/lib/fonts

# As a RHEL 7 desktop has them: Mesa's software rasterizer (Xvfb has no GLX
# without swrast_dri.so) and a machine id (the image's is empty, and libdbus
# aborts without one).
RUN set -eux && \
    yum -y install mesa-dri-drivers dbus && \
    yum clean all && rm -rf /var/cache/yum && \
    dbus-uuidgen > /etc/machine-id

CMD ["sh", "-c", "ldd --version | head -1; gcc --version | head -1"]
