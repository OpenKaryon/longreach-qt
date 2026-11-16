# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2026 OpenKaryon
#
# Qt 5 for Ubuntu 10.04 on amd64 and i386, with upstream LLVM 21.1.8.

ARG SDK_IMAGE=sdk
ARG BASE_REGISTRY=ghcr.io/openkaryonlab
ARG LUCID_PLATFORM=amd64
ARG LUCID_ARCH=amd64
ARG LLVM_COMPILER_IMAGE=longreach-llvm:21.1.8-compiler
ARG DOWNLOAD_DIR=downloads
ARG OPENSSL_DISTRO=openssl-3.5.7.tar.gz
ARG QT_DISTRO=qt-everywhere-opensource-src-5.15.19.tar.xz

FROM --platform=linux/${LUCID_PLATFORM} ${BASE_REGISTRY}/ubuntu:16.04@sha256:1f1a2d56de1d604801a9671f301190704c25d604a416f59e03c04f5c6ffee0d6 AS lucid-gcc
# An apt-get update that fails on an index it could not fetch.
COPY scripts/build/apt-update.sh /usr/local/bin/apt-update
ARG LUCID_ARCH
ARG DOWNLOAD_DIR
ARG PARALLEL_JOBS=6
ENV LUCID_JOBS=${PARALLEL_JOBS} DEBIAN_FRONTEND=noninteractive
RUN sh /usr/local/bin/apt-update && apt-get install -y --no-install-recommends \
        build-essential python3 xz-utils file ca-certificates && \
    rm -rf /var/lib/apt/lists/*
COPY ${DOWNLOAD_DIR}/ubuntu-lucid-${LUCID_ARCH} /packages
COPY scripts/fetch/locks/qt5-lucid-${LUCID_ARCH}-packages.json /packages-lock.json
COPY ${DOWNLOAD_DIR}/gcc-5.5.0.tar.xz /archives/
COPY scripts/build/qt5-lucid/prepare.sh scripts/build/qt5-lucid/relativize-sysroot.py \
     scripts/build/qt5-lucid/build-cxx-runtime.sh scripts/build/qt5-lucid/max-glibc.py \
     scripts/build/qt5-lucid/probe.cpp scripts/build/qt5-lucid/build-optional-dlopen.sh /scripts/
RUN bash /scripts/prepare.sh && rm -rf /work/gcc-source /work/cxx-build
ENV PATH="/work/toolchain/bin:${PATH}"
LABEL org.openkaryon.longreach-qt.platform="ubuntu-lucid-${LUCID_ARCH}" \
      org.openkaryon.longreach-qt.glibc="2.11"

# ---------------------------------------------------------------------------
FROM lucid-gcc AS xdeps
ARG PARALLEL_JOBS=6
ENV LUCID_JOBS=${PARALLEL_JOBS}
RUN sh /usr/local/bin/apt-update && apt-get install -y --no-install-recommends \
        pkg-config python bison flex bzip2 libwayland-dev libasound2-dev libpulse-dev \
        libglib2.0-dev libspeechd-dev libbluetooth-dev libgstreamer1.0-dev \
        libgstreamer-plugins-base1.0-dev && rm -rf /var/lib/apt/lists/*
COPY ${DOWNLOAD_DIR}/lucid-xsrc /xsrc
COPY scripts/build/qt5-lucid/build-xdeps.sh scripts/build/qt5-lucid/xcb-lucid-compat.c scripts/build/qt5-lucid/x11-xcb-stub.c /scripts/
RUN bash /scripts/build-xdeps.sh && rm -rf /work/xsrc
# Wayland, ALSA, PulseAudio, speech-dispatcher, BlueZ and GStreamer without
# depending on them at run time: dlopen stubs (build-optional-dlopen.sh).
COPY scripts/build/dlopen /scripts/dlopen
COPY scripts/build/qt5-lucid/speechd-missing.c scripts/build/qt5-lucid/gstreamer-init.c /scripts/
RUN bash /scripts/build-optional-dlopen.sh

FROM xdeps AS lucid
ARG DOWNLOAD_DIR
ARG OPENSSL_DISTRO
ARG PARALLEL_JOBS=6
RUN --network=none \
    --mount=type=bind,source=${DOWNLOAD_DIR}/${OPENSSL_DISTRO},target=/tmp/openssl.tar.gz \
    --mount=type=bind,source=scripts/build/openssl.sh,target=/tmp/build-openssl.sh \
    target=$(case "$(gcc -dumpmachine)" in x86_64*) echo linux-x86_64;; *) echo linux-elf;; esac) && \
    { CC=lucid-gcc PARALLEL_JOBS="$PARALLEL_JOBS" bash /tmp/build-openssl.sh \
        /tmp/openssl.tar.gz "$target" /opt/openssl-3 no-async no-shared no-tests > /tmp/openssl.log 2>&1 \
        || { tail -40 /tmp/openssl.log; exit 1; }; } && \
    rm -rf /tmp/openssl-build /tmp/openssl.log

FROM ${BASE_REGISTRY}/ubuntu:16.04@sha256:1f1a2d56de1d604801a9671f301190704c25d604a416f59e03c04f5c6ffee0d6 AS lucid-tools
COPY scripts/build/apt-update.sh /usr/local/bin/apt-update
RUN sh /usr/local/bin/apt-update && apt-get install -y --no-install-recommends libwayland-bin && \
    rm -rf /var/lib/apt/lists/*

FROM ${LLVM_COMPILER_IMAGE} AS compiler
FROM ${BASE_REGISTRY}/debian:12@sha256:2c037a04925515fdd6ea85ea14a682d0e79931f5e9f5d07b6dbfc6ba12f9e858 AS inputs
ARG APT_SNAPSHOT
ARG LUCID_ARCH
ENV DEBIAN_FRONTEND=noninteractive
RUN --mount=type=bind,source=scripts/build/apt-snapshot.sh,target=/tmp/apt-snapshot.sh \
    sh /tmp/apt-snapshot.sh "$APT_SNAPSHOT" && apt-get update -qq && \
    apt-get install -y --no-install-recommends build-essential cmake ninja-build \
        python3 perl pkg-config git bison flex xz-utils libxml2 libexpat1 && \
    rm -rf /var/lib/apt/lists/*
COPY --from=lucid /work/sysroot /opt/sysroot-lucid
COPY --from=lucid /opt/openssl-3 /opt/openssl-lucid
COPY --from=lucid-tools /usr/bin/wayland-scanner /usr/local/bin/wayland-scanner
COPY --from=compiler /opt/llvm-21 /opt/llvm-21
# The i386 FreeType header uses register for an output already constrained
# by inline assembly. Clang rejects that specifier in C++17 and newer.
RUN --network=none if [ "$LUCID_ARCH" = i386 ]; then \
        sed -i 's/^    register FT_Int32  result;/    FT_Int32  result;/' \
            /opt/sysroot-lucid/usr/include/freetype2/freetype/config/ftconfig.h; \
    fi
ENV LUCID_ARCH=${LUCID_ARCH} \
    PATH=/opt/llvm-21/bin:${PATH} \
    PKG_CONFIG_SYSROOT_DIR=/opt/sysroot-lucid \
    PKG_CONFIG_LIBDIR=/opt/sysroot-lucid/usr/local/lib/pkgconfig:/opt/sysroot-lucid/usr/local/share/pkgconfig:/opt/sysroot-lucid/usr/lib/pkgconfig:/opt/sysroot-lucid/usr/share/pkgconfig \
    LLVM_ROOT=/opt/llvm-21 \
    QT_INSTALL_DIR=/opt/qt5-linux-${LUCID_ARCH}-llvm

FROM inputs AS build-runtime
ARG PARALLEL_JOBS=4
RUN --network=none \
    --mount=type=bind,source=scripts/build/qt5-lucid/prepare-llvm.sh,target=/src/scripts/build/qt5-lucid/prepare-llvm.sh \
    --mount=type=bind,source=scripts/build/qt5-lucid/max-glibc.py,target=/src/scripts/build/qt5-lucid/max-glibc.py \
    --mount=type=bind,source=scripts/build/qt6-llvm-probes/build-runtime.sh,target=/src/scripts/build/qt6-llvm-probes/build-runtime.sh \
    --mount=type=bind,source=scripts/tests/qt6-llvm-probes,target=/src/scripts/tests/qt6-llvm-probes \
    --mount=type=bind,source=tests/common,target=/src/tests/common \
    --mount=type=bind,source=patches/llvm/linux-lucid,target=/src/patches/llvm/linux-lucid \
    --mount=type=bind,source=downloads/llvm-project-21.1.8.src.tar.xz,target=/src/llvm.tar.xz \
    PARALLEL_JOBS="$PARALLEL_JOBS" bash /src/scripts/build/qt5-lucid/prepare-llvm.sh

FROM inputs AS toolchain
COPY --from=build-runtime /opt/llvm-runtime-lucid /opt/llvm-runtime-lucid

FROM toolchain AS build-qt
ARG PARALLEL_JOBS=4
ARG DOWNLOAD_DIR
ARG QT_DISTRO
ARG QT_FULL_VERSION=5.15.19
ARG QT_SHA256=173c2326dae138bbb0d98921e9d911e55c00163d93a6db29f294b5e19ff306ae
ARG LICENSE_PROFILE=gpl-enabled
RUN --network=none \
    --mount=type=bind,source=scripts/build/qt5-lucid,target=/src/qt5-lucid \
    --mount=type=bind,source=patches/qt5/all,target=/src/patches/qt5/all \
    --mount=type=bind,source=patches/qt5/linux,target=/src/patches/qt5/linux \
    --mount=type=bind,source=patches/qt5/linux-lucid-llvm,target=/src/patches/qt5/linux-lucid-llvm \
    --mount=type=bind,source=patches/qt5/linux-arm64-llvm/02-mapbox-clang21.patch,target=/src/mapbox-clang21.patch \
    --mount=type=bind,source=${DOWNLOAD_DIR}/${QT_DISTRO},target=/src/qt.tar.xz \
    --mount=type=bind,source=scripts/build/license-configure-args.sh,target=/src/license-configure-args.sh \
    PARALLEL_JOBS="$PARALLEL_JOBS" bash /src/qt5-lucid/build-qt-llvm.sh

FROM toolchain AS sdk
COPY --from=build-qt ${QT_INSTALL_DIR} ${QT_INSTALL_DIR}
COPY cmake/qt5/toolchain-linux-lucid-llvm.cmake /opt/llvm-runtime-lucid/toolchain.cmake
ENV PATH=${QT_INSTALL_DIR}/bin:/opt/llvm-runtime-lucid/bin:${PATH} \
    CC=/opt/llvm-runtime-lucid/bin/target-cc CXX=/opt/llvm-runtime-lucid/bin/target-cxx
ENTRYPOINT ["/bin/bash", "-c"]
CMD ["qmake -query QT_VERSION"]
LABEL org.openkaryon.longreach-qt.platform="ubuntu-lucid-${LUCID_ARCH}" \
      org.openkaryon.longreach-qt.glibc="2.11"

FROM ${SDK_IMAGE} AS examples
ARG PARALLEL_JOBS=4
ARG LICENSE_PROFILE=gpl-enabled
RUN --network=none \
    --mount=type=bind,source=tests,target=/src/tests \
    --mount=type=bind,source=scripts/build/tests.sh,target=/tmp/build-tests.sh \
    --mount=type=bind,source=scripts/build/qt5-lucid/max-glibc.py,target=/tmp/max-glibc.py \
    --mount=type=bind,source=scripts/build/qt5-lucid/check-llvm-examples.sh,target=/tmp/check-llvm-examples.sh \
    PARALLEL_JOBS="$PARALLEL_JOBS" SMOKE_LICENSE_PROFILE="$LICENSE_PROFILE" bash /tmp/check-llvm-examples.sh
