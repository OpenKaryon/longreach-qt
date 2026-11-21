#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-or-later
abi=${ANDROID_ABI:-armeabi-v7a}
case "$abi" in
    armeabi-v7a)
        api=10
        profile=gingerbread
        processor=armv7-a
        ndk_triple=arm-linux-androideabi
        openssl_target=linux-armv4
        ;;
    x86)
        api=10
        profile=gingerbread
        processor=i686
        ndk_triple=i686-linux-android
        openssl_target=linux-x86
        ;;
    arm64-v8a)
        api=21
        profile=lollipop
        processor=aarch64
        ndk_triple=aarch64-linux-android
        openssl_target=linux-aarch64
        ;;
    x86_64)
        api=21
        profile=lollipop
        processor=x86_64
        ndk_triple=x86_64-linux-android
        openssl_target=linux-x86_64
        ;;
    *) echo "Unsupported Qt5 Android ABI: $abi" >&2; exit 1 ;;
esac
sdk_prefix=/opt/qt5-android-${abi}-llvm
openssl_prefix=/opt/openssl-api${api}

# The API10 runtime captures these values for installed compiler wrappers.
# API21 targets use the shared API21 runtime producer instead.
if [[ "$api" == 10 ]]; then
    case "$abi" in
        armeabi-v7a)
            target=armv7a-linux-androideabi10
            runtime_processor=arm
            builtins_arch=arm
            ndk_arch=arm
            arch_flags=(-march=armv7-a -mfpu=vfpv3-d16 -mfloat-abi=softfp)
            sysroot_archive=aosp-ndk-r7-api9-arm.tar.gz
            sysroot_sha256=6f7ec1a9b177ccd1da48c2045d14c5f62fc7db32581919535269cc2738a35f8d
            ;;
        x86)
            target=i686-linux-android10
            runtime_processor=i686
            builtins_arch=i686
            ndk_arch=x86
            arch_flags=(-march=i686 -mssse3 -mstackrealign -mfpmath=sse)
            sysroot_archive=aosp-ndk-r7-api9-x86.tar.gz
            sysroot_sha256=b439f09f897cda29bb7600308f5b928c4ba00407c1503f76d9c6482807e78b92
            ;;
    esac
fi
