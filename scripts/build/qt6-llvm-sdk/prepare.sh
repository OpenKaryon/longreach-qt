#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2026 OpenKaryon
set -euo pipefail
target=${1:?target required}
case "$target" in
    linux-arm64|windows-amd64|windows-arm64) ;;
    *) exit 2 ;;
esac
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
    sed -e "s#/work/runtimes/$target#/opt/llvm-runtime-21#g" \
        -e "s#/work/sysroots/mingw13/$target#/opt/llvm-sysroot-21#g" \
        "/work/runtimes/$target/bin/clang-$source_name" > "/opt/longreach-llvm/bin/target-$item"
    chmod +x "/opt/longreach-llvm/bin/target-$item"
done
if [[ "$target" = windows-* ]]; then
    case "$target" in
        windows-amd64) arch=amd64; processor=x86_64; version=6.1; pe=pe-x86-64 ;;
        windows-arm64) arch=arm64; processor=aarch64; version=10.0; pe=aarch64-w64-windows-gnu ;;
    esac
    triple=$processor-w64-windows-gnu
    mingw=$processor-w64-mingw32
    mkdir -p /opt/llvm-sysroot-21
    cp -a "/work/sysroots/mingw13/$target/." /opt/llvm-sysroot-21/
    sed -e "s/@ARCH@/$arch/g" -e "s/@PROCESSOR@/$processor/g" \
        -e "s/@VERSION@/$version/g" -e "s/@TRIPLE@/$triple/g" \
        /src/scripts/build/qt6-llvm-sdk/windows-toolchain.cmake.in \
        > /opt/longreach-llvm/cmake/toolchain.cmake
    cat > /opt/longreach-llvm/bin/target-windres <<EOF
#!/bin/sh
exec /opt/llvm-21/bin/llvm-windres --target=$pe \
    --preprocessor=/opt/longreach-llvm/bin/target-cc \
    --preprocessor-arg=-E --preprocessor-arg=-xc --preprocessor-arg=-DRC_INVOKED "\$@"
EOF
    chmod +x /opt/longreach-llvm/bin/target-windres
    ln -sfn target-cc "/opt/longreach-llvm/bin/$mingw-clang"
    ln -sfn target-cxx "/opt/longreach-llvm/bin/$mingw-clang++"
    ln -sfn target-windres "/opt/longreach-llvm/bin/$mingw-windres"
    for tool in ar ranlib nm strip objcopy objdump; do
        ln -sfn "/opt/llvm-21/bin/llvm-$tool" "/opt/longreach-llvm/bin/$mingw-$tool"
    done
else
    cp "/src/scripts/build/qt6-llvm-sdk/$target.cmake" /opt/longreach-llvm/cmake/toolchain.cmake
fi
for tool in moc rcc qsb qmlcachegen qmltyperegistrar; do
    binary="/opt/qt6-host-llvm21/libexec/$tool"
    if [ ! -f "$binary" ]; then binary="/opt/qt6-host-llvm21/bin/$tool"; fi
    test -f "$binary"
    ldd "$binary" > "/out/host-$tool-dependencies.log"
    if grep -F 'not found' "/out/host-$tool-dependencies.log"; then exit 1; fi
done
if [[ "$target" = windows-* ]]; then
    cat > /tmp/toolchain-version.rc <<'EOF'
#include <windows.h>
1 RCDATA { 21, 1, 8 }
EOF
    /opt/longreach-llvm/bin/target-windres --input=/tmp/toolchain-version.rc \
        --output=/tmp/toolchain-version.o --output-format=coff
    /opt/longreach-llvm/bin/target-cxx -std=c++23 -O2 \
        /src/scripts/tests/qt6-llvm-probes/main.cpp /tmp/toolchain-version.o \
        -o /out/installed-toolchain-cxx23.exe
    /opt/llvm-21/bin/llvm-readobj --file-headers --coff-imports \
        /out/installed-toolchain-cxx23.exe > /out/installed-toolchain-dependencies.log
    if [ "$target" = windows-amd64 ]; then
        PATH=/opt/llvm-21/bin:$PATH bash /src/scripts/audit/qt6-win7-audit.sh /out/installed-toolchain-cxx23.exe
    fi
else
    /opt/longreach-llvm/bin/target-cxx -std=c++23 -O2 \
        /src/scripts/tests/qt6-llvm-probes/main.cpp -o /out/installed-toolchain-cxx23
    timeout 60 env -u LD_LIBRARY_PATH qemu-aarch64-static -L /opt/sysroot-arm64 \
        /out/installed-toolchain-cxx23 | tee /out/installed-toolchain-cxx23.log
    python3 /src/scripts/tests/require-modern-cpp.py /out/installed-toolchain-cxx23.log
fi
