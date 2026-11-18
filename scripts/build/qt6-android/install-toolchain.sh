#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-or-later

set -euo pipefail
prefix=/opt/longreach-android-api21
ndk="$prefix/ndk"
original=/ndk/toolchains/llvm/prebuilt/linux-x86_64/sysroot
copy_if_changed() {
    if ! cmp -s "$1" "$2"; then
        cp "$1" "$2"
    fi
}
mkdir -p "$prefix/bin" "$prefix/sysroot/usr/lib" "$prefix/sysroot/usr/include"
if [[ ! -e "$prefix/sysroot/usr/include/android" ]]; then
    cp -a "$original/usr/include/." "$prefix/sysroot/usr/include/"
fi
for patch in /repo/patches/android/lollipop/*.patch; do
    if patch -p1 --reverse --dry-run -d "$prefix/sysroot" < "$patch" >/dev/null 2>&1; then
        continue
    fi
    patch -p1 --forward -d "$prefix/sysroot" < "$patch"
done
if [[ ! -d "$prefix/sysroot/usr/lib/arm-linux-androideabi/21" ]]; then
    cp -a "$original/usr/lib/arm-linux-androideabi" "$prefix/sysroot/usr/lib/"
fi
copy_if_changed "$prefix/lib/libc++_shared.so" "$prefix/sysroot/usr/lib/arm-linux-androideabi/libc++_shared.so"
copy_if_changed "$prefix/lib/libc++.a" "$prefix/sysroot/usr/lib/arm-linux-androideabi/libc++_static.a"
for library in libc++abi.a libc++experimental.a libunwind.a; do
    copy_if_changed "$prefix/lib/$library" "$prefix/sysroot/usr/lib/arm-linux-androideabi/$library"
done
if [[ -d "$prefix/sysroot/usr/include/c++/v1" && ! -L "$prefix/sysroot/usr/include/c++/v1" ]]; then
    test ! -e /work/api21/unused-ndk-cxx-headers
    mv "$prefix/sysroot/usr/include/c++/v1" /work/api21/unused-ndk-cxx-headers
fi
ln -sfn "$prefix/include/c++/v1" "$prefix/sysroot/usr/include/c++/v1"
if [[ ! -f "$prefix/lib/tmpfile-android.o" || /repo/scripts/build/qt4-android/tmpfile-donut.c -nt "$prefix/lib/tmpfile-android.o" ]]; then
    clang-21 --target=armv7a-linux-androideabi21 --sysroot="$prefix/sysroot" \
        -march=armv7-a -mfpu=vfpv3-d16 -mfloat-abi=softfp -fPIC \
        -c /repo/scripts/build/qt4-android/tmpfile-donut.c -o "$prefix/lib/tmpfile-android.o"
fi
copy_if_changed /repo/scripts/build/qt6-android/clang-wrapper.sh "$prefix/bin/cxx"
chmod +x "$prefix/bin/cxx"
ln -sfn cxx "$prefix/bin/cc"
toolchain="$ndk/toolchains/llvm/prebuilt/linux-x86_64"
mkdir -p "$toolchain/bin"
cp /ndk/source.properties "$ndk/source.properties"
cp -a /ndk/meta "$ndk/"
if [[ ! -f "$ndk/sources/android/cpufeatures/cpu-features.c" ]]; then
    mkdir -p "$ndk/sources/android"
    cp -a /ndk/sources/android/cpufeatures /ndk/sources/android/native_app_glue "$ndk/sources/android/"
fi
ln -sfn "$prefix/sysroot" "$toolchain/sysroot"
ln -sfn "$prefix/bin/cc" "$toolchain/bin/clang"
ln -sfn "$prefix/bin/cc" "$toolchain/bin/armv7a-linux-androideabi21-clang"
ln -sfn "$prefix/bin/cxx" "$toolchain/bin/clang++"
for tool in ar ranlib strip objcopy nm readobj readelf objdump; do
    ln -sfn "/usr/bin/llvm-$tool-21" "$toolchain/bin/llvm-$tool"
done
copy_if_changed /repo/scripts/build/qt6-android/toolchain.cmake "$prefix/toolchain.cmake"
echo 'Installed external upstream LLVM21 API21 toolchain'
