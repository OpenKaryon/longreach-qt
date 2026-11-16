# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2026 OpenKaryon
#
# Qt 5 with upstream LLVM 21.1.8 for Intel Mac OS X 10.6.

ARG SDK_IMAGE=sdk
ARG BASE_REGISTRY=ghcr.io/openkaryonlab
ARG LLVM_COMPILER_IMAGE=longreach-llvm:21.1.8-snow-tls
ARG DOWNLOAD_DIR=downloads
ARG OPENSSL_DISTRO=openssl-3.5.7.tar.gz
ARG QT_DISTRO=qt-everywhere-opensource-src-5.15.19.tar.xz

FROM ${BASE_REGISTRY}/ubuntu:22.04@sha256:5ec03bb3441e8b0bf3b4f9cd4629a1ae763010dc3035bb8da3ae6cf026486401 AS osxcross
ARG APT_SNAPSHOT
COPY scripts/build/apt-snapshot.sh /usr/local/bin/apt-snapshot

# The macOS SDK comes from the build context and is never redistributed (see
# QT5_MACOS_SDK in mk/qt5.mk). Its version and the deployment target are
# independent: see MACOS_DEPLOYMENT_TARGET below.
ARG OSX_SDK="MacOSX11.3.sdk.tar.xz"
# ARGs do not cross FROM; DOWNLOAD_DIR is declared again in the builder.
ARG DOWNLOAD_DIR="downloads"

# osxcross has no tags; a verified commit keeps the image from changing with
# master. make qt5-macos-amd64 OSXCROSS_REF=master tests another.
# osxcross and the projects it builds (cctools-port, ...) come from the
# OpenKaryonLab copies in LAB_GIT: scripts/build/osxcross-sources.sh.
ARG LAB_GIT="https://github.com/OpenKaryonLab"
ARG OSXCROSS_REF="27d21e4977c9751d01199c7a226a6faf494c3dd9"

# The compiler's architecture; the darwin version is read from the SDK.
ARG OSXCROSS_ARCH="x86_64"
ARG PARALLEL_JOBS=3

# The oldest macOS the binaries load on (the SDK stays current). It is set in
# both places that decide it: osxcross' clang wrapper (OSX_VERSION_MIN), whose
# flag comes last and wins, and qtbase's macx.conf, which applications built
# with this SDK inherit.
#
# 10.6 is Qt 4.8's floor; patches/qt5/macos select newer APIs at run time.
# Below 10.11 OpenSSL is linked statically, below 10.7 libc++ too.
ARG MACOS_DEPLOYMENT_TARGET="10.6"
# The LLVM source the static C++ runtime is built from (only below 10.7).
ARG LLVM_SRC="llvm-project-14.0.6.src.tar.xz"

RUN \
    set -eux && \
    export DEBIAN_FRONTEND=noninteractive && \
    sh /usr/local/bin/apt-snapshot "${APT_SNAPSHOT:-}" && apt -y update && \
    apt -y upgrade && \
    apt -y install \
        build-essential python3 perl git patch wget nano ca-certificates \
        bash clang cmake bzip2 binutils-multiarch-dev cpio xz-utils \
        libbz2-dev libmpc-dev libmpfr-dev libgmp-dev libssl-dev \
        libxml2-dev liblzma-dev lzma-dev zlib1g-dev && \
    apt -y autoremove && \
    apt -y autoclean && \
    apt -y clean && \
    rm -rf /var/lib/apt/lists/* && \
    # git over HTTP/2 drops long transfers on a poor link; HTTP/1.1 does not. \
    git config --system http.version HTTP/1.1 && \
    exit 0

COPY ${DOWNLOAD_DIR}/${OSX_SDK} /opt/sdk-staging/${OSX_SDK}
COPY ${DOWNLOAD_DIR}/${LLVM_SRC} /opt/llvm-staging/${LLVM_SRC}
COPY scripts/build/osxcross-sources.sh scripts/build/git-fetch-pinned.sh /tmp/

# The resolved commit goes into the build log; only the pinned ref is fetched.
RUN \
    set -eux && \
    bash /tmp/git-fetch-pinned.sh /opt/osxcross "$OSXCROSS_REF" "$LAB_GIT/osxcross.git" && \
    cd /opt/osxcross && \
    echo "osxcross ref '$OSXCROSS_REF' resolved to $(git rev-parse HEAD)" && \
    # The wrapper refuses libc++ below 10.7; the kit links its own there (LLVM_SRC), \
    # so the check is lifted for SDKs without libstdc++. \
    sed -i 's|    if (OSNum.Num() \&\& OSNum < OSVersion(10, 7)) {|    if (OSNum.Num() \&\& OSNum < OSVersion(10, 7) \&\& SDKOSNum < OSVersion(10, 14)) {|' \
        wrapper/target.cpp && \
    grep -q 'OSNum < OSVersion(10, 7) && SDKOSNum < OSVersion(10, 14)' wrapper/target.cpp && \
    mv /opt/sdk-staging/$OSX_SDK tarballs/$OSX_SDK && \
    LAB_GIT="$LAB_GIT" bash /tmp/osxcross-sources.sh /opt/osxcross-sources \
        apple-libtapi=640b4623929c923c0468143ff2a363a48665fa54 cctools-port=e101a6940dcb5988808a16626bc43851f00dc05f xar=5fa4675419cfec60ac19a9c7f7c2d0e7c831a497 \
        compiler-rt=archive:/opt/llvm-staging/$LLVM_SRC && \
    TP_OSXCROSS_DEV=/opt/osxcross-sources \
    OCDEBUG=1 OSX_VERSION_MIN=$MACOS_DEPLOYMENT_TARGET UNATTENDED=1 JOBS="$PARALLEL_JOBS" \
        TARGET_DIR=/usr/local/osxcross ./build.sh && \
    ln -s /usr/local/osxcross/bin/xcrun /usr/bin/xcrun && \
    ls /usr/local/osxcross/bin/${OSXCROSS_ARCH}-apple-darwin*-clang++ \
        | sort | head -1 | sed 's#.*/##; s#clang++$##' > /opt/osxcross-prefix && \
    echo "target prefix: $(cat /opt/osxcross-prefix)" && \
    exit 0
