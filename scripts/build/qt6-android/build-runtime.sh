#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-or-later

set -euo pipefail
llvm=/work/api21/llvm-project-21.1.8.src
runtime=/work/api21/runtime
builtins=/work/api21/builtins
sysroot=/ndk/toolchains/llvm/prebuilt/linux-x86_64/sysroot
prefix=/opt/longreach-android-api21
source /repo/scripts/build/qt6-android/target-config.sh
mkdir -p /out /work/api21 "$prefix"/{lib,include/c++/v1}
echo '4633a23617fa31a3ea51242586ea7fb1da7140e426bd62fc164261fe036aa142  /repo/downloads/llvm-project-21.1.8.src.tar.xz' | sha256sum -c -
clang++-21 --version | head -1
if [[ ! -f "$llvm/runtimes/CMakeLists.txt" ]]; then
    tar -xJf /repo/downloads/llvm-project-21.1.8.src.tar.xz -C /work/api21 \
        llvm-project-21.1.8.src/{cmake,compiler-rt,libc,libcxx,libcxxabi,libunwind,llvm,runtimes,third-party}
fi
flags="${arch_flags[*]} -fPIC -femulated-tls -ffunction-sections -fdata-sections"
options=(
    -G Ninja -DCMAKE_SYSTEM_NAME=Linux "-DCMAKE_SYSTEM_PROCESSOR=$processor" -DCMAKE_BUILD_TYPE=Release
    -DCMAKE_C_COMPILER=clang-21 -DCMAKE_CXX_COMPILER=clang++-21 -DCMAKE_ASM_COMPILER=clang-21
    "-DCMAKE_SYSROOT=$sysroot" "-DCMAKE_C_COMPILER_TARGET=$target"
    "-DCMAKE_CXX_COMPILER_TARGET=$target" "-DCMAKE_ASM_COMPILER_TARGET=$target"
    "-DCMAKE_CXX_FLAGS=$flags" "-DCMAKE_ASM_FLAGS=$flags"
    -DCMAKE_AR=/usr/bin/llvm-ar-21 -DCMAKE_RANLIB=/usr/bin/llvm-ranlib-21
    -DCMAKE_TRY_COMPILE_TARGET_TYPE=STATIC_LIBRARY -DCMAKE_EXE_LINKER_FLAGS=-fuse-ld=lld
    '-DCMAKE_SHARED_LINKER_FLAGS=-fuse-ld=lld -Wl,--hash-style=sysv'
    "-DLLVM_DEFAULT_TARGET_TRIPLE=$target" -DLLVM_ENABLE_PER_TARGET_RUNTIME_DIR=OFF
    -DLLVM_INCLUDE_TESTS=OFF -DLLVM_FORCE_SMALLFILE_FOR_ANDROID=TRUE -DCMAKE_EXPORT_COMPILE_COMMANDS=ON
)
cmake -S "$llvm/runtimes" -B "$runtime" "${options[@]}" "-DCMAKE_C_FLAGS=$flags" \
    '-DLLVM_ENABLE_RUNTIMES=libunwind;libcxxabi;libcxx' \
    -DLIBUNWIND_ENABLE_SHARED=OFF -DLIBUNWIND_ENABLE_STATIC=ON -DLIBUNWIND_INCLUDE_TESTS=OFF \
    -DLIBCXXABI_ENABLE_SHARED=OFF -DLIBCXXABI_ENABLE_STATIC=ON -DLIBCXXABI_USE_LLVM_UNWINDER=ON \
    -DLIBCXXABI_INCLUDE_TESTS=OFF -DLIBCXXABI_HAS_CXA_THREAD_ATEXIT_IMPL=OFF \
    -DLIBCXX_ENABLE_SHARED=OFF -DLIBCXX_ENABLE_STATIC=ON \
    -DLIBCXX_CXX_ABI=libcxxabi -DLIBCXX_ENABLE_STATIC_ABI_LIBRARY=OFF \
    -DLIBCXX_INCLUDE_TESTS=OFF -DLIBCXX_INCLUDE_BENCHMARKS=OFF -DLIBCXX_INSTALL_MODULES=OFF
cmake --build "$runtime" --parallel "${PARALLEL_JOBS:-2}"
cmake -S "$llvm/runtimes" -B "$builtins" "${options[@]}" "-DCMAKE_C_FLAGS=$flags" \
    -DLLVM_ENABLE_RUNTIMES=compiler-rt -DCOMPILER_RT_DEFAULT_TARGET_ONLY=ON \
    -DCOMPILER_RT_LIBATOMIC_USE_PTHREAD=ON -DCOMPILER_RT_INCLUDE_TESTS=OFF \
    -DCOMPILER_RT_BUILD_SANITIZERS=OFF -DCOMPILER_RT_BUILD_XRAY=OFF \
    -DCOMPILER_RT_BUILD_LIBFUZZER=OFF -DCOMPILER_RT_BUILD_PROFILE=OFF \
    -DCOMPILER_RT_BUILD_CTX_PROFILE=OFF -DCOMPILER_RT_BUILD_ORC=OFF \
    -DCOMPILER_RT_BUILD_MEMPROF=OFF -DCOMPILER_RT_BUILD_GWP_ASAN=OFF -DCOMPILER_RT_BUILD_CRT=OFF
cmake --build "$builtins" --parallel "${PARALLEL_JOBS:-2}"
cp -a "$runtime/include/c++/v1/." "$prefix/include/c++/v1/"
cp "$runtime/lib/"*.a "$prefix/lib/"
builtins_archive="$builtins/compiler-rt/lib/linux/libclang_rt.builtins-${builtins_arch}-android.a"
cp "$builtins_archive" "$prefix/lib/"
platform="$sysroot/usr/lib/$ndk_triple/21"
arch=(--target="$target" --sysroot="$sysroot" "${arch_flags[@]}" -fPIC -femulated-tls)
clang++-21 "${arch[@]}" -shared -nostdlib -fuse-ld=lld \
    -Wl,--hash-style=sysv,--no-undefined,--no-dependent-libraries,-soname,libc++_shared.so \
    "$platform/crtbegin_so.o" -Wl,--whole-archive \
    "$runtime/lib/libc++.a" "$runtime/lib/libc++experimental.a" "$runtime/lib/libc++abi.a" \
    "$runtime/lib/libunwind.a" -Wl,--no-whole-archive \
    -Wl,-u,__emutls_get_address,-u,__emutls_register_common "$builtins_archive" \
    -L"$platform" -llog -ldl -lm -lc "$platform/crtend_so.o" -o "$prefix/lib/libc++_shared.so"
llvm-readobj-21 --file-header --dynamic-table "$prefix/lib/libc++_shared.so" > /out/runtime-elf.txt
cp "$prefix/lib/libc++_shared.so" /out/
echo 'Upstream LLVM 21.1.8 API21 shared runtime built'
