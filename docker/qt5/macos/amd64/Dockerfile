# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2026 OpenKaryon
#
# Qt 5.15, static, for Intel Macs from OS X 10.6 Snow Leopard (see
# MACOS_DEPLOYMENT_TARGET), cross-built with osxcross.
#
#   toolchain  cmake + osxcross (+ the static libc++ below 10.7)
#   builder    patch, configure, build, install
#   final      the toolchain plus the installed SDK and the tests/ suite
#
# The final stage inherits the toolchain stage, so applications are built with
# exactly the osxcross Qt was built with.

# ---------------------------------------------------------------------------
# toolchain: cmake + osxcross, shared by the builder and the final image.
# Ubuntu 22.04: osxcross builds apple-libtapi from current LLVM, which needs
# newer clang and CMake than 16.04 has; the host's glibc does not matter for a
# Mach-O cross-build.
# ---------------------------------------------------------------------------
FROM --platform=linux/amd64 ubuntu:22.04 AS toolchain

# The macOS SDK comes from the build context and is never redistributed (see
# QT5_MACOS_SDK in mk/qt5.mk). Its version and the deployment target are
# independent: see MACOS_DEPLOYMENT_TARGET below.
ARG OSX_SDK="MacOSX11.3.sdk.tar.xz"
# ARGs do not cross FROM; DOWNLOAD_DIR is declared again in the builder.
ARG DOWNLOAD_DIR="downloads"

# osxcross has no tags; a verified commit keeps the image from changing with
# master. make qt5-macos-amd64 OSXCROSS_REF=master tests another.
ARG OSXCROSS_REPO="https://github.com/OpenKaryon/osxcross.git"
ARG OSXCROSS_REF="27d21e4977c9751d01199c7a226a6faf494c3dd9"

# The compiler's architecture; the darwin version is read from the SDK.
ARG OSXCROSS_ARCH="x86_64"

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
    apt -y update && \
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

# The resolved commit goes into the build log; only the pinned ref is fetched.
RUN \
    set -eux && \
    mkdir -p /opt/osxcross && \
    cd /opt/osxcross && \
    git init -q && \
    git remote add origin "$OSXCROSS_REPO" && \
    git fetch --depth 1 origin "$OSXCROSS_REF" && \
    git checkout -q FETCH_HEAD && \
    echo "osxcross ref '$OSXCROSS_REF' resolved to $(git rev-parse HEAD)" && \
    # The wrapper refuses libc++ below 10.7; the kit links its own there (LLVM_SRC), \
    # so the check is lifted for SDKs without libstdc++. \
    sed -i 's|    if (OSNum.Num() \&\& OSNum < OSVersion(10, 7)) {|    if (OSNum.Num() \&\& OSNum < OSVersion(10, 7) \&\& SDKOSNum < OSVersion(10, 14)) {|' \
        wrapper/target.cpp && \
    grep -q 'OSNum < OSVersion(10, 7) && SDKOSNum < OSVersion(10, 14)' wrapper/target.cpp && \
    mv /opt/sdk-staging/$OSX_SDK tarballs/$OSX_SDK && \
    OCDEBUG=1 OSX_VERSION_MIN=$MACOS_DEPLOYMENT_TARGET UNATTENDED=1 \
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
    UNATTENDED=1 ENABLE_COMPILER_RT_INSTALL=1 ./build_compiler_rt.sh && \
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

# Below 10.7: the static C++ runtime, installed into the SDK so every C++ link
# picks it up through -lc++ (scripts/build/qt5-macos/build-libcxx.sh). The
# LLVM tarball is copied either way; COPY cannot be conditional.
COPY ${DOWNLOAD_DIR}/${LLVM_SRC} /opt/llvm-staging/${LLVM_SRC}
COPY scripts/build/qt5-macos/build-libcxx.sh /tmp/build-libcxx.sh
ARG PARALLEL_JOBS=""
RUN \
    set -eux && \
    if [ "$(printf '%s\n' 10.7 "$MACOS_DEPLOYMENT_TARGET" | sort -V | head -1)" != 10.7 ]; then \
        PARALLEL_JOBS="$PARALLEL_JOBS" bash /tmp/build-libcxx.sh /opt/llvm-staging/$LLVM_SRC; \
    fi && \
    rm -rf /opt/llvm-staging /tmp/build-libcxx.sh && \
    exit 0

# ---------------------------------------------------------------------------
# builder: unpack, patch, configure, build and install Qt.
# ---------------------------------------------------------------------------
FROM toolchain AS builder

ARG QT_FULL_VERSION="5.15.19"
ARG QT_DISTRO="qt-everywhere-opensource-src-${QT_FULL_VERSION}.tar.xz"
ARG DOWNLOAD_DIR="downloads"
ARG QT_SRC_DIR="qt-everywhere-src-${QT_FULL_VERSION}"
ARG PARALLEL_JOBS=""
# ARGs do not cross FROM.
ARG MACOS_DEPLOYMENT_TARGET

# patches/qt5/all for every Qt 5 target, patches/qt5/macos for macOS.
COPY patches/qt5/all /tmp/patches/all
COPY patches/qt5/macos /tmp/patches/macos
COPY ${DOWNLOAD_DIR}/${QT_DISTRO} /opt/${QT_DISTRO}

