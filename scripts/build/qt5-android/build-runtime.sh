#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-or-later

set -euo pipefail

repo=${REPO_ROOT:-/repo}
inputs=${ANDROID_INPUTS:-$repo/downloads/android-gingerbread}
llvm=/work/android-llvm/llvm-project-21.1.8.src
sysroot=/work/android-sysroot
runtime=/work/android-runtime
builtins=/work/android-builtins
source "$repo/scripts/build/qt5-android/target-config.sh"
[[ "$api" == 10 ]] || { echo "This runtime producer requires API10" >&2; exit 1; }

echo '4633a23617fa31a3ea51242586ea7fb1da7140e426bd62fc164261fe036aa142  '"$repo/downloads/llvm-project-21.1.8.src.tar.xz" | sha256sum -c -
echo "$sysroot_sha256  $inputs/$sysroot_archive" | sha256sum -c -

state="$target $sysroot_sha256"
if [[ -f /work/.android-runtime-prepared ]]; then
    previous=$(cat /work/.android-runtime-prepared)
    # An empty marker belongs to the historical ARMv7-only producer.
    if [[ -z "$previous" && "$abi" == armeabi-v7a ]]; then
        printf '%s\n' "$state" > /work/.android-runtime-prepared
    elif [[ "$previous" != "$state" ]]; then
        echo 'The API10 work cache belongs to another ABI/sysroot; use a matching build container' >&2
        exit 1
    fi
fi
if [[ ! -f /work/.android-runtime-prepared ]]; then
    mkdir -p /work/android-llvm "$sysroot"
    tar -xf "$repo/downloads/llvm-project-21.1.8.src.tar.xz" -C /work/android-llvm \
        "llvm-project-21.1.8.src"/{cmake,compiler-rt,libc,libcxx,libcxxabi,libunwind,llvm,runtimes,third-party}
    tar -xzf "$inputs/$sysroot_archive" -C "$sysroot"
    printf '%s\n' "$state" > /work/.android-runtime-prepared
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

flags="${arch_flags[*]} -fPIC -femulated-tls -ffunction-sections -fdata-sections -D__STDC_LIMIT_MACROS -D__STDC_CONSTANT_MACROS -DSIZE_MAX=__SIZE_MAX__"
options=(
    -G Ninja -DCMAKE_SYSTEM_NAME=Linux "-DCMAKE_SYSTEM_PROCESSOR=$runtime_processor" -DCMAKE_BUILD_TYPE=Release
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
    -DLIBUNWIND_USE_FRAME_HEADER_CACHE=OFF \
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
    -DCOMPILER_RT_EXCLUDE_ATOMIC_BUILTIN=ON -DCOMPILER_RT_BUILD_STANDALONE_LIBATOMIC=OFF \
    -DCOMPILER_RT_BUILD_SANITIZERS=OFF -DCOMPILER_RT_BUILD_XRAY=OFF \
    -DCOMPILER_RT_BUILD_LIBFUZZER=OFF -DCOMPILER_RT_BUILD_PROFILE=OFF \
    -DCOMPILER_RT_BUILD_CTX_PROFILE=OFF -DCOMPILER_RT_BUILD_ORC=OFF \
    -DCOMPILER_RT_BUILD_MEMPROF=OFF -DCOMPILER_RT_BUILD_GWP_ASAN=OFF -DCOMPILER_RT_BUILD_CRT=OFF
cmake --build "$builtins" --parallel "${PARALLEL_JOBS:-2}"
bash "$repo/scripts/build/qt5-android/install-toolchain.sh"
python3 "$repo/scripts/build/qt5-android/input-provenance.py"
