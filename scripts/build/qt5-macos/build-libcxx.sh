#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2026 OpenKaryon
#
# A static C++ runtime for the OS X 10.6 target.
#
#   build-libcxx.sh <llvm-project source tarball>
#
# 10.6 has no libc++, and its libstdc++ (GCC 4.2) cannot hold Qt 5.15's C++14.
# libc++ and libc++abi 14.0.6 are built for x86_64-apple-macosx10.6 and
# installed into the osxcross SDK: the headers replace usr/include/c++/v1, and
# libc++.a (with libc++abi merged in) replaces the libc++ stubs, so the driver's
# -lc++ links it. The result needs only libSystem; __config_site gets
# _LIBCPP_DISABLE_AVAILABILITY, as the library travels with the binary.
set -eu
tarball=${1:?llvm-project source tarball}
prefix=$(cat /opt/osxcross-prefix)
sdk=$(ls -d /usr/local/osxcross/SDK/MacOSX*.sdk | sort | tail -1)
bin=/usr/local/osxcross/bin
src=/tmp/llvm-src
build=/tmp/libcxx-build
install=/opt/libcxx-10.6
jobs=${PARALLEL_JOBS:-$(nproc)}

rm -rf "$src" "$build" "$install"
mkdir -p "$src"
top=$(tar -tJf "$tarball" | head -1 | cut -d/ -f1)
tar -xJf "$tarball" -C "$src" --strip-components=1 \
    "$top/libcxx" "$top/libcxxabi" "$top/libunwind/include" "$top/runtimes" \
    "$top/cmake" "$top/llvm/cmake" "$top/llvm/utils/llvm-lit"

cmake -G "Unix Makefiles" -S "$src/runtimes" -B "$build" \
    -DLLVM_ENABLE_RUNTIMES="libcxx;libcxxabi" \
    -DCMAKE_SYSTEM_NAME=Darwin \
    -DCMAKE_C_COMPILER=clang -DCMAKE_CXX_COMPILER=clang++ \
    -DCMAKE_C_COMPILER_TARGET=x86_64-apple-macosx10.6 \
    -DCMAKE_CXX_COMPILER_TARGET=x86_64-apple-macosx10.6 \
    -DCMAKE_OSX_SYSROOT="$sdk" -DCMAKE_OSX_ARCHITECTURES=x86_64 \
    -DCMAKE_OSX_DEPLOYMENT_TARGET=10.6 \
    -DCMAKE_AR="$bin/${prefix}ar" -DCMAKE_RANLIB="$bin/${prefix}ranlib" \
    -DCMAKE_TRY_COMPILE_TARGET_TYPE=STATIC_LIBRARY \
    -DCMAKE_BUILD_TYPE=MinSizeRel \
    -DCMAKE_INSTALL_PREFIX="$install" \
    -DLIBCXX_ENABLE_SHARED=OFF -DLIBCXXABI_ENABLE_SHARED=OFF \
    -DLIBCXX_ENABLE_STATIC=ON -DLIBCXXABI_ENABLE_STATIC=ON \
    -DLIBCXXABI_USE_LLVM_UNWINDER=OFF \
    -DLIBCXX_INCLUDE_TESTS=OFF -DLIBCXXABI_INCLUDE_TESTS=OFF \
    -DLIBCXX_INCLUDE_BENCHMARKS=OFF -DLIBCXX_INCLUDE_DOCS=OFF \
    -DLIBCXX_ENABLE_ASSERTIONS=OFF
make -C "$build" -j "$jobs" install-cxx install-cxxabi

merge=/tmp/libcxx-merge
rm -rf "$merge" && mkdir -p "$merge/cxx" "$merge/cxxabi"
(cd "$merge/cxx" && "$bin/${prefix}ar" x "$install/lib/libc++.a")
(cd "$merge/cxxabi" && "$bin/${prefix}ar" x "$install/lib/libc++abi.a")
for f in "$merge"/cxxabi/*.o; do mv "$f" "$merge/cxx/abi_$(basename "$f")"; done
rm -f "$install/lib/libc++.a"
"$bin/${prefix}ar" rcs "$install/lib/libc++.a" "$merge"/cxx/*.o

rm -rf "$sdk/usr/include/c++/v1"
cp -a "$install/include/c++/v1" "$sdk/usr/include/c++/v1"
sed -i 's|^#endif // _LIBCPP_CONFIG_SITE|#define _LIBCPP_DISABLE_AVAILABILITY\n#endif // _LIBCPP_CONFIG_SITE|' \
    "$sdk/usr/include/c++/v1/__config_site"
grep -q '^#define _LIBCPP_DISABLE_AVAILABILITY' "$sdk/usr/include/c++/v1/__config_site"
rm -f "$sdk"/usr/lib/libc++.tbd "$sdk"/usr/lib/libc++.1.tbd "$sdk"/usr/lib/libc++abi.tbd
cp "$install/lib/libc++.a" "$sdk/usr/lib/libc++.a"
rm -rf "$src" "$build" "$merge"

# Self-check: a program using threads, exceptions and iostreams links, and
# needs nothing but libSystem on the target.
cat > /tmp/libcxx-probe.cpp <<'CPP'
#include <iostream>
#include <map>
#include <mutex>
#include <string>
#include <thread>
#include <stdexcept>
int main()
{
    std::map<std::string, int> m{{"a", 1}};
    std::mutex mu;
    std::thread t([&] { std::lock_guard<std::mutex> l(mu); m["b"] = 2; });
    t.join();
    try { throw std::runtime_error("x"); }
    catch (const std::exception &e) { std::cout << e.what() << m.size() << std::endl; }
    return 0;
}
CPP
"$bin/${prefix}clang++" -std=c++14 /tmp/libcxx-probe.cpp -o /tmp/libcxx-probe
"$bin/${prefix}otool" -L /tmp/libcxx-probe
if "$bin/${prefix}otool" -L /tmp/libcxx-probe | grep -q 'libc++'; then
    echo 'libc++ is still linked dynamically' >&2
    exit 1
fi
rm -f /tmp/libcxx-probe /tmp/libcxx-probe.cpp
echo "static libc++ installed into $sdk"
