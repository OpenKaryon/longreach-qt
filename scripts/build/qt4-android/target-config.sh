#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-or-later
api=${ANDROID_API:-4}
abi=${ANDROID_ABI:-armeabi}
if [[ "$api" == 4 && "$abi" == armeabi ]]; then
    target=armv5te-linux-androideabi4
    qt_arch=arm
    sdk=/work/sysroot-api4
    runtime=/work/runtime-build
    core_tree=/work/qt4-donut
    quick_tree=/work/qt4-donut-quick
    core_prefix=/work/qtcore-donut-sdk
    quick_prefix=/work/qtquick-donut-sdk
elif [[ "$api" == 10 && "$abi" == x86 ]]; then
    source /opt/longreach-android/target.sh
    [[ "$abi" == "$ANDROID_ABI" ]] || { echo 'Runtime ABI does not match Qt4 target' >&2; exit 1; }
    qt_arch=i386
    sdk=/opt/longreach-android/sysroot
    runtime=/opt/longreach-android
    core_tree=/work/qt4-android-$abi/core
    quick_tree=/work/qt4-android-$abi/quick
    core_prefix=/opt/qt4-android-$abi-llvm-core
    quick_prefix=/opt/qt4-android-$abi-llvm
elif [[ "$api" == 21 && "$abi" == x86_64 ]]; then
    source /opt/longreach-android-api21/target.sh
    [[ "$abi" == "$ANDROID_ABI" ]] || { echo 'Runtime ABI does not match Qt4 target' >&2; exit 1; }
    qt_arch=x86_64
    sdk=/opt/longreach-android-api21/sysroot
    runtime=/opt/longreach-android-api21
    core_tree=/work/qt4-android-$abi/core
    quick_tree=/work/qt4-android-$abi/quick
    core_prefix=/opt/qt4-android-$abi-llvm-core
    quick_prefix=/opt/qt4-android-$abi-llvm
else
    echo "Unsupported Qt4 Android ABI/API: $abi/$api" >&2
    exit 1
fi