ENV PATH="/usr/local/osxcross/bin:$PATH"

# compiler-rt, built by its own script: @available and __builtin_available
# lower to __isPlatformVersionAtLeast, which lives in libclang_rt.osx.a.
RUN \
    set -eux && \
    cd /opt/osxcross && \
    TP_OSXCROSS_DEV=/opt/osxcross-sources UNATTENDED=1 ENABLE_COMPILER_RT_INSTALL=1 JOBS="$PARALLEL_JOBS" ./build_compiler_rt.sh && \
    exit 0

# Self-checks: osxcross' own, and that an availability guard compiles and links.
RUN \
    set -eux && \
    cd /opt/osxcross && \
    "$(cat /opt/osxcross-prefix)clang++" oclang/test.cpp -O3 -o test && \
    echo 'int main(){ if (__builtin_available(macOS 10.12, *)) return 1; return 0; }' \
        > /tmp/availability.cpp && \
    "$(cat /opt/osxcross-prefix)clang++" /tmp/availability.cpp -O3 -o /tmp/availability && \
    exit 0

# Seed the SDK for the static LLVM runtime stage, which replaces this archive.
COPY scripts/build/qt5-macos/build-libcxx.sh /tmp/build-libcxx.sh
RUN \
    set -eux && \
    PARALLEL_JOBS="$PARALLEL_JOBS" bash /tmp/build-libcxx.sh /opt/llvm-staging/$LLVM_SRC && \
    rm -rf /opt/llvm-staging /tmp/build-libcxx.sh && \
    exit 0

FROM ${LLVM_COMPILER_IMAGE} AS compiler

FROM osxcross AS toolchain
ARG PARALLEL_JOBS=3
ARG LEGACY_MACOS_SDK=MacOSX10.7.sdk.tar.xz
COPY --from=compiler /opt/llvm-21 /opt/llvm-21
COPY --from=compiler /opt/cmake-3.27.9-linux-x86_64 /opt/cmake-3.27.9-linux-x86_64
ENV PATH=/opt/llvm-21/bin:/opt/cmake-3.27.9-linux-x86_64/bin:${PATH}
RUN --network=none \
    --mount=type=bind,source=downloads/llvm-project-21.1.8.src.tar.xz,target=/src/llvm.tar.xz \
    --mount=type=bind,source=downloads/${LEGACY_MACOS_SDK},target=/src/macos10.7.tar.xz \
    --mount=type=bind,source=patches/llvm/macos-snow-leopard/01-legacy-darwin-filesystem-and-clocks.patch,target=/src/libcxx.patch \
    --mount=type=bind,source=patches/llvm/macos-snow-leopard/03-runtime-emulated-tls.patch,target=/src/tls-runtime.patch \
    --mount=type=bind,source=scripts/build/qt5-macos/build-snow-libcxx-llvm.sh,target=/src/build-libcxx.sh \
    PARALLEL_JOBS="$PARALLEL_JOBS" bash /src/build-libcxx.sh \
        /src/llvm.tar.xz /src/libcxx.patch /src/tls-runtime.patch x86_64 /src/macos10.7.tar.xz

