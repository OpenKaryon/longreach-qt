#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2026 OpenKaryon
set -euo pipefail

archive=${1:?LLVM source archive required}
patches=${2:?LLVM patches directory required}
jobs=${PARALLEL_JOBS:-3}
[[ $jobs =~ ^[1-9][0-9]*$ ]] || { echo "Invalid PARALLEL_JOBS: $jobs" >&2; exit 2; }
scripts=$(cd "$(dirname "$0")" && pwd)
runtime=/opt/jaguar-llvm-runtime
sdk=/opt/jaguar/MacOSX10.2.8.sdk
gcc=/opt/jaguar-gcc/bin/powerpc-apple-darwin8-gcc
work=$(mktemp -d)
trap 'wait; rm -rf "$work"' EXIT

echo "4633a23617fa31a3ea51242586ea7fb1da7140e426bd62fc164261fe036aa142  $archive" | sha256sum -c -
tar -xJf "$archive" -C "$work" --strip-components=1 --wildcards \
    '*/libcxx/include' '*/libcxx/src' '*/libcxxabi/include' '*/libcxxabi/src' \
    '*/libc' '*/compiler-rt/lib/builtins'
cd "$work"
git apply "$patches/macos-jaguar/12-libcxx-jaguar.patch"
git apply "$patches/macos-snow-leopard/03-runtime-emulated-tls.patch"

mkdir -p "$runtime/include" "$runtime/lib" "$work/objects/libcxx" "$work/objects/libcxxabi"
cp -R libcxx/include/. "$runtime/include/"
cp "$scripts/__config_site" "$scripts/__assertion_handler" "$runtime/include/"

arch=(--target=powerpc-apple-macosx10.2 -mcpu=750 -isysroot "$sdk" -O2 -fPIC
      -mllvm -ppc-asm-full-reg-names)
cxx=(-std=c++23 -femulated-tls -faligned-allocation -fno-blocks -fno-use-cxa-atexit
     -nostdinc++ -isystem "$runtime/include" -isystem "$scripts/sdk-overlay"
     -fno-builtin-wcslen -fno-builtin-wmemcmp -fno-builtin-wmemchr
     -DLONGREACH_JAGUAR -D_LIBCPP_BUILDING_LIBRARY -D_LIBCPP_ENABLE_EXPERIMENTAL)

compile_unit() {
    local library=$1 unit=$2 name=$3
    local asm="$work/objects/$library/$name.s"
    local definitions=(-DLIBCXX_BUILDING_LIBCXXABI)
    if [[ $library == libcxxabi ]]; then
        definitions=(-D_LIBCXXABI_BUILDING_LIBRARY -DLIBCXXABI_BUILDING_LIBCXXABI)
    fi
    clang++ "${arch[@]}" "${cxx[@]}" "${definitions[@]}" \
        -I"$work/libcxxabi/include" -I"$work/libcxx/src" -I"$work/libcxx/src/include" -I"$work/libc" \
        -S "$unit" -o "$asm" &&
        sed -i 's/__lcxx_override,regular/__textcoal_nt,coalesced/g' "$asm" &&
        python3 "$scripts/convert-assembly.py" "$asm" "$asm.legacy" &&
        powerpc-apple-darwin8-as -arch ppc750 -o "${asm%.s}.o" "$asm.legacy"
}

# Batch compiles so any failed object aborts the runtime build.
pids=()
queue_unit() {
    compile_unit "$@" &
    pids+=("$!")
    if (( ${#pids[@]} >= jobs )); then
        wait "${pids[0]}"
        pids=("${pids[@]:1}")
    fi
}

for unit in libcxx/src/*.cpp libcxx/src/filesystem/*.cpp libcxx/src/ryu/*.cpp; do
    name=${unit#libcxx/src/}
    name=${name//\//-}
    queue_unit libcxx "$unit" "${name%.cpp}"
done
for name in abort_message cxa_aux_runtime cxa_default_handlers cxa_demangle \
    cxa_exception_storage cxa_exception cxa_guard cxa_handlers cxa_personality \
    cxa_thread_atexit cxa_vector cxa_virtual fallback_malloc private_typeinfo \
    stdlib_exception stdlib_stdexcept stdlib_typeinfo; do
    queue_unit libcxxabi "libcxxabi/src/$name.cpp" "$name"
done
for pid in "${pids[@]}"; do
    wait "$pid"
done
powerpc-apple-darwin8-ar rcs "$runtime/lib/libc++.a" "$work/objects/libcxx/"*.o
powerpc-apple-darwin8-ar rcs "$runtime/lib/libc++abi.a" "$work/objects/libcxxabi/"*.o

clang "${arch[@]}" -isystem "$scripts/sdk-overlay" -fno-unwind-tables \
    -fno-asynchronous-unwind-tables -S compiler-rt/lib/builtins/emutls.c -o "$work/emutls.s"
sed -i '/^[[:space:]]*\.macosx_version_min /d' "$work/emutls.s"
powerpc-apple-darwin8-as -arch ppc750 -o "$runtime/lib/emutls.o" "$work/emutls.s"
for unit in jaguar-locale jaguar-wide-symbols jaguar-qt-compat; do
    "$gcc" -mmacosx-version-min=10.2 -mcpu=750 -std=gnu99 \
        -isystem "$scripts/sdk-overlay" -O2 -fno-builtin -Werror=implicit-function-declaration \
        -c "$scripts/$unit.c" -o "$runtime/lib/$unit.o"
done

# qmake's static link uses -all_load. Keep compiler-rt's emutls definition.
archive=$("$gcc" -mmacosx-version-min=10.2 -mcpu=750 -print-libgcc-file-name)
cp "$archive" "$runtime/lib/libgcc.a"
powerpc-apple-darwin8-ar d "$runtime/lib/libgcc.a" emutls.o
powerpc-apple-darwin8-ranlib "$runtime/lib/libgcc.a"
test "$("$gcc" -B"$runtime/lib/" -mmacosx-version-min=10.2 -mcpu=750 -print-libgcc-file-name)" = "$runtime/lib/libgcc.a"
