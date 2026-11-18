#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-or-later

set -euo pipefail
prefix=/opt/longreach-android-api21
compiler=clang++-21
include=(-nostdinc++ -isystem "$prefix/include/c++/v1")
if [[ "${0##*/}" == cc || "${0##*/}" == clang || "${0##*/}" == *-clang ]]; then
    compiler=clang-21
    include=()
fi
flags=(--target=armv7a-linux-androideabi21 --sysroot="$prefix/sysroot"
    -march=armv7-a -mfpu=vfpv3-d16 -mfloat-abi=softfp -DANDROID -fPIC -femulated-tls
    -Wno-unused-command-line-argument)
for argument in "$@"; do
    case "$argument" in
        -c|-E|-S|-M|-MM|--version|-dumpmachine|-dumpversion|-print-*|--print-*)
            exec "$compiler" "${flags[@]}" "${include[@]}" "$@"
            ;;
    esac
done
platform="$prefix/sysroot/usr/lib/arm-linux-androideabi/21"
exec "$compiler" "${flags[@]}" "${include[@]}" -fuse-ld=lld -shared -nostdlib \
    -L"$prefix/lib" -L"$platform" \
    -Wl,--hash-style=sysv,--no-undefined,--no-dependent-libraries,--wrap=tmpfile \
    "$platform/crtbegin_so.o" "$prefix/lib/tmpfile-android.o" "$@" \
    -lc++_shared "$prefix/lib/libclang_rt.builtins-arm-android.a" \
    -llog -ldl -lm -lc "$platform/crtend_so.o"
