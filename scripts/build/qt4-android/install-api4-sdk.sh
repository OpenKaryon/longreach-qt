#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2026 OpenKaryon
set -euo pipefail
tree=/work/qt4-donut-quick
installed=/work/qtquick-donut-sdk
prefix=/opt/qt4-android-armeabi-llvm
runtime=/opt/longreach-android-api4
test ! -e "$prefix"
test ! -e "$runtime"
for module in corelib network gui sql xml svg script declarative; do
    make -C "$tree/src/$module" install
done
for module in folderlistmodel gestures particles; do
    make -C "$tree/src/imports/$module" install
done
make -C "$tree/src/plugins/platforms/minimal" install
make -C "$tree/src/plugins/imageformats/svg" install
mkdir -p "$prefix" "$runtime/lib" "$runtime/include/c++" "$runtime/bin"
cp -aL "$installed/." "$prefix/"
mkdir -p "$prefix/bin" "$prefix/longreach-reports" "$prefix/licenses"
for tool in qmake moc rcc uic; do
    cp "$tree/bin/$tool" "$prefix/bin/$tool"
done
cp -aL /work/sysroot-api4 "$runtime/sysroot"
cp -aL /work/runtime-build/include/c++/v1 "$runtime/include/c++/v1"
for name in libc++.a libc++abi.a libc++experimental.a libunwind.a; do
    cp "/work/runtime-build/lib/$name" "$runtime/lib/"
done
cp /work/builtins-build/compiler-rt/lib/linux/libclang_rt.builtins-arm-android.a "$runtime/lib/"
for name in crt-donut armv5-compat tmpfile-donut; do
    cp "/work/apks/$name.o" "$runtime/lib/"
done
cat >"$runtime/target.sh" <<'EOF'
target=armv5te-linux-androideabi4
arch_flags=(-march=armv5te -mfloat-abi=soft)
EOF
for name in cc cxx; do
    cp /repo/scripts/build/qt4-android/api4-clang-wrapper.sh "$runtime/bin/$name"
    chmod +x "$runtime/bin/$name"
done
printf '[Paths]\nPrefix=%s\n' "$prefix" >"$prefix/bin/qt.conf"
python3 /repo/scripts/build/qt4-android/export-mkspecs.py export --source "$tree" --prefix "$prefix" --runtime "$runtime"
mkdir -p "$prefix/libexec/api4-sdk"
for name in api4-sdk.py sdk-provenance.py export-mkspecs.py prepare-source.py; do
    cp "/repo/scripts/build/qt4-android/$name" "$prefix/libexec/api4-sdk/"
done
python3 /repo/scripts/build/qt4-android/api4-sdk.py normalize-metadata --prefix "$prefix" --runtime "$runtime"
"$prefix/bin/qmake" -query >"$prefix/longreach-reports/qmake-query.txt"
cp "$tree"/LICENSE* "$tree/LGPL_EXCEPTION.txt" "$prefix/licenses/"
for component in libcxx libcxxabi libunwind compiler-rt; do
    cp "/work/llvm-project-21.1.8.src/$component/LICENSE.TXT" "$prefix/licenses/LLVM-$component-LICENSE.TXT"
done
python3 /repo/scripts/build/qt4-android/api4-sdk.py seal --prefix "$prefix" --runtime "$runtime"
