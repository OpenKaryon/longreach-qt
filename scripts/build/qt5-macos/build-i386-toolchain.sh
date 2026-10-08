#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2026 OpenKaryon
#
# The i386 toolchain of the Qt 5 Mac OS X 10.6 target, on top of the x86_64
# one (osxcross, the 11.3 SDK, the static libc++):
#
#   build-i386-toolchain.sh <llvm-project source tarball> <MacOSX10.7.sdk tarball>
#
# osxcross has no i386 for SDKs newer than 10.13. So i386 compiles against a
# copy of the 11.3 SDK headers in which the system classes get their 32-bit
# instance layouts back (i386/fragile-ivars.py), and links against the i386
# libraries of the 10.7 SDK, which also receives:
#
#   - libc++.a: libc++ and libc++abi 14.0.6 for i386-apple-macosx10.6, without
#     std::filesystem (no openat() in 10.7);
#   - crt1.10.6.o, the i386 startup object;
#   - libqt-i386-rt.a: __isOSVersionAtLeast for @available, and the __atomic_*
#     functions clang calls for 8-byte atomics on i386 (Darwin has no
#     libatomic).
#
# The drivers are i386-apple-darwin10-clang and -clang++ (clang-wrapper.sh),
# with osxcross' cctools under the same prefix.
set -eu
llvm=${1:?llvm-project source tarball}
sdktar=${2:?MacOSX10.7.sdk tarball}
here=$(cd "$(dirname "$0")" && pwd)
osx=/usr/local/osxcross
bin=$osx/bin
xprefix=$(cat /opt/osxcross-prefix)
sdk=$(ls -d $osx/SDK/MacOSX1[1-9]*.sdk | sort | tail -1)
link=$osx/SDK/MacOSX10.7-i386.sdk
csdk=$osx/SDK-i386/$(basename "$sdk")
prefix=i386-apple-darwin10-
target=i386-apple-macosx10.6
jobs=${PARALLEL_JOBS:-$(nproc)}

rm -rf "$link" && mkdir -p "$link"
tar -xJf "$sdktar" -C "$link" --strip-components=1
test -f "$link/usr/lib/libSystem.B.dylib"
# Binutils: osxcross' cctools under the i386 prefix.
for t in ar ranlib nm otool lipo strip libtool install_name_tool ld; do
    ln -sf "$bin/${xprefix}$t" "$bin/${prefix}$t"
done
for d in clang clang++; do
    sed -e "s|@SDK@|$csdk|g" -e "s|@LINKSDK@|$link|g" -e "s|@LD@|$bin/${xprefix}ld|g" \
        -e "s|@SHIM@|$osx/include/qt-i386-sdk-shim.h|g" -e "s|@LOOKUP@|$osx/include/qt-i386-dynamic-lookup.txt|g" \
        "$here/i386/clang-wrapper.sh" > "$bin/${prefix}$d"
    chmod +x "$bin/${prefix}$d"
done
mkdir -p "$osx/include"
cp "$here/i386/sdk-shim.h" "$osx/include/qt-i386-sdk-shim.h"
cp "$here/i386/dynamic-lookup.txt" "$osx/include/qt-i386-dynamic-lookup.txt"

# The compile SDK (fragile-ivars.py uses the i386 nm above).
rm -rf "$osx/SDK-i386" && mkdir -p "$osx/SDK-i386"
cp -a "$sdk" "$csdk"
python3 "$here/i386/fragile-ivars.py" "$link" "$csdk" /tmp/fragile-ivars
# NSView's own variables take 72 of its 80 bytes (NSResponder has 8).
grep -q '_qt_i386_ivars_NSView\[72\]' "$csdk/System/Library/Frameworks/AppKit.framework/Headers/NSView.h"
rm -rf /tmp/fragile-ivars
# NSEventMask became 64-bit in the 10.12 SDK while the 32-bit AppKit takes an
# NSUInteger; passed as 64 bits it shifts every later argument. Masks above
# bit 31 are 64-bit only and become 0.
ev=$csdk/System/Library/Frameworks/AppKit.framework/Headers/NSEvent.h
sed -i -e 's/typedef NS_OPTIONS(unsigned long long, NSEventMask)/typedef NS_OPTIONS(NSUInteger, NSEventMask)/' \
    -e 's/= 1ULL << \(NSEventType[A-Za-z]*\),/= (NSUInteger)(1ULL << \1),/' "$ev"
grep -q 'NS_OPTIONS(NSUInteger, NSEventMask)' "$ev"

# libc++ / libc++abi.
src=/tmp/llvm-src-i386
build=/tmp/libcxx-build-i386
install=/tmp/libcxx-i386
rm -rf "$src" "$build" "$install" && mkdir -p "$src"
top=$(tar -tJf "$llvm" | head -1 | cut -d/ -f1)
tar -xJf "$llvm" -C "$src" --strip-components=1 \
    "$top/libcxx" "$top/libcxxabi" "$top/libunwind/include" "$top/runtimes" \
    "$top/cmake" "$top/llvm/cmake" "$top/llvm/utils/llvm-lit" \
    "$top/compiler-rt/lib/builtins/os_version_check.c" "$top/compiler-rt/lib/builtins/atomic.c"     "$top/compiler-rt/lib/builtins/assembly.h" "$top/compiler-rt/lib/builtins/int_lib.h"     "$top/compiler-rt/lib/builtins/int_types.h" "$top/compiler-rt/lib/builtins/int_endianness.h"     "$top/compiler-rt/lib/builtins/int_util.h" "$top/compiler-rt/lib/builtins/int_math.h"
