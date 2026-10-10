# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2026 OpenKaryon
#
# Qt 6 for Windows on ARM64, cross-built with LLVM-MinGW and the host tools
# from the qt6-host image.

ARG QT_VERSION=6.10.1
ARG QT_ARCHIVE=qt-everywhere-src-${QT_VERSION}.tar.xz
ARG QT_SRC_DOWNLOAD_URL=""
ARG LLVM_MINGW_VERSION=20241217
ARG LLVM_MINGW_ARCHIVE=""
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
# builder: Qt for Windows ARM64 with LLVM-MinGW
# ---------------------------------------------------------------------------

FROM ${QT6_HOST_IMAGE} AS host-qt

FROM debian:12 AS builder

ENV DEBIAN_FRONTEND=noninteractive

ARG QT_VERSION
ARG LLVM_MINGW_VERSION
ARG LLVM_MINGW_ARCHIVE
ARG PARALLEL_JOBS

RUN apt-get update && apt-get install -y \
    build-essential \
    cmake ninja-build python3 python3-pip perl pkg-config \
    libssl-dev libgl1-mesa-dev libglu1-mesa-dev \
    libfontconfig1-dev libfreetype6-dev \
    libx11-dev libx11-xcb-dev libxext-dev libxfixes-dev libxi-dev \
    libxrender-dev libxcb1-dev libxcb-glx0-dev libxcb-keysyms1-dev \
    libxcb-image0-dev libxcb-shm0-dev libxcb-icccm4-dev \
    libxcb-sync-dev libxcb-xfixes0-dev libxcb-shape0-dev \
    libxcb-randr0-dev libxcb-render-util0-dev libxcb-util-dev \
    libxcb-xinerama0-dev libxcb-xkb-dev libxkbcommon-dev libxkbcommon-x11-dev \
    unzip dos2unix file wget xz-utils \
    && rm -rf /var/lib/apt/lists/*

COPY --from=host-qt /opt/qt6-host /opt/qt6-host

ENV LLVM_MINGW_ROOT=/opt/llvm-mingw
WORKDIR /tmp

ARG DOWNLOAD_DIR="downloads"
RUN --mount=type=bind,source=.,target=/context \
    set -e; \
    DEFAULT_ARCHIVE="llvm-mingw-${LLVM_MINGW_VERSION}-ucrt-ubuntu-20.04-x86_64.tar.xz"; \
    if [ -f "/context/${DOWNLOAD_DIR}/${DEFAULT_ARCHIVE}" ]; then \
        echo "Using local LLVM-MinGW archive /context/${DOWNLOAD_DIR}/${DEFAULT_ARCHIVE}"; \
        cp "/context/${DOWNLOAD_DIR}/${DEFAULT_ARCHIVE}" /tmp/llvm-mingw.tar.xz; \
    elif [ -n "${LLVM_MINGW_ARCHIVE}" ] && [ -f "/context/${LLVM_MINGW_ARCHIVE}" ]; then \
        echo "Using local LLVM-MinGW archive /context/${LLVM_MINGW_ARCHIVE}"; \
        cp "/context/${LLVM_MINGW_ARCHIVE}" /tmp/llvm-mingw.tar.xz; \
    elif [ -f "/context/${DEFAULT_ARCHIVE}" ]; then \
        echo "Using local LLVM-MinGW archive /context/${DEFAULT_ARCHIVE}"; \
        cp "/context/${DEFAULT_ARCHIVE}" /tmp/llvm-mingw.tar.xz; \
    else \
        echo "Downloading LLVM-MinGW ${LLVM_MINGW_VERSION} from GitHub..."; \
        wget -q \
          "https://github.com/mstorsjo/llvm-mingw/releases/download/${LLVM_MINGW_VERSION}/${DEFAULT_ARCHIVE}" \
          -O /tmp/llvm-mingw.tar.xz; \
    fi; \
    mkdir -p ${LLVM_MINGW_ROOT}; \
    tar -C ${LLVM_MINGW_ROOT} --strip-components=1 -xf /tmp/llvm-mingw.tar.xz; \
    rm -f /tmp/llvm-mingw.tar.xz; \
    for d in ${LLVM_MINGW_ROOT}/*-w64-mingw32/include; do \
        [ -f "$d/winsock2.h" ] && ln -sf winsock2.h "$d/Winsock2.h"; \
    done; \
    exit 0

# qtquick3dphysics' PhysX includes <Winsock2.h>; mingw-w64 ships winsock2.h,
# and a Linux filesystem is case-sensitive.

ENV PATH="${LLVM_MINGW_ROOT}/bin:${PATH}"

ENV QT_SRC_DIR=/workspace/qt-src
ENV QT_BUILD_DIR=/workspace/qt-build
ENV QT_INSTALL_DIR=/opt/qt6-arm64

RUN mkdir -p ${QT_BUILD_DIR} ${QT_INSTALL_DIR}

COPY --from=qt-src /tmp/qt-src.tar.xz /workspace/qt-src.tar.xz
COPY patches/qt6/all /tmp/patches/all
COPY patches/qt6/windows /tmp/patches/windows

WORKDIR /workspace

# Unpack without the modules skipped below; the two lists must agree.
RUN tar -xJf qt-src.tar.xz --wildcards \
      --exclude="qt-everywhere-src-${QT_VERSION}/qtwebengine/*" \
      --exclude="qt-everywhere-src-${QT_VERSION}/qtwebview/*" \
      --exclude="qt-everywhere-src-${QT_VERSION}/qtwayland/*" && \
    mv qt-everywhere-src-${QT_VERSION} ${QT_SRC_DIR} && \
    rm -f qt-src.tar.xz

# patches/qt6/all for every Qt 6 target, patches/qt6/windows for Windows: the
# Windows 7 backport, which selects newer APIs at run time.
RUN cd ${QT_SRC_DIR} && \
    for p in /tmp/patches/all/*.patch /tmp/patches/windows/*.patch; do echo "applying $p"; patch -p1 < "$p"; done

RUN cd ${QT_SRC_DIR} && \
    find . \( -name "configure" -o -name "*.sh" -o -name "*.pl" \) -print0 \
      | xargs -0 dos2unix 2>/dev/null || true && \
    find . \( -name "configure" -o -name "*.sh" -o -name "*.pl" \) -exec chmod +x {} + 2>/dev/null || true

COPY cmake/qt6/qt-toolchain-llvm-arm64.cmake ${QT_BUILD_DIR}/toolchain.cmake

WORKDIR ${QT_BUILD_DIR}

# The module set of the Qt 5 targets: not built are qtwebengine and qtwebview
# (Chromium), qtwayland (no Wayland libraries in these images) and qtactiveqt
# (its host idc tool needs Windows headers; ActiveQt has no classes in the
# coverage database). Qt3D and the rest are built: tests/ needs them.
RUN ${QT_SRC_DIR}/configure \
        -opensource -confirm-license \
        -prefix ${QT_INSTALL_DIR} \
        -qt-host-path /opt/qt6-host \
        -release -optimize-size -strip -static \
        -platform linux-g++ \
        -xplatform win32-clang-g++ \
        -device-option CROSS_COMPILE=aarch64-w64-mingw32- \
        -nomake examples -nomake tests \
        -no-vulkan -no-dbus \
        -qt-zlib -qt-pcre -qt-libpng -qt-libjpeg -qt-freetype -qt-harfbuzz \
        -skip qtwebengine -skip qtwebview -skip qtwayland -skip qtactiveqt \
        -- \
        -DCMAKE_TOOLCHAIN_FILE=${QT_BUILD_DIR}/toolchain.cmake \
        -DCMAKE_BUILD_TYPE=Release && \
    cmake --build . --parallel ${PARALLEL_JOBS:-$(nproc)} && \
    cmake --install .

# ---------------------------------------------------------------------------
# final: LLVM-MinGW, the host tools and the installed SDK
# ---------------------------------------------------------------------------

FROM debian:12-slim

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update && apt-get install -y --no-install-recommends \
    cmake ninja-build make \
    ca-certificates \
    && rm -rf /var/lib/apt/lists/*

COPY --from=builder /opt/llvm-mingw /opt/llvm-mingw

COPY --from=builder /opt/qt6-host /opt/qt6-host

COPY --from=builder /opt/qt6-arm64 /opt/qt6-arm64

# The toolchain file is referenced by Qt's CMake packages.
COPY --from=builder /workspace/qt-build/toolchain.cmake /workspace/qt-build/toolchain.cmake

ENV LLVM_MINGW_ROOT=/opt/llvm-mingw
ENV QT_INSTALL_DIR=/opt/qt6-arm64
ENV PATH="${LLVM_MINGW_ROOT}/bin:${QT_INSTALL_DIR}/bin:${PATH}"

WORKDIR /workspace

CMD ["bash", "-c", "echo 'Qt 6 for Windows ARM64 cross-compilation image'; echo 'Qt: /opt/qt6-arm64'; echo 'Toolchain: /opt/llvm-mingw'"]
