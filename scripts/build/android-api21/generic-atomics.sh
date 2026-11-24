#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-or-later
# One generic provider in libc++_shared; compiler-rt builtins exclude atomic.c.
build_android_generic_atomics() {
    local source=$1 object=$2
    clang-21 "${arch[@]}" -O2 -D_LIBATOMIC_USE_PTHREAD -fvisibility=default \
        -c "$source" -o "$object"
    atomic_objects=("$object")
}

check_android_atomic_builtins() {
    local archive=$1 report=$2
    llvm-nm-21 --defined-only "$archive" > "$report"
    if ! awk '$NF ~ /^__atomic_/ { print; found=1 } END { exit found }' "$report"; then
        echo 'Generic atomics must not be copied into the static builtins archive' >&2
        return 1
    fi
}

check_android_generic_atomic_exports() {
    local runtime=$1 report=$2 symbol count
    llvm-nm-21 --dynamic --defined-only "$runtime" > "$report"
    for symbol in __atomic_load __atomic_store __atomic_exchange __atomic_compare_exchange __atomic_is_lock_free; do
        count=$(awk -v wanted="$symbol" '$2 ~ /^[TW]$/ && $3 == wanted { n++ } END { print n+0 }' "$report")
        if [[ "$count" != 1 ]]; then
            echo "Expected one exported generic atomic function: $symbol (found $count)" >&2
            return 1
        fi
    done
}


# Consumer DSOs/executable must import the same generic API, not embed a pool.
check_android_atomic_client_imports() {
    local client=$1 report=$2 symbol count
    shift 2
    llvm-nm-21 --dynamic "$client" > "$report"
    if ! awk '$NF ~ /^__atomic_/ && $(NF-1) !~ /^[Uw]$/ { print; found=1 } END { exit found }' "$report"; then
        echo 'Atomic consumer embeds a generic provider' >&2
        return 1
    fi
    for symbol in __atomic_load __atomic_store __atomic_exchange __atomic_compare_exchange __atomic_is_lock_free; do
        count=$(awk -v wanted="$symbol" '$(NF-1) == "U" && $NF == wanted { n++ } END { print n+0 }' "$report")
        if [[ "$count" != 1 ]]; then
            echo "Atomic consumer must import $symbol once (found $count)" >&2
            return 1
        fi
    done
    for symbol in "$@"; do
        count=$(awk -v wanted="$symbol" '$2 ~ /^[TW]$/ && $3 == wanted { n++ } END { print n+0 }' "$report")
        if [[ "$count" != 1 ]]; then
            echo "Atomic consumer lacks one worker function export: $symbol" >&2
            return 1
        fi
    done
}
