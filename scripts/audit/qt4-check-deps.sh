#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2026 OpenKaryon
#
# Fail the build if a Qt 4 binary is not self-contained: no Qt library and no
# C++ runtime (libstdc++/libgcc_s, or their DLLs) among its dependencies, and on
# Windows neither libwinpthread nor the UCRT (api-ms-win-crt-* would mean
# Windows 10 and later). System libraries are expected and not checked.
set -eu

bin=${1:?usage: qt4-check-deps.sh <binary>}
test -f "$bin" || { echo "no such binary: $bin" >&2; exit 2; }

fail=0
note() { printf '  %s\n' "$*"; }

case "$bin" in
    *.exe)
        echo "checking Windows dependencies of $(basename "$bin")"
        # The cross image's objdump, whichever MinGW triple it carries.
        objdump_bin=$(command -v i686-w64-mingw32-objdump \
                   || command -v x86_64-w64-mingw32-objdump \
                   || command -v objdump) \
            || { echo "no objdump in this image - cannot check dependencies" >&2; exit 2; }
        deps=$("$objdump_bin" -p "$bin" | sed -n 's/^\s*DLL Name: //p' | sort -f)
        echo "$deps" | sed 's/^/  /'

        for bad in libgcc_s libstdc++ libwinpthread; do
            if echo "$deps" | grep -qi "$bad"; then
                note "FAIL: imports $bad - the static runtime flags are not reaching the link"
                fail=1
            fi
        done
        if echo "$deps" | grep -qiE "^\s*Qt[A-Za-z0-9]+4?\.dll"; then
            note "FAIL: imports a Qt DLL - Qt is not statically linked"
            fail=1
        fi
        if echo "$deps" | grep -qi "api-ms-win-crt"; then
            note "FAIL: imports the UCRT - that is in-box only from Windows 10"
            fail=1
        fi
        ;;
    *)
        echo "checking ELF dependencies of $(basename "$bin")"
        deps=$(objdump -p "$bin" | sed -n 's/^\s*NEEDED\s*//p' | sort)
        echo "$deps" | sed 's/^/  /'

        for bad in libstdc++ libgcc_s; do
            if echo "$deps" | grep -q "$bad"; then
                note "FAIL: needs $bad - the static C++ runtime flags are not reaching the link"
                fail=1
            fi
        done
        if echo "$deps" | grep -qE "^libQt"; then
            note "FAIL: needs a Qt shared library - Qt is not statically linked"
            fail=1
        fi
        ;;
esac

if [ "$fail" -ne 0 ]; then
    echo "dependency check failed" >&2
    exit 1
fi
echo "  ok: no Qt libraries and no C++ runtime among the dependencies"
