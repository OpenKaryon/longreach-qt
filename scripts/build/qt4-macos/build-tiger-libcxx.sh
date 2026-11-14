#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2026 OpenKaryon
set -euo pipefail

archive=${1:?LLVM source archive required}
patches=${2:?Patch directory required}
jobs=${PARALLEL_JOBS:-3}
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
src="$work/source"
sdk=/opt/tiger-toolchain/SDK/MacOSX10.4u.sdk
echo "4633a23617fa31a3ea51242586ea7fb1da7140e426bd62fc164261fe036aa142  $archive" | sha256sum -c -
mkdir "$src"
tar -xJf "$archive" -C "$src" --strip-components=1
(
    cd "$src"
    git apply "$patches/macos-snow-leopard/01-legacy-darwin-filesystem-and-clocks.patch" \
        "$patches/macos-snow-leopard/03-runtime-emulated-tls.patch" "$patches/macos-tiger/"*.patch
)
cmake -G 'Unix Makefiles' -S "$src/runtimes" -B "$work/build" \
    -DLLVM_ENABLE_RUNTIMES='libcxx;libcxxabi' \
    -DCMAKE_SYSTEM_NAME=Darwin -DCMAKE_SYSTEM_PROCESSOR=i386 \
    -DCMAKE_C_COMPILER=/opt/llvm-21/bin/clang -DCMAKE_CXX_COMPILER=/opt/llvm-21/bin/clang++ \
    -DCMAKE_C_COMPILER_TARGET=i386-apple-macosx10.4 -DCMAKE_CXX_COMPILER_TARGET=i386-apple-macosx10.4 \
    -DCMAKE_OSX_SYSROOT="$sdk" -DCMAKE_OSX_ARCHITECTURES=i386 -DCMAKE_OSX_DEPLOYMENT_TARGET=10.4 \
    -DCMAKE_CXX_FLAGS='-femulated-tls -fno-blocks' -DCMAKE_C_FLAGS=-fno-blocks \
    -DCMAKE_AR=/opt/tiger-toolchain/bin/i386-apple-darwin8-ar -DCMAKE_RANLIB=/opt/tiger-toolchain/bin/i386-apple-darwin8-ranlib \
    -DCMAKE_TRY_COMPILE_TARGET_TYPE=STATIC_LIBRARY -DCMAKE_BUILD_TYPE=Release -DCMAKE_INSTALL_PREFIX=/opt/tiger-llvm-runtime \
    -DLIBCXX_ENABLE_SHARED=OFF -DLIBCXXABI_ENABLE_SHARED=OFF -DLIBCXX_ENABLE_STATIC=ON -DLIBCXXABI_ENABLE_STATIC=ON \
    -DLIBCXXABI_USE_LLVM_UNWINDER=OFF -DLIBCXX_ENABLE_VENDOR_AVAILABILITY_ANNOTATIONS=OFF \
    -DLIBCXX_INCLUDE_TESTS=OFF -DLIBCXXABI_INCLUDE_TESTS=OFF -DLIBCXX_INCLUDE_BENCHMARKS=OFF -DLIBCXX_INSTALL_MODULES=OFF
cmake --build "$work/build" --target install-cxx install-cxxabi --parallel "$jobs"
install -D -m 644 "$src/libcxx/LICENSE.TXT" /opt/qt4-licenses/LLVM-LIBCXX-LICENSE.txt
install -D -m 644 "$src/libcxxabi/LICENSE.TXT" /opt/qt4-licenses/LLVM-LIBCXXABI-LICENSE.txt
install -D -m 644 "$src/compiler-rt/LICENSE.TXT" /opt/qt4-licenses/LLVM-COMPILER-RT-LICENSE.txt
clang --target=i386-apple-macosx10.4 -isysroot "$sdk" -O2 -c "$src/compiler-rt/lib/builtins/emutls.c" -o /opt/tiger-llvm-runtime/lib/emutls.o
clang++ --target=i386-apple-macosx10.4 -isysroot "$sdk" -std=c++23 -femulated-tls -O2 -nostdinc++ \
    -isystem /opt/tiger-llvm-runtime/include/c++/v1 -I"$src/libcxxabi/include" \
    -D_LIBCPP_BUILDING_LIBRARY -D_LIBCXXABI_BUILDING_LIBRARY -DLIBCXXABI_BUILDING_LIBCXXABI \
    -c "$src/libcxxabi/src/cxa_thread_atexit.cpp" -o /opt/tiger-llvm-runtime/lib/cxa_thread_atexit.o
