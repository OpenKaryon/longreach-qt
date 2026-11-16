# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2026 OpenKaryon
ARG SDK_IMAGE=sdk
ARG BASE_REGISTRY=docker.io/library
ARG LLVM_COMPILER_IMAGE=longreach-llvm:21.1.8-compiler
ARG SARGE_ARCH=i386

FROM ${LLVM_COMPILER_IMAGE} AS compiler
FROM ${BASE_REGISTRY}/debian:12@sha256:2c037a04925515fdd6ea85ea14a682d0e79931f5e9f5d07b6dbfc6ba12f9e858 AS host-packages
ARG APT_SNAPSHOT
RUN --mount=type=bind,source=scripts/build/apt-snapshot.sh,target=/tmp/apt-snapshot.sh \
    sh /tmp/apt-snapshot.sh "$APT_SNAPSHOT" && apt-get update -qq && \
    apt-get install -y --no-install-recommends build-essential cmake ninja-build \
        python3 perl pkg-config git xz-utils libxml2 libexpat1 xfonts-utils && \
    rm -rf /var/lib/apt/lists/*

FROM host-packages AS sysroot
ARG SARGE_ARCH
ARG SARGE_CRT_FILENAME
ARG SARGE_CRT_SHA256
ENV SARGE_ARCH=${SARGE_ARCH}
RUN --network=none \
    --mount=type=bind,source=downloads/debian-sarge-${SARGE_ARCH},target=/packages \
    --mount=type=bind,source=scripts/fetch/locks/qt4-sarge-${SARGE_ARCH}-packages.json,target=/packages-lock.json \
    --mount=type=bind,source=scripts/build/qt4-sarge,target=/scripts \
    --mount=type=bind,source=downloads/${SARGE_CRT_FILENAME},target=/tmp/sarge-crt.deb \
    SARGE_CRT_SHA256="$SARGE_CRT_SHA256" bash /scripts/prepare-sysroot.sh
ENTRYPOINT ["/bin/bash"]

FROM sysroot AS toolchain
ARG SARGE_ARCH
ENV SARGE_ARCH=${SARGE_ARCH}
ENV PATH=/opt/llvm-21/bin:/usr/local/bin:/usr/bin:/bin CC="" CXX="" \
    PKG_CONFIG_SYSROOT_DIR="" PKG_CONFIG_LIBDIR=""
COPY --from=compiler /opt/llvm-21 /opt/llvm-21
RUN ln -s /work/sysroot /opt/sysroot-sarge

FROM toolchain AS runtime
ARG PARALLEL_JOBS=3
RUN --network=none \
    --mount=type=bind,source=downloads/llvm-project-21.1.8.src.tar.xz,target=/src/llvm.tar.xz \
    --mount=type=bind,source=scripts,target=/src/scripts \
    --mount=type=bind,source=patches/llvm,target=/src/patches/llvm \
    --mount=type=bind,source=tests/common,target=/src/tests/common \
    PARALLEL_JOBS="$PARALLEL_JOBS" bash /src/scripts/build/qt4-sarge/prepare-llvm.sh

FROM toolchain AS sdk-toolchain
ARG SARGE_ARCH
COPY --from=runtime /work/sarge-llvm/runtimes/linux-sarge-${SARGE_ARCH} /work/sarge-llvm/runtimes/linux-sarge-${SARGE_ARCH}
COPY --from=runtime /out/linux-sarge-${SARGE_ARCH}/cxx23-probe /opt/qt4-sarge/cxx23-probe

FROM sdk-toolchain AS dependencies
ARG PARALLEL_JOBS=3
RUN --network=none \
    --mount=type=bind,source=downloads/openssl-1.0.2u.tar.gz,target=/src/openssl.tar.gz \
    --mount=type=bind,source=scripts/build/qt4-sarge,target=/scripts \
    PARALLEL_JOBS="$PARALLEL_JOBS" bash /scripts/build-openssl.sh

FROM dependencies AS build-qt
ARG PARALLEL_JOBS=3
RUN --network=none \
    --mount=type=bind,source=downloads/qt-everywhere-opensource-src-4.8.7.tar.gz,target=/src/qt.tar.gz \
    --mount=type=bind,source=patches/qt4,target=/src/patches/qt4 \
    --mount=type=bind,source=scripts/build/qt4-sarge/build-qt-llvm.sh,target=/src/build-qt.sh \
    PARALLEL_JOBS="$PARALLEL_JOBS" bash /src/build-qt.sh

FROM dependencies AS sdk
ARG SARGE_ARCH
COPY --from=build-qt /opt/qt4-sarge-llvm-sdk /opt/qt4-sarge-llvm-sdk
COPY --from=build-qt /work/qt4-sarge-llvm-sdk-src/LICENSE.LGPLv21 /work/qt4-sarge-llvm-sdk-src/LICENSE.LGPLv3 /work/qt4-sarge-llvm-sdk-src/LGPL_EXCEPTION.txt /opt/qt4-sarge/licenses/
COPY --from=runtime /work/sarge-llvm/source/LICENSE.TXT /opt/qt4-sarge/licenses/LLVM-LICENSE.txt
LABEL org.openkaryon.longreach-qt.platform="debian-sarge-${SARGE_ARCH}" \
      org.openkaryon.longreach-qt.glibc="2.3.2" \
      org.openkaryon.longreach-qt.openssl="1.0.2u"
ENV PATH=/opt/qt4-sarge-llvm-sdk/bin:${PATH} QMAKESPEC=linux-sarge-llvm
ENTRYPOINT ["/bin/bash"]

FROM ${SDK_IMAGE} AS examples
ARG PARALLEL_JOBS=3
RUN --network=none \
    --mount=type=bind,source=tests,target=/src/tests \
    --mount=type=bind,source=scripts/build,target=/src/scripts/build \
    PARALLEL_JOBS="$PARALLEL_JOBS" bash /src/scripts/build/qt4-sarge/build-examples-llvm.sh
