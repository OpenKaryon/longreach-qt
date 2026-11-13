#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2026 OpenKaryon
set -euo pipefail

export LLVM_ROOT=/opt/llvm-21 LLVM_BUILD_ROOT=/work/llvm-xp
archive=/src/llvm.tar.xz
echo "4633a23617fa31a3ea51242586ea7fb1da7140e426bd62fc164261fe036aa142  $archive" | sha256sum -c -
"$LLVM_ROOT/bin/clang" --version | grep -E '^clang version 21\.1\.8([[:space:]]|$)'
mkdir -p "$LLVM_BUILD_ROOT/source"
tar -xJf "$archive" -C "$LLVM_BUILD_ROOT/source" --strip-components=1
for patch in /src/patches/llvm/windows-xp/*.patch; do
    (cd "$LLVM_BUILD_ROOT/source" && git apply "$patch")
done
target=windows-xp-${XP_ARCH:?}
bash /src/build-runtime.sh "$target"

runtime="$LLVM_BUILD_ROOT/runtimes/$target"
prefix=/opt/llvm-runtime-xp
bin="$prefix/bin"
tools=${XP_CROSS:?}
case "$XP_ARCH" in
    i386) windres_target=pe-i386; minimum=0x0501 ;;
    amd64) windres_target=pe-x86-64; minimum=0x0502 ;;
esac
mkdir -p "$bin" "$prefix/share"
cp -a "$runtime"/{include,lib,resource} "$prefix/"
for pair in c:clang cxx:clang++; do
    wrapper="$bin/$tools-${pair#*:}"
    sed -e "s@$runtime@$prefix@g" \
        -e 's@ -DWINVER=@ -D_POSIX_THREAD_SAFE_FUNCTIONS=200112L -DWINVER=@' \
        "$runtime/bin/clang-${pair%:*}" > "$wrapper"
    chmod +x "$wrapper"
done
for tool in ar nm objcopy objdump ranlib strip; do
    ln -s "$LLVM_ROOT/bin/llvm-$tool" "$bin/$tools-$tool"
done
cat > "$bin/$tools-windres" <<WRAPPER
#!/bin/bash
exec /opt/llvm-21/bin/llvm-windres --target=$windres_target --include-dir /opt/sysroot-xp/include \
    --define _WIN32_WINNT=$minimum --define WINVER=$minimum "\$@"
WRAPPER
chmod +x "$bin/$tools-windres"
install -m 755 "/out/$target/cxx23-probe.exe" "$prefix/share/cxx23-probe.exe"
install -m 644 "/out/$target/pe.log" "$prefix/share/cxx23-probe.pe.log"
