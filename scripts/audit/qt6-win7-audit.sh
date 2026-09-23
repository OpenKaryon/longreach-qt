#!/bin/sh
# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2026 OpenKaryon
# Screen PE headers and imports for known Windows 8+ loader dependencies. This does not
# replace a Windows 7 SP1 runtime test or a review of every imported function.
set -eu

objdump_bin=$(command -v x86_64-w64-mingw32-objdump || command -v llvm-objdump)
fail=0
count=0
for bin in "$@"; do
    [ -f "$bin" ] || continue
    count=$((count + 1))
    imports=$("$objdump_bin" -p "$bin")
    major=$(printf '%s\n' "$imports" | awk '$1 == "MajorSubsystemVersion" { print $2; exit }')
    minor=$(printf '%s\n' "$imports" | awk '$1 == "MinorSubsystemVersion" { print $2; exit }')
    if [ -z "$major" ] || [ -z "$minor" ]; then
        echo "FAIL: $(basename "$bin"): missing PE subsystem version" >&2
        fail=1
        continue
    fi
    if [ "$major" -gt 6 ] || { [ "$major" -eq 6 ] && [ "$minor" -gt 1 ]; }; then
        echo "FAIL: $(basename "$bin"): PE subsystem $major.$minor exceeds Windows 7 (6.1)" >&2
        fail=1
        continue
    fi
    dlls=$(printf '%s\n' "$imports" | sed -n 's/^[[:space:]]*DLL Name: //p')
    bad_dlls=$(printf '%s\n' "$dlls" | grep -Ei \
        '^(api-ms-win-|SHCORE\.dll$|runtimeobject\.dll$|d3d12\.dll$|ucrtbase\.dll$|Qt6.*\.dll$|libstdc\+\+|libgcc)' || true)
    bad_apis=$(printf '%s\n' "$imports" | grep -Ei \
        '[[:space:]](WaitOnAddress|WakeByAddress(All|Single)|GetDpiForMonitor|GetDpiForWindow|GetDpiForSystem|SetThreadDescription|CreateDXGIFactory2|D3D12[A-Za-z0-9_]*|RoGetActivationFactory|WindowsCreateStringReference|SetProcessDpiAwareness|GetProcessDpiAwareness)$' || true)
    if [ -n "$bad_dlls" ] || [ -n "$bad_apis" ]; then
        echo "FAIL: $(basename "$bin")"
        [ -z "$bad_dlls" ] || printf '  DLL: %s\n' "$bad_dlls"
        [ -z "$bad_apis" ] || printf '  API: %s\n' "$bad_apis"
        fail=1
    else
        echo "PASS: $(basename "$bin") (PE subsystem $major.$minor)"
    fi
done

[ "$count" -gt 0 ] || { echo 'no PE executables found' >&2; exit 2; }
echo "audited $count PE executables"
exit "$fail"
