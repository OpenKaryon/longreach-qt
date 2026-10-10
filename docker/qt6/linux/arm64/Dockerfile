# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2026 OpenKaryon
#
# Qt 6 for Linux arm64, cross-built against a Debian 12 arm64 sysroot with the
# host tools from the qt6-host image.

ARG QT_VERSION=6.10.1
ARG QT_ARCHIVE=qt-everywhere-src-${QT_VERSION}.tar.xz
ARG QT_SRC_DOWNLOAD_URL=""
ARG PARALLEL_JOBS=""
# The host Qt image by its tag, which carries the licence profile.
ARG QT6_HOST_IMAGE=qt6-host

# ---------------------------------------------------------------------------
# qt-src: the Qt source archive
# ---------------------------------------------------------------------------

FROM debian:12 AS qt-src

ENV DEBIAN_FRONTEND=noninteractive

ARG QT_VERSION
ARG QT_ARCHIVE
ARG QT_SRC_DOWNLOAD_URL

RUN apt-get update && apt-get install -y \
    wget ca-certificates && \
    rm -rf /var/lib/apt/lists/*

ARG DOWNLOAD_DIR="downloads"
RUN --mount=type=bind,source=.,target=/context \
    set -e; \
    ARCHIVE_NAME="${QT_ARCHIVE:-qt-everywhere-src-${QT_VERSION}.tar.xz}"; \
    if [ -f "/context/${DOWNLOAD_DIR}/${ARCHIVE_NAME}" ]; then \
        echo "Using local Qt archive /context/${DOWNLOAD_DIR}/${ARCHIVE_NAME}"; \
        cp "/context/${DOWNLOAD_DIR}/${ARCHIVE_NAME}" /tmp/qt-src.tar.xz; \
    elif [ -f "/context/${ARCHIVE_NAME}" ]; then \
        echo "Using local Qt archive /context/${ARCHIVE_NAME}"; \
        cp "/context/${ARCHIVE_NAME}" /tmp/qt-src.tar.xz; \
    elif [ -n "${QT_SRC_DOWNLOAD_URL}" ]; then \
        echo "Downloading Qt archive from ${QT_SRC_DOWNLOAD_URL}"; \
        wget -qO /tmp/qt-src.tar.xz "${QT_SRC_DOWNLOAD_URL}"; \
    else \
        echo "ERROR: Qt archive not found in build context and QT_SRC_DOWNLOAD_URL not set"; \
        exit 1; \
    fi

# ---------------------------------------------------------------------------
# builder: Qt for Linux arm64 against a Debian multiarch sysroot
# ---------------------------------------------------------------------------

FROM ${QT6_HOST_IMAGE} AS host-qt

FROM debian:12 AS builder

ENV DEBIAN_FRONTEND=noninteractive

ARG QT_VERSION
ARG PARALLEL_JOBS

RUN dpkg --add-architecture arm64

RUN apt-get update && apt-get install -y \
    build-essential \
    cmake ninja-build python3 python3-pip perl pkg-config \
    gcc-aarch64-linux-gnu g++-aarch64-linux-gnu \
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

# The arm64 libraries that make up the sysroot.
RUN apt-get update && apt-get install -y \
    libc6-dev:arm64 \
    libstdc++-12-dev:arm64 \
    libgcc-12-dev:arm64 \
    libfontconfig-dev:arm64 \
    libfreetype-dev:arm64 \
    libx11-dev:arm64 \
    libx11-xcb-dev:arm64 \
    libxext-dev:arm64 \
    libxfixes-dev:arm64 \
    libxi-dev:arm64 \
    libxrender-dev:arm64 \
    libxcb1-dev:arm64 \
    libxcb-cursor-dev:arm64 \
    libxcb-glx0-dev:arm64 \
    libxcb-icccm4-dev:arm64 \
    libxcb-image0-dev:arm64 \
    libxcb-keysyms1-dev:arm64 \
    libxcb-randr0-dev:arm64 \
    libxcb-render0-dev:arm64 \
    libxcb-render-util0-dev:arm64 \
    libxcb-shape0-dev:arm64 \
    libxcb-shm0-dev:arm64 \
    libxcb-sync-dev:arm64 \
    libxcb-util-dev:arm64 \
    libxcb-xfixes0-dev:arm64 \
    libxcb-xinerama0-dev:arm64 \
    libxcb-xkb-dev:arm64 \
    libxkbcommon-dev:arm64 \
    libxkbcommon-x11-dev:arm64 \
    libgl1-mesa-dev:arm64 \
    libglu1-mesa-dev:arm64 \
    libegl1-mesa-dev:arm64 \
    libgles2-mesa-dev:arm64 \
    libgbm-dev:arm64 \
    libdrm-dev:arm64 \
    mesa-common-dev:arm64 \
    && rm -rf /var/lib/apt/lists/*

ENV SYSROOT=/opt/sysroot-arm64
RUN mkdir -p ${SYSROOT}/usr/lib ${SYSROOT}/lib && \
    ln -s /usr/lib/aarch64-linux-gnu ${SYSROOT}/usr/lib/aarch64-linux-gnu && \
    ln -s /lib/aarch64-linux-gnu ${SYSROOT}/lib/aarch64-linux-gnu && \
    ln -s /usr/include ${SYSROOT}/usr/include && \
    ln -s /usr/share ${SYSROOT}/usr/share

COPY --from=host-qt /opt/qt6-host /opt/qt6-host

ENV QT_SRC_DIR=/workspace/qt-src
ENV QT_BUILD_DIR=/workspace/qt-build
ENV QT_INSTALL_DIR=/opt/qt6-linux-arm64

RUN mkdir -p ${QT_BUILD_DIR} ${QT_INSTALL_DIR}

COPY --from=qt-src /tmp/qt-src.tar.xz /workspace/qt-src.tar.xz
COPY patches/qt6/all /tmp/patches-qt6-all

WORKDIR /workspace

# Unpack without the modules skipped below; the two lists must agree.
RUN tar -xJf qt-src.tar.xz --wildcards \
      --exclude="qt-everywhere-src-${QT_VERSION}/qtwebengine/*" \
      --exclude="qt-everywhere-src-${QT_VERSION}/qtwebview/*" \
      --exclude="qt-everywhere-src-${QT_VERSION}/qtwayland/*" && \
    mv qt-everywhere-src-${QT_VERSION} ${QT_SRC_DIR} && \
    rm -f qt-src.tar.xz

RUN cd ${QT_SRC_DIR} && \
    for p in /tmp/patches-qt6-all/*.patch; do echo "applying qt6/all/$(basename $p)"; patch -p1 < "$p"; done

RUN cd ${QT_SRC_DIR} && \
    find . \( -name "configure" -o -name "*.sh" -o -name "*.pl" \) -print0 \
      | xargs -0 dos2unix 2>/dev/null || true && \
    find . \( -name "configure" -o -name "*.sh" -o -name "*.pl" \) -exec chmod +x {} + 2>/dev/null || true

COPY cmake/qt6/qt-toolchain-linux-arm64.cmake ${QT_BUILD_DIR}/toolchain.cmake

WORKDIR ${QT_BUILD_DIR}

# The module set of the Qt 5 targets: not built are qtwebengine and qtwebview
# (Chromium) and qtwayland. XCB comes from the sysroot.
RUN ${QT_SRC_DIR}/configure \
        -opensource -confirm-license \
        -prefix ${QT_INSTALL_DIR} \
        -qt-host-path /opt/qt6-host \
        -release -optimize-size -strip -static \
        -nomake examples -nomake tests \
        -no-vulkan -no-dbus \
        -xcb \
        -qt-zlib -qt-pcre -qt-libpng -qt-libjpeg -qt-harfbuzz \
        -fontconfig -system-freetype \
        -skip qtwebengine -skip qtwebview -skip qtwayland \
        -- \
        -DCMAKE_TOOLCHAIN_FILE=${QT_BUILD_DIR}/toolchain.cmake \
        -DCMAKE_BUILD_TYPE=Release && \
    cmake --build . --parallel ${PARALLEL_JOBS:-$(nproc)} && \
    cmake --install .

# ---------------------------------------------------------------------------
# final: the cross-compiler, the arm64 sysroot, the host tools and the SDK
# ---------------------------------------------------------------------------

FROM debian:12-slim

ENV DEBIAN_FRONTEND=noninteractive

RUN dpkg --add-architecture arm64

RUN apt-get update && apt-get install -y --no-install-recommends \
    cmake ninja-build make \
    gcc-aarch64-linux-gnu g++-aarch64-linux-gnu \
    pkg-config \
    ca-certificates \
    libc6-dev:arm64 \
    libstdc++-12-dev:arm64 \
    libfontconfig-dev:arm64 \
    libfreetype-dev:arm64 \
    libx11-dev:arm64 \
    libx11-xcb-dev:arm64 \
    libxext-dev:arm64 \
    libxfixes-dev:arm64 \
    libxi-dev:arm64 \
    libxrender-dev:arm64 \
    libxcb1-dev:arm64 \
    libxcb-cursor-dev:arm64 \
    libxcb-glx0-dev:arm64 \
    libxcb-icccm4-dev:arm64 \
    libxcb-image0-dev:arm64 \
    libxcb-keysyms1-dev:arm64 \
    libxcb-randr0-dev:arm64 \
    libxcb-render0-dev:arm64 \
    libxcb-render-util0-dev:arm64 \
    libxcb-shape0-dev:arm64 \
    libxcb-shm0-dev:arm64 \
    libxcb-sync-dev:arm64 \
    libxcb-util-dev:arm64 \
    libxcb-xfixes0-dev:arm64 \
    libxcb-xinerama0-dev:arm64 \
    libxcb-xkb-dev:arm64 \
    libxkbcommon-dev:arm64 \
    libxkbcommon-x11-dev:arm64 \
    libgl1-mesa-dev:arm64 \
    libglu1-mesa-dev:arm64 \
    libegl1-mesa-dev:arm64 \
    libgles2-mesa-dev:arm64 \
    libgbm-dev:arm64 \
    libdrm-dev:arm64 \
    mesa-common-dev:arm64 \
    && rm -rf /var/lib/apt/lists/*

ENV SYSROOT=/opt/sysroot-arm64
RUN mkdir -p ${SYSROOT}/usr/lib ${SYSROOT}/lib && \
    ln -s /usr/lib/aarch64-linux-gnu ${SYSROOT}/usr/lib/aarch64-linux-gnu && \
    ln -s /lib/aarch64-linux-gnu ${SYSROOT}/lib/aarch64-linux-gnu && \
    ln -s /usr/include ${SYSROOT}/usr/include && \
    ln -s /usr/share ${SYSROOT}/usr/share

COPY --from=builder /opt/qt6-host /opt/qt6-host

COPY --from=builder /opt/qt6-linux-arm64 /opt/qt6-linux-arm64

# The toolchain file is referenced by Qt's CMake packages.
COPY --from=builder /workspace/qt-build/toolchain.cmake /workspace/qt-build/toolchain.cmake

ENV QT_INSTALL_DIR=/opt/qt6-linux-arm64
ENV PATH="${QT_INSTALL_DIR}/bin:${PATH}"

WORKDIR /workspace

CMD ["bash", "-c", "echo 'Qt 6 for Linux ARM64 cross-compilation image'; echo 'Qt: /opt/qt6-linux-arm64'; echo 'Sysroot: /opt/sysroot-arm64'"]
