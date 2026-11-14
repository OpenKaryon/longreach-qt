#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2026 OpenKaryon
set -euo pipefail
export LLVM_ROOT=/opt/llvm-21 LLVM_BUILD_ROOT=/work/sarge-llvm
archive=/src/llvm.tar.xz
echo "4633a23617fa31a3ea51242586ea7fb1da7140e426bd62fc164261fe036aa142  $archive" | sha256sum -c -
"$LLVM_ROOT/bin/clang" --version | grep -E '^clang version 21[.]1[.]8([[:space:]]|$)'
mkdir -p "$LLVM_BUILD_ROOT/source"
tar -xJf "$archive" -C "$LLVM_BUILD_ROOT/source" --strip-components=1
arch=${SARGE_ARCH:-i386}
patches=(/src/patches/llvm/linux-lucid/*.patch /src/patches/llvm/linux-sarge/0[2345]-*.patch)
if [ "$arch" = i386 ]; then
    patches+=(/src/patches/llvm/linux-sarge/01-compiler-rt-no-half.patch)
fi
for patch in "${patches[@]}"; do
    (cd "$LLVM_BUILD_ROOT/source" && git apply "$patch")
done
bash /src/scripts/build/qt6-llvm-probes/build-runtime.sh "linux-sarge-$arch"
