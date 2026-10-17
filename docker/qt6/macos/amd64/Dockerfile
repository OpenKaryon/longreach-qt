# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2026 OpenKaryon
#
# Qt 6 for Intel Macs from macOS 10.13, cross-built with osxcross and the host
# tools from the qt6-host image.


ARG QT_VERSION=6.10.1
ARG QT_ARCHIVE=qt-everywhere-src-${QT_VERSION}.tar.xz
ARG PARALLEL_JOBS=""
ARG QT6_HOST_IMAGE=qt6-host

# The SDK and the deployment floor: macOS 10.13 (Qt 6.8 asks for 12; patches/qt6/macos).
ARG OSX_SDK_VERSION=14.0
ARG OSX_DEPLOYMENT_TARGET=10.13
ARG OSXCROSS_MIN_VERSION=10.11
ARG OSX_SDK="MacOSX${OSX_SDK_VERSION}.sdk.tar.xz"
ARG OSX_SDK_URL="https://github.com/joseluisq/macosx-sdks/releases/download/${OSX_SDK_VERSION}/${OSX_SDK}"
ARG OSX_SDK_SHA256=5e4d3be6b445f0eacc0333ff2117e93e4433d8c4fe44053a14f735033a98aaa9
ARG OSXCROSS_REF=27d21e4977c9751d01199c7a226a6faf494c3dd9

FROM ${QT6_HOST_IMAGE} AS host-qt

# ---------------------------------------------------------------------------
# qt-src: the Qt source archive
# ---------------------------------------------------------------------------

FROM debian:12 AS qt-src

ARG QT_VERSION
ARG QT_ARCHIVE

# Only the archive: a bind mount of the whole context made every change
# anywhere in the repository a new cache key for the Qt build below.
ARG DOWNLOAD_DIR="downloads"
COPY ${DOWNLOAD_DIR}/${QT_ARCHIVE} /tmp/qt-src.tar.xz

# ---------------------------------------------------------------------------
# osxcross: the macOS SDK and toolchain
# ---------------------------------------------------------------------------

FROM debian:12 AS osxcross-builder

ENV DEBIAN_FRONTEND=noninteractive

ARG PARALLEL_JOBS
ARG OSX_SDK
ARG OSX_SDK_URL
ARG OSX_SDK_SHA256
ARG OSXCROSS_MIN_VERSION
ARG OSXCROSS_REF