FROM toolchain AS build-qt
ARG MACOS_DEPLOYMENT_TARGET=10.6
ARG PARALLEL_JOBS=3
ARG DOWNLOAD_DIR
ARG OPENSSL_DISTRO
ARG QT_DISTRO
ARG QT_FULL_VERSION=5.15.19
ARG QT_SHA256=173c2326dae138bbb0d98921e9d911e55c00163d93a6db29f294b5e19ff306ae
RUN --network=none \
    --mount=type=bind,source=${DOWNLOAD_DIR}/${OPENSSL_DISTRO},target=/src/openssl.tar.gz \
    --mount=type=bind,source=scripts/build/openssl.sh,target=/src/build-openssl.sh \
    prefix=$(cat /opt/osxcross-prefix) && \
    CC="${prefix}clang" CXX="${prefix}clang++" AR="${prefix}ar" RANLIB="${prefix}ranlib" \
    MACOSX_DEPLOYMENT_TARGET="$MACOS_DEPLOYMENT_TARGET" PARALLEL_JOBS="$PARALLEL_JOBS" bash /src/build-openssl.sh \
        /src/openssl.tar.gz darwin64-x86_64-cc /opt/openssl-3 no-async no-shared no-tests && rm -rf /tmp/openssl-build
RUN --network=none \
    --mount=type=bind,source=${DOWNLOAD_DIR}/${QT_DISTRO},target=/src/qt.tar.xz \
    --mount=type=bind,source=patches/qt5/all,target=/src/patches/all \
    --mount=type=bind,source=patches/qt5/macos,target=/src/patches/macos \
    --mount=type=bind,source=patches/qt5/macos-llvm,target=/src/patches/macos-llvm \
    --mount=type=bind,source=patches/qt5/linux-lucid-llvm/01-qml-x86-register-enum.patch,target=/src/qml-x86.patch \
    --mount=type=bind,source=patches/qt5/linux-arm64-llvm/02-mapbox-clang21.patch,target=/src/mapbox.patch \
    --mount=type=bind,source=scripts/build/qt5-macos/build-qt-llvm.sh,target=/src/build-qt.sh \
    --mount=type=cache,id=qt5-macos-amd64-llvm21-qt,target=/work,sharing=locked \
    MACOSX_DEPLOYMENT_TARGET="$MACOS_DEPLOYMENT_TARGET" PARALLEL_JOBS="$PARALLEL_JOBS" bash /src/build-qt.sh x86_64

FROM toolchain AS sdk
COPY --from=build-qt /usr/local/Qt-5.15 /usr/local/Qt-5.15
COPY --from=build-qt /opt/openssl-3 /opt/openssl-3
COPY cmake/qt5/toolchain-macos-amd64.cmake /opt/longreach-llvm/cmake/toolchain.cmake
RUN --network=none \
    printf '\nstring(APPEND CMAKE_CXX_FLAGS_INIT " -femulated-tls -Wl,-force_load,/opt/longreach-llvm/lib/liblongreach-snow-tls.a")\n' >> /opt/longreach-llvm/cmake/toolchain.cmake && \
    printf '\nQMAKE_CXXFLAGS += -femulated-tls\nQMAKE_LFLAGS += -Wl,-force_load,/opt/longreach-llvm/lib/liblongreach-snow-tls.a\n' >> /usr/local/Qt-5.15/mkspecs/common/macx.conf
ENV PATH=/usr/local/Qt-5.15/bin:${PATH}
ENTRYPOINT ["/bin/bash", "-c"]
CMD ["qmake -query QT_VERSION"]

FROM ${SDK_IMAGE} AS examples
ARG PARALLEL_JOBS=3
COPY tests /tmp/qt-smoke-tests
RUN --network=none \
    --mount=type=bind,source=scripts/build/tests.sh,target=/src/build-tests.sh \
    SMOKE_CMAKE_TOOLCHAIN=/opt/longreach-llvm/cmake/toolchain.cmake SMOKE_OPENSSL_PREFIX=/opt/openssl-3 \
    SMOKE_REQUIRE_CXX23=1 PARALLEL_JOBS="$PARALLEL_JOBS" \
    bash /src/build-tests.sh /tmp/qt-smoke-tests /opt/qt-smoke-bin
