#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-or-later
# API21 target metadata shared by the producer and installed compiler driver.
abi=${ANDROID_ABI:-armeabi-v7a}
case "$abi" in
    armeabi-v7a)
        target=armv7a-linux-androideabi21
        ndk_triple=arm-linux-androideabi
        processor=armv7-a
        builtins_arch=arm
        openssl_target=android-arm
        arch_flags=(-march=armv7-a -mfpu=vfpv3-d16 -mfloat-abi=softfp)
        ;;
    arm64-v8a)
        target=aarch64-linux-android21
        ndk_triple=aarch64-linux-android
        processor=aarch64
        builtins_arch=aarch64
        openssl_target=android-arm64
        arch_flags=()
        ;;
    *) echo "Unsupported Android ABI: $abi" >&2; exit 1 ;;
esac
sdk_prefix=/opt/qt6-android-${abi}-llvm
