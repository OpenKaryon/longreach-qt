#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2026 OpenKaryon
set -euo pipefail

archive=${1:-/src/downloads/llvm-project-21.1.8.src.tar.xz}
work=${LLVM_BUILD_ROOT:-/work}
prefix=${LLVM_ROOT:-/opt/llvm-21}
jobs=${PARALLEL_JOBS:-4}

echo '4633a23617fa31a3ea51242586ea7fb1da7140e426bd62fc164261fe036aa142  '"$archive" | sha256sum -c -
mkdir -p "$work/source"
if [ ! -f "$work/source/llvm/CMakeLists.txt" ]; then
    tar -xJf "$archive" -C "$work/source" --strip-components=1
fi

cmake -S "$work/source/llvm" -B "$work/compiler" -G Ninja \
    -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_C_FLAGS_RELEASE='-O2 -DNDEBUG' \
    -DCMAKE_CXX_FLAGS_RELEASE='-O2 -DNDEBUG' \
    -DCMAKE_INSTALL_PREFIX="$prefix" \
    -DLLVM_ENABLE_PROJECTS='clang;lld' \
    -DLLVM_TARGETS_TO_BUILD='X86;AArch64' \
    -DLLVM_DISTRIBUTION_COMPONENTS='clang;clang-resource-headers;lld;llvm-ar;llvm-ranlib;llvm-nm;llvm-objcopy;llvm-strip;llvm-objdump;llvm-readobj;llvm-rc;llvm-cvtres' \
    -DLLVM_PARALLEL_LINK_JOBS=1 \
    -DLLVM_INCLUDE_TESTS=OFF -DCLANG_INCLUDE_TESTS=OFF \
    -DLLVM_INCLUDE_EXAMPLES=OFF -DLLVM_INCLUDE_BENCHMARKS=OFF \
    -DLLVM_INCLUDE_DOCS=OFF -DLLVM_ENABLE_TERMINFO=OFF \
    -DLLVM_ENABLE_LIBEDIT=OFF -DLLVM_ENABLE_LIBXML2=OFF \
    -DLLVM_ENABLE_ZLIB=OFF -DLLVM_ENABLE_ZSTD=OFF
cmake --build "$work/compiler" --target distribution --parallel "$jobs"
cmake --build "$work/compiler" --target install-distribution --parallel 1
ln -sf llvm-ar "$prefix/bin/llvm-dlltool"
ln -sf llvm-rc "$prefix/bin/llvm-windres"
"$prefix/bin/clang" --version
