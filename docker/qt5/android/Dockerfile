# SPDX-License-Identifier: GPL-3.0-or-later
#
# Qt 5.15.19, upstream LLVM 21.1.8, Android 2.3.3/API 10, armeabi-v7a.
# The Qt 4 Android image is a shared host-tools image, not its target SDK.

ARG LLVM_TOOLS_IMAGE=longreach-qt4-android-donut:llvm21
FROM ${LLVM_TOOLS_IMAGE} AS tools
RUN apt-get update \
    && apt-get install -y --no-install-recommends git openjdk-17-jdk-headless pkg-config \
    && rm -rf /var/lib/apt/lists/*
RUN clang-21 --version | grep -E 'clang version 21\.1\.8([[:space:]]|$)'
ENV JAVA_HOME=/usr/lib/jvm/java-17-openjdk-amd64

FROM tools AS runtime
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

FROM runtime AS openssl
COPY scripts/build/openssl.sh /repo/scripts/build/
COPY scripts/build/qt5-android/build-openssl.sh /repo/scripts/build/qt5-android/
RUN --network=none \
    --mount=type=bind,source=downloads/openssl-3.5.7.tar.gz,target=/repo/downloads/openssl-3.5.7.tar.gz \
    bash /repo/scripts/build/qt5-android/build-openssl.sh

FROM openssl AS qtbase
COPY patches/qt5/all /repo/patches/qt5/all
COPY patches/qt5/android /repo/patches/qt5/android
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

FROM tools AS sdk
COPY --from=qt-build /opt/longreach-android /opt/longreach-android
COPY --from=qt-build /opt/openssl-api10 /opt/openssl-api10
COPY --from=qt-build /opt/qt5-android-armeabi-v7a-llvm /opt/qt5-android-armeabi-v7a-llvm
COPY scripts/build/qt5-android/toolchain.cmake /opt/qt5-android-armeabi-v7a-llvm/toolchain.cmake
ENV PATH=/opt/qt5-android-armeabi-v7a-llvm/bin:${PATH} \
    ANDROID_NDK_ROOT=/opt/longreach-android/ndk
LABEL org.openkaryon.longreach-qt.platform="android-gingerbread-armeabi-v7a" \
      org.openkaryon.longreach-qt.android-api="10" \
      org.openkaryon.longreach-qt.compiler="LLVM 21.1.8" \
      org.openkaryon.longreach-qt.version="5.15.19"
WORKDIR /work
