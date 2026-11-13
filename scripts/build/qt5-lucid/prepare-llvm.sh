#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2026 OpenKaryon
set -euo pipefail

export LLVM_ROOT=/opt/llvm-21 LLVM_BUILD_ROOT=/work/llvm-lucid
archive=/src/llvm.tar.xz
echo "4633a23617fa31a3ea51242586ea7fb1da7140e426bd62fc164261fe036aa142  $archive" | sha256sum -c -
"$LLVM_ROOT/bin/clang" --version | grep -E '^clang version 21\.1\.8([[:space:]]|$)'
mkdir -p "$LLVM_BUILD_ROOT/source"
tar -xJf "$archive" -C "$LLVM_BUILD_ROOT/source" --strip-components=1
for patch in /src/patches/llvm/linux-lucid/*.patch; do
    (cd "$LLVM_BUILD_ROOT/source" && git apply "$patch")
done
target=linux-lucid-${LUCID_ARCH:?}
bash /src/scripts/build/qt6-llvm-probes/build-runtime.sh "$target"

runtime="$LLVM_BUILD_ROOT/runtimes/$target"
prefix=/opt/llvm-runtime-lucid
mkdir -p "$prefix/bin" "$prefix/share"
cp -a "$runtime"/{include,lib,resource} "$prefix/"
for pair in c:cc cxx:cxx; do
    wrapper="$prefix/bin/target-${pair#*:}"
    sed -e "s@$runtime@$prefix@g" \
        -e 's@-isystem /opt/sysroot-lucid/usr/include@-isystem /opt/sysroot-lucid/usr/local/include -isystem /opt/sysroot-lucid/usr/include@' \
        -e 's@-L/opt/sysroot-lucid/usr/lib@-L/opt/sysroot-lucid/usr/local/lib -L/opt/sysroot-lucid/usr/lib@' \
        "$runtime/bin/clang-${pair%:*}" > "$wrapper"
    chmod +x "$wrapper"
done
install -m 755 "/out/$target/cxx23-probe" "$prefix/share/cxx23-probe"
