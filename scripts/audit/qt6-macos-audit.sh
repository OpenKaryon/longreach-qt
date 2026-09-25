#!/bin/sh
# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2026 OpenKaryon
# Inspect a cross-built macOS smoke set. A deployment header is not a runtime test.
set -eu

expected_min=$1
shift
tool_arch=${MACHO_AUDIT_ARCH:-x86_64}
otool_bin=$(find /opt/osxcross/target/bin -maxdepth 1 -name "${tool_arch}-apple-darwin*-otool" | sort | tail -1)
nm_bin=$(find /opt/osxcross/target/bin -maxdepth 1 -name "${tool_arch}-apple-darwin*-nm" | sort | tail -1)
test -n "$otool_bin" && test -n "$nm_bin"

count=0
for bin in "$@"; do
    case "$bin" in *.json) continue ;; esac
    test -f "$bin" || continue
    count=$((count + 1))
    min=$("$otool_bin" -l "$bin" | awk '
        /cmd LC_VERSION_MIN_MACOSX/ || /cmd LC_BUILD_VERSION/ { found = 1; next }
        found && /^[[:space:]]*(version|minos)[[:space:]]/ { print $2; exit }
    ')
    if [ "$min" != "$expected_min" ]; then
        echo "FAIL: $(basename "$bin"): minimum ${min:-missing}, expected $expected_min" >&2
        exit 1
    fi
    # The aligned operator new/delete are in the system libc++abi from macOS
    # 10.14 on; only an older target needs the shim that avoids importing them.
    if [ "$(printf '%s\n' 10.14 "$expected_min" | sort -V | head -1)" != 10.14 ]; then
        if "$nm_bin" -u "$bin" | grep -q 'St11align_val_t'; then
            echo "FAIL: $(basename "$bin"): unresolved aligned allocation below 10.14" >&2
            exit 1
        fi
        echo "PASS: $(basename "$bin"): macOS $min, no unresolved aligned allocation"
    else
        echo "PASS: $(basename "$bin"): macOS $min (aligned allocation is in the system from 10.14)"
    fi
done

test "$count" -gt 0 || { echo 'no Mach-O executables found' >&2; exit 2; }
echo "audited $count Mach-O executables"
