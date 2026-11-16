# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2026 OpenKaryon
#
# Qt 5 with upstream LLVM 21.1.8 for Intel Mac OS X 10.6.

ARG SDK_IMAGE=sdk
ARG BASE_REGISTRY=ghcr.io/openkaryonlab
ARG LLVM_COMPILER_IMAGE=longreach-llvm:21.1.8-compiler
ARG SNOW_COMPILER_IMAGE=longreach-llvm:21.1.8-snow-tls
ARG OSXCROSS_IMAGE=qt5-macos-snow-osxcross
ARG DOWNLOAD_DIR=downloads
ARG OPENSSL_DISTRO=openssl-3.5.7.tar.gz
ARG QT_DISTRO=qt-everywhere-opensource-src-5.15.19.tar.xz

FROM ${LLVM_COMPILER_IMAGE} AS snow-compiler
ARG PARALLEL_JOBS=3
RUN --network=none \
    --mount=type=bind,source=downloads/llvm-project-21.1.8.src.tar.xz,target=/src/llvm.tar.xz \
    --mount=type=bind,source=patches/llvm/macos-snow-leopard/02-clang-emulated-tls.patch,target=/src/clang.patch \
    --mount=type=bind,source=scripts/build/qt6-llvm-probes/build-compiler.sh,target=/src/build-compiler.sh \
    --mount=type=cache,id=qt5-llvm21-snow-compiler,target=/work,sharing=locked \
    set -eu; \
    echo '4633a23617fa31a3ea51242586ea7fb1da7140e426bd62fc164261fe036aa142  /src/llvm.tar.xz' | sha256sum -c -; \
    if [ ! -f /work/source/llvm/CMakeLists.txt ]; then \
        mkdir -p /work/source; tar -xJf /src/llvm.tar.xz -C /work/source --strip-components=1; \
    fi; \
    cd /work/source; \
    if git apply --check /src/clang.patch >/dev/null 2>&1; then git apply /src/clang.patch; \
    else git apply --reverse --check /src/clang.patch; fi; \
    PARALLEL_JOBS="$PARALLEL_JOBS" bash /src/build-compiler.sh /src/llvm.tar.xz

FROM ${SNOW_COMPILER_IMAGE} AS compiler

FROM ${OSXCROSS_IMAGE} AS osxcross-i386

ARG DOWNLOAD_DIR="downloads"
ARG LLVM_SRC="llvm-project-14.0.6.src.tar.xz"
# The 10.7 SDK, of which only the i386 libraries are used (QT5_MACOS_I386_LINK_SDK).
ARG I386_LINK_SDK="MacOSX10.7.sdk.tar.xz"
ARG PARALLEL_JOBS=""

COPY ${DOWNLOAD_DIR}/${LLVM_SRC} /opt/staging/${LLVM_SRC}
COPY ${DOWNLOAD_DIR}/${I386_LINK_SDK} /opt/staging/${I386_LINK_SDK}
COPY scripts/build/qt5-macos /tmp/qt5-macos
RUN \
    set -eux && \
    PARALLEL_JOBS="$PARALLEL_JOBS" bash /tmp/qt5-macos/build-i386-toolchain.sh \
        /opt/staging/$LLVM_SRC /opt/staging/$I386_LINK_SDK && \
    rm -rf /opt/staging /tmp/qt5-macos && \
    exit 0

FROM osxcross-i386 AS toolchain
ARG PARALLEL_JOBS=3
COPY --from=compiler /opt/llvm-21 /opt/llvm-21
COPY --from=compiler /opt/cmake-3.27.9-linux-x86_64 /opt/cmake-3.27.9-linux-x86_64
ENV PATH=/opt/llvm-21/bin:/opt/cmake-3.27.9-linux-x86_64/bin:${PATH}
RUN --network=none \
    --mount=type=bind,source=downloads/llvm-project-21.1.8.src.tar.xz,target=/src/llvm.tar.xz \
    --mount=type=bind,source=patches/llvm/macos-snow-leopard/01-legacy-darwin-filesystem-and-clocks.patch,target=/src/libcxx.patch \
    --mount=type=bind,source=patches/llvm/macos-snow-leopard/03-runtime-emulated-tls.patch,target=/src/tls-runtime.patch \
    --mount=type=bind,source=scripts/build/qt5-macos/build-snow-libcxx-llvm.sh,target=/src/build-libcxx.sh \
    PARALLEL_JOBS="$PARALLEL_JOBS" bash /src/build-libcxx.sh /src/llvm.tar.xz /src/libcxx.patch /src/tls-runtime.patch

