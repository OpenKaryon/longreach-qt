# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2026 OpenKaryon
#
# Qt 4.8.7 with upstream LLVM 21.1.8 for Mac OS X 10.4 Tiger (i386).

# Base images are pinned by digest; BASE_REGISTRY is where they are pulled
# from (the OpenKaryonLab copy, or docker.io/library: docs/sources.md).
ARG SDK_IMAGE=sdk
ARG BASE_REGISTRY=ghcr.io/openkaryonlab
ARG LLVM_COMPILER_IMAGE=longreach-llvm:21.1.8-snow-tls
FROM ${LLVM_COMPILER_IMAGE} AS compiler

FROM --platform=linux/amd64 ${BASE_REGISTRY}/ubuntu:22.04@sha256:5ec03bb3441e8b0bf3b4f9cd4629a1ae763010dc3035bb8da3ae6cf026486401 AS toolchain
ARG APT_SNAPSHOT
COPY scripts/build/apt-snapshot.sh /usr/local/bin/apt-snapshot
ARG PARALLEL_JOBS=6
ARG OSXCROSS_REF=f547d14e6ac6c5bb0ddd7563651eb29057e1d755
ARG LAB_GIT=https://github.com/OpenKaryonLab
ENV DEBIAN_FRONTEND=noninteractive
RUN sh /usr/local/bin/apt-snapshot "$APT_SNAPSHOT" && apt-get update && apt-get install -y --no-install-recommends \
    build-essential clang llvm-dev cmake git patch python3 perl curl ca-certificates \
    autoconf automake libtool libssl-dev libxml2-dev liblzma-dev zlib1g-dev \
    libbz2-dev bzip2 xz-utils file && rm -rf /var/lib/apt/lists/*
COPY downloads/MacOSX10.4u.sdk.tar.xz /tmp/MacOSX10.4u.sdk.tar.xz
COPY scripts/build/osxcross-sources.sh scripts/build/git-fetch-pinned.sh /tmp/
RUN echo 'd28276ce6b0f14af30f3bfdc171f8ef4033652da593578568f8be189506c1021  /tmp/MacOSX10.4u.sdk.tar.xz' | sha256sum -c - \
    && bash /tmp/git-fetch-pinned.sh /opt/osxcross "$OSXCROSS_REF" "$LAB_GIT/osxcross.git" \
    && cd /opt/osxcross \
    && mv /tmp/MacOSX10.4u.sdk.tar.xz tarballs/ \
    && LAB_GIT="$LAB_GIT" bash /tmp/osxcross-sources.sh /opt/osxcross-sources \
       cctools-port=b73df358be0cd809c6ccf3cc26989320aa6a9b20 xar=5fa4675419cfec60ac19a9c7f7c2d0e7c831a497 \
    && TP_OSXCROSS_DEV=/opt/osxcross-sources UNATTENDED=1 OSX_VERSION_MIN=10.4 JOBS="$PARALLEL_JOBS" \
       TARGET_DIR=/opt/tiger-toolchain ./build.sh
ENV PATH=/opt/tiger-toolchain/bin:$PATH
ENV MACOSX_DEPLOYMENT_TARGET=10.4

COPY scripts/build/qt4-macos/normalize-sdk-stubs.py /scripts/normalize-sdk-stubs.py
RUN python3 /scripts/normalize-sdk-stubs.py /opt/tiger-toolchain/SDK/MacOSX10.4u.sdk

RUN --network=none \
    --mount=type=bind,source=downloads/openssl-1.0.2u.tar.gz,target=/archives/openssl-1.0.2u.tar.gz \
    echo 'ecd0c6ffb493dd06707d38b14bb4d8c2288bb7033735606569d8f90f89669d16  /archives/openssl-1.0.2u.tar.gz' | sha256sum -c - \
    && mkdir -p /work/openssl-source && cd /work/openssl-source \
    && tar -xzf /archives/openssl-1.0.2u.tar.gz --strip-components=1 \
    && ./Configure darwin-i386-cc --prefix=/opt/openssl-tiger no-shared no-asm no-capieng \
       -L/opt/tiger-toolchain/SDK/MacOSX10.4u.sdk/usr/lib/gcc/i686-apple-darwin10/4.0.1 -lgcc -lgcc_s.10.4 \
    && make -j "$PARALLEL_JOBS" CC=i386-apple-darwin8-clang AR='i386-apple-darwin8-ar r' RANLIB=i386-apple-darwin8-ranlib \
    && make install_sw CC=i386-apple-darwin8-clang AR='i386-apple-darwin8-ar r' RANLIB=i386-apple-darwin8-ranlib \
    && cp LICENSE /tmp/openssl-tiger-license \
    && cd /work && rm -rf /work/openssl-source \
    && mkdir -p /work/openssl-source && mv /tmp/openssl-tiger-license /work/openssl-source/LICENSE

FROM toolchain AS runtime
ARG PARALLEL_JOBS=3
COPY --from=compiler /opt/llvm-21 /opt/llvm-21
COPY --from=compiler /opt/cmake-3.27.9-linux-x86_64 /opt/cmake-3.27.9-linux-x86_64
ENV PATH=/opt/llvm-21/bin:/opt/cmake-3.27.9-linux-x86_64/bin:${PATH}
ENV TIGER_SPEC=macx-tiger-llvm
ENTRYPOINT ["/bin/bash", "-c"]
RUN --network=none \
    --mount=type=bind,source=downloads/llvm-project-21.1.8.src.tar.xz,target=/src/llvm.tar.xz \
    --mount=type=bind,source=patches/llvm,target=/src/patches \
    --mount=type=bind,source=scripts/build/qt4-macos/build-tiger-libcxx.sh,target=/src/build-libcxx.sh \
    clang --version | grep -E '^clang version 21\.1\.8([[:space:]]|$)' && \
    PARALLEL_JOBS="$PARALLEL_JOBS" bash /src/build-libcxx.sh /src/llvm.tar.xz /src/patches
COPY --chmod=0755 scripts/build/qt4-macos/tiger-llvm-cc scripts/build/qt4-macos/tiger-llvm-cxx /usr/local/bin/

FROM runtime AS probe
COPY scripts/tests/qt6-llvm-probes/main.cpp /probe/scripts/tests/qt6-llvm-probes/
COPY tests/common/moderncpp_checks.h /probe/tests/common/
RUN --network=none mkdir /out && \
    tiger-llvm-cxx -std=c++23 -O2 -c /probe/scripts/tests/qt6-llvm-probes/main.cpp -o /tmp/probe.o && \
    tiger-llvm-cxx /tmp/probe.o -o /out/cxx23-probe && \
    tiger-llvm-cxx -std=c++23 -O2 /probe/scripts/tests/qt6-llvm-probes/main.cpp -o /tmp/probe-direct && \
    i386-apple-darwin8-otool -L /out/cxx23-probe /tmp/probe-direct

FROM runtime AS sdk
ARG PARALLEL_JOBS=3
COPY scripts/build/qt4-macos/build-qt.sh scripts/build/qt4-macos/qmake.conf /scripts/
COPY patches/qt4/all /patches/all
COPY patches/qt4/macos /patches/macos
COPY patches/qt4/macos-tiger-llvm /patches/tiger-llvm
COPY patches/qt4/linux-sarge-llvm/02-widget-style-optimization.patch /patches/tiger-llvm/04-widget-style-optimization.patch
RUN --network=none \
    --mount=type=bind,source=downloads/qt-everywhere-opensource-src-4.8.7.tar.gz,target=/archives/qt-everywhere-opensource-src-4.8.7.tar.gz \
    --mount=type=cache,id=qt4-tiger-i386-llvm21-qt,target=/work/qt-source,sharing=locked \
    sed -i -e 's/^QMAKE_CC = .*/QMAKE_CC = tiger-llvm-cc/' \
           -e 's/^QMAKE_CXX = .*/QMAKE_CXX = tiger-llvm-cxx/' /scripts/qmake.conf && \
    TIGER_CACHE_KEY=$(sha256sum /opt/llvm-21/bin/clang /opt/tiger-llvm-runtime/lib/* \
        /opt/openssl-tiger/lib/*.a /usr/local/bin/tiger-llvm-* /scripts/build-qt.sh /scripts/qmake.conf) && \
    TIGER_CACHE_KEY="$TIGER_CACHE_KEY" TIGER_EXTRA_PATCHES=1 TIGER_JOBS="$PARALLEL_JOBS" bash /scripts/build-qt.sh && \
    /opt/qt4-tiger/bin/qmake -v

ENV PATH=/opt/qt4-tiger/bin:$PATH
LABEL org.openkaryon.longreach-qt.platform=macos-tiger-i386

FROM ${SDK_IMAGE} AS examples
ARG PARALLEL_JOBS=3
COPY scripts/build/qt4-macos/build-examples.sh scripts/build/qt4-macos/build-examples-llvm.sh \
     scripts/build/qt4-macos/write-bundle.py scripts/build/qt4-macos/audit-macho.py /scripts/
COPY tests /input
RUN --network=none TIGER_JOBS="$PARALLEL_JOBS" bash /scripts/build-examples-llvm.sh
