#!/bin/sh
# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2026 OpenKaryon
#
# Check Mach-O executables against the libraries of an older macOS SDK.
#
#   macos-symbol-audit.sh <old-sdk-or-system-root> <binary>...
#
# The deployment target only says where dyld loads a binary. This lists each
# binary's strong imports that no dylib or framework of the older SDK exports,
# and strong LC_LOAD_DYLIB paths the older SDK lacks; either stops the binary
# at load time there. Weak imports belong to availability guards and are only
# counted. The match is by name across the SDK: a screen, not a runtime test.
set -eu

sdk=$1
shift
tool_arch=${MACHO_AUDIT_ARCH:-x86_64}
nm_bin=$(find /opt/osxcross/target/bin /usr/local/osxcross/bin -maxdepth 1 -name "${tool_arch}-apple-darwin*-nm" 2>/dev/null | sort | tail -1)
otool_bin=$(find /opt/osxcross/target/bin /usr/local/osxcross/bin -maxdepth 1 -name "${tool_arch}-apple-darwin*-otool" 2>/dev/null | sort | tail -1)
test -n "$nm_bin" && test -n "$otool_bin" || { echo 'no osxcross nm/otool found' >&2; exit 2; }
test -d "$sdk/usr/lib" || { echo "not an SDK: $sdk" >&2; exit 2; }

exports=$(mktemp)
trap 'rm -f "$exports" "$exports.imp"' EXIT
{
    # Every dylib, including those inside frameworks (OpenGL keeps glGetString
    # in OpenGL.framework/Versions/A/Libraries/libGL.dylib).
    find "$sdk/usr/lib" "$sdk/System/Library/Frameworks" -type f -name '*.dylib'
    # Framework binaries: Foo.framework/Versions/X/Foo, including frameworks
    # nested in umbrella frameworks.
    find "$sdk/System/Library/Frameworks" -type f -path '*.framework/Versions/*' |
        awk -F/ '{ name = $NF; fw = $(NF - 3); if (fw == name ".framework") print }'
} | while IFS= read -r lib; do
    "$nm_bin" -gU "$lib" 2>/dev/null | awk 'NF { print $NF }'
done | sort -u > "$exports"
echo "$(wc -l < "$exports") symbols exported by $(basename "$sdk")"

count=0
failed=0
for bin in "$@"; do
    case "$bin" in *.json|*.txt|*.log) continue ;; esac
    test -f "$bin" || continue
    "$nm_bin" -m "$bin" >/dev/null 2>&1 || continue
    count=$((count + 1))
    # Every strong LC_LOAD_DYLIB must exist on the old system: dyld refuses
    # to start the binary otherwise, whatever the symbols. Weak loads may be
    # missing, and @-relative paths belong to the application.
    missing_libs=$("$otool_bin" -l "$bin" | awk '
        /cmd LC_LOAD_DYLIB$/ { strong = 1; next }
        /cmd / { strong = 0 }
        strong && /^ *name / { print $2; strong = 0 }' |
        while IFS= read -r lib; do
            case "$lib" in @*) continue ;; esac
            test -e "$sdk$lib" || echo "$lib"
        done)
    if [ -n "$missing_libs" ]; then
        failed=$((failed + 1))
        echo "FAIL: $(basename "$bin"): loads libraries missing from $(basename "$sdk")"
        printf '%s\n' "$missing_libs" | sed 's/^/    /'
        continue
    fi
    weak=$("$nm_bin" -m "$bin" | grep -c '(undefined) weak external' || true)
    "$nm_bin" -m "$bin" | awk '
        /\(undefined\)/ && !/weak external/ {
            for (i = 1; i <= NF; i++) if ($i == "external") { print $(i + 1); break }
        }' | sort -u > "$exports.imp"
    missing=$(comm -23 "$exports.imp" "$exports")
    if [ -n "$missing" ]; then
        failed=$((failed + 1))
        echo "FAIL: $(basename "$bin"): $(printf '%s\n' "$missing" | wc -l) imports missing, $weak weak"
        printf '%s\n' "$missing" | sed 's/^/    /'
    else
        echo "PASS: $(basename "$bin"): all $(wc -l < "$exports.imp") strong imports present, $weak weak"
    fi
done

test "$count" -gt 0 || { echo 'no Mach-O executables found' >&2; exit 2; }
echo "audited $count Mach-O executables, $failed with missing imports"
test "$failed" -eq 0
