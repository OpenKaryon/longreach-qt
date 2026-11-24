#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-or-later
# Shared 25 behavior checks and an all-ABI cross-DSO generic atomic probe.
set -euo pipefail
repo=/repo
prefix=/opt/longreach-android-api21
output=${PROBE_OUTPUT_DIR:-/out}
source "$prefix/target.sh"
source "$repo/scripts/build/android-api21/generic-atomics.sh"
platform="$prefix/sysroot/usr/lib/$ndk_triple/21"
linker=/system/bin/linker
if [[ "$abi" == arm64-v8a || "$abi" == x86_64 ]]; then linker=/system/bin/linker64; fi
mkdir -p "$output"
clang++-21 --target="$target" --sysroot="$prefix/sysroot" "${arch_flags[@]}" \
    -std=c++23 -fexperimental-library -femulated-tls -fPIE -pie -O2 \
    -nostdinc++ -isystem "$prefix/include/c++/v1" -fuse-ld=lld -nostdlib \
    -Wl,--hash-style=sysv,--no-undefined,--no-dependent-libraries,--wrap=tmpfile \
    -Wl,-dynamic-linker,"$linker" "$platform/crtbegin_dynamic.o" \
    "$repo/scripts/tests/qt6-llvm-probes/main.cpp" "$prefix/lib/tmpfile-android.o" \
    -L"$prefix/lib" -lc++_shared "$prefix/lib/libclang_rt.builtins-${builtins_arch}-android.a" \
    -L"$platform" -llog -ldl -lm -lc "$platform/crtend_android.o" -o "$output/cxx23-probe"
cp "$prefix/lib/libc++_shared.so" "$output/libc++_shared.so"
llvm-readobj-21 --file-header --dynamic-table "$output/cxx23-probe" > "$output/cxx23-probe-elf.txt"

atomic_flags=(-O2 -std=c++23 -fexperimental-library)
for side in a b; do
    library="liblongreach-atomic-$side.so"
    worker="longreach_atomic_worker_$side"
    provider="longreach_atomic_provider_$side"
    "$prefix/bin/cxx" "${atomic_flags[@]}" -shared -fvisibility=hidden \
        "-Wl,-soname,$library" "-DLONGREACH_ATOMIC_WORKER=$worker" "-DLONGREACH_ATOMIC_PROVIDER=$provider" \
        "$repo/scripts/tests/qt6-llvm-probes/android-atomic-worker.cpp" -o "$output/$library"
    check_android_atomic_client_imports "$output/$library" "$output/$library-symbols.txt" "$worker" "$provider"
    llvm-readobj-21 --file-header --dynamic-table "$output/$library" > "$output/$library-elf.txt"
done
"$prefix/bin/cxx" "${atomic_flags[@]}" \
    "$repo/scripts/tests/qt6-llvm-probes/android-atomic.cpp" "-L$output" \
    -llongreach-atomic-a -llongreach-atomic-b -o "$output/atomic-probe"
check_android_atomic_client_imports "$output/atomic-probe" "$output/atomic-probe-symbols.txt"
llvm-readobj-21 --file-header --dynamic-table "$output/atomic-probe" > "$output/atomic-probe-elf.txt"