RUN apt-get update && apt-get install -y \
    build-essential cmake python3 perl git patch wget nano \
    bash clang bzip2 binutils-multiarch-dev cpio xz-utils \
    libbz2-dev libmpc-dev libmpfr-dev libgmp-dev libssl-dev \
    libxml2-dev zlib1g-dev liblzma-dev \
    && rm -rf /var/lib/apt/lists/*

RUN set -eux; \
    cd /opt; \
    git clone https://github.com/tpoechtrager/osxcross.git; \
    cd /opt/osxcross; \
    git checkout "${OSXCROSS_REF}"; \
    echo "osxcross ref resolved to $(git rev-parse HEAD)"; \
    mkdir -p tarballs; \
    wget -q "${OSX_SDK_URL}" -O "tarballs/${OSX_SDK}"; \
    echo "${OSX_SDK_SHA256}  tarballs/${OSX_SDK}" | sha256sum -c -; \
    JOBS="${PARALLEL_JOBS:-4}" UNATTENDED=1 OSX_VERSION_MIN="${OSXCROSS_MIN_VERSION}" ./build.sh

ENV OSXCROSS_ROOT=/opt/osxcross
ENV PATH="${OSXCROSS_ROOT}/bin:${OSXCROSS_ROOT}/target/bin:${PATH}"

# @available checks call __isPlatformVersionAtLeast, from the Darwin compiler
# runtime, which osxcross does not install: built from the pinned LLVM source.
RUN set -eux; \
    wget -q https://raw.githubusercontent.com/llvm/llvm-project/f28c006a5895fc0e329fe15fead81e37457cb1d1/compiler-rt/lib/builtins/os_version_check.c \
      -O /tmp/os_version_check.c; \
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

# ---------------------------------------------------------------------------
# builder: Qt for macOS amd64
# ---------------------------------------------------------------------------

FROM debian:12 AS builder

ENV DEBIAN_FRONTEND=noninteractive

ARG QT_VERSION
ARG PARALLEL_JOBS
ARG OSX_SDK_VERSION
ARG OSX_DEPLOYMENT_TARGET

RUN apt-get update && apt-get install -y \
    build-essential \
    cmake ninja-build ccache python3 python3-pip perl pkg-config \
    gcc g++ clang \
    libssl-dev libgl1-mesa-dev libglu1-mesa-dev \
    libfontconfig1-dev libfreetype6-dev \
    libx11-dev libx11-xcb-dev libxext-dev libxfixes-dev libxi-dev \
    libxrender-dev libxcb1-dev libxcb-glx0-dev libxcb-keysyms1-dev \
    libxcb-image0-dev libxcb-shm0-dev libxcb-icccm4-dev \
    libxcb-sync-dev libxcb-xfixes0-dev libxcb-shape0-dev \
    libxcb-randr0-dev libxcb-render-util0-dev libxcb-util-dev \
    libxcb-xinerama0-dev libxcb-xkb-dev libxkbcommon-dev libxkbcommon-x11-dev \
    libxcb-cursor-dev \
    unzip dos2unix file wget xz-utils \
    && rm -rf /var/lib/apt/lists/*

ENV CCACHE_DIR=/root/.cache/ccache \
    CCACHE_MAXSIZE=8G \
    CCACHE_COMPRESS=true

COPY --from=osxcross-builder /opt/osxcross /opt/osxcross
ENV OSXCROSS_ROOT=/opt/osxcross
ENV PATH="${OSXCROSS_ROOT}/bin:${OSXCROSS_ROOT}/target/bin:${PATH}"
RUN install -D /opt/osxcross/target/lib/darwin/libclang_rt.osx.a \
      "$(clang -print-resource-dir)/lib/darwin/libclang_rt.osx.a"

COPY --from=host-qt /opt/qt6-host /opt/qt6-host

ENV QT_SRC_DIR=/workspace/qt-src
ENV QT_BUILD_DIR=/workspace/qt-build
ENV QT_INSTALL_DIR=/opt/qt6-macos-amd64

RUN mkdir -p "${QT_BUILD_DIR}" "${QT_INSTALL_DIR}"

COPY --from=qt-src /tmp/qt-src.tar.xz /workspace/qt-src.tar.xz
COPY patches/qt6/all /tmp/patches/all
COPY patches/qt6/macos /tmp/patches/macos

WORKDIR /workspace

# Unpack without the modules skipped below; the two lists must agree.
RUN tar -xJf qt-src.tar.xz --wildcards \
      --exclude="qt-everywhere-src-${QT_VERSION}/qtwebengine/*" \
      --exclude="qt-everywhere-src-${QT_VERSION}/qtwebview/*" \
      --exclude="qt-everywhere-src-${QT_VERSION}/qtwayland/*" && \
    mv qt-everywhere-src-${QT_VERSION} "${QT_SRC_DIR}" && \
    rm -f qt-src.tar.xz

# patches/qt6/all for every Qt 6 target, patches/qt6/macos for macOS: newer
# APIs are chosen at run time, or at compile time from the deployment target.
RUN cd "${QT_SRC_DIR}" && \
    for p in /tmp/patches/all/*.patch /tmp/patches/macos/*.patch; do echo "applying $p"; patch -p1 < "$p"; done

RUN cd "${QT_SRC_DIR}" && \
    find . \( -name "configure" -o -name "*.sh" -o -name "*.pl" \) -print0 \
      | xargs -0 dos2unix 2>/dev/null || true && \
    find . \( -name "configure" -o -name "*.sh" -o -name "*.pl" \) -exec chmod +x {} + 2>/dev/null || true

# The SDK spells AVFoundation, and the Linux filesystem is case-sensitive.
RUN set -eux && \
    cd "${QT_SRC_DIR}" && \
    echo "=== Fixing AvFoundation case sensitivity ===" && \
    find . -type f \( -name "*.h" -o -name "*.hpp" -o -name "*.mm" -o -name "*.m" -o -name "*.cpp" \) \
        -exec grep -l "AvFoundation/AVFoundation.h" {} \; 2>/dev/null | head -20 || true && \
    find . -type f \( -name "*.h" -o -name "*.hpp" -o -name "*.mm" -o -name "*.m" -o -name "*.cpp" \) \
        -exec sed -i 's#AvFoundation/AVFoundation\.h#AVFoundation/AVFoundation.h#g' {} \; && \
    echo "=== Done fixing AvFoundation ==="

COPY cmake/qt6/qt-toolchain-macos-amd64.cmake "${QT_BUILD_DIR}/toolchain.cmake"

# Qt runs codesign after building some tools; a stub stands in for it.
RUN set -eux && \
    mkdir -p /usr/local/bin && \
    printf '#!/bin/sh\necho "stub codesign: $@" >&2\nexit 0\n' > /usr/local/bin/codesign && \
    chmod +x /usr/local/bin/codesign

WORKDIR "${QT_BUILD_DIR}"

# The module set of the Qt 5 targets: not built are qtwebengine and qtwebview
# (Chromium) and qtwayland. Qt3D and the rest are built: tests/ needs them.
# -faligned-allocation lets QtCore's own aligned new and delete stand in for
# the libc++ ones 10.13 lacks.
RUN if dpkg --compare-versions "${OSX_DEPLOYMENT_TARGET}" lt 10.14; then \
        export CXXFLAGS="${CXXFLAGS:+${CXXFLAGS} }-faligned-allocation"; \
        export OBJCXXFLAGS="${OBJCXXFLAGS:+${OBJCXXFLAGS} }-faligned-allocation"; \
    fi; \
    "${QT_SRC_DIR}/configure" \
        -opensource -confirm-license \
        -prefix "${QT_INSTALL_DIR}" \
        -qt-host-path /opt/qt6-host \
        -release -optimize-size -strip -static \
        -nomake examples -nomake tests \
        -no-vulkan -no-dbus -no-cups \
        -qt-zlib -qt-pcre -qt-libpng -qt-libjpeg -qt-freetype -qt-harfbuzz \
        -skip qtwebengine -skip qtwebview -skip qtwayland \
        -- \
        -DQT_FORCE_WARN_APPLE_SDK_AND_XCODE_CHECK=ON \
        -DQT_CREATE_VERSIONED_HARD_LINK=OFF \
        -DOSXCROSS_SDK_VERSION="${OSX_SDK_VERSION}" \
        -DCMAKE_OSX_DEPLOYMENT_TARGET="${OSX_DEPLOYMENT_TARGET}" \
        -DCMAKE_TOOLCHAIN_FILE="${QT_BUILD_DIR}/toolchain.cmake" \
        -DCMAKE_C_COMPILER_LAUNCHER=ccache \
        -DCMAKE_CXX_COMPILER_LAUNCHER=ccache \
        -DCMAKE_OBJC_COMPILER_LAUNCHER=ccache \
        -DCMAKE_OBJCXX_COMPILER_LAUNCHER=ccache \
        -DCMAKE_BUILD_TYPE=Release && \
    cmake --build . --parallel ${PARALLEL_JOBS:-$(nproc)} && \
    cmake --install .

# ---------------------------------------------------------------------------
# final: osxcross, the host tools and the installed SDK
# ---------------------------------------------------------------------------

FROM debian:12-slim

ENV DEBIAN_FRONTEND=noninteractive
ARG OSX_SDK_VERSION
ARG OSX_DEPLOYMENT_TARGET
ENV OSXCROSS_SDK_VERSION="${OSX_SDK_VERSION}" \
    MACOSX_DEPLOYMENT_TARGET="${OSX_DEPLOYMENT_TARGET}"

RUN apt-get update && apt-get install -y --no-install-recommends \
    cmake ninja-build make \
    clang \
    ca-certificates \
    && rm -rf /var/lib/apt/lists/*

COPY --from=osxcross-builder /opt/osxcross /opt/osxcross
RUN install -D /opt/osxcross/target/lib/darwin/libclang_rt.osx.a \
      "$(clang -print-resource-dir)/lib/darwin/libclang_rt.osx.a"

COPY --from=host-qt /opt/qt6-host /opt/qt6-host

COPY --from=builder /opt/qt6-macos-amd64 /opt/qt6-macos-amd64

# The CMake toolchain file for your own projects.
COPY --from=builder /workspace/qt-build/toolchain.cmake /workspace/qt-build/toolchain.cmake

ENV OSXCROSS_ROOT=/opt/osxcross
ENV QT_INSTALL_DIR=/opt/qt6-macos-amd64
ENV PATH="/opt/osxcross/bin:/opt/osxcross/target/bin:${QT_INSTALL_DIR}/bin:${PATH}"

WORKDIR /workspace

CMD ["bash", "-c", "echo 'Qt 6 for macOS amd64 cross-compilation image'; echo 'Qt: /opt/qt6-macos-amd64'; echo 'osxcross: /opt/osxcross'"]
