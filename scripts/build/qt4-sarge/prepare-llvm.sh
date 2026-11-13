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
for patch in /src/patches/llvm/{linux-lucid,linux-sarge}/*.patch; do
    (cd "$LLVM_BUILD_ROOT/source" && git apply "$patch")
done
bash /src/scripts/build/qt6-llvm-probes/build-runtime.sh linux-sarge-i386
