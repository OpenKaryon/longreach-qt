# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2026 OpenKaryon
#
# Qt 4.8.7, static, for Linux amd64 from Debian 3.1 Sarge (glibc 2.3.2), whose
# amd64 packages come from the archived unofficial port: applications run there
# and on every later amd64 Linux (make qt4-linux-amd64). docker/qt4/linux/i386
# is the same build for i386; SARGE_ARCH picks the packages, SARGE_PLATFORM the
# build image whose GCC decides the target.
#
# The compiler runs on Ubuntu 16.04; headers and libraries come from the pinned
# Sarge packages (scripts/fetch/locks/qt4-sarge-<arch>-packages.json). GCC 5.5
# is rebuilt against that sysroot, then OpenSSL 1.0.2u and Qt
# (scripts/build/qt4-sarge).
#
#   toolchain  the Ubuntu host compiler
#   builder    the Sarge sysroot, GCC, OpenSSL and Qt
#   final      the toolchain plus the installed SDK

# ---------------------------------------------------------------------------

# Base images are pinned by digest; BASE_REGISTRY is where they are pulled
# from (the OpenKaryonLab copy, or docker.io/library: docs/sources.md).
ARG BASE_REGISTRY=ghcr.io/openkaryonlab
ARG SARGE_PLATFORM=amd64
FROM --platform=linux/${SARGE_PLATFORM} ${BASE_REGISTRY}/ubuntu:16.04@sha256:1f1a2d56de1d604801a9671f301190704c25d604a416f59e03c04f5c6ffee0d6 AS toolchain
ARG SARGE_ARCH=amd64
ENV SARGE_ARCH=${SARGE_ARCH}

# Qt 4 has no XCB backend: its X11 extensions come through Xlib (Xrender,
# Xrandr, Xcursor, Xfixes, Xinerama, Xi, Xext, SM/ICE), listed so configure
# does not quietly leave them out. Mesa GL/GLU back -opengl desktop; ALSA is
# QtMultimedia's audio backend.
RUN \
    set -eux && \
    export DEBIAN_FRONTEND=noninteractive && \
    apt -y update && \
    apt -y upgrade && \
    apt -y install \
        build-essential python perl git wget nano ca-certificates xz-utils \
        libfontconfig1-dev libfreetype6-dev \
        libx11-dev libxext-dev libxrender-dev libxrandr-dev libxcursor-dev \
        libxfixes-dev libxinerama-dev libxi-dev libsm-dev libice-dev libxt-dev \
        libgl1-mesa-dev libglu1-mesa-dev libasound2-dev && \
    apt -y autoremove && \
    apt -y autoclean && \
    apt -y clean && \
    rm -rf /var/lib/apt/lists/* && \
    exit 0

# mkfontdir generates the font indexes Debian's post-install would create.
RUN apt-get update && apt-get install -y --no-install-recommends xfonts-utils && \
    apt-get clean && rm -rf /var/lib/apt/lists/*

# ---------------------------------------------------------------------------
FROM toolchain AS builder
ARG SARGE_ARCH=amd64
ARG PARALLEL_JOBS=6
ENV SARGE_JOBS=${PARALLEL_JOBS}
COPY downloads/debian-sarge-${SARGE_ARCH} /packages
COPY downloads/gcc-5.5.0.tar.xz downloads/openssl-1.0.2u.tar.gz downloads/qt-everywhere-opensource-src-4.8.7.tar.gz /archives/
COPY scripts/build/qt4-sarge /scripts
COPY patches/qt4/all /patches/all
COPY patches/qt4/linux /patches/linux
RUN mkdir -p /out && bash /scripts/prepare.sh && bash /scripts/build-qt.sh

# ---------------------------------------------------------------------------
FROM toolchain
ARG SARGE_ARCH=amd64
COPY --from=builder /work/sdk /work/sdk
COPY --from=builder /work/sysroot /work/sysroot
COPY --from=builder /work/toolchain /work/toolchain
COPY --from=builder /work/cxx-runtime /work/cxx-runtime
COPY --from=builder /work/openssl-1.0.2u /work/openssl-1.0.2u
COPY --from=builder /out/compiler-probe /opt/qt4-sarge/compiler-probe
COPY --from=builder /work/qt-source/LICENSE.LGPLv21 /work/qt-source/LICENSE.LGPLv3 /work/qt-source/LGPL_EXCEPTION.txt /opt/qt4-sarge/licenses/
COPY --from=builder /work/gcc-source/COPYING3 /work/gcc-source/COPYING.RUNTIME /opt/qt4-sarge/licenses/
COPY --from=builder /work/openssl-source/LICENSE /opt/qt4-sarge/licenses/OPENSSL-LICENSE.txt
COPY downloads/openssl-1.0.2u.tar.gz /opt/qt4-sarge/licenses/
COPY scripts/fetch/locks/qt4-sarge-${SARGE_ARCH}-packages.json /opt/qt4-sarge/packages-lock.json
COPY scripts/build/qt4-sarge /opt/qt4-sarge/scripts
ENV PATH="/work/sdk/bin:/work/toolchain/bin:${PATH}" \
    QMAKESPEC="/work/sdk/mkspecs/linux-sarge-${SARGE_ARCH}-g++" \
    SARGE_LICENSE_DIR="/opt/qt4-sarge/licenses"
LABEL org.openkaryon.longreach-qt.platform="debian-sarge-${SARGE_ARCH}" \
      org.openkaryon.longreach-qt.glibc="2.3.2" \
      org.openkaryon.longreach-qt.openssl="1.0.2u"
RUN ln -s /work/sdk /usr/local/Qt-4.8 && \
    test ! -e /work/qt-source && test ! -e /work/cxx-build && \
    . /opt/qt4-sarge/scripts/arch.sh && \
    "/work/sysroot$SARGE_LOADER" --library-path /work/sysroot/lib:/work/sysroot/usr/lib /opt/qt4-sarge/compiler-probe
ENTRYPOINT ["/bin/bash"]
