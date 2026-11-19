#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-or-later

set -euo pipefail
prefix=/opt/longreach-android-api21
source "$prefix/target.sh"
compiler=clang++-21
include=(-nostdinc++ -isystem "$prefix/include/c++/v1")
if [[ "${0##*/}" == cc || "${0##*/}" == clang || "${0##*/}" == *-clang ]]; then
    compiler=clang-21
    include=()
fi
flags=(--target="$target" --sysroot="$prefix/sysroot"
    "${arch_flags[@]}" -DANDROID -fPIC -femulated-tls
    -Wno-unused-command-line-argument)
for argument in "$@"; do
    case "$argument" in
        -c|-E|-S|-M|-MM|--version|-dumpmachine|-dumpversion|-print-*|--print-*)
            exec "$compiler" "${flags[@]}" "${include[@]}" "$@"
            ;;
    esac
done
platform="$prefix/sysroot/usr/lib/$ndk_triple/21"
# CMake uses PIE executables for feature checks. Linking their -fPIE objects
# as a shared library is invalid on AArch64; preserve the requested link kind.
linker=/system/bin/linker
if [[ "$abi" == arm64-v8a ]]; then linker=/system/bin/linker64; fi
link=(-pie -Wl,-dynamic-linker,"$linker")
start=crtbegin_dynamic.o
end=crtend_android.o
for argument in "$@"; do
    if [[ "$argument" == -shared ]]; then
        link=(-shared)
        start=crtbegin_so.o
        end=crtend_so.o
        break
    fi
done
exec "$compiler" "${flags[@]}" "${include[@]}" -fuse-ld=lld "${link[@]}" -nostdlib \
    -L"$prefix/lib" -L"$platform" \
    -Wl,--hash-style=sysv,--no-undefined,--no-dependent-libraries,--wrap=tmpfile \
    "$platform/$start" "$prefix/lib/tmpfile-android.o" "$@" \
    -lc++_shared "$prefix/lib/libclang_rt.builtins-${builtins_arch}-android.a" \
    -llog -ldl -lm -lc "$platform/$end"
