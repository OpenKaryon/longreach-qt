#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2026 OpenKaryon
set -euo pipefail

archive=${1:-/src/downloads/llvm-project-21.1.8.src.tar.xz}
work=${LLVM_BUILD_ROOT:-/work}
export LLVM_ROOT=${LLVM_ROOT:-/opt/llvm-21}
export LLVM_BUILD_ROOT="$work"
echo '4633a23617fa31a3ea51242586ea7fb1da7140e426bd62fc164261fe036aa142  '"$archive" | sha256sum -c -
mkdir -p "$work/source" /out
if [ ! -f "$work/source/llvm/CMakeLists.txt" ]; then
    tar -xJf "$archive" -C "$work/source" --strip-components=1
fi
"$LLVM_ROOT/bin/clang" --version | head -1 | grep -F '21.1.8'
bash /src/scripts/build/qt6-llvm-probes/build-runtime.sh linux-amd64

# Install the tested runtime alongside the shared compiler, so no consumer
# depends on the work volume or its generated probe wrappers.
runtime="$work/runtimes/linux-amd64"
cp -a "$runtime/include/." "$LLVM_ROOT/include/"
cp -a "$runtime/lib/." "$LLVM_ROOT/lib/"
cp -a "$runtime/resource/." "$LLVM_ROOT/lib/clang/21/"
mkdir -p /opt/longreach-llvm/bin
install -m 755 /src/scripts/build/qt6-linux-amd64/clang-c \
    /src/scripts/build/qt6-linux-amd64/clang-cxx /opt/longreach-llvm/bin/

/opt/longreach-llvm/bin/clang-cxx -std=c++23 -O2 -Wall -Wextra -Werror \
    /src/scripts/tests/qt6-llvm-probes/main.cpp -o /out/toolchain-cxx23
timeout 60 /out/toolchain-cxx23 | tee /out/toolchain-cxx23.log
python3 /src/scripts/tests/require-modern-cpp.py /out/toolchain-cxx23.log
python3 /src/scripts/build/qt5-lucid/max-glibc.py /out/toolchain-cxx23 2.17
