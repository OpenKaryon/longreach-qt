#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2026 OpenKaryon
#
# A static archive of dlopen stubs (stubs.py) that stands in for shared
# libraries at link time:
#
#   archive.sh OUTPUT.a PREFIX [--fail FUNCTION=VALUE]... [--skip FUNCTION]...
#              [--extra FILE.c]... [--mirror] SONAME=LIBRARY...
#
# LIBRARY is the build's copy of a library, read only for the symbols it
# exports; SONAME is what the stubs load at run time. --fail is passed to
# stubs.py; --skip leaves a function out, for an --extra file to define;
# --extra compiles a C file into the archive (the functions --fail and --skip
# name). Stubs cannot stand in for exported data: --mirror has stubs.py define
# it and copy it from the library; without it the names are written to
# OUTPUT.a.data, for the caller to provide or to rule out. CC compiles
# (default cc) with CFLAGS for the extra files, NM reads the symbols (default
# nm), AR archives (default ar).
set -euo pipefail
here=$(cd "$(dirname "$0")" && pwd)
out=$1
prefix=$2
shift 2
cc=${CC:-cc}
nm=${NM:-nm}
ar=${AR:-ar}
work=$(mktemp -d)
fails=()
extras=()
libs=()
mirrors=()
mirror=
: > "$work/data.txt"
: > "$work/skip.txt"
# What the linker defines in every shared object, which is not the library's.
linker='^(_init|_fini|_edata|_end|__bss_start|_DYNAMIC|_GLOBAL_OFFSET_TABLE_|_IO_stdin_used)$'
while [ $# -gt 0 ]; do
    case $1 in
        --fail) fails+=(--fail "$2"); shift 2 ;;
        --skip) echo "$2" >> "$work/skip.txt"; shift 2 ;;
        --extra) extras+=("$2"); shift 2 ;;
        --mirror) mirror=1; shift ;;
        *=*)
            soname=${1%%=*}
            library=${1#*=}
            n=${#libs[@]}
            # Newer nm prints symbol versions (name@@VERSION); a name exported
            # in two versions is stubbed once, and dlsym picks the default.
            "$nm" -D -S --defined-only "$library" > "$work/nm-$n.txt"
            awk -v linker="$linker" '($NF ~ linker) { next }
                NF >= 3 && ($(NF-1) == "T" || $(NF-1) == "W" || $(NF-1) == "i") { sub(/@.*/, "", $NF); print $NF }' \
                "$work/nm-$n.txt" | sort -u > "$work/all-functions-$n.txt"
            grep -v -x -F -f "$work/skip.txt" "$work/all-functions-$n.txt" > "$work/functions-$n.txt" || true
            awk -v linker="$linker" 'NF == 4 && $3 ~ /^[DRBV]$/ && $4 !~ linker { sub(/@.*/, "", $4); print $4, "0x" $2 }' \
                "$work/nm-$n.txt" | sort -u > "$work/data-$n.txt"
            libs+=("$soname:$work/functions-$n.txt")
            mirrors+=(--mirror "$soname:$work/data-$n.txt")
            cut -d' ' -f1 "$work/data-$n.txt" >> "$work/data.txt"
            shift ;;
        *) echo "archive.sh: unexpected argument $1" >&2; exit 2 ;;
    esac
done
case $("$cc" -dumpmachine) in
    x86_64*) arch=x86_64 ;;
    i?86*) arch=i386 ;;
    aarch64*) arch=aarch64 ;;
    *) echo "archive.sh: no stubs for $("$cc" -dumpmachine)" >&2; exit 1 ;;
esac
if [ -n "$mirror" ]; then
    fails+=("${mirrors[@]}")
    : > "$work/data.txt"
fi
python3 "$here/stubs.py" --arch "$arch" --prefix "$prefix" --out "$work" ${fails[@]+"${fails[@]}"} "${libs[@]}"
"$cc" -c -o "$work/stubs.o" "$work/$prefix-stubs.S"
"$cc" -c -O2 -o "$work/resolve.o" "$work/$prefix-resolve.c"
objects=("$work/stubs.o" "$work/resolve.o")
for extra in ${extras[@]+"${extras[@]}"}; do
    object=$work/extra-${#objects[@]}.o
    "$cc" ${CFLAGS:-} -c -O2 -o "$object" "$extra"
    objects+=("$object")
done
mkdir -p "$(dirname "$out")"
"$ar" rcs "$out" "${objects[@]}"
sort -u "$work/data.txt" > "$out.data"
rm -rf "$work"