FROM toolchain AS build-qt
ARG PARALLEL_JOBS=3
ARG DOWNLOAD_DIR
ARG OPENSSL_DISTRO
ARG QT_DISTRO
ARG QT_FULL_VERSION=5.15.19
ARG QT_SHA256=173c2326dae138bbb0d98921e9d911e55c00163d93a6db29f294b5e19ff306ae
RUN --network=none \
    --mount=type=bind,source=${DOWNLOAD_DIR}/${OPENSSL_DISTRO},target=/src/openssl.tar.gz \
    --mount=type=bind,source=scripts/build/openssl.sh,target=/src/build-openssl.sh \
    CC=i386-apple-darwin10-clang CXX=i386-apple-darwin10-clang++ \
    AR=i386-apple-darwin10-ar RANLIB=i386-apple-darwin10-ranlib MACOSX_DEPLOYMENT_TARGET=10.6 \
    PARALLEL_JOBS="$PARALLEL_JOBS" bash /src/build-openssl.sh \
        /src/openssl.tar.gz darwin-i386-cc /opt/openssl-3 no-async no-shared no-tests && rm -rf /tmp/openssl-build
RUN --network=none \
    --mount=type=bind,source=${DOWNLOAD_DIR}/${QT_DISTRO},target=/src/qt.tar.xz \
    --mount=type=bind,source=patches/qt5/all,target=/src/patches/all \
    --mount=type=bind,source=patches/qt5/macos,target=/src/patches/macos \
    --mount=type=bind,source=patches/qt5/macos-llvm,target=/src/patches/macos-llvm \
    --mount=type=bind,source=patches/qt5/linux-lucid-llvm/01-qml-x86-register-enum.patch,target=/src/qml-x86.patch \
    --mount=type=bind,source=patches/qt5/linux-arm64-llvm/02-mapbox-clang21.patch,target=/src/mapbox.patch \
    --mount=type=bind,source=scripts/build/qt5-macos/build-qt-llvm.sh,target=/src/build-qt.sh \
    --mount=type=cache,id=qt5-macos-i386-llvm21-qt,target=/work,sharing=locked \
    PARALLEL_JOBS="$PARALLEL_JOBS" bash /src/build-qt.sh i386

FROM toolchain AS sdk
COPY --from=build-qt /usr/local/Qt-5.15 /usr/local/Qt-5.15
COPY --from=build-qt /opt/openssl-3 /opt/openssl-3
COPY cmake/qt5/toolchain-macos-i386.cmake /opt/longreach-llvm/cmake/toolchain.cmake
RUN --network=none \
    driver=/usr/local/osxcross/bin/i386-apple-darwin10-clang++ && \
    sed -i 's/cxx=(-nostdinc++/cxx=(-femulated-tls -nostdinc++/' "$driver" && \
    grep -Fq 'cxx=(-femulated-tls -nostdinc++' "$driver"
# CMake 3.28 emits framework flag/name pairs the i386 driver can map to
# the 10.7 link SDK. CMake 3.27 expands pairs through -Xlinker.
ARG DOWNLOAD_DIR=downloads
RUN --network=none \
    --mount=type=bind,source=${DOWNLOAD_DIR}/cmake-3.28.6-linux-x86_64.tar.gz,target=/src/cmake.tar.gz \
    echo '931e3c0d546ee03ca72bb147ccd9b49e3b6252f765f66bf21b9d165519940458  /src/cmake.tar.gz' | sha256sum -c - && \
    mkdir -p /opt/cmake && tar -xzf /src/cmake.tar.gz -C /opt/cmake --strip-components=1
ENV PATH=/usr/local/Qt-5.15/bin:/opt/cmake/bin:${PATH}
ENTRYPOINT ["/bin/bash", "-c"]
CMD ["qmake -query QT_VERSION"]

FROM ${SDK_IMAGE} AS examples
ARG PARALLEL_JOBS=3
COPY tests /tmp/qt-smoke-tests
RUN --network=none \
    --mount=type=bind,source=scripts/build/tests.sh,target=/src/build-tests.sh \
    SMOKE_CMAKE_TOOLCHAIN=/opt/longreach-llvm/cmake/toolchain.cmake \
    SMOKE_OPENSSL_PREFIX=/opt/openssl-3 SMOKE_REQUIRE_CXX23=1 PARALLEL_JOBS="$PARALLEL_JOBS" \
    bash /src/build-tests.sh /tmp/qt-smoke-tests /opt/qt-smoke-bin
