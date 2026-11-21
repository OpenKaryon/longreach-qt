#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-or-later
# A Qt-independent APK client of the selected API10 upstream LLVM runtime.
set -euo pipefail
repo=${REPO_ROOT:-/repo}
source "$repo/scripts/build/qt5-android/target-config.sh"
[[ "$api" == 10 ]] || { echo 'The legacy runtime probe requires API10' >&2; exit 1; }
prefix=/opt/longreach-android
expected_abi=$abi
expected_target=$target
source "$prefix/target.sh"
[[ "$abi" == "$expected_abi" && "$target" == "$expected_target" ]] || {
    echo 'The installed runtime does not match the requested API10 target' >&2
    exit 1
}
output=${PROBE_OUTPUT_DIR:-/out/probe}
mkdir -p "$output"
"$prefix/bin/cxx" -O2 -std=c++23 -fexperimental-library \
    -I"$repo/scripts/tests/qt6-llvm-probes" \
    -Wl,--exclude-libs,ALL,-soname,libdonut_probe.so \
    "$repo/tests/android-donut/strict-jni.cpp" -o "$output/strict.so"
cp "$prefix/lib/libc++_shared.so" "$output/"
"$prefix/bin/cxx" --version > "$output/compiler-version.txt"
sha256sum "$output/strict.so" "$output/libc++_shared.so" > "$output/native-sha256.txt"
llvm-readobj-21 --file-header --program-headers --dynamic-table \
    "$output/strict.so" "$output/libc++_shared.so" > "$output/native-elf.txt"
echo "Built the shared canonical25 JNI probe for $abi/API$api; no Qt dependency"
