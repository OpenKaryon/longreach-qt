# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2026 OpenKaryon
#
# Qt 6 for Linux arm64 from RHEL/CentOS 7 aarch64 (glibc 2.17).
# The CentOS sysroot and C dependencies come from the locked packages
# and source archives. Qt and the examples use upstream Clang and libc++.
# Base images are pinned by digest; BASE_REGISTRY is where they are pulled
# from (the OpenKaryonLab copy, or docker.io/library: docs/sources.md).
ARG BASE_REGISTRY=ghcr.io/openkaryonlab
ARG QT_VERSION=6.8.5
ARG QT_ARCHIVE=qt-everywhere-src-${QT_VERSION}.tar.xz
ARG PARALLEL_JOBS=""
ARG QT_HOST_IMAGE=qt6-linux-amd64:llvm21
ARG QT_TARGET_INPUTS_IMAGE=deps
ARG LLVM_COMPILER_IMAGE=longreach-llvm:21.1.8-compiler

FROM ${QT_HOST_IMAGE} AS host-qt
RUN --network=none \
    --mount=type=bind,source=scripts/build/qt6-llvm-sdk/host-libs.sh,target=/tmp/host-libs.sh \
    bash /tmp/host-libs.sh
FROM ${LLVM_COMPILER_IMAGE} AS llvm-compiler

# ---------------------------------------------------------------------------
# toolchain: the cross-compiler, the CentOS 7 aarch64 sysroot and the host Qt
# ---------------------------------------------------------------------------

FROM ${BASE_REGISTRY}/debian:12@sha256:2c037a04925515fdd6ea85ea14a682d0e79931f5e9f5d07b6dbfc6ba12f9e858 AS cross-host
ARG APT_SNAPSHOT
COPY scripts/build/apt-snapshot.sh /usr/local/bin/apt-snapshot

ENV DEBIAN_FRONTEND=noninteractive

