# SPDX-License-Identifier: GPL-3.0-or-later
# Qt 6.8.5 / Android API21 ARMv7, ARM64, x86 or x86_64; upstream LLVM 21.1.8, never the NDK compiler.
ARG LLVM_TOOLS_IMAGE=longreach-qt4-android-donut:llvm21
ARG QT_HOST_IMAGE=qt6-linux-amd64-llvm21:latest
FROM ${QT_HOST_IMAGE} AS qt-host
FROM ${LLVM_TOOLS_IMAGE} AS tools
COPY scripts/build/android-api21/generic-atomics.sh /repo/scripts/build/android-api21/
RUN apt-get update && apt-get install -y --no-install-recommends \
    git openjdk-17-jdk-headless pkg-config libgl1 libegl1 libxkbcommon-x11-0 \
    libxcb-icccm4 libxcb-util1 libxcb-image0 libxcb-keysyms1 libxcb-randr0 \
    libxcb-render-util0 libxcb-shm0 libxcb-sync1 libxcb-xfixes0 libxcb-render0 \
    libxcb-shape0 libxcb-xkb1 libxcb-glx0 libx11-xcb1 \
    && rm -rf /var/lib/apt/lists/*
RUN clang-21 --version | grep -E 'clang version 21\.1\.8([[:space:]]|$)'
COPY --from=qt-host /opt/qt6-linux-amd64-llvm /opt/qt6-linux-amd64-llvm
RUN ln -s /opt/qt6-linux-amd64-llvm /opt/qt6-host-llvm21 \
    && /opt/qt6-host-llvm21/libexec/moc --version | grep -E '^moc 6\.8\.5$' \
    && /opt/qt6-host-llvm21/bin/qsb --version | grep -E '6\.8\.5$'
ENV JAVA_HOME=/usr/lib/jvm/java-17-openjdk-amd64
ARG PARALLEL_JOBS=2
ENV PARALLEL_JOBS=${PARALLEL_JOBS}
WORKDIR /work

FROM tools AS platform
ARG ANDROID_ABI=armeabi-v7a
ENV ANDROID_ABI=${ANDROID_ABI}
COPY scripts/build/qt6-android/prepare-inputs.py /repo/scripts/build/qt6-android/
COPY scripts/fetch/locks/qt6-android-api21-inputs.json /repo/scripts/fetch/locks/
RUN --network=none \
    --mount=type=bind,source=downloads/android-lollipop,target=/inputs \
    python3 /repo/scripts/build/qt6-android/prepare-inputs.py

FROM platform AS runtime
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

FROM runtime AS openssl
COPY scripts/build/qt6-android/build-openssl.sh /repo/scripts/build/qt6-android/
RUN --network=none \
    --mount=type=bind,source=downloads/openssl-3.5.7.tar.gz,target=/repo/downloads/openssl-3.5.7.tar.gz \
    bash /repo/scripts/build/qt6-android/build-openssl.sh

FROM openssl AS qt-build
COPY patches/qt6/all /repo/patches/qt6/all
COPY patches/qt6/android /repo/patches/qt6/android
COPY scripts/build/qt6-android/build-sdk.sh \
     scripts/build/qt6-android/apply-qt-patches.py /repo/scripts/build/qt6-android/
RUN --network=none \
    --mount=type=bind,source=downloads/qt-everywhere-src-6.8.5.tar.xz,target=/repo/downloads/qt-everywhere-src-6.8.5.tar.xz \
    bash /repo/scripts/build/qt6-android/build-sdk.sh

# Report-only recipe updates reuse the completed native SDK layer.
FROM qt-build AS validated
COPY scripts/build/android-api21/sdk-reports.py /repo/scripts/build/android-api21/
COPY scripts/build/qt6-android/finish-sdk.sh \
     scripts/build/qt6-android/validate-api21-elf.py \
     scripts/build/qt6-android/input-provenance.py /repo/scripts/build/qt6-android/
RUN --network=none bash /repo/scripts/build/qt6-android/finish-sdk.sh

FROM tools AS sdk
ARG ANDROID_ABI=armeabi-v7a
ENV ANDROID_ABI=${ANDROID_ABI}
COPY --from=validated /opt/longreach-android-api21 /opt/longreach-android-api21
COPY --from=validated /opt/openssl-api21 /opt/openssl-api21
COPY --from=validated /opt/qt6-android-${ANDROID_ABI}-llvm /opt/qt6-android-${ANDROID_ABI}-llvm
COPY --from=validated /work/android-sdk /work/android-sdk
COPY --from=validated /out/sdk-reports /opt/longreach-reports
COPY --from=validated /out/sdk-packaging /opt/longreach-packaging
ENV PATH=/opt/qt6-android-${ANDROID_ABI}-llvm/bin:${PATH} \
    ANDROID_NDK_ROOT=/opt/longreach-android-api21/ndk
LABEL org.openkaryon.longreach-qt.platform="android-lollipop-${ANDROID_ABI}" \
      org.openkaryon.longreach-qt.android-api="21" \
      org.openkaryon.longreach-qt.compiler="LLVM 21.1.8" \
      org.openkaryon.longreach-qt.version="6.8.5"
WORKDIR /work
