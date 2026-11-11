#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2026 OpenKaryon
set -euo pipefail

target=${1:?target required}
work=${LLVM_BUILD_ROOT:-/work}
llvm=${LLVM_ROOT:-$work/toolchain}
source=$work/source
prefix=$work/runtimes/$target
jobs=${PARALLEL_JOBS:-4}
build_root=$work
if [ -n "${LLVM_BUILD_VARIANT:-}" ]; then
    case "$LLVM_BUILD_VARIANT" in
        *[!a-zA-Z0-9_-]*) echo 'invalid runtime build variant' >&2; exit 2 ;;
    esac
    build_root="$work/variants/$LLVM_BUILD_VARIANT"
    mkdir -p "$build_root"
fi
compiler_flags=()
cmake_args=(-DCMAKE_EXPORT_COMPILE_COMMANDS=ON)
link_flags='-fuse-ld=lld -Wl,--threads=2'
exe_suffix=
mkdir -p "$prefix/resource"
cp -a "$llvm/lib/clang/21/include" "$prefix/resource/"

case "$target" in
    linux-amd64)
        triple=x86_64-unknown-linux-gnu
        compiler_flags=(--gcc-toolchain=/opt/rh/devtoolset-11/root/usr -pthread)
        ;;
    linux-arm64)
        triple=aarch64-unknown-linux-gnu
        sysroot=/opt/sysroot-arm64
        compiler_flags=(--sysroot="$sysroot" --gcc-toolchain=/usr -pthread -nostdinc
                        -isystem "$llvm/lib/clang/21/include" -isystem "$sysroot/usr/include"
                        -B"$sysroot/usr/lib64" -L"$sysroot/usr/lib64"
                        -Wl,-rpath-link,"$sysroot/usr/lib64")
        cmake_args=(-DCMAKE_SYSTEM_NAME=Linux -DCMAKE_SYSTEM_PROCESSOR=aarch64
                    -DCMAKE_SYSROOT="$sysroot" -DCMAKE_TRY_COMPILE_TARGET_TYPE=STATIC_LIBRARY)
        ;;
    windows-amd64|windows-arm64)
        bash /src/scripts/build/qt6-llvm-probes/build-windows-sysroot.sh "$target"
        sysroot=$work/sysroots/mingw13/$target
        exe_suffix=.exe
        if [ "$target" = windows-amd64 ]; then
            triple=x86_64-w64-windows-gnu
            minimum=0x0601
            system_version=6.1
            link_flags='-fuse-ld=lld -Wl,--major-subsystem-version,6,--minor-subsystem-version,1'
        else
            triple=aarch64-w64-windows-gnu
            minimum=0x0a00
            system_version=10.0
            link_flags='-fuse-ld=lld -Wl,--major-subsystem-version,10,--minor-subsystem-version,0'
        fi
        compiler_flags=(--sysroot="$sysroot" -D_WIN32_WINNT="$minimum" -DWINVER="$minimum"
                        --rtlib=compiler-rt -isystem "$sysroot/include" -L"$sysroot/lib")
        cmake_args=(-DCMAKE_SYSTEM_NAME=Windows -DCMAKE_SYSTEM_VERSION="$system_version"
                    -DCMAKE_SYSROOT="$sysroot" -DCMAKE_TRY_COMPILE_TARGET_TYPE=STATIC_LIBRARY
                    -DLIBCXX_HAS_WIN32_THREAD_API=ON -DLIBCXX_HAS_PTHREAD_API=OFF)
        ;;
    macos-amd64|macos-arm64)
        sysroot=/opt/osxcross/target/SDK/MacOSX14.0.sdk
        if [ "$target" = macos-amd64 ]; then
            arch=x86_64
            minimum=10.13
        else
            arch=arm64
            minimum=11.0
        fi
        host_python=${LLVM_HOST_PYTHON:-$work/host-python/bin/python3.11}
        "$host_python" -c \
            'import plistlib, sys; data = plistlib.load(open(sys.argv[1], "rb")); assert sys.argv[2] in data["SupportedTargets"]["macosx"]["Archs"]' \
            "$sysroot/SDKSettings.plist" "$arch"
        triple=$arch-apple-darwin23
        link_flags='-fuse-ld=lld -Wl,-fatal_warnings'
        compiler_flags=(-isysroot "$sysroot" -mmacosx-version-min="$minimum")
        cmake_args=(-DCMAKE_SYSTEM_NAME=Darwin -DCMAKE_SYSTEM_PROCESSOR="$arch"
                    -DCMAKE_OSX_SYSROOT="$sysroot" -DCMAKE_OSX_ARCHITECTURES="$arch"
                    -DCMAKE_OSX_DEPLOYMENT_TARGET="$minimum"
                    -DPython3_EXECUTABLE="$host_python"
                    -DCMAKE_TRY_COMPILE_TARGET_TYPE=STATIC_LIBRARY
                    -DCOMPILER_RT_OSX_ARCHITECTURES="$arch" -DDARWIN_osx_ARCHS="$arch"
                    -DDARWIN_osx_BUILTIN_ARCHS="$arch"
                    -DDARWIN_osx_SYSROOT="$sysroot" -DDARWIN_macosx_CACHED_SYSROOT="$sysroot"
                    -DDARWIN_macosx_OVERRIDE_SDK_VERSION=14.0
                    -DCOMPILER_RT_ENABLE_IOS=OFF -DCOMPILER_RT_ENABLE_TVOS=OFF
                    -DCOMPILER_RT_ENABLE_WATCHOS=OFF -DCOMPILER_RT_ENABLE_VISIONOS=OFF
                    -DLIBCXX_ENABLE_VENDOR_AVAILABILITY_ANNOTATIONS=OFF)
        ;;
    *)
        echo "unsupported target: $target" >&2
        exit 2
        ;;
