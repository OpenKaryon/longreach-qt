#!/bin/sh
# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2026 OpenKaryon
# Build the C, C++ and Objective-C probes for Mac OS X 10.2 and fail unless
# every one of them links against the 10.2.8 SDK alone and carries only load
# commands that the 10.2 dynamic loader knows. Output lands in /out.
set -eu
SDK=/opt/jaguar/MacOSX10.2.8.sdk
CC=powerpc-apple-darwin8-gcc
CXX=powerpc-apple-darwin8-g++
OTOOL=powerpc-apple-darwin8-otool
FLAGS="-isysroot $SDK -F$SDK/System/Library/Frameworks -mmacosx-version-min=10.2 -Os"
mkdir -p /out
cd /probes

build() {
    out=$1; shift
    "$@" -o "/out/$out" -Wl,-t > "/out/$out.link.log" 2>&1 || { cat "/out/$out.link.log"; exit 1; }
    # A library picked up from any other SDK means the undefined symbols were
    # checked against the wrong system.
    if grep -v "^$SDK" "/out/$out.link.log" | grep -qE '\.dylib|\.framework/'; then
        echo "$out: linked a library from outside the 10.2.8 SDK:"; grep -v "^$SDK" "/out/$out.link.log"; exit 1
    fi
    # LC_MAIN, LC_DYLD_INFO and similar arrived with 10.5 and later.
    unknown=$($OTOOL -l "/out/$out" | awk '$1 == "cmd" {print $2}' \
        | grep -vxE 'LC_SEGMENT|LC_SYMTAB|LC_DYSYMTAB|LC_LOAD_DYLINKER|LC_LOAD_DYLIB|LC_UNIXTHREAD|LC_TWOLEVEL_HINTS' || true)
    if [ -n "$unknown" ]; then echo "$out: load commands unknown to 10.2: $unknown"; exit 1; fi
    echo "== $out"; file "/out/$out"; $OTOOL -L "/out/$out" | tail -n +2
}

build c-probe    $CC  $FLAGS c-probe.c
build cxx-probe  $CXX $FLAGS cxx-probe.cpp
build objc-probe $CC  $FLAGS objc-probe.m -framework Foundation -lobjc

# objc-probe defines no class. Jaguar's libobjc crashes in _objcInit on a
# module whose symtab pointer (the fourth word of each 16-byte module_info
# entry) is NULL, so every entry must point at a symtab.
$OTOOL -s __OBJC __module_info /out/objc-probe | awk '
    NR > 1 { symtab = ""; for (i = 5; i <= NF; i++) symtab = symtab $i
             modules++; if (symtab ~ /^0+$/) nulls++ }
    END { if (!modules || nulls) { print "objc-probe: " nulls + 0 " of " modules + 0 " modules lack a symtab"; exit 1 }
          print "objc-probe: all " modules " modules carry a symtab" }'
