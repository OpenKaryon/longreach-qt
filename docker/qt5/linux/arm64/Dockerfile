# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2026 OpenKaryon
#
# Qt 5 for Ubuntu 14.04 on arm64, with upstream LLVM 21.1.8.

ARG SDK_IMAGE=sdk
ARG BASE_REGISTRY=ghcr.io/openkaryonlab
ARG LLVM_TOOLCHAIN_IMAGE=longreach-llvm:21.1.8-linux-arm64-runtime
ARG DOWNLOAD_DIR=downloads
ARG OPENSSL_DISTRO=openssl-3.5.7.tar.gz
ARG QT_DISTRO=qt-everywhere-opensource-src-5.15.19.tar.xz

FROM ${BASE_REGISTRY}/ubuntu:14.04@sha256:64483f3496c1373bfd55348e88694d1c4d0c9b660dee6bfef5e12f43b9933b30 AS sysroot
# An apt-get update that fails on an index it could not fetch.
COPY scripts/build/apt-update.sh /usr/local/bin/apt-update
COPY scripts/build/qt5-linux-arm64/packages.txt /tmp/packages.txt
# The arm64 packages come from ports.ubuntu.com, verified by apt; the
# architecture-independent ones (protocol headers) from the amd64 archive.
RUN set -eux; \
    dpkg --add-architecture arm64; \
    sed -i 's/^deb /deb [arch=amd64] /' /etc/apt/sources.list; \
    for pocket in trusty trusty-updates trusty-security; do \
        echo "deb [arch=arm64] http://ports.ubuntu.com/ubuntu-ports $pocket main universe" >> /etc/apt/sources.list; \
    done; \
    sh /usr/local/bin/apt-update; \
    mkdir -p /debs /sysroot; cd /debs; \
    for p in $(grep -v '^#' /tmp/packages.txt); do \
        if apt-cache show --no-all-versions "$p" | grep -q '^Architecture: all'; then echo "$p"; else echo "$p:arm64"; fi; \
    done > /tmp/download.txt; \
    apt-get download $(cat /tmp/download.txt); \
    for deb in *.deb; do dpkg-deb -x "$deb" /sysroot; done; \
    ls /debs | wc -l

# ---------------------------------------------------------------------------
FROM ${BASE_REGISTRY}/ubuntu:16.04@sha256:1f1a2d56de1d604801a9671f301190704c25d604a416f59e03c04f5c6ffee0d6 AS trusty-gcc
# An apt-get update that fails on an index it could not fetch.
COPY scripts/build/apt-update.sh /usr/local/bin/apt-update
ARG PARALLEL_JOBS=6
ARG DOWNLOAD_DIR
ENV JOBS=${PARALLEL_JOBS} DEBIAN_FRONTEND=noninteractive
# The -dev packages give the headers and the function names of the optional
# libraries; nothing of the build image's own architecture is linked.
RUN sh /usr/local/bin/apt-update && apt-get install -y --no-install-recommends \
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
COPY ${DOWNLOAD_DIR}/lucid-xsrc /xsrc
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

FROM trusty-gcc AS trusty
ARG OPENSSL_DISTRO
RUN --network=none \
    --mount=type=bind,source=${DOWNLOAD_DIR}/${OPENSSL_DISTRO},target=/tmp/openssl.tar.gz \
    --mount=type=bind,source=scripts/build/openssl.sh,target=/tmp/build-openssl.sh \
    { CC=aarch64-trusty-gcc AR=aarch64-linux-gnu-ar RANLIB=aarch64-linux-gnu-ranlib \
        PARALLEL_JOBS="$JOBS" bash /tmp/build-openssl.sh /tmp/openssl.tar.gz linux-aarch64 /opt/openssl-3 \
        no-async no-shared no-tests > /tmp/openssl.log 2>&1 || { tail -40 /tmp/openssl.log; exit 1; }; } && \
    rm -rf /tmp/openssl-build /tmp/openssl.log

