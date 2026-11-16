# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2026 OpenKaryon
ARG LLVM_COMPILER_IMAGE=longreach-llvm:21.1.8-compiler
ARG QT_HOST_IMAGE=qt6-linux-amd64:llvm21
ARG QT_TARGET_INPUTS_IMAGE=qt6-llvm-cross-host
ARG QT_VERSION=6.8.5
ARG QT_ARCHIVE=qt-everywhere-src-${QT_VERSION}.tar.xz
FROM ${LLVM_COMPILER_IMAGE} AS compiler
FROM ${QT_HOST_IMAGE} AS host
RUN --network=none \
    --mount=type=bind,source=scripts/build/qt6-llvm-sdk/host-libs.sh,target=/tmp/host-libs.sh \
    bash /tmp/host-libs.sh
FROM ${QT_TARGET_INPUTS_IMAGE} AS inputs
COPY --from=compiler /opt/llvm-21 /opt/llvm-21
COPY --from=host /opt/qt6-linux-amd64-llvm /opt/qt6-host-llvm21
COPY --from=host /opt/longreach-host-libs /opt/longreach-host-libs
ENV LD_LIBRARY_PATH=/opt/longreach-host-libs

FROM inputs AS toolchain
ARG PARALLEL_JOBS=4
RUN --network=none \
    --mount=type=bind,source=scripts,target=/src/scripts \
    --mount=type=bind,source=tests,target=/src/tests \
    --mount=type=bind,source=downloads/llvm-project-21.1.8.src.tar.xz,target=/src/downloads/llvm-project-21.1.8.src.tar.xz \
    --mount=type=bind,source=downloads/mingw-w64-v13.0.0.tar.bz2,target=/src/downloads/mingw-w64-v13.0.0.tar.bz2 \
    --mount=type=cache,id=qt6-llvm21-cross-runtime,target=/work,sharing=locked \
    mkdir -p /out && \
    PARALLEL_JOBS="$PARALLEL_JOBS" bash /src/scripts/build/qt6-llvm-sdk/prepare.sh windows-amd64
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
    --mount=type=cache,id=qt6-llvm21-windows-amd64-qt,target=/build,sharing=locked \
    PARALLEL_JOBS="$PARALLEL_JOBS" QT_VERSION="$QT_VERSION" \
        QT_ARCHIVE_PATH=/src/qt.tar.xz QT_ARCHIVE_SHA256="$QT_SHA256" QT_CACHE_ROOT=/build \
        bash /src/scripts/build/qt6-llvm-sdk/build-qt.sh windows-amd64
ENV QT_INSTALL_DIR=/opt/qt6-windows-amd64-llvm
