#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-or-later

set -euo pipefail
repo=${REPO_ROOT:-/repo}
source "$repo/scripts/build/qt5-android/target-config.sh"
[[ "$api" == 10 ]] || { echo "This toolchain installer requires API10" >&2; exit 1; }
prefix=/opt/longreach-android
sysroot=/work/android-sysroot
runtime=/work/android-runtime
builtins=/work/android-builtins/compiler-rt/lib/linux/libclang_rt.builtins-${builtins_arch}-android.a
arch=(--target="$target" --sysroot="$sysroot" "${arch_flags[@]}" -fPIC)

mkdir -p "$prefix"/{bin,lib,include/c++}
mkdir -p "$prefix/sysroot"
cp -a "$sysroot/." "$prefix/sysroot/"
mkdir -p "$prefix/include/c++/v1"
cp -a "$runtime/include/c++/v1/." "$prefix/include/c++/v1/"
cp "$runtime/lib/"*.a "$prefix/lib/"
cp "$builtins" "$prefix/lib/"
clang-21 "${arch[@]}" -fvisibility=hidden \
    -c "$repo/scripts/build/qt4-android/crt-donut.c" -o "$prefix/lib/crt-android.o"
clang-21 "${arch[@]}" -fno-builtin \
    -c "$repo/scripts/build/qt5-android/compat.c" -o "$prefix/lib/android-compat.o"
# Bionic's tmpfile ignores the APK-private TMPDIR. Reuse the shared legacy
# adapter; compiler-driver wrapping redirects consumers without changing tests.
clang-21 "${arch[@]}" \
    -c "$repo/scripts/build/qt4-android/tmpfile-donut.c" -o "$prefix/lib/tmpfile-android.o"
atomic_objects=()
if [[ "$abi" == x86 ]]; then
    clang-21 "${arch[@]}" -O2 -D_LIBATOMIC_USE_PTHREAD -fvisibility=default \
        -c /work/android-llvm/llvm-project-21.1.8.src/compiler-rt/lib/builtins/atomic.c \
        -o "$prefix/lib/atomic-android.o"
    atomic_objects=("$prefix/lib/atomic-android.o")
fi
clang++-21 "${arch[@]}" \
    -fuse-ld=lld -shared -nostdlib -Wl,--hash-style=sysv,--no-undefined,--no-dependent-libraries,-soname,libc++_shared.so \
    "${atomic_objects[@]}" "$prefix/lib/crt-android.o" "$prefix/lib/android-compat.o" "$prefix/lib/tmpfile-android.o" -Wl,--whole-archive \
    "$runtime/lib/libc++.a" "$runtime/lib/libc++experimental.a" "$runtime/lib/libc++abi.a" \
    "$runtime/lib/libunwind.a" "$builtins" -Wl,--no-whole-archive \
    -L"$sysroot/usr/lib" -llog -ldl -lm -lc -o "$prefix/lib/libc++_shared.so"

{ declare -p abi target ndk_triple builtins_arch arch_flags; } > "$prefix/target.sh"
cp "$repo/scripts/build/qt5-android/clang-wrapper.sh" "$prefix/bin/cxx"
ln -sf cxx "$prefix/bin/cc"
chmod +x "$prefix/bin/cxx"

ndk="$prefix/ndk"

cpufeatures="$repo/downloads/android-gingerbread/aosp-cpufeatures-android-4.0.3-r1.tar.gz"
echo 'cc8fffee51a932dd6329a57dceedc448d46173c2135da98f52010e82ba296a0e  '"$cpufeatures" | sha256sum -c -
mkdir -p "$ndk/sources/android/cpufeatures"
tar -xzf "$cpufeatures" -C "$ndk/sources/android/cpufeatures"

toolchain="$ndk/toolchains/llvm/prebuilt/linux-x86_64"
mkdir -p "$toolchain/bin" "$ndk/platforms/android-10"
ln -sfnT "$prefix/sysroot" "$toolchain/sysroot"
ln -sfnT "$prefix/sysroot" "$ndk/platforms/android-10/arch-$ndk_arch"
ln -sfnT "$prefix/bin/cc" "$toolchain/bin/clang"
ln -sfnT "$prefix/bin/cxx" "$toolchain/bin/clang++"
for tool in ar ranlib strip objcopy nm readobj readelf objdump; do
    ln -sfnT "/usr/bin/llvm-$tool-21" "$toolchain/bin/llvm-$tool"
done
mkdir -p "$prefix/sysroot/usr/lib/$ndk_triple"
ln -sfnT "$prefix/lib/libc++_shared.so" "$prefix/sysroot/usr/lib/$ndk_triple/libc++_shared.so"
cat >"$ndk/source.properties" <<'EOF'
Pkg.Desc = Longreach upstream LLVM 21.1.8 Android toolchain with the AOSP NDK r7 sysroot
Pkg.Revision = 21.1.8
EOF
llvm-readobj-21 --file-header --dynamic-table "$prefix/lib/libc++_shared.so" > "$prefix/runtime-elf.txt"
llvm-nm-21 --dynamic --defined-only "$prefix/lib/libc++_shared.so" > "$prefix/runtime-exports.txt"