cmake -G "Unix Makefiles" -S "$src/runtimes" -B "$build" \
    -DLLVM_ENABLE_RUNTIMES="libcxx;libcxxabi" \
    -DCMAKE_SYSTEM_NAME=Darwin \
    -DCMAKE_C_COMPILER=clang -DCMAKE_CXX_COMPILER=clang++ \
    -DCMAKE_C_COMPILER_TARGET=$target -DCMAKE_CXX_COMPILER_TARGET=$target \
    -DCMAKE_OSX_SYSROOT="$link" -DCMAKE_OSX_ARCHITECTURES=i386 \
    -DCMAKE_OSX_DEPLOYMENT_TARGET=10.6 \
    -DCMAKE_AR="$bin/${xprefix}ar" -DCMAKE_RANLIB="$bin/${xprefix}ranlib" \
    -DCMAKE_TRY_COMPILE_TARGET_TYPE=STATIC_LIBRARY \
    -DCMAKE_BUILD_TYPE=MinSizeRel \
    -DCMAKE_INSTALL_PREFIX="$install" \
    -DLIBCXX_ENABLE_SHARED=OFF -DLIBCXXABI_ENABLE_SHARED=OFF \
    -DLIBCXX_ENABLE_STATIC=ON -DLIBCXXABI_ENABLE_STATIC=ON \
    -DLIBCXXABI_USE_LLVM_UNWINDER=OFF -DLIBCXX_ENABLE_FILESYSTEM=OFF \
    -DLIBCXX_INCLUDE_TESTS=OFF -DLIBCXXABI_INCLUDE_TESTS=OFF \
    -DLIBCXX_INCLUDE_BENCHMARKS=OFF -DLIBCXX_INCLUDE_DOCS=OFF \
    -DLIBCXX_ENABLE_ASSERTIONS=OFF
make -C "$build" -j "$jobs" install-cxx install-cxxabi
# Same headers as the x86_64 build installed into the 11.3 SDK: one libc++.
diff -r -x __config_site "$install/include/c++/v1" "$sdk/usr/include/c++/v1" >/dev/null
merge=/tmp/libcxx-merge-i386
rm -rf "$merge" && mkdir -p "$merge/cxx" "$merge/cxxabi"
(cd "$merge/cxx" && "$bin/${xprefix}ar" x "$install/lib/libc++.a")
(cd "$merge/cxxabi" && "$bin/${xprefix}ar" x "$install/lib/libc++abi.a")
for f in "$merge"/cxxabi/*.o; do mv "$f" "$merge/cxx/abi_$(basename "$f")"; done
rm -f "$link"/usr/lib/libc++*.dylib "$link"/usr/lib/libc++abi*.dylib
"$bin/${xprefix}ar" rcs "$link/usr/lib/libc++.a" "$merge"/cxx/*.o

# The @available helper and the startup object.
work=/tmp/i386-rt && rm -rf "$work" && mkdir -p "$work"
# The 10.7 SDK predates TARGET_OS_SIMULATOR.
clang -target $target -isysroot "$link" -Os -DTARGET_OS_SIMULATOR=0 -c "$src/compiler-rt/lib/builtins/os_version_check.c" -o "$work/os_version_check.o"
clang -target $target -isysroot "$link" -Os -fno-builtin -Wno-builtin-requires-header     -Wno-atomic-alignment -c "$src/compiler-rt/lib/builtins/atomic.c" -o "$work/atomic.o"
"$bin/${xprefix}ar" rcs "$link/usr/lib/libqt-i386-rt.a" "$work/os_version_check.o" "$work/atomic.o"
clang -target $target -c "$here/i386/crt1-start.s" -o "$work/start.o"
clang -target $target -isysroot "$link" -Os -c "$here/i386/crt1-start.c" -o "$work/crt.o"
"$bin/${xprefix}ld" -r -arch i386 "$work/start.o" "$work/crt.o" -o "$link/usr/lib/crt1.10.6.o"
cp "$link/usr/lib/crt1.10.6.o" "$link/usr/lib/crt1.10.5.o"
rm -rf "$src" "$build" "$install" "$merge" "$work"

# Self-check: threads, exceptions, iostreams and @available link and need
# nothing but libSystem, with a 10.6 load command.
cat > /tmp/i386-probe.cpp <<'CPP'
#include <atomic>
#include <iostream>
#include <map>
#include <mutex>
#include <stdexcept>
#include <string>
#include <thread>
int main()
{
    std::map<std::string, int> m{{"a", 1}};
    std::mutex mu;
    std::thread t([&] { std::lock_guard<std::mutex> l(mu); m["b"] = 2; });
    t.join();
    if (__builtin_available(macOS 10.7, *))
        m["c"] = 3;
    struct { char c; std::atomic<long long> v; } a{'x', {0}};
    a.v.fetch_add(5);
    try { throw std::runtime_error("x"); }
    catch (const std::exception &e) { std::cout << e.what() << m.size() << std::endl; }
    return 0;
}
CPP
"$bin/${prefix}clang++" -arch i386 -isysroot "$sdk" -mmacosx-version-min=10.6 -std=c++14 -stdlib=libc++ \
    /tmp/i386-probe.cpp -o /tmp/i386-probe
"$bin/${prefix}otool" -hL /tmp/i386-probe
"$bin/${prefix}otool" -l /tmp/i386-probe | grep -A2 LC_VERSION_MIN_MACOSX | grep -q 'version 10.6'
! "$bin/${prefix}otool" -L /tmp/i386-probe | grep -q 'libc++'
rm -f /tmp/i386-probe /tmp/i386-probe.cpp
echo "i386 toolchain ready: ${prefix}clang/clang++, link SDK $link"