esac
compiler_flags=(--target="$triple" -resource-dir="$prefix/resource" -Qunused-arguments "${compiler_flags[@]}")
read -r -a linker_flags <<< "$link_flags"
printf -v flags '%q ' "${compiler_flags[@]}"

common_args=(
    "${cmake_args[@]}"
    -DCMAKE_BUILD_TYPE=Release -DCMAKE_INSTALL_PREFIX="$prefix"
    -DCMAKE_C_COMPILER="$llvm/bin/clang" -DCMAKE_CXX_COMPILER="$llvm/bin/clang++"
    -DCMAKE_C_COMPILER_TARGET="$triple" -DCMAKE_CXX_COMPILER_TARGET="$triple"
    -DCMAKE_ASM_COMPILER="$llvm/bin/clang" -DCMAKE_ASM_COMPILER_TARGET="$triple"
    -DCMAKE_ASM_FLAGS="$flags"
    -DCMAKE_AR="$llvm/bin/llvm-ar" -DCMAKE_RANLIB="$llvm/bin/llvm-ranlib"
    -DCMAKE_C_FLAGS="$flags" -DCMAKE_CXX_FLAGS="$flags"
    -DCMAKE_EXE_LINKER_FLAGS="$link_flags"
    -DLLVM_DEFAULT_TARGET_TRIPLE="$triple" -DLLVM_ENABLE_PER_TARGET_RUNTIME_DIR=OFF
)
# libc++abi and libunwind query Clang for an existing compiler-rt archive.
# Install builtins first, so a clean build does not depend on a prior attempt.
cmake -S "$source/runtimes" -B "${build_root}/build-builtins-$target" -G Ninja \
    "${common_args[@]}" -DLLVM_ENABLE_RUNTIMES=compiler-rt \
    -DCOMPILER_RT_INSTALL_PATH="$prefix/resource" \
    -DCOMPILER_RT_DEFAULT_TARGET_ONLY=ON -DCOMPILER_RT_INCLUDE_TESTS=OFF \
    -DCOMPILER_RT_BUILD_SANITIZERS=OFF -DCOMPILER_RT_BUILD_XRAY=OFF \
    -DCOMPILER_RT_BUILD_LIBFUZZER=OFF -DCOMPILER_RT_BUILD_PROFILE=OFF \
    -DCOMPILER_RT_BUILD_CTX_PROFILE=OFF -DCOMPILER_RT_BUILD_ORC=OFF \
    -DCOMPILER_RT_BUILD_MEMPROF=OFF
cmake --build "${build_root}/build-builtins-$target" --parallel "$jobs"
cmake --install "${build_root}/build-builtins-$target"

runtime_args=(-DLLVM_ENABLE_RUNTIMES='libunwind;libcxxabi;libcxx')
if [[ "$target" = linux-* ]]; then
    # The 2.17 sysroots lack this glibc entry point. Cross compile-only checks
    # cannot detect that, so select libc++abi's existing weak-symbol fallback.
    runtime_args+=(-DLIBCXXABI_HAS_CXA_THREAD_ATEXIT_IMPL=OFF)