# TLS below 10.11 goes through a static OpenSSL: 10.7's SecureTransport stops
# at TLS 1.0 and lacks the API Qt 5.15 uses.
ARG OPENSSL_VERSION="3.5.7"
ARG OPENSSL_DISTRO="openssl-${OPENSSL_VERSION}.tar.gz"
COPY ${DOWNLOAD_DIR}/${OPENSSL_DISTRO} /opt/${OPENSSL_DISTRO}
COPY scripts/build/openssl.sh /tmp/build-openssl.sh

# -opengl desktop gives Qt3D, DataVisualization, Quick3D and QtOpenGL;
# -dbus-runtime loads libdbus at run time, as the SDK has no D-Bus headers.
RUN \
    set -eux && \
    pre1011= && \
    if [ "$(printf '%s\n' 10.11 "$MACOS_DEPLOYMENT_TARGET" | sort -V | head -1)" != 10.11 ]; then pre1011=1; fi && \
    mkdir -p /opt/openssl-3 && \
    if [ -n "$pre1011" ]; then \
        prefix=$(cat /opt/osxcross-prefix) && \
        CC=${prefix}clang CXX=${prefix}clang++ AR=${prefix}ar RANLIB=${prefix}ranlib \
            bash /tmp/build-openssl.sh /opt/$OPENSSL_DISTRO darwin64-x86_64-cc /opt/openssl-3 \
            no-async no-shared no-tests && \
        set -- -openssl-linked -no-securetransport OPENSSL_PATH=/opt/openssl-3 \
            "OPENSSL_LIBS=-L/opt/openssl-3/lib -lssl -lcrypto"; \
    else \
        set -- -no-openssl -securetransport; \
    fi && \
    rm -f /opt/$OPENSSL_DISTRO && \
    cd /opt && \
    tar -xJf $QT_DISTRO && \
    mv $QT_SRC_DIR Qt-5.15 && \
    rm -f $QT_DISTRO && \
    cd /opt/Qt-5.15/ && \
    for p in /tmp/patches/all/*.patch /tmp/patches/macos/*.patch; do echo "applying $p"; git apply "$p"; done && \
    sed -i "s|^QMAKE_MACOSX_DEPLOYMENT_TARGET = .*|QMAKE_MACOSX_DEPLOYMENT_TARGET = $MACOS_DEPLOYMENT_TARGET|" \
        qtbase/mkspecs/common/macx.conf && \
    grep -q "^QMAKE_MACOSX_DEPLOYMENT_TARGET = $MACOS_DEPLOYMENT_TARGET\$" qtbase/mkspecs/common/macx.conf && \
    ./configure -v -prefix "/usr/local/Qt-5.15" \
        -xplatform macx-clang -device-option CROSS_COMPILE="$(cat /opt/osxcross-prefix)" \
        -no-avx -c++std c++14 -static -optimize-size -release -opensource -confirm-license \
        -nomake examples -nomake tests -nomake tools -no-cups -dbus-runtime -gif -no-iconv \
        -no-icu -opengl desktop "$@" -no-openvg -no-pch -sql-sqlite -qt-sqlite -ssl \
        -make libs -qt-harfbuzz -qt-libjpeg -qt-libpng -qt-pcre -qt-zlib -skip wayland -skip qtwebengine && \
    make -j "${PARALLEL_JOBS:-$(nproc)}" && \
    make install && \
    echo "SDK prefix to be shipped:" && du -sh /usr/local/Qt-5.15 && \
    exit 0

# ---------------------------------------------------------------------------
# final: the toolchain stage plus the installed SDK, with tests/ built
# against it.
# ---------------------------------------------------------------------------
FROM toolchain

ARG PARALLEL_JOBS=""

COPY --from=builder /usr/local/Qt-5.15 /usr/local/Qt-5.15
# Empty unless the target is below 10.11.
COPY --from=builder /opt/openssl-3 /opt/openssl-3

ENV PATH="/usr/local/Qt-5.15/bin:$PATH"

# CMake for tests/ (Qt 5.15's static plugin import needs 3.15+), installed
# here so the builder's cache stays valid.
ARG CMAKE_VERSION="3.28.6"
COPY scripts/build/cmake.sh /tmp/build-cmake.sh
RUN bash /tmp/build-cmake.sh "${CMAKE_VERSION}" /opt/cmake

ENV PATH="/opt/cmake/bin:${PATH}"

COPY tests /tmp/qt-smoke-tests
COPY cmake/qt5 /tmp/qt-smoke-cmake
COPY scripts/build/tests.sh /tmp/build-tests.sh

# Building the suite against the installed SDK alone proves it self-contained;
# running it needs a Mac.
RUN if [ -d /opt/openssl-3/lib ]; then export SMOKE_OPENSSL_PREFIX=/opt/openssl-3; fi && \
    SMOKE_CMAKE_TOOLCHAIN=/tmp/qt-smoke-cmake/toolchain-macos-amd64.cmake \
    bash /tmp/build-tests.sh /tmp/qt-smoke-tests /opt/qt-smoke-bin

ENTRYPOINT ["/bin/bash", "-l", "-c"]
