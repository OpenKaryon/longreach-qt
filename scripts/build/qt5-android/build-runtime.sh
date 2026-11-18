#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-or-later

set -euo pipefail

repo=${REPO_ROOT:-/repo}
inputs=${ANDROID_INPUTS:-$repo/downloads/android-gingerbread}
llvm=/work/android-llvm/llvm-project-21.1.8.src
sysroot=/work/android-sysroot
runtime=/work/android-runtime
builtins=/work/android-builtins
target=armv7a-linux-androideabi10

echo '4633a23617fa31a3ea51242586ea7fb1da7140e426bd62fc164261fe036aa142  '"$repo/downloads/llvm-project-21.1.8.src.tar.xz" | sha256sum -c -
echo '6f7ec1a9b177ccd1da48c2045d14c5f62fc7db32581919535269cc2738a35f8d  '"$inputs/aosp-ndk-r7-api9-arm.tar.gz" | sha256sum -c -

if [[ ! -f /work/.android-runtime-prepared ]]; then
    mkdir -p /work/android-llvm "$sysroot"
    tar -xf "$repo/downloads/llvm-project-21.1.8.src.tar.xz" -C /work/android-llvm \
        "llvm-project-21.1.8.src"/{cmake,compiler-rt,libc,libcxx,libcxxabi,libunwind,llvm,runtimes,third-party}
    tar -xzf "$inputs/aosp-ndk-r7-api9-arm.tar.gz" -C "$sysroot"
    touch /work/.android-runtime-prepared
fi
for change in "$repo"/patches/android/gingerbread/*.patch; do
    root="$sysroot"
    if [[ "$change" == */llvm.patch ]]; then
        root="$llvm"
    fi
    if (cd "$root" && git apply --reverse --check "$change" 2>/dev/null); then
        continue
    fi
    (cd "$root" && git apply "$change")
done

flags='-march=armv7-a -mfpu=vfpv3-d16 -mfloat-abi=softfp -fPIC -femulated-tls -ffunction-sections -fdata-sections -D__STDC_LIMIT_MACROS -D__STDC_CONSTANT_MACROS -DSIZE_MAX=__SIZE_MAX__'
options=(
    -G Ninja -DCMAKE_SYSTEM_NAME=Linux -DCMAKE_SYSTEM_PROCESSOR=arm -DCMAKE_BUILD_TYPE=Release
    -DCMAKE_C_COMPILER=clang-21 -DCMAKE_CXX_COMPILER=clang++-21 -DCMAKE_ASM_COMPILER=clang-21
    "-DCMAKE_SYSROOT=$sysroot" "-DCMAKE_C_COMPILER_TARGET=$target"
    "-DCMAKE_CXX_COMPILER_TARGET=$target" "-DCMAKE_ASM_COMPILER_TARGET=$target"
    "-DCMAKE_CXX_FLAGS=$flags -D_LIBCPP_PROVIDES_DEFAULT_RUNE_TABLE" "-DCMAKE_ASM_FLAGS=$flags"
    -DCMAKE_AR=/usr/bin/llvm-ar-21 -DCMAKE_RANLIB=/usr/bin/llvm-ranlib-21
    -DCMAKE_TRY_COMPILE_TARGET_TYPE=STATIC_LIBRARY -DCMAKE_EXE_LINKER_FLAGS=-fuse-ld=lld
    '-DCMAKE_SHARED_LINKER_FLAGS=-fuse-ld=lld -Wl,--hash-style=sysv'
    "-DLLVM_DEFAULT_TARGET_TRIPLE=$target" -DLLVM_ENABLE_PER_TARGET_RUNTIME_DIR=OFF -DLLVM_INCLUDE_TESTS=OFF
)
cmake -S "$llvm/runtimes" -B "$runtime" "${options[@]}" "-DCMAKE_C_FLAGS=$flags" \
    '-DLLVM_ENABLE_RUNTIMES=libunwind;libcxxabi;libcxx' \
    -DLIBUNWIND_ENABLE_SHARED=OFF -DLIBUNWIND_ENABLE_STATIC=ON -DLIBUNWIND_INCLUDE_TESTS=OFF \
    -DLIBCXXABI_ENABLE_SHARED=OFF -DLIBCXXABI_ENABLE_STATIC=ON -DLIBCXXABI_USE_LLVM_UNWINDER=ON \
    -DLIBCXXABI_INCLUDE_TESTS=OFF -DLIBCXXABI_HAS_CXA_THREAD_ATEXIT_IMPL=OFF \
    -DLIBCXX_ENABLE_SHARED=OFF -DLIBCXX_ENABLE_STATIC=ON -DLIBCXX_ENABLE_WIDE_CHARACTERS=OFF \
    -DLIBCXX_CXX_ABI=libcxxabi -DLIBCXX_ENABLE_STATIC_ABI_LIBRARY=OFF \
    -DLIBCXX_INCLUDE_TESTS=OFF -DLIBCXX_INCLUDE_BENCHMARKS=OFF -DLIBCXX_INSTALL_MODULES=OFF
cmake --build "$runtime" --parallel "${PARALLEL_JOBS:-2}"
cmake -S "$llvm/runtimes" -B "$builtins" "${options[@]}" \
    "-DCMAKE_C_FLAGS=$flags -D__ANDROID_API_FUTURE__=10000" \
    -DLLVM_ENABLE_RUNTIMES=compiler-rt -DCOMPILER_RT_DEFAULT_TARGET_ONLY=ON \
    -DCOMPILER_RT_LIBATOMIC_USE_PTHREAD=ON -DCOMPILER_RT_INCLUDE_TESTS=OFF \
    -DCOMPILER_RT_BUILD_SANITIZERS=OFF -DCOMPILER_RT_BUILD_XRAY=OFF \
    -DCOMPILER_RT_BUILD_LIBFUZZER=OFF -DCOMPILER_RT_BUILD_PROFILE=OFF \
    -DCOMPILER_RT_BUILD_CTX_PROFILE=OFF -DCOMPILER_RT_BUILD_ORC=OFF \
    -DCOMPILER_RT_BUILD_MEMPROF=OFF -DCOMPILER_RT_BUILD_GWP_ASAN=OFF -DCOMPILER_RT_BUILD_CRT=OFF
cmake --build "$builtins" --parallel "${PARALLEL_JOBS:-2}"
bash "$repo/scripts/build/qt5-android/install-toolchain.sh"
