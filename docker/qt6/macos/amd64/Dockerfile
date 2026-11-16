# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2026 OpenKaryon
ARG LLVM_COMPILER_IMAGE=longreach-llvm:21.1.8-compiler
ARG QT_HOST_IMAGE=qt6-linux-amd64:llvm21
ARG QT_TARGET_INPUTS_IMAGE=qt6-llvm-cross-host
ARG QT_VERSION=6.8.5
ARG QT_ARCHIVE=qt-everywhere-src-${QT_VERSION}.tar.xz
ARG OSX_SDK_IMAGE=osxcross-builder
ARG OSX_SDK_VERSION=14.0
ARG OSX_DEPLOYMENT_TARGET=10.13
ARG BASE_REGISTRY=ghcr.io/openkaryonlab
ARG OSXCROSS_MIN_VERSION=10.11
ARG OSX_SDK=MacOSX${OSX_SDK_VERSION}.sdk.tar.xz
ARG OSX_SDK_SHA256=5e4d3be6b445f0eacc0333ff2117e93e4433d8c4fe44053a14f735033a98aaa9
ARG OSXCROSS_REF=27d21e4977c9751d01199c7a226a6faf494c3dd9
FROM ${LLVM_COMPILER_IMAGE} AS compiler
FROM ${QT_HOST_IMAGE} AS host
RUN --network=none \
    --mount=type=bind,source=scripts/build/qt6-llvm-sdk/host-libs.sh,target=/tmp/host-libs.sh \
    bash /tmp/host-libs.sh
FROM ${BASE_REGISTRY}/debian:12@sha256:2c037a04925515fdd6ea85ea14a682d0e79931f5e9f5d07b6dbfc6ba12f9e858 AS osxcross-builder
ARG APT_SNAPSHOT
COPY scripts/build/apt-snapshot.sh /usr/local/bin/apt-snapshot

ENV DEBIAN_FRONTEND=noninteractive

ARG PARALLEL_JOBS
ARG OSX_SDK
ARG OSX_SDK_SHA256
ARG OSXCROSS_MIN_VERSION
ARG OSXCROSS_REF
ARG LAB_GIT=https://github.com/OpenKaryonLab

