#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2026 OpenKaryon
set -euo pipefail

export LLVM_ROOT=/opt/llvm-21 LLVM_BUILD_ROOT=/work/win95-llvm
unset CC CXX
archive=/src/llvm.tar.xz
mingw_archive=/src/mingw-w64.tar.bz2
jobs=${PARALLEL_JOBS:-3}
echo "4633a23617fa31a3ea51242586ea7fb1da7140e426bd62fc164261fe036aa142  $archive" | sha256sum -c -
echo "89356a0aa8cf9f8b9dc8d92bc8dd01a131d4750c3acb30c6350a406316c42199  $mingw_archive" | sha256sum -c -
"$LLVM_ROOT/bin/clang" --version | grep -E '^clang version 21\.1\.8([[:space:]]|$)'

prefix=/opt/llvm-runtime-win95
mkdir -p "$prefix/bin"
cat > "$prefix/bin/i686-w64-mingw32-windres" <<'WRAPPER'
#!/bin/bash
exec /opt/llvm-21/bin/llvm-windres --target=pe-i386 --include-dir /opt/sysroot-xp/include \
    --define _WIN32_WINNT=0x0400 --define WINVER=0x0400 "$@"
WRAPPER
chmod +x "$prefix/bin/i686-w64-mingw32-windres"

mkdir -p "$LLVM_BUILD_ROOT/source" /work/winpthreads
tar -xJf "$archive" -C "$LLVM_BUILD_ROOT/source" --strip-components=1
for patch in /src/patches/llvm/{windows-xp,windows-95}/*.patch; do
    (cd "$LLVM_BUILD_ROOT/source" && git apply "$patch")
done
tar -xjf "$mingw_archive" -C /work/winpthreads --strip-components=3 \
    --wildcards '*/mingw-w64-libraries/winpthreads/*'
(
    cd /work/winpthreads
    patch -p1 --fuzz=0 < /src/patches/winpthreads/windows-95/01-osr2-threading.patch
    CC="$LLVM_ROOT/bin/clang --target=i686-w64-windows-gnu --sysroot=/opt/sysroot-xp" \
        AR="$LLVM_ROOT/bin/llvm-ar" RANLIB="$LLVM_ROOT/bin/llvm-ranlib" \
        RC="$prefix/bin/i686-w64-mingw32-windres" \
        CFLAGS="-O2 -march=pentium -mno-sse -mno-sse2 -D_WIN32_WINNT=0x0400 -DWINVER=0x0400" \
        LDFLAGS="-fuse-ld=lld" ./configure --host=i686-w64-mingw32 --disable-shared --enable-static
    make -j"$jobs"
    install -m644 libpthread.a /opt/sysroot-xp/lib/libpthread.a
    install -m644 libpthread.a /opt/sysroot-xp/lib/libwinpthread.a
)

target=windows-95-i386
bash /src/scripts/build/qt6-llvm-probes/build-runtime.sh "$target"
runtime="$LLVM_BUILD_ROOT/runtimes/$target"
mkdir -p "$prefix/bin" "$prefix/share/licenses"
cp -a "$runtime"/{include,lib,resource} "$prefix/"
install -m644 "$LLVM_BUILD_ROOT/source/LICENSE.TXT" "$prefix/share/licenses/LLVM-LICENSE.txt"
install -m644 /work/winpthreads/COPYING "$prefix/share/licenses/WINPTHREADS-LICENSE.txt"
for pair in c:clang cxx:clang++; do
    wrapper="$prefix/bin/i686-w64-mingw32-${pair#*:}"
    sed "s@$runtime@$prefix@g" "$runtime/bin/clang-${pair%:*}" > "$wrapper"
    chmod +x "$wrapper"
done
"$LLVM_ROOT/bin/llvm-strip" --strip-all "/out/$target/cxx23-probe.exe" -o "$prefix/share/cxx23-probe.exe"
