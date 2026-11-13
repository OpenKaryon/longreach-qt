#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2026 OpenKaryon
set -euo pipefail

archive=${1:?LLVM source archive required}
patch=${2:?Darwin runtime patch required}
tls_patch=${3:?Darwin TLS patch required}
arch=${4:-i386}
osxcross=/usr/local/osxcross
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
case "$arch" in
    i386)
        bin="$osxcross/bin/i386-apple-darwin10-"
        compile_sdk=$(find "$osxcross/SDK-i386" -mindepth 1 -maxdepth 1 -name 'MacOSX*.sdk' -type d)
        link_sdk="$osxcross/SDK/MacOSX10.7-i386.sdk"
        runtime_archive="$link_sdk/usr/lib/libc++.a"
        ;;
    x86_64)
        bin="$osxcross/bin/$(cat /opt/osxcross-prefix)"
        compile_sdk=$(find "$osxcross/SDK" -mindepth 1 -maxdepth 1 -name 'MacOSX*.sdk' -type d)
        legacy_sdk=${5:?MacOSX10.7 SDK archive required}
        echo "e5cf1c4026fa2b538201268d1b057854eb6e47676ff31a336d19b981c6fd4d2a  $legacy_sdk" | sha256sum -c -
        link_sdk="$work/MacOSX10.7.sdk"
        mkdir "$link_sdk"
        tar -xJf "$legacy_sdk" -C "$link_sdk" --strip-components=1
        runtime_archive="$compile_sdk/usr/lib/libc++.a"
        ;;
    *)
        echo "Unsupported Snow Leopard architecture: $arch" >&2
        exit 2
        ;;
esac
test -f "$compile_sdk/usr/include/c++/v1/__config"
test -f "$runtime_archive"
test -f "$link_sdk/usr/lib/libSystem.B.dylib"
clang --version | grep -E '^clang version 21\.1\.8([[:space:]]|$)'

echo "4633a23617fa31a3ea51242586ea7fb1da7140e426bd62fc164261fe036aa142  $archive" | sha256sum -c -
mkdir -p "$work/source"
tar -xJf "$archive" -C "$work/source" --strip-components=1
(cd "$work/source" && git apply "$patch" "$tls_patch")

target=$arch-apple-macosx10.6
cmake -G 'Unix Makefiles' -S "$work/source/runtimes" -B "$work/build" \
    -DLLVM_ENABLE_RUNTIMES='libcxx;libcxxabi' \
    -DCMAKE_SYSTEM_NAME=Darwin -DCMAKE_SYSTEM_PROCESSOR="$arch" \
    -DCMAKE_C_COMPILER="$(command -v clang)" -DCMAKE_CXX_COMPILER="$(command -v clang++)" \
    -DCMAKE_C_COMPILER_TARGET="$target" -DCMAKE_CXX_COMPILER_TARGET="$target" \
    -DCMAKE_OSX_SYSROOT="$link_sdk" -DCMAKE_OSX_ARCHITECTURES="$arch" \
    -DCMAKE_OSX_DEPLOYMENT_TARGET=10.6 \
    -DCMAKE_AR="${bin}ar" -DCMAKE_RANLIB="${bin}ranlib" \
    -DCMAKE_TRY_COMPILE_TARGET_TYPE=STATIC_LIBRARY \
    -DCMAKE_BUILD_TYPE=Release -DCMAKE_INSTALL_PREFIX="$work/runtime" \
    -DLIBCXX_ENABLE_SHARED=OFF -DLIBCXXABI_ENABLE_SHARED=OFF \
    -DLIBCXX_ENABLE_STATIC=ON -DLIBCXXABI_ENABLE_STATIC=ON \
    -DLIBCXXABI_USE_LLVM_UNWINDER=OFF \
    -DLIBCXX_ENABLE_VENDOR_AVAILABILITY_ANNOTATIONS=OFF \
    -DLIBCXX_INCLUDE_TESTS=OFF -DLIBCXXABI_INCLUDE_TESTS=OFF \
    -DLIBCXX_INCLUDE_BENCHMARKS=OFF -DLIBCXX_INSTALL_MODULES=OFF
cmake --build "$work/build" --target install-cxx install-cxxabi --parallel "${PARALLEL_JOBS:-3}"

# The osxcross driver links -lc++; combine both archives in the selected SDK.
mkdir "$work/cxx" "$work/cxxabi"
(cd "$work/cxx" && "${bin}ar" x "$work/runtime/lib/libc++.a")
(cd "$work/cxxabi" && "${bin}ar" x "$work/runtime/lib/libc++abi.a")
for object in "$work/cxxabi"/*.o; do
    mv "$object" "$work/cxx/abi_${object##*/}"
done
# Snow Leopard has no dyld thread-local storage. The compiler emits calls
# into these helpers when the SDK driver passes -femulated-tls.
builtins="$work/source/compiler-rt/lib/builtins"
abi="$work/source/libcxxabi"
target_flags=(--target="$target" -isysroot "$link_sdk")
clang "${target_flags[@]}" -O2 -c "$builtins/emutls.c" -o "$work/emutls.o"
clang++ "${target_flags[@]}" -std=c++23 -femulated-tls -O2 -nostdinc++ \
    -isystem "$work/runtime/include/c++/v1" -I"$abi/include" \
    -D_LIBCPP_BUILDING_LIBRARY -D_LIBCXXABI_BUILDING_LIBRARY -DLIBCXX_BUILDING_LIBCXXABI \
    -c "$abi/src/cxa_thread_atexit.cpp" -o "$work/cxa_thread_atexit.o"
if [ "$arch" = x86_64 ]; then
    # Clang lowers @available to this compiler-rt builtin on the Snow Leopard target.
    clang "${target_flags[@]}" -Os -DTARGET_OS_SIMULATOR=0 \
        -c "$builtins/os_version_check.c" -o "$work/os_version_check.o"
    resource_dir="$(clang -print-resource-dir)/lib/darwin"
    mkdir -p "$resource_dir"
    llvm-ar rcs "$resource_dir/libclang_rt.osx.a" "$work/os_version_check.o"
fi
if [ "$arch" = i386 ]; then
    "${bin}ar" rcs "$link_sdk/usr/lib/libqt-i386-rt.a" "$work/emutls.o" "$work/cxa_thread_atexit.o"
else
    mkdir -p /opt/longreach-llvm/lib
    llvm-ar rcs /opt/longreach-llvm/lib/liblongreach-snow-tls.a "$work/emutls.o" "$work/cxa_thread_atexit.o"
fi
"${bin}ar" rcs "$work/libc++.a" "$work/cxx"/*.o
install -m 644 "$work/libc++.a" "$runtime_archive"
rm -rf "$compile_sdk/usr/include/c++/v1"
cp -a "$work/runtime/include/c++/v1" "$compile_sdk/usr/include/c++/v1"