RUN sh /usr/local/bin/apt-snapshot "$APT_SNAPSHOT" && apt-get update && apt-get install -y \
    build-essential cmake python3 perl git patch wget nano \
    bash clang bzip2 binutils-multiarch-dev cpio xz-utils \
    libbz2-dev libmpc-dev libmpfr-dev libgmp-dev libssl-dev \
    libxml2-dev zlib1g-dev liblzma-dev \
    && rm -rf /var/lib/apt/lists/*

COPY scripts/build/osxcross-sources.sh scripts/build/git-fetch-pinned.sh /tmp/
# The SDK, fetched by make with its SHA256 (not redistributable, so not in
# the OpenKaryonLab copy; keep your own: docs/sources.md).
ARG DOWNLOAD_DIR="downloads"
COPY ${DOWNLOAD_DIR}/${OSX_SDK} /tmp/${OSX_SDK}
RUN set -eux; \
    bash /tmp/git-fetch-pinned.sh /opt/osxcross "${OSXCROSS_REF}" "${LAB_GIT}/osxcross.git"; \
    cd /opt/osxcross; \
    echo "osxcross ref resolved to $(git rev-parse HEAD)"; \
    mkdir -p tarballs; \
    mv "/tmp/${OSX_SDK}" "tarballs/${OSX_SDK}"; \
    echo "${OSX_SDK_SHA256}  tarballs/${OSX_SDK}" | sha256sum -c -; \
    LAB_GIT="${LAB_GIT}" bash /tmp/osxcross-sources.sh /opt/osxcross-sources \
        apple-libtapi=640b4623929c923c0468143ff2a363a48665fa54 cctools-port=e101a6940dcb5988808a16626bc43851f00dc05f xar=5fa4675419cfec60ac19a9c7f7c2d0e7c831a497; \
    TP_OSXCROSS_DEV=/opt/osxcross-sources \
    JOBS="${PARALLEL_JOBS:-4}" UNATTENDED=1 OSX_VERSION_MIN="${OSXCROSS_MIN_VERSION}" ./build.sh

ENV OSXCROSS_ROOT=/opt/osxcross
ENV PATH="${OSXCROSS_ROOT}/bin:${OSXCROSS_ROOT}/target/bin:${PATH}"

# @available checks call __isPlatformVersionAtLeast, from the Darwin compiler
# runtime, which osxcross does not install: built from the pinned LLVM source
# (llvm-project f28c006, fetched by make with its SHA256).
ARG DOWNLOAD_DIR="downloads"
COPY ${DOWNLOAD_DIR}/os_version_check-f28c006.c /tmp/os_version_check.c
RUN set -eux; \
    echo '846d994b7dc1f229a3086b113ad946befaf963c5d6e8838323b17447bb5749fb  /tmp/os_version_check.c' | sha256sum -c -; \
    compiler="$(find /opt/osxcross/target/bin -maxdepth 1 -name 'x86_64-apple-darwin*-clang' ! -name '*-cmake-clang' | sort | tail -1)"; \
    test -n "${compiler}"; \
    "${compiler}" -mmacosx-version-min="${OSXCROSS_MIN_VERSION}" -c /tmp/os_version_check.c -o /tmp/os_version_check.o; \
    mkdir -p /opt/osxcross/target/lib/darwin; \
    "${compiler%-clang}-ar" rcs /opt/osxcross/target/lib/darwin/libclang_rt.osx.a /tmp/os_version_check.o; \
    "${compiler%-clang}-ranlib" /opt/osxcross/target/lib/darwin/libclang_rt.osx.a

RUN set -eux; \
    ls -la "${OSXCROSS_ROOT}"; \
    ls -la "${OSXCROSS_ROOT}/target"; \
    ls -la "${OSXCROSS_ROOT}/target/bin"; \
    "${OSXCROSS_ROOT}/target/bin/"x86_64-apple-darwin*-clang --version; \
    "${OSXCROSS_ROOT}/target/bin/"x86_64-apple-darwin*-clang++ --version

FROM ${OSX_SDK_IMAGE} AS osx-sdk
FROM ${QT_TARGET_INPUTS_IMAGE} AS inputs
COPY --from=compiler /opt/llvm-21 /opt/llvm-21
COPY --from=host /opt/qt6-linux-amd64-llvm /opt/qt6-host-llvm21
COPY --from=host /opt/longreach-host-libs /opt/longreach-host-libs
ARG OSX_SDK_VERSION
ARG OSX_DEPLOYMENT_TARGET
COPY --from=osx-sdk /opt/osxcross /opt/osxcross
ENV LD_LIBRARY_PATH=/opt/longreach-host-libs \
    OSXCROSS_ROOT=/opt/osxcross OSXCROSS_SDK_VERSION=${OSX_SDK_VERSION} MACOSX_DEPLOYMENT_TARGET=${OSX_DEPLOYMENT_TARGET} \
    PATH=/opt/osxcross/target/bin:/opt/osxcross/bin:${PATH}

FROM inputs AS toolchain
ARG PARALLEL_JOBS=4
RUN --network=none \
    --mount=type=bind,source=scripts,target=/src/scripts \
    --mount=type=bind,source=tests,target=/src/tests \
    --mount=type=bind,source=downloads/llvm-project-21.1.8.src.tar.xz,target=/src/downloads/llvm-project-21.1.8.src.tar.xz \
    --mount=type=cache,id=qt6-llvm21-cross-runtime,target=/work,sharing=locked \
    mkdir -p /out && \
    PARALLEL_JOBS="$PARALLEL_JOBS" bash /src/scripts/build/qt6-llvm-sdk/prepare.sh macos-amd64
ENV PATH=/opt/longreach-llvm/bin:/opt/llvm-21/bin:/opt/qt6-host-llvm21/bin:${PATH} \
    CC=/opt/longreach-llvm/bin/target-cc CXX=/opt/longreach-llvm/bin/target-cxx

FROM toolchain AS qt
ARG PARALLEL_JOBS=4
ARG QT_VERSION
ARG QT_ARCHIVE
ARG DOWNLOAD_DIR=downloads
ARG QT_SHA256=c0537548bb3871cbb3cac85fb55813430d45ac4d5d4daa64bdf41f3c2ae65ff9
RUN --network=none \
    --mount=type=bind,source=scripts,target=/src/scripts \
    --mount=type=bind,source=patches,target=/src/patches \
    --mount=type=bind,source=${DOWNLOAD_DIR}/${QT_ARCHIVE},target=/src/qt.tar.xz \
    --mount=type=cache,id=qt6-llvm21-macos-amd64-qt,target=/build,sharing=locked \
    PARALLEL_JOBS="$PARALLEL_JOBS" QT_VERSION="$QT_VERSION" \
        QT_ARCHIVE_PATH=/src/qt.tar.xz QT_ARCHIVE_SHA256="$QT_SHA256" QT_CACHE_ROOT=/build \
        bash /src/scripts/build/qt6-llvm-sdk/build-qt.sh macos-amd64
ENV QT_INSTALL_DIR=/opt/qt6-macos-amd64-llvm
