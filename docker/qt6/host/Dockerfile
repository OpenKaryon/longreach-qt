# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2026 OpenKaryon
#
# Qt 6 for the Linux build host, with the tools every cross target needs (moc,
# uic, rcc, lupdate, qscxmlc, repc, ...).

ARG QT_VERSION=6.10.1
ARG QT_ARCHIVE=qt-everywhere-src-${QT_VERSION}.tar.xz
ARG QT_SRC_DOWNLOAD_URL=""
ARG PARALLEL_JOBS=""

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
# builder: Qt for the host with all tools
# ---------------------------------------------------------------------------

FROM debian:12 AS builder

ENV DEBIAN_FRONTEND=noninteractive

ARG QT_VERSION
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
    libxcb-cursor-dev \
    unzip dos2unix file wget xz-utils \
    && rm -rf /var/lib/apt/lists/*

COPY --from=qt-src /tmp/qt-src.tar.xz /tmp/qt-src.tar.xz

WORKDIR /tmp

# Unpack without the modules skipped below; the two lists must agree.
RUN tar -xJf qt-src.tar.xz --wildcards \
      --exclude="qt-everywhere-src-${QT_VERSION}/qtwebengine/*" \
      --exclude="qt-everywhere-src-${QT_VERSION}/qtwebview/*" \
      --exclude="qt-everywhere-src-${QT_VERSION}/qtwayland/*" && \
    mv qt-everywhere-src-${QT_VERSION} ./qt-src && \
    rm -f qt-src.tar.xz

ENV QT_SRC_DIR=/tmp/qt-src

RUN cd ${QT_SRC_DIR} && \
    find . \( -name "configure" -o -name "*.sh" -o -name "*.pl" \) -print0 \
      | xargs -0 dos2unix 2>/dev/null || true && \
    find . \( -name "configure" -o -name "*.sh" -o -name "*.pl" \) -exec chmod +x {} + 2>/dev/null || true

WORKDIR /tmp/qt-build-host
# The module set of the targets: not built are qtwebengine and qtwebview
# (Chromium) and qtwayland.
RUN ${QT_SRC_DIR}/configure \
      -prefix /opt/qt6-host \
      -release \
      -nomake tests -nomake examples \
      -no-opengl -no-dbus \
      -skip qtwebengine -skip qtwebview -skip qtwayland \
&& cmake --build . --parallel ${PARALLEL_JOBS:-$(nproc)} \
      && cmake --install .

# ---------------------------------------------------------------------------
# final: the installed host Qt only
# ---------------------------------------------------------------------------

FROM debian:12-slim

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update && apt-get install -y --no-install-recommends \
    libgl1 libglib2.0-0 libdbus-1-3 \
    ca-certificates \
    && rm -rf /var/lib/apt/lists/*

COPY --from=builder /opt/qt6-host /opt/qt6-host

ENV PATH="/opt/qt6-host/bin:/opt/qt6-host/libexec:${PATH}"

# Verify installed tools
RUN echo "=== Host Qt installed tools ===" && \
    ls -la /opt/qt6-host/libexec/ 2>/dev/null | head -20 || true

CMD ["bash", "-c", "echo 'Host Qt is installed at /opt/qt6-host'; ls /opt/qt6-host/libexec/"]
