# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2026 OpenKaryon
#
# Qt 4.8.7, static, for Intel Macs from Mac OS X 10.4 Tiger, with the legacy
# osxcross branch (current osxcross rejects SDKs older than 10.6).
FROM --platform=linux/amd64 ubuntu:22.04 AS toolchain
ARG PARALLEL_JOBS=6
ARG OSXCROSS_REF=f547d14e6ac6c5bb0ddd7563651eb29057e1d755
ENV DEBIAN_FRONTEND=noninteractive
RUN apt-get update && apt-get install -y --no-install-recommends \
    build-essential clang llvm-dev cmake git patch python3 perl curl ca-certificates \
    autoconf automake libtool libssl-dev libxml2-dev liblzma-dev zlib1g-dev \
    libbz2-dev bzip2 xz-utils file && rm -rf /var/lib/apt/lists/*
COPY downloads/MacOSX10.4u.sdk.tar.xz /tmp/MacOSX10.4u.sdk.tar.xz
RUN echo 'd28276ce6b0f14af30f3bfdc171f8ef4033652da593578568f8be189506c1021  /tmp/MacOSX10.4u.sdk.tar.xz' | sha256sum -c - \
    && git clone https://github.com/tpoechtrager/osxcross.git /opt/osxcross \
    && cd /opt/osxcross && git checkout "$OSXCROSS_REF" \
    && mv /tmp/MacOSX10.4u.sdk.tar.xz tarballs/ \
    && UNATTENDED=1 OSX_VERSION_MIN=10.4 JOBS="$PARALLEL_JOBS" \
       TARGET_DIR=/opt/tiger-toolchain ./build.sh
ENV PATH=/opt/tiger-toolchain/bin:$PATH
ENV MACOSX_DEPLOYMENT_TARGET=10.4
RUN printf '#include <iostream>\nint main(){std::cout << "Tiger";return 0;}\n' > /tmp/tiger.cpp \
    && i386-apple-darwin8-clang++ -std=gnu++98 /tmp/tiger.cpp -o /tmp/tiger-probe \
    && file /tmp/tiger-probe && i386-apple-darwin8-otool -l /tmp/tiger-probe

FROM toolchain AS cxx-runtime
ARG PARALLEL_JOBS=6
COPY downloads/gcc-5.5.0.tar.xz /archives/gcc-5.5.0.tar.xz
COPY scripts/build/qt4-macos/build-cxx-runtime.sh /scripts/build-cxx-runtime.sh
RUN echo '530cea139d82fe542b358961130c69cfde8b3d14556370b65823d2f91f0ced87  /archives/gcc-5.5.0.tar.xz' | sha256sum -c - \
    && TIGER_JOBS="$PARALLEL_JOBS" bash /scripts/build-cxx-runtime.sh

FROM cxx-runtime AS tiger-sdk
COPY scripts/build/qt4-macos/normalize-sdk-stubs.py /scripts/normalize-sdk-stubs.py
RUN python3 /scripts/normalize-sdk-stubs.py /opt/tiger-toolchain/SDK/MacOSX10.4u.sdk

FROM tiger-sdk AS builder
ARG PARALLEL_JOBS=6
COPY downloads/qt-everywhere-opensource-src-4.8.7.tar.gz downloads/openssl-1.0.2u.tar.gz /archives/
RUN echo 'ecd0c6ffb493dd06707d38b14bb4d8c2288bb7033735606569d8f90f89669d16  /archives/openssl-1.0.2u.tar.gz' | sha256sum -c - \
    && mkdir -p /work/openssl-source && cd /work/openssl-source \
    && tar -xzf /archives/openssl-1.0.2u.tar.gz --strip-components=1 \
    && ./Configure darwin-i386-cc --prefix=/opt/openssl-tiger no-shared no-asm no-capieng \
       -L/opt/tiger-toolchain/SDK/MacOSX10.4u.sdk/usr/lib/gcc/i686-apple-darwin10/4.0.1 -lgcc -lgcc_s.10.4 \
    && make -j "$PARALLEL_JOBS" CC=i386-apple-darwin8-clang AR='i386-apple-darwin8-ar r' RANLIB=i386-apple-darwin8-ranlib \
    && make install_sw CC=i386-apple-darwin8-clang AR='i386-apple-darwin8-ar r' RANLIB=i386-apple-darwin8-ranlib
COPY scripts/build/qt4-macos/build-qt.sh scripts/build/qt4-macos/qmake.conf /scripts/
COPY patches/qt4 /patches
RUN --mount=type=cache,id=qt4-tiger-i386-source,target=/work/qt-source,sharing=locked \
    TIGER_JOBS="$PARALLEL_JOBS" bash /scripts/build-qt.sh

FROM tiger-sdk
COPY --from=builder /opt/qt4-tiger /opt/qt4-tiger
COPY --from=builder /opt/openssl-tiger /opt/openssl-tiger
COPY --from=builder /opt/qt4-licenses /opt/qt4-licenses
ENV PATH=/opt/qt4-tiger/bin:$PATH
LABEL org.openkaryon.longreach-qt.platform=macos-tiger-i386
ENTRYPOINT ["/bin/bash", "-l", "-c"]
