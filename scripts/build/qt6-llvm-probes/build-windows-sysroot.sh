#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2026 OpenKaryon
set -euo pipefail

target=${1:?target required}
work=${LLVM_BUILD_ROOT:-/work}
llvm=${LLVM_ROOT:-$work/toolchain}
sysroot=$work/sysroots/mingw13/$target
source=$work/mingw-w64-13
jobs=${PARALLEL_JOBS:-4}

case "$target" in
    windows-amd64)
        host=x86_64-w64-mingw32
        triple=x86_64-w64-windows-gnu
        crt=msvcrt
        minimum=0x0601
        machine=i386:x86-64
        libraries=(--enable-lib64 --disable-lib32 --disable-libarm32 --disable-libarm64)
        ;;
    windows-arm64)
        host=aarch64-w64-mingw32
        triple=aarch64-w64-windows-gnu
        crt=ucrt
        minimum=0x0a00
        machine=arm64
        libraries=(--disable-lib64 --disable-lib32 --disable-libarm32 --enable-libarm64)
        ;;
    *) exit 2 ;;
esac
archive=/src/downloads/mingw-w64-v13.0.0.tar.bz2
echo '5afe822af5c4edbf67daaf45eec61d538f49eef6b19524de64897c6b95828caf  '"$archive" | sha256sum -c -
signature=$({ sha256sum "$0" "$llvm/bin/clang"; printf '%s\n' "$target:$crt:$minimum"; } | sha256sum | cut -d ' ' -f 1)
if [ -f "$sysroot/.longreach-crt-inputs" ] && [ "$(cat "$sysroot/.longreach-crt-inputs")" = "$signature" ]; then
    echo "Reusing unchanged source-built headers/CRT for $target"
    exit 0
fi
mkdir -p "$source" "$sysroot" "$work/build-headers-mingw13-$target" "$work/build-crt-mingw13-$target"
if [ ! -f "$source/mingw-w64-crt/configure" ]; then
    python3 -c 'import bz2, shutil, sys; shutil.copyfileobj(bz2.open(sys.argv[1], "rb"), sys.stdout.buffer)' "$archive" \
        | tar -xf - -C "$source" --strip-components=1
fi
(
    cd "$work/build-headers-mingw13-$target"
    "$source/mingw-w64-headers/configure" --host="$host" --prefix="$sysroot" \
        --enable-sdk=all --with-default-msvcrt="$crt" \
        --with-default-win32-winnt="$minimum"
    make install
)
(
    cd "$work/build-crt-mingw13-$target"
    CC="$llvm/bin/clang --target=$triple --sysroot=$sysroot -fuse-ld=lld" \
    AR="$llvm/bin/llvm-ar" RANLIB="$llvm/bin/llvm-ranlib" \
    DLLTOOL="$llvm/bin/llvm-dlltool -m $machine" \
    CFLAGS=-O2 \
        "$source/mingw-w64-crt/configure" --host="$host" --prefix="$sysroot" \
            --with-default-msvcrt="$crt" "${libraries[@]}" --disable-dependency-tracking
    make -j "$jobs"
    make install
)

printf '%s\n' "$signature" > "$sysroot/.longreach-crt-inputs"