# qemu-user-static runs the sysroot's wayland-scanner (see its wrapper); the
# libraries after it are what the host tools (qsb and the rest) load.
RUN sh /usr/local/bin/apt-snapshot "$APT_SNAPSHOT" && apt-get update && apt-get install -y --no-install-recommends \
        g++-11-aarch64-linux-gnu binutils-aarch64-linux-gnu \
        cmake ninja-build make m4 perl python3 pkg-config file xz-utils git \
        rpm2cpio cpio qemu-user-static binutils ca-certificates \
        libfontconfig1 libfreetype6 libpng16-16 zlib1g libbrotli1 libglib2.0-0 libdbus-1-3 \
        libx11-6 libx11-xcb1 libxcb1 libxcb-cursor0 libxcb-icccm4 libxcb-image0 libxcb-keysyms1 \
        libxcb-randr0 libxcb-render-util0 libxcb-render0 libxcb-shape0 libxcb-shm0 libxcb-sync1 \
        libxcb-xfixes0 libxcb-xkb1 libxkbcommon0 libxkbcommon-x11-0 \
        libwayland-client0 libwayland-cursor0 libwayland-server0 && \
    rm -rf /var/lib/apt/lists/*

FROM cross-host AS centos-inputs
ENV SYSROOT=/opt/sysroot-arm64
# The CentOS 7.9 aarch64 packages, each by URL and SHA256 from the lock
# (scripts/build/qt6-linux-arm64/packages.txt says how it is made).
COPY scripts/build/rpm-sysroot.py scripts/fetch/locks/qt6-centos7-aarch64-packages.json /tmp/sysroot/
RUN python3 /tmp/sysroot/rpm-sysroot.py --lock /tmp/sysroot/qt6-centos7-aarch64-packages.json \
        --dest ${SYSROOT} --merged-usr > /tmp/sysroot/installed.txt && \
    wc -l < /tmp/sysroot/installed.txt && rm -rf /tmp/sysroot

# Build the shared aarch64 runtime at the CentOS 7 glibc floor.
FROM centos-inputs AS llvm-runtime
ARG PARALLEL_JOBS=4
COPY --from=llvm-compiler /opt/llvm-21 /opt/llvm-21
RUN --network=none \
    --mount=type=bind,source=downloads/llvm-project-21.1.8.src.tar.xz,target=/src/llvm.tar.xz \
    --mount=type=bind,source=scripts,target=/src/scripts \
    --mount=type=bind,source=tests/common,target=/src/tests/common \
    --mount=type=cache,id=llvm21-linux-arm64-runtime,target=/work/llvm,sharing=locked <<'EOF'
set -eu
echo '4633a23617fa31a3ea51242586ea7fb1da7140e426bd62fc164261fe036aa142  /src/llvm.tar.xz' | sha256sum -c -
if [ ! -f /work/llvm/source/.longreach-ready ]; then
    rm -rf /work/llvm/source
    mkdir -p /work/llvm/source
    tar -xJf /src/llvm.tar.xz -C /work/llvm/source --strip-components=1
    touch /work/llvm/source/.longreach-ready
fi
LLVM_ROOT=/opt/llvm-21 LLVM_BUILD_ROOT=/work/llvm PARALLEL_JOBS="$PARALLEL_JOBS" \
    bash /src/scripts/build/qt6-llvm-probes/build-runtime.sh linux-arm64
cp -a /work/llvm/runtimes/linux-arm64 /opt/llvm-runtime-21
EOF

FROM centos-inputs AS deps-toolchain
COPY scripts/build/qt6-linux-arm64/gcc /opt/cross/bin/aarch64-centos7-gcc
COPY scripts/build/qt6-linux-arm64/g++ /opt/cross/bin/aarch64-centos7-g++
COPY scripts/build/qt6-linux-arm64/wayland-scanner /opt/cross/bin/wayland-scanner
RUN chmod +x /opt/cross/bin/*
ENV PATH="/opt/cross/bin:${PATH}"

# The toolchain must produce nothing that needs a glibc newer than RHEL 7's.
COPY scripts/build/qt5-lucid/probe.cpp scripts/build/qt5-lucid/max-glibc.py /tmp/probe/
RUN aarch64-centos7-g++ -std=c++17 -O2 -pthread /tmp/probe/probe.cpp -o /tmp/probe/probe && \
    python3 /tmp/probe/max-glibc.py /tmp/probe/probe 2.17 && rm -rf /tmp/probe

# ---------------------------------------------------------------------------
# deps: what Qt links statically, and the Wayland stubs
# ---------------------------------------------------------------------------

FROM deps-toolchain AS deps
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

FROM ${QT_TARGET_INPUTS_IMAGE} AS inputs
COPY --from=llvm-compiler /opt/llvm-21 /opt/llvm-21
COPY --from=host-qt /opt/qt6-linux-amd64-llvm /opt/qt6-host-llvm21
COPY --from=host-qt /opt/longreach-host-libs /opt/longreach-host-libs
ENV LD_LIBRARY_PATH=/opt/longreach-host-libs

FROM inputs AS toolchain
ARG PARALLEL_JOBS=4
RUN --network=none \
    --mount=type=bind,source=scripts,target=/src/scripts \
    --mount=type=bind,source=tests,target=/src/tests \
    --mount=type=bind,source=downloads/llvm-project-21.1.8.src.tar.xz,target=/src/downloads/llvm-project-21.1.8.src.tar.xz \
    --mount=type=cache,id=qt6-llvm21-cross-runtime,target=/work,sharing=locked \
    mkdir -p /out && \
    PARALLEL_JOBS="$PARALLEL_JOBS" bash /src/scripts/build/qt6-llvm-sdk/prepare.sh linux-arm64
ENV PATH=/opt/longreach-llvm/bin:/opt/llvm-21/bin:/opt/qt6-host-llvm21/bin:${PATH} \
    CC=/opt/longreach-llvm/bin/target-cc CXX=/opt/longreach-llvm/bin/target-cxx

FROM toolchain AS qt
ARG PARALLEL_JOBS=4
ARG QT_VERSION
ARG QT_ARCHIVE
ARG DOWNLOAD_DIR=downloads
ARG QT_SHA256=c0537548bb3871cbb3cac85fb55813430d45ac4d5d4daa64bdf41f3c2ae65ff9
ARG LICENSE_PROFILE=gpl-enabled
RUN --network=none \
    --mount=type=bind,source=scripts,target=/src/scripts \
    --mount=type=bind,source=patches,target=/src/patches \
    --mount=type=bind,source=${DOWNLOAD_DIR}/${QT_ARCHIVE},target=/src/qt.tar.xz \
    --mount=type=cache,id=qt6-llvm21-linux-arm64-qt,target=/build,sharing=locked \
    PARALLEL_JOBS="$PARALLEL_JOBS" QT_VERSION="$QT_VERSION" LICENSE_PROFILE="$LICENSE_PROFILE" \
        QT_ARCHIVE_PATH=/src/qt.tar.xz QT_ARCHIVE_SHA256="$QT_SHA256" QT_CACHE_ROOT=/build \
        bash /src/scripts/build/qt6-llvm-sdk/build-qt.sh linux-arm64
ENV QT_INSTALL_DIR=/opt/qt6-linux-arm64-llvm
