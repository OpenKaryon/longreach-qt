#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2026 OpenKaryon
#
# i386-apple-darwin10-clang / -clang++: the compiler driver of the i386 target
# (installed by build-i386-toolchain.sh, which fills in the @...@ paths).
#
# osxcross has no i386 for SDKs newer than 10.13, and the 11.3 SDK's stubs
# have no i386 slices. So this runs the host clang directly: it compiles
# against the 11.3 SDK headers (@SDK@) like the x86_64 target, and links
# against the i386 libraries of the 10.7 SDK (@LINKSDK@), which also holds the
# static libc++, the startup object and libqt-i386-rt.a. A link line gets the
# link SDK as its -isysroot; a compile line keeps the 11.3 SDK. A line that
# does both ("cc a.c -o a") is split: each source is compiled first.
# libc++ always: below 10.9 clang would default to the system libstdc++.
case "$(basename "$0")" in
    *clang++) driver=clang++; cxx=(-nostdinc++ -isystem @SDK@/usr/include/c++/v1); cxxlink=(-stdlib=libc++) ;;
    *) driver=clang; cxx=(); cxxlink=() ;;
esac
# No automatic property synthesis on the 32-bit runtime: a property without
# @synthesize would have no accessors at all, which is only a warning.
common=(-target i386-apple-macosx10.6 --ld-path=@LD@ -mlinker-version=711 -DNS_BUILD_32_LIKE_64=1
        -Werror=objc-property-implementation)
# In the 10.7 SDK, ImageIO, CoreText, CoreGraphics and others are still
# sub-frameworks (of ApplicationServices, CoreServices, IOBluetooth) and link
# only through their umbrella; umbrella() maps the 11.3 names to it.
umbrella() {
    case "$1" in
        ATS|ColorSync|CoreGraphics|CoreText|HIServices|ImageIO|LangAnalysis|PrintCore|QD|SpeechSynthesis)
            echo ApplicationServices ;;
        AE|CFNetwork|CarbonCore|DictionaryServices|LaunchServices|Metadata|OSServices|SearchKit)
            echo CoreServices ;;
        CoreBluetooth) echo IOBluetooth ;;
        *) echo "$1" ;;
    esac
}
# Frameworks with no 32-bit slice: dropped from the link, their code runs only
# behind @available on newer systems. Frameworks newer than 10.6: linked weak,
# as 32-bit Objective-C class references are never weak on their own.
weak_on_106() {
    case "$1" in
        AVFoundation|CoreMedia|StoreKit|GSS) return 0 ;;
    esac
    return 1
}
no_i386() {
    case "$1" in
        Metal|MetalKit|GameController) return 0 ;;
    esac
    return 1
}
# Weak symbols newer than the 10.7 SDK's i386 stubs (see dynamic-lookup.txt).
lookup=()
while read -r sym; do
    case "$sym" in ''|'#'*) ;; *) lookup+=("-Wl,-U,$sym") ;; esac
done < @LOOKUP@

link=1
for a in "$@"; do
    case "$a" in
        -c|-E|-S|-M|-MM|-fsyntax-only) link= ;;
    esac
done

# Drop every -isysroot (and its value); the right one is added below.
args=()
skip=
for a in "$@"; do
    if [ -n "$skip" ]; then skip=; continue; fi
    case "$a" in
        -isysroot) skip=1 ;;
        *) args+=("$a") ;;
    esac
done

if [ -z "$link" ]; then
    exec "$driver" "${common[@]}" "${cxx[@]}" -isysroot @SDK@ -include @SHIM@ "${args[@]}"
fi

# Link, compiling any sources on the line first; each object takes its
# source's place, so the order against libraries is kept.
is_source() {
    case "$1" in
        *.c|*.cc|*.cpp|*.cxx|*.c++|*.C|*.m|*.mm|*.s|*.S) return 0 ;;
    esac
    return 1
}
flags=()
skip=
for a in "${args[@]}"; do
    if [ "$skip" = drop ]; then skip=; continue; fi
    if [ -n "$skip" ]; then flags+=("$a"); skip=; continue; fi
    case "$a" in
        -o) skip=drop ;;
        -x|-arch|-framework|-weak_framework|-Xlinker|-include|-I|-L|-F) flags+=("$a"); skip=1 ;;
        -*) flags+=("$a") ;;
        *) is_source "$a" || flags+=("$a") ;;
    esac
done
linkargs=()
tmp=
n=0
skip=
for a in "${args[@]}"; do
    if [ -n "$skip" ] && [ "${skip#framework}" != "$skip" ]; then
        if ! no_i386 "$a"; then
            if weak_on_106 "$a"; then linkargs+=(-weak_framework "$a")
            else linkargs+=("${skip#framework:}" "$(umbrella "$a")"); fi
        fi
        skip=
        continue
    fi
    if [ -n "$skip" ]; then linkargs+=("$a"); skip=; continue; fi
    case "$a" in
        -framework|-weak_framework) skip="framework:$a"; continue ;;
        -Wl,-framework,*|-Wl,-weak_framework,*)
            if ! no_i386 "${a##*,}"; then
                if weak_on_106 "${a##*,}"; then linkargs+=(-weak_framework "${a##*,}")
                else linkargs+=("${a%,*},$(umbrella "${a##*,}")"); fi
            fi
            continue ;;
    esac
    case "$a" in
        -o|-x|-arch|-framework|-weak_framework|-Xlinker|-include|-I|-L|-F) linkargs+=("$a"); skip=1; continue ;;
    esac
    # CMake resolves the -lcups or -framework X of a Qt .prl file to a path in
    # the 11.3 SDK, whose stubs have no i386: name the library instead, so the
    # linker finds it in the link SDK.
    case "$a" in
        /*.sdk/usr/lib/lib*.tbd|/*.sdk/usr/lib/lib*.dylib)
            l=${a##*/lib}; linkargs+=("-l${l%%.*}"); continue ;;
        /*.sdk/System/Library/Frameworks/*.framework|/*.sdk/System/Library/Frameworks/*.framework/*)
            f=${a#*.sdk/System/Library/Frameworks/}; f=${f%%.framework*}
            if ! no_i386 "$f"; then
                if weak_on_106 "$f"; then linkargs+=(-weak_framework "$f")
                else linkargs+=(-framework "$(umbrella "$f")"); fi
            fi
            continue ;;
    esac
    if [ "${a#-}" = "$a" ] && is_source "$a"; then
        if [ -z "$tmp" ]; then tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT; fi
        n=$((n + 1))
        "$driver" "${common[@]}" "${cxx[@]}" -isysroot @SDK@ -include @SHIM@ "${flags[@]}"             -Wno-unused-command-line-argument -c "$a" -o "$tmp/$n.o" || exit $?
        linkargs+=("$tmp/$n.o")
    else
        linkargs+=("$a")
    fi
done
# libobjc first: otherwise, with -no_implicit_dylibs, the runtime's symbols
# bind to whichever linked framework brought it in (IOBluetooth, through
# CoreBluetooth), and macOS 10.13 resolves objc_msgSend there in vain.
"$driver" "${common[@]}" "${cxxlink[@]}" -isysroot @LINKSDK@ -lobjc "${linkargs[@]}" "${lookup[@]}" -lqt-i386-rt