FROM ${LLVM_TOOLCHAIN_IMAGE} AS llvm
FROM ${BASE_REGISTRY}/debian:12@sha256:2c037a04925515fdd6ea85ea14a682d0e79931f5e9f5d07b6dbfc6ba12f9e858 AS inputs
ARG APT_SNAPSHOT
ENV DEBIAN_FRONTEND=noninteractive
RUN --mount=type=bind,source=scripts/build/apt-snapshot.sh,target=/tmp/apt-snapshot.sh \
    sh /tmp/apt-snapshot.sh "$APT_SNAPSHOT" && apt-get update -qq && \
    apt-get install -y --no-install-recommends build-essential cmake ninja-build \
        python3 perl pkg-config git bison flex xz-utils libxml2 libexpat1 && \
    rm -rf /var/lib/apt/lists/*
COPY --from=trusty /work/sysroot /work/sysroot
COPY --from=trusty /opt/openssl-3 /opt/openssl-3
COPY --from=trusty /usr/bin/wayland-scanner /usr/local/bin/wayland-scanner
COPY --from=llvm /opt/llvm-21 /opt/llvm-21
COPY --from=llvm /opt/llvm-runtime-21 /opt/llvm-runtime-21
ENV PATH=/opt/llvm-21/bin:${PATH} \
    PKG_CONFIG_SYSROOT_DIR=/work/sysroot \
    PKG_CONFIG_LIBDIR=/work/sysroot/usr/local/lib/pkgconfig:/work/sysroot/usr/local/share/pkgconfig:/work/sysroot/usr/lib/aarch64-linux-gnu/pkgconfig:/work/sysroot/usr/lib/pkgconfig:/work/sysroot/usr/share/pkgconfig \
    LLVM_ROOT=/opt/llvm-21 \
    QT_INSTALL_DIR=/opt/qt5-linux-arm64-llvm

FROM inputs AS build
ARG PARALLEL_JOBS=4
ARG DOWNLOAD_DIR
ARG QT_DISTRO
ARG QT_FULL_VERSION=5.15.19
ARG QT_SHA256=173c2326dae138bbb0d98921e9d911e55c00163d93a6db29f294b5e19ff306ae
ARG LICENSE_PROFILE=gpl-enabled
RUN --network=none \
    --mount=type=bind,source=scripts/build/qt5-linux-arm64,target=/src/qt5-linux-arm64 \
    --mount=type=bind,source=patches/qt5/all,target=/src/patches/qt5/all \
    --mount=type=bind,source=patches/qt5/linux,target=/src/patches/qt5/linux \
    --mount=type=bind,source=patches/qt5/windows-xp-llvm/02-qtscript-host-call-flag.patch,target=/src/qtscript-host-call-flag.patch \
    --mount=type=bind,source=patches/qt5/linux-arm64-llvm,target=/src/patches/qt5/linux-arm64-llvm \
    --mount=type=bind,source=${DOWNLOAD_DIR}/${QT_DISTRO},target=/src/qt.tar.xz \
    --mount=type=bind,source=scripts/build/license-configure-args.sh,target=/src/license-configure-args.sh \
    PARALLEL_JOBS="$PARALLEL_JOBS" bash /src/qt5-linux-arm64/build-llvm.sh

FROM inputs AS sdk
COPY --from=build /opt/qt5-linux-arm64-llvm /opt/qt5-linux-arm64-llvm
COPY --from=build /opt/qt5-llvm /opt/qt5-llvm
COPY cmake/qt5/toolchain-linux-arm64-llvm.cmake /opt/qt5-llvm/toolchain.cmake
ENV PATH=/opt/qt5-linux-arm64-llvm/bin:/opt/qt5-llvm/bin:${PATH} \
    CC=/opt/qt5-llvm/bin/target-cc CXX=/opt/qt5-llvm/bin/target-cxx
ENTRYPOINT ["/bin/bash", "-c"]
CMD ["qmake -query QT_VERSION"]
LABEL org.openkaryon.longreach-qt.platform="ubuntu-trusty-arm64" \
      org.openkaryon.longreach-qt.glibc="2.19"

FROM ${SDK_IMAGE} AS examples
ARG PARALLEL_JOBS=4
ARG LICENSE_PROFILE=gpl-enabled
RUN --network=none \
    --mount=type=bind,source=tests,target=/src/tests \
    --mount=type=bind,source=scripts/build/tests.sh,target=/tmp/build-tests.sh \
    --mount=type=bind,source=scripts/build/qt5-lucid/max-glibc.py,target=/tmp/max-glibc.py \
    --mount=type=bind,source=scripts/build/qt5-linux-arm64/check-llvm-examples.sh,target=/tmp/check-llvm-examples.sh \
    PARALLEL_JOBS="$PARALLEL_JOBS" SMOKE_LICENSE_PROFILE="$LICENSE_PROFILE" bash /tmp/check-llvm-examples.sh
