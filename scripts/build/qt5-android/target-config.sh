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
