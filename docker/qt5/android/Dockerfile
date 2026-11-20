# SPDX-License-Identifier: GPL-3.0-or-later
#
# Qt 5.15.19, upstream LLVM21.1.8: ARMv7/API10 or ARM64/API21.
# The Qt 4 Android image is a shared host-tools image, not its target SDK.

ARG ANDROID_ABI=armeabi-v7a
ARG LLVM_TOOLS_IMAGE=longreach-qt4-android-donut:llvm21
FROM ${LLVM_TOOLS_IMAGE} AS tools
RUN apt-get update \
    && apt-get install -y --no-install-recommends git openjdk-17-jdk-headless pkg-config \
    && rm -rf /var/lib/apt/lists/*
RUN clang-21 --version | grep -E 'clang version 21\.1\.8([[:space:]]|$)'
ENV JAVA_HOME=/usr/lib/jvm/java-17-openjdk-amd64

FROM tools AS armeabi-v7a-runtime
ARG PARALLEL_JOBS=2
ENV PARALLEL_JOBS=${PARALLEL_JOBS}
WORKDIR /work
COPY patches/android/gingerbread /repo/patches/android/gingerbread
COPY scripts/build/qt4-android/crt-donut.c scripts/build/qt4-android/tmpfile-donut.c /repo/scripts/build/qt4-android/
COPY scripts/build/qt5-android/build-runtime.sh \
     scripts/build/qt5-android/install-toolchain.sh \
     scripts/build/qt5-android/clang-wrapper.sh \
     scripts/build/qt5-android/compat.c /repo/scripts/build/qt5-android/
RUN --network=none \
    --mount=type=bind,source=downloads/llvm-project-21.1.8.src.tar.xz,target=/repo/downloads/llvm-project-21.1.8.src.tar.xz \
    --mount=type=bind,source=downloads/android-gingerbread/aosp-ndk-r7-api9-arm.tar.gz,target=/repo/downloads/android-gingerbread/aosp-ndk-r7-api9-arm.tar.gz \
    --mount=type=bind,source=downloads/android-gingerbread/aosp-cpufeatures-android-4.0.3-r1.tar.gz,target=/repo/downloads/android-gingerbread/aosp-cpufeatures-android-4.0.3-r1.tar.gz \
    bash /repo/scripts/build/qt5-android/build-runtime.sh && rm -rf /work/* /work/.android-runtime-prepared

# API21 reuses the platform/runtime producer, not a Qt6 target SDK/image.
FROM tools AS api21-platform
ARG ANDROID_ABI
ENV ANDROID_ABI=${ANDROID_ABI}
ARG PARALLEL_JOBS=2
ENV PARALLEL_JOBS=${PARALLEL_JOBS}
WORKDIR /work
COPY scripts/build/qt6-android/prepare-inputs.py /repo/scripts/build/qt6-android/
COPY scripts/fetch/locks/qt6-android-api21-inputs.json /repo/scripts/fetch/locks/
RUN --network=none \
    --mount=type=bind,source=downloads/android-lollipop,target=/inputs \
    python3 /repo/scripts/build/qt6-android/prepare-inputs.py

FROM api21-platform AS api21-runtime
COPY patches/android/lollipop /repo/patches/android/lollipop
COPY scripts/build/qt4-android/tmpfile-donut.c /repo/scripts/build/qt4-android/
COPY scripts/build/qt6-android/target-config.sh \
     scripts/build/qt6-android/build-runtime.sh \
     scripts/build/qt6-android/install-toolchain.sh \
     scripts/build/qt6-android/clang-wrapper.sh \
     scripts/build/qt6-android/toolchain.cmake /repo/scripts/build/qt6-android/
COPY scripts/tests/android-api21-driver.sh /repo/scripts/tests/
RUN --network=none \
    --mount=type=bind,source=downloads/llvm-project-21.1.8.src.tar.xz,target=/repo/downloads/llvm-project-21.1.8.src.tar.xz \
    bash /repo/scripts/build/qt6-android/build-runtime.sh \
    && bash /repo/scripts/build/qt6-android/install-toolchain.sh \
    && bash /repo/scripts/tests/android-api21-driver.sh \
    && ln -s /opt/longreach-android-api21 /opt/longreach-android

FROM api21-runtime AS arm64-v8a-runtime

FROM ${ANDROID_ABI}-runtime AS runtime
ARG ANDROID_ABI
ENV ANDROID_ABI=${ANDROID_ABI}
COPY scripts/build/qt5-android/target-config.sh \
     scripts/build/qt5-android/install-target-config.sh /repo/scripts/build/qt5-android/
RUN bash /repo/scripts/build/qt5-android/install-target-config.sh

FROM runtime AS openssl
COPY scripts/build/openssl.sh /repo/scripts/build/
COPY scripts/build/qt5-android/build-openssl.sh /repo/scripts/build/qt5-android/
RUN --network=none \
    --mount=type=bind,source=downloads/openssl-3.5.7.tar.gz,target=/repo/downloads/openssl-3.5.7.tar.gz \
    bash /repo/scripts/build/qt5-android/build-openssl.sh

FROM openssl AS qtbase
COPY patches/qt5/all /repo/patches/qt5/all
COPY patches/qt5/android /repo/patches/qt5/android
COPY patches/qt5/windows-xp-llvm/02-qtscript-host-call-flag.patch /repo/patches/qt5/windows-xp-llvm/
COPY patches/qt5/linux-arm64-llvm/01-qml-arm64-register-enum.patch /repo/patches/qt5/linux-arm64-llvm/
COPY scripts/build/qt5-android/build-qt.sh scripts/build/qt5-android/apply-qt-patches.py /repo/scripts/build/qt5-android/
COPY scripts/build/qt5-android/mkspec /repo/scripts/build/qt5-android/mkspec
RUN --network=none \
    --mount=type=bind,source=downloads/qt-everywhere-opensource-src-5.15.19.tar.xz,target=/repo/downloads/qt-everywhere-opensource-src-5.15.19.tar.xz \
    --mount=type=bind,source=downloads/android-gingerbread/android-35.jar,target=/work/android-sdk/platforms/android-35/android.jar \
    echo '4566663c3876e022b4fa4ced8c8697c4ab1688267f090114fd92d027b32e619b  /work/android-sdk/platforms/android-35/android.jar' | sha256sum -c - \
    && bash /repo/scripts/build/qt5-android/build-qt.sh base

FROM qtbase AS qt-build
RUN --network=none \
    --mount=type=bind,source=downloads/qt-everywhere-opensource-src-5.15.19.tar.xz,target=/repo/downloads/qt-everywhere-opensource-src-5.15.19.tar.xz \
    --mount=type=bind,source=downloads/android-gingerbread/android-35.jar,target=/work/android-sdk/platforms/android-35/android.jar \
    bash /repo/scripts/build/qt5-android/build-qt.sh all

FROM qt-build AS validated
COPY scripts/build/qt5-android/finish-sdk.sh /repo/scripts/build/qt5-android/
COPY scripts/build/qt6-android/validate-api21-elf.py \
     scripts/build/qt6-android/input-provenance.py /repo/scripts/build/qt6-android/
RUN --network=none bash /repo/scripts/build/qt5-android/finish-sdk.sh

FROM tools AS sdk-base
ARG ANDROID_ABI
ENV ANDROID_ABI=${ANDROID_ABI}
COPY --from=validated /out/qt5-sdk /opt/longreach-reports
COPY --from=validated /opt/qt5-android-${ANDROID_ABI}-llvm /opt/qt5-android-${ANDROID_ABI}-llvm
COPY scripts/build/qt5-android/toolchain.cmake /opt/qt5-android-${ANDROID_ABI}-llvm/toolchain.cmake
ENV PATH=/opt/qt5-android-${ANDROID_ABI}-llvm/bin:${PATH} \
    ANDROID_NDK_ROOT=/opt/longreach-android/ndk
LABEL org.openkaryon.longreach-qt.compiler="LLVM 21.1.8" \
      org.openkaryon.longreach-qt.version="5.15.19"
WORKDIR /work

FROM sdk-base AS armeabi-v7a-sdk
COPY --from=validated /opt/longreach-android /opt/longreach-android
COPY --from=validated /opt/openssl-api10 /opt/openssl-api10
LABEL org.openkaryon.longreach-qt.platform="android-gingerbread-armeabi-v7a" \
      org.openkaryon.longreach-qt.android-api="10"

FROM sdk-base AS arm64-v8a-sdk
COPY --from=validated /opt/openssl-api21 /opt/openssl-api21
COPY --from=validated /opt/longreach-android-api21 /opt/longreach-android-api21
RUN ln -s /opt/longreach-android-api21 /opt/longreach-android
LABEL org.openkaryon.longreach-qt.platform="android-lollipop-arm64-v8a" \
      org.openkaryon.longreach-qt.android-api="21"

FROM ${ANDROID_ABI}-sdk AS sdk
