#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2026 OpenKaryon
set -euo pipefail
prefix=/opt/longreach-android-api4
source "$prefix/target.sh"
compiler=clang++-21
include=(-nostdinc++ -isystem "$prefix/include/c++/v1" -fexperimental-library)
cxx=true
if [[ "${0##*/}" == cc || "${0##*/}" == clang || "${0##*/}" == *-clang ]]; then
    compiler=clang-21
    include=()
    cxx=false
fi
flags=(--target="$target" --sysroot="$prefix/sysroot" "${arch_flags[@]}" -fPIC -femulated-tls
    -D__STDC_LIMIT_MACROS -D__STDC_CONSTANT_MACROS -DSIZE_MAX=__SIZE_MAX__
    -D_LIBCPP_PROVIDES_DEFAULT_RUNE_TABLE -Wno-unused-command-line-argument)
# The runtime is supplied explicitly, so recognize link kind both at the driver
# and in forwarded linker arguments. Consume option operands before interpreting
# flags: the value in -Wl,-rpath,-shared does not request a shared library.
kind=executable
static=false
static_pie=false
pie=false
no_link=false
has_input=false
start_files=true
default_libraries=true
linker_operand=false
linker_argument() {
    if $linker_operand; then linker_operand=false; return; fi
    case "$1" in
        -shared|--shared) kind=shared ;;
        -r|--relocatable) kind=relocatable ;;
        -static|--static) static=true ;;
        -pie|--pie) pie=true ;;
        -no-pie|--no-pie) pie=false ;;
        -rpath|--rpath|-rpath-link|--rpath-link|-soname|--soname|-h|-o|--output|\
        -L|--library-path|-l|--library|-e|--entry|-u|--undefined|-z|-T|--script|\
        --dynamic-linker|-dynamic-linker|--version-script|--dynamic-list|\
        --retain-symbols-file|--just-symbols|--defsym|-m|--emulation)
            linker_operand=true ;;
    esac
}
driver_operand=false
forward_linker=false
inputs_only=false
for argument in "$@"; do
    if $inputs_only; then has_input=true; continue; fi
    if $forward_linker; then
        linker_argument "$argument"
        forward_linker=false
        continue
    fi
    if $driver_operand; then driver_operand=false; continue; fi
    case "$argument" in
        --) inputs_only=true ;;
        -Xlinker|--for-linker) forward_linker=true ;;
        -Wl,*)
            IFS=, read -r -a forwarded <<< "${argument#-Wl,}"
            for value in "${forwarded[@]}"; do linker_argument "$value"; done ;;
        -c|-E|-S|-M|-MM|-fsyntax-only|--version|-dumpmachine|-dumpversion|-print-*|--print-*)
            no_link=true ;;
        -shared|--shared|-r|--relocatable|-static|--static|-pie|--pie|-no-pie|--no-pie)
            linker_argument "$argument" ;;
        -static-pie) static=true; static_pie=true ;;
        -nostdlib) start_files=false; default_libraries=false ;;
        -nostartfiles) start_files=false ;;
        -nodefaultlibs) default_libraries=false ;;
        -o|-x|-I|-isystem|-iquote|-idirafter|-include|-imacros|-L|-target|--target|\
        --sysroot|-isysroot|-resource-dir|-B|-D|-U|-Xclang|-Xpreprocessor|-Xassembler|\
        -MF|-MT|-MQ|-MJ|-gcc-toolchain|--gcc-toolchain|-stdlib)
            driver_operand=true ;;
        -l) has_input=true; driver_operand=true ;;
        -l?*|@*|-) has_input=true ;;
        -*) ;;
        *) has_input=true ;;
    esac
done
if $no_link || ! $has_input; then
    exec "$compiler" "${flags[@]}" "${include[@]}" "$@"
fi
if [[ "$kind" == relocatable ]]; then
    # No CRT, runtime libraries or executable/shared-only linker policy in -r.
    exec "$compiler" "${flags[@]}" "${include[@]}" -fuse-ld=lld -r -nostdlib "$@"
fi
if [[ "$kind" == shared ]] && $static; then
    echo 'longreach clang wrapper: shared and static link modes cannot be combined' >&2
    exit 2
fi

platform="$prefix/sysroot/usr/lib"
link=()
begin=()
finish=()
if [[ "$kind" == shared ]]; then
    link=(-shared)
    if $start_files; then begin=("$prefix/lib/crt-donut.o"); fi
else
    start=crtbegin_dynamic.o
    if $static_pie; then
        link=(-static-pie)
    elif $static; then
        link=(-static)
        start=crtbegin_static.o
    else
        if $pie; then link=(-pie); else link=(-no-pie); fi
        link+=(-Wl,-dynamic-linker,/system/bin/linker)
    fi
    if $start_files; then
        begin=("$platform/$start")
        finish=("$platform/crtend_android.o")
    fi
fi
libraries=()
if $default_libraries; then
    libraries=("$prefix/lib/armv5-compat.o" "$prefix/lib/tmpfile-donut.o" -Wl,--start-group)
    if $cxx; then
        libraries+=("$prefix/lib/libc++.a" "$prefix/lib/libc++experimental.a"
            "$prefix/lib/libc++abi.a" "$prefix/lib/libunwind.a")
    fi
    libraries+=("$prefix/lib/libclang_rt.builtins-arm-android.a" -llog -ldl -lm -lc -Wl,--end-group)
fi
exec "$compiler" "${flags[@]}" "${include[@]}" -fuse-ld=lld "${link[@]}" -nostdlib \
    -L"$prefix/lib" -L"$platform" \
    -Wl,--hash-style=sysv,--no-undefined,--no-dependent-libraries,--exclude-libs,ALL,--wrap=tmpfile \
    "${begin[@]}" "$@" "${libraries[@]}" "${finish[@]}"
