# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2026 OpenKaryon
#
# Qt 6 for the Linux build host, with the tools every cross target needs (moc,
# uic, rcc, lupdate, qscxmlc, repc, ...).

# Base images are pinned by digest; BASE_REGISTRY is where they are pulled
# from (the OpenKaryonLab copy, or docker.io/library: docs/sources.md).
ARG BASE_REGISTRY=ghcr.io/openkaryonlab
ARG QT_VERSION=6.8.5
ARG QT_ARCHIVE=qt-everywhere-src-${QT_VERSION}.tar.xz
ARG PARALLEL_JOBS=""

# ---------------------------------------------------------------------------
# qt-src: the Qt source archive
# ---------------------------------------------------------------------------

FROM ${BASE_REGISTRY}/debian:12@sha256:2c037a04925515fdd6ea85ea14a682d0e79931f5e9f5d07b6dbfc6ba12f9e858 AS qt-src

ARG QT_VERSION
ARG QT_ARCHIVE

# Only the archive: a bind mount of the whole context made every change
# anywhere in the repository a new cache key for the Qt build below.
ARG DOWNLOAD_DIR="downloads"
COPY ${DOWNLOAD_DIR}/${QT_ARCHIVE} /tmp/qt-src.tar.xz

# ---------------------------------------------------------------------------
# builder: Qt for the host with all tools
# ---------------------------------------------------------------------------

FROM ${BASE_REGISTRY}/debian:12@sha256:2c037a04925515fdd6ea85ea14a682d0e79931f5e9f5d07b6dbfc6ba12f9e858 AS builder
ARG APT_SNAPSHOT
COPY scripts/build/apt-snapshot.sh /usr/local/bin/apt-snapshot

ENV DEBIAN_FRONTEND=noninteractive

ARG QT_VERSION
ARG PARALLEL_JOBS

RUN sh /usr/local/bin/apt-snapshot "$APT_SNAPSHOT" && apt-get update && apt-get install -y \
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
    libxcb-cursor-dev libwayland-dev \
    unzip dos2unix file wget xz-utils \
    && rm -rf /var/lib/apt/lists/*

COPY --from=qt-src /tmp/qt-src.tar.xz /tmp/qt-src.tar.xz

WORKDIR /tmp

# Unpack without the modules skipped below; the two lists must agree.
RUN tar -xJf qt-src.tar.xz --wildcards \
      --exclude="qt-everywhere-src-${QT_VERSION}/qtwebengine/*" \
      --exclude="qt-everywhere-src-${QT_VERSION}/qtwebview/*" && \
    mv qt-everywhere-src-${QT_VERSION} ./qt-src && \
    rm -f qt-src.tar.xz

ENV QT_SRC_DIR=/tmp/qt-src

RUN cd ${QT_SRC_DIR} && \
    find . \( -name "configure" -o -name "*.sh" -o -name "*.pl" \) -print0 \
      | xargs -0 dos2unix 2>/dev/null || true && \
    find . \( -name "configure" -o -name "*.sh" -o -name "*.pl" \) -exec chmod +x {} + 2>/dev/null || true

WORKDIR /tmp/qt-build-host
# The module set of the targets: not built are qtwebengine and qtwebview
# (Chromium). qtwayland provides qtwaylandscanner and QtDBus the D-Bus tools
# for the Linux cross-builds.
RUN ${QT_SRC_DIR}/configure \
      -prefix /opt/qt6-host \
      -release \
      -nomake tests -nomake examples \
      -no-opengl \
      -skip qtwebengine -skip qtwebview \
&& cmake --build . --parallel ${PARALLEL_JOBS:-$(nproc)} \
      && cmake --install .

# ---------------------------------------------------------------------------
# final: the installed host Qt only
# ---------------------------------------------------------------------------

FROM ${BASE_REGISTRY}/debian:12-slim@sha256:7c7b2c966bc9ee8cedfeef67e0e279108992c77681fa595db4a9d65c06ccc587
ARG APT_SNAPSHOT
COPY scripts/build/apt-snapshot.sh /usr/local/bin/apt-snapshot

ENV DEBIAN_FRONTEND=noninteractive

RUN sh /usr/local/bin/apt-snapshot "$APT_SNAPSHOT" && apt-get update && apt-get install -y --no-install-recommends \
    libgl1 libglib2.0-0 libdbus-1-3 \
    ca-certificates \
    && rm -rf /var/lib/apt/lists/*

COPY --from=builder /opt/qt6-host /opt/qt6-host

ENV PATH="/opt/qt6-host/bin:/opt/qt6-host/libexec:${PATH}"

# Verify installed tools
RUN echo "=== Host Qt installed tools ===" && \
    ls -la /opt/qt6-host/libexec/ 2>/dev/null | head -20 || true

CMD ["bash", "-c", "echo 'Host Qt is installed at /opt/qt6-host'; ls /opt/qt6-host/libexec/"]
