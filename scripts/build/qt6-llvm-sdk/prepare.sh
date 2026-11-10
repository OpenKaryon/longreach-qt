#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2026 OpenKaryon
set -euo pipefail
target=${1:?target required}
test "$target" = linux-arm64
export LLVM_ROOT=/opt/llvm-21 LLVM_BUILD_ROOT=/work LLVM_BUILD_VARIANT=sdk
archive=/src/downloads/llvm-project-21.1.8.src.tar.xz
echo '4633a23617fa31a3ea51242586ea7fb1da7140e426bd62fc164261fe036aa142  '"$archive" | sha256sum -c -
mkdir -p /work/source
if [ ! -f /work/source/llvm/CMakeLists.txt ]; then
    tar -xJf "$archive" -C /work/source --strip-components=1
fi
bash /src/scripts/build/qt6-llvm-probes/build-runtime.sh "$target"
mkdir -p /opt/llvm-runtime-21
cp -a "/work/runtimes/$target/." /opt/llvm-runtime-21/
mkdir -p /opt/longreach-llvm/bin /opt/longreach-llvm/cmake
for item in cc cxx; do
    source_name=c
    if [ "$item" = cxx ]; then source_name=cxx; fi
    sed "s#/work/runtimes/$target#/opt/llvm-runtime-21#g" \
        "/work/runtimes/$target/bin/clang-$source_name" > "/opt/longreach-llvm/bin/target-$item"
    chmod +x "/opt/longreach-llvm/bin/target-$item"
done
cp "/src/scripts/build/qt6-llvm-sdk/$target.cmake" /opt/longreach-llvm/cmake/toolchain.cmake
for tool in moc rcc qsb qmlcachegen qmltyperegistrar; do
    binary="/opt/qt6-host-llvm21/libexec/$tool"
    if [ ! -f "$binary" ]; then binary="/opt/qt6-host-llvm21/bin/$tool"; fi
    test -f "$binary"
    ldd "$binary" > "/out/host-$tool-dependencies.log"
    if grep -F 'not found' "/out/host-$tool-dependencies.log"; then exit 1; fi
done
/opt/longreach-llvm/bin/target-cxx -std=c++23 -O2 \
    /src/scripts/tests/qt6-llvm-probes/main.cpp -o /out/installed-toolchain-cxx23
timeout 60 env -u LD_LIBRARY_PATH qemu-aarch64-static -L /opt/sysroot-arm64 \
    /out/installed-toolchain-cxx23 | tee /out/installed-toolchain-cxx23.log
python3 /src/scripts/tests/require-modern-cpp.py /out/installed-toolchain-cxx23.log
