# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2026 OpenKaryon
# Shared Android host tools; build context is the repository root.
ARG ANDROID_ABI=x86_64
FROM ghcr.io/openkaryonlab/ubuntu:22.04@sha256:5ec03bb3441e8b0bf3b4f9cd4629a1ae763010dc3035bb8da3ae6cf026486401 AS base
ARG APT_SNAPSHOT
COPY scripts/build/apt-snapshot.sh /usr/local/bin/apt-snapshot
RUN sh /usr/local/bin/apt-snapshot "$APT_SNAPSHOT" \
    && apt-get update \
    && DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
        ca-certificates cmake g++ git make ninja-build patch perl python3 xz-utils \
    && rm -rf /var/lib/apt/lists/*

FROM base AS compiler
ARG PARALLEL_JOBS=2
ENV LLVM_ROOT=/opt/llvm-21
COPY scripts/build/qt6-llvm-probes/build-compiler.sh /tmp/build-compiler.sh
RUN --network=none \
    --mount=type=bind,source=downloads/llvm-project-21.1.8.src.tar.xz,target=/tmp/llvm.tar.xz \
    --mount=type=cache,id=android-llvm21-compiler,target=/work \
    LLVM_TARGETS='X86;ARM;AArch64' PARALLEL_JOBS="${PARALLEL_JOBS}" \
    bash /tmp/build-compiler.sh /tmp/llvm.tar.xz

FROM base AS tools
COPY scripts/build/android-api21/generic-atomics.sh /repo/scripts/build/android-api21/
COPY --from=compiler /opt/llvm-21 /opt/llvm-21
RUN --network=none set -e; \
    for tool in clang clang++ ld.lld lld llvm-ar llvm-ranlib llvm-nm llvm-objcopy \
            llvm-objdump llvm-readobj llvm-readelf llvm-strip; do \
        test -x "/opt/llvm-21/bin/$tool"; \
        ln -s "/opt/llvm-21/bin/$tool" "/usr/bin/$tool-21"; \
    done; \
    clang-21 --version | grep -E 'clang version 21\.1\.8([[:space:]]|$)'; \
    for target in arm aarch64 x86-64; do \
        clang-21 --print-targets | grep -E "^[[:space:]]+$target[[:space:]]"; \
    done
LABEL org.openkaryon.longreach-qt.role="android-llvm-tools" \
      org.openkaryon.longreach-qt.llvm="21.1.8"

# API21 uses the common upstream LLVM runtime producer, not a Qt5/Qt6 SDK.
FROM tools AS platform
ARG ANDROID_ABI
ENV ANDROID_ABI=${ANDROID_ABI} ANDROID_API=21
WORKDIR /work
COPY scripts/build/qt6-android/prepare-inputs.py /repo/scripts/build/qt6-android/
COPY scripts/fetch/locks/qt6-android-api21-inputs.json /repo/scripts/fetch/locks/
RUN --network=none \
    --mount=type=bind,source=downloads/android-lollipop,target=/inputs \
    python3 /repo/scripts/build/qt6-android/prepare-inputs.py

FROM platform AS api21-runtime
ARG PARALLEL_JOBS=2
ENV PARALLEL_JOBS=${PARALLEL_JOBS}
COPY patches/android/lollipop /repo/patches/android/lollipop
COPY scripts/build/qt4-android/tmpfile-donut.c /repo/scripts/build/qt4-android/
COPY scripts/build/qt6-android/target-config.sh \
     scripts/build/qt6-android/build-runtime.sh \
     scripts/build/qt6-android/install-toolchain.sh \
     scripts/build/qt6-android/clang-wrapper.sh \
     scripts/build/qt6-android/toolchain.cmake /repo/scripts/build/qt6-android/
COPY scripts/tests/android/android-api21-driver.sh /repo/scripts/tests/android/
RUN --network=none \
    --mount=type=bind,source=downloads/llvm-project-21.1.8.src.tar.xz,target=/repo/downloads/llvm-project-21.1.8.src.tar.xz \
    bash /repo/scripts/build/qt6-android/build-runtime.sh \
    && bash /repo/scripts/build/qt6-android/install-toolchain.sh \
    && bash /repo/scripts/tests/android/android-api21-driver.sh

FROM api21-runtime AS x86_64-runtime

FROM api21-runtime AS arm64-v8a-runtime

# API10 reuses the legacy LLVM runtime producer, without a Qt5 SDK.
FROM tools AS x86-runtime
ARG PARALLEL_JOBS=2
ENV ANDROID_ABI=x86 ANDROID_API=10 PARALLEL_JOBS=${PARALLEL_JOBS}
WORKDIR /work
COPY patches/android/gingerbread /repo/patches/android/gingerbread
COPY scripts/fetch/locks/qt5-android-api10-inputs.json /repo/scripts/fetch/locks/
COPY scripts/build/qt4-android/crt-donut.c scripts/build/qt4-android/tmpfile-donut.c /repo/scripts/build/qt4-android/
COPY scripts/build/qt5-android/build-runtime.sh \
     scripts/build/qt5-android/target-config.sh \
     scripts/build/qt5-android/input-provenance.py \
     scripts/build/qt5-android/install-toolchain.sh \
     scripts/build/qt5-android/clang-wrapper.sh \
     scripts/build/qt5-android/compat.c /repo/scripts/build/qt5-android/
RUN --network=none \
    --mount=type=bind,source=downloads/llvm-project-21.1.8.src.tar.xz,target=/repo/downloads/llvm-project-21.1.8.src.tar.xz \
    --mount=type=bind,source=downloads/android-gingerbread,target=/repo/downloads/android-gingerbread \
    bash /repo/scripts/build/qt5-android/build-runtime.sh && rm -rf /work/* /work/.android-runtime-prepared

FROM ${ANDROID_ABI}-runtime AS runtime

# ANDROID_ABI is inherited from the selected runtime ENV, including cache IDs.
FROM runtime AS qt-build
ARG ANDROID_ABI
COPY scripts/build/android-api21/sdk-reports.py /repo/scripts/build/android-api21/
ARG PARALLEL_JOBS=2
ENV PARALLEL_JOBS=${PARALLEL_JOBS}
COPY scripts/build/qt4-android/target-config.sh \
     scripts/build/qt4-android/cache-inputs.py \
     scripts/build/qt4-android/prepare-source.py \
     scripts/build/qt4-android/build-qtcore.sh \
     scripts/build/qt4-android/patch-qtcore.py \
     scripts/build/qt4-android/build-api21-sdk.sh \
     scripts/build/qt4-android/sdk-provenance.py \
     scripts/build/qt4-android/export-mkspecs.py \
     scripts/build/qt4-android/toolchain.cmake /repo/scripts/build/qt4-android/
COPY patches/qt4/all/03-static-gui-animation-registration.patch \
     patches/qt4/all/04-script-tagged-frame-pointers.patch /repo/patches/qt4/all/
COPY patches/qt4/android /repo/patches/qt4/android
COPY patches/qt4/linux-sarge-llvm/01-xmlpatterns-color-mask.patch /repo/patches/qt4/linux-sarge-llvm/
RUN --network=none \
    --mount=type=cache,id=qt4-android-${ANDROID_ABI}-sdk,target=/work,sharing=locked \
    --mount=type=bind,source=downloads/qt-everywhere-opensource-src-4.8.7.tar.gz,target=/inputs/qt-everywhere-opensource-src-4.8.7.tar.gz \
    bash /repo/scripts/build/qt4-android/build-api21-sdk.sh quick

FROM tools AS sdk-base
ARG ANDROID_ABI
ENV ANDROID_ABI=${ANDROID_ABI}
COPY --from=qt-build /opt/qt4-android-${ANDROID_ABI}-llvm /opt/qt4-android-${ANDROID_ABI}-llvm
COPY scripts/build/qt4-android/toolchain.cmake /opt/qt4-android-${ANDROID_ABI}-llvm/toolchain.cmake
COPY scripts/build/qt4-android/export-mkspecs.py /opt/qt4-android-${ANDROID_ABI}-llvm/libexec/longreach-export-mkspecs.py
ENV PATH=/opt/qt4-android-${ANDROID_ABI}-llvm/bin:${PATH} \
    QMAKESPEC=/opt/qt4-android-${ANDROID_ABI}-llvm/mkspecs/android-longreach-clang
LABEL org.openkaryon.longreach-qt.compiler="LLVM 21.1.8" \
      org.openkaryon.longreach-qt.version="4.8.7"
WORKDIR /work

FROM sdk-base AS api21-sdk
ENV ANDROID_API=21 ANDROID_NDK_ROOT=/opt/longreach-android-api21/ndk
COPY --from=qt-build /opt/longreach-android-api21 /opt/longreach-android-api21
LABEL org.openkaryon.longreach-qt.platform="android-lollipop-${ANDROID_ABI}" \
      org.openkaryon.longreach-qt.android-api="21"

FROM api21-sdk AS x86_64-sdk

FROM api21-sdk AS arm64-v8a-sdk

FROM sdk-base AS x86-sdk
ENV ANDROID_API=10 ANDROID_NDK_ROOT=/opt/longreach-android/ndk
COPY --from=qt-build /opt/longreach-android /opt/longreach-android
LABEL org.openkaryon.longreach-qt.platform="android-gingerbread-${ANDROID_ABI}" \
      org.openkaryon.longreach-qt.android-api="10"

FROM ${ANDROID_ABI}-sdk AS sdk
RUN --network=none runtime=/opt/longreach-android-api21 && \
    if [ "$ANDROID_API" = 10 ]; then runtime=/opt/longreach-android; fi && \
    python3 "/opt/qt4-android-${ANDROID_ABI}-llvm/libexec/longreach-export-mkspecs.py" verify \
        --prefix "/opt/qt4-android-${ANDROID_ABI}-llvm" --runtime "$runtime"

# Historical API4 and Qt5/6 bootstrap callers build only these host tools.
FROM tools AS default
