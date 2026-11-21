#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-or-later

set -euo pipefail
prefix=/opt/longreach-android
source "$prefix/target.sh"
compiler=clang++-21
include=(-nostdinc++ -isystem "$prefix/include/c++/v1")
if [[ "${0##*/}" == cc || "${0##*/}" == clang ]]; then
    compiler=clang-21
    include=()
fi
flags=(--target="$target" --sysroot="$prefix/sysroot"
    "${arch_flags[@]}" -fPIC -femulated-tls
    -D__STDC_LIMIT_MACROS -D__STDC_CONSTANT_MACROS -DSIZE_MAX=__SIZE_MAX__
    -D_LIBCPP_PROVIDES_DEFAULT_RUNE_TABLE -Wno-unused-command-line-argument)
for argument in "$@"; do
    case "$argument" in
        -c|-E|-S|-M|-MM|--version|-dumpmachine|-dumpversion|-print-*|--print-*)
            exec "$compiler" "${flags[@]}" "${include[@]}" "$@"
            ;;
    esac
done
exec "$compiler" "${flags[@]}" "${include[@]}" -fuse-ld=lld -shared -nostdlib \
    -Wl,--hash-style=sysv,--no-undefined,--no-dependent-libraries,--wrap=tmpfile \
    "$prefix/lib/crt-android.o" "$@" \
    -L"$prefix/lib" -lc++_shared \
    "$prefix/lib/libclang_rt.builtins-${builtins_arch}-android.a" \
    -L"$prefix/sysroot/usr/lib" -llog -ldl -lm -lc