fi
cmake -S "$source/runtimes" -B "${build_root}/build-runtime-$target" -G Ninja \
    "${common_args[@]}" "${runtime_args[@]}" \
    -DLIBUNWIND_ENABLE_SHARED=OFF -DLIBUNWIND_ENABLE_STATIC=ON \
    -DLIBUNWIND_USE_COMPILER_RT=ON -DLIBUNWIND_INCLUDE_TESTS=OFF \
    -DLIBCXXABI_ENABLE_SHARED=OFF -DLIBCXXABI_ENABLE_STATIC=ON \
    -DLIBCXXABI_USE_COMPILER_RT=ON -DLIBCXXABI_USE_LLVM_UNWINDER=ON \
    -DLIBCXXABI_STATICALLY_LINK_UNWINDER_IN_STATIC_LIBRARY=ON \
    -DLIBCXXABI_INCLUDE_TESTS=OFF -DLIBCXXABI_HERMETIC_STATIC_LIBRARY=ON \
    -DLIBCXX_ENABLE_SHARED=OFF -DLIBCXX_ENABLE_STATIC=ON \
    -DLIBCXX_USE_COMPILER_RT=ON -DLIBCXX_CXX_ABI=libcxxabi \
    -DLIBCXX_ENABLE_STATIC_ABI_LIBRARY=ON -DLIBCXX_STATICALLY_LINK_ABI_IN_STATIC_LIBRARY=ON \
    -DLIBCXX_INCLUDE_TESTS=OFF -DLIBCXX_INCLUDE_BENCHMARKS=OFF \
    -DLIBCXX_HERMETIC_STATIC_LIBRARY=ON -DLIBCXX_INSTALL_MODULES=OFF
cmake --build "${build_root}/build-runtime-$target" --parallel "$jobs"
cmake --install "${build_root}/build-runtime-$target"

if [[ "$target" = macos-* ]]; then
    mkdir -p "/out/$target"
    lipo=$(find /opt/osxcross/target/bin -maxdepth 1 -name '*-lipo' | sort | head -1)
    test -n "$lipo"
    : > "/out/$target/runtime-architectures.log"
    for library in "$prefix/resource/lib/darwin/libclang_rt.osx.a" \
                   "$prefix/lib/libunwind.a" "$prefix/lib/libc++abi.a" "$prefix/lib/libc++.a"; do
        "$lipo" "$library" -verify_arch "$arch"
        "$lipo" "$library" -info | tee -a "/out/$target/runtime-architectures.log"
    done
fi

mkdir -p "$prefix/bin"
for language in c cxx; do
    arguments=("$llvm/bin/clang" "${compiler_flags[@]}" -L"$prefix/lib"
               --rtlib=compiler-rt --unwindlib=libunwind)
    if [ "$language" = cxx ]; then
        arguments=("$llvm/bin/clang++" -stdlib=libc++ -nostdinc++
                   -isystem "$prefix/include/c++/v1" "${compiler_flags[@]}" -L"$prefix/lib"
                   --rtlib=compiler-rt --unwindlib=libunwind)
    fi
    {
        echo '#!/bin/bash'
        printf 'exec '
        printf '%q ' "${arguments[@]}" "${linker_flags[@]}"
        printf '"$@"\n'
    } > "$prefix/bin/clang-$language"
    chmod +x "$prefix/bin/clang-$language"
done

cmake -S /src/scripts/tests/qt6-llvm-probes -B "${build_root}/build-probe-$target" -G Ninja \
    "${cmake_args[@]}" -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_CXX_COMPILER="$prefix/bin/clang-cxx" -DCMAKE_CXX_COMPILER_TARGET="$triple"
cmake --build "${build_root}/build-probe-$target" --clean-first --parallel 2
mkdir -p "/out/$target"
binary=/out/$target/cxx23-probe$exe_suffix
cp "${build_root}/build-probe-$target/cxx23-probe$exe_suffix" "$binary"
export PATH="$llvm/bin:$PATH"
case "$target" in
    linux-*)
        python3 /src/scripts/build/qt5-lucid/max-glibc.py "$binary" 2.17
        readelf -d "$binary" | grep NEEDED | tee "/out/$target/dependencies.log"
        if grep -E 'lib(c\+\+|stdc\+\+|gcc_s|unwind)' "/out/$target/dependencies.log"; then
            echo 'unexpected shared C++ runtime dependency' >&2
            exit 1
        fi
        if [ "$target" = linux-amd64 ]; then
            timeout 60 "$binary" | tee "/out/$target/run.log"
        else
            timeout 60 env -u LD_LIBRARY_PATH qemu-aarch64-static -L "$sysroot" "$binary" \
                | tee "/out/$target/run.log"
        fi
        python3 /src/scripts/tests/require-modern-cpp.py "/out/$target/run.log"
        ;;
    windows-amd64)
        bash /src/scripts/audit/qt6-win7-audit.sh "$binary" | tee "/out/$target/audit.log"
        llvm-objdump -p "$binary" > "/out/$target/dependencies.log"
        ;;
    windows-arm64)
        llvm-readobj --file-headers --coff-imports "$binary" | tee "/out/$target/dependencies.log"
        ;;
    macos-*)
        MACHO_AUDIT_ARCH="$arch" bash /src/scripts/audit/qt6-macos-audit.sh "$minimum" "$binary" \
            | tee "/out/$target/audit.log"
        llvm-objdump --macho --dylibs-used "$binary" | tee "/out/$target/dependencies.log"
        ;;
esac
