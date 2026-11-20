#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-or-later
# A small pre-SDK check using exactly the shared 25 behavior probes.
set -euo pipefail
prefix=/opt/longreach-android-api21
source "$prefix/target.sh"
platform="$prefix/sysroot/usr/lib/$ndk_triple/21"
linker=/system/bin/linker
if [[ "$abi" == arm64-v8a || "$abi" == x86_64 ]]; then linker=/system/bin/linker64; fi
mkdir -p /out
clang++-21 --target="$target" --sysroot="$prefix/sysroot" "${arch_flags[@]}" \
    -std=c++23 -fexperimental-library -femulated-tls -fPIE -pie -O2 \
    -nostdinc++ -isystem "$prefix/include/c++/v1" -fuse-ld=lld -nostdlib \
    -Wl,--hash-style=sysv,--no-undefined,--no-dependent-libraries,--wrap=tmpfile \
    -Wl,-dynamic-linker,"$linker" "$platform/crtbegin_dynamic.o" \
    /repo/scripts/tests/qt6-llvm-probes/main.cpp "$prefix/lib/tmpfile-android.o" \
    -L"$prefix/lib" -lc++_shared "$prefix/lib/libclang_rt.builtins-${builtins_arch}-android.a" \
    -L"$platform" -llog -ldl -lm -lc "$platform/crtend_android.o" -o /out/cxx23-probe
cp "$prefix/lib/libc++_shared.so" /out/libc++_shared.so
llvm-readobj-21 --file-header --dynamic-table /out/cxx23-probe > /out/cxx23-probe-elf.txt
