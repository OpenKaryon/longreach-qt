#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-or-later

set -euo pipefail
source /repo/scripts/build/qt6-android/target-config.sh
build=/work/api21/qt-sdk-build
prefix=$sdk_prefix
export JAVA_HOME=/usr/lib/jvm/java-17-openjdk-amd64
export PATH="$JAVA_HOME/bin:$PATH"
export LANG=C.UTF-8 LC_ALL=C.UTF-8
report=/out/sdk-reports
rm -rf -- "$report"
mkdir -p "$report"
cp "$build/config.summary" "$report/qt-sdk-config.summary"
cp /work/api21/qt-src/.longreach-patches.json "$report/qt-patch-state.json"
find "$prefix/lib" -maxdepth 1 -type f -name 'libQt6*.so' -printf '%f\n' | sort > "$report/sdk-modules.txt"
python3 /repo/scripts/build/qt6-android/validate-api21-elf.py "$prefix" --abi "$abi" --report "$report/sdk-api21-elf.json"
ANDROID_ABI="$abi" python3 /repo/scripts/build/qt6-android/input-provenance.py
cp /out/platform-input-provenance.json "$report/"
"$prefix/bin/qmake" -query > "$report/sdk-qmake-query.txt"
test "$("$prefix/bin/qmake" -query QT_VERSION)" = 6.8.5
test "$("$prefix/bin/qmake" -query QT_INSTALL_PREFIX)" = "$prefix"
/opt/longreach-android-api21/bin/cxx --version > "$report/sdk-compiler-version.txt"
grep -q '21.1.8' "$report/sdk-compiler-version.txt"
mkdir -p /out/sdk-packaging/{jar,src/android} "$report/sdk-java-audit"
cp -a "$prefix/src/android/java" /out/sdk-packaging/src/android/
cp "$prefix/jar/"*.jar /out/sdk-packaging/jar/
cp "$prefix/jar/"*.jar "$report/sdk-java-audit"/
test "$(find "$prefix/jar" -maxdepth 1 -name '*.jar' | wc -l)" -eq 10
cp /opt/longreach-android-api21/lib/libc++_shared.so /out/libc++_shared.so
sha256sum /opt/longreach-android-api21/lib/libc++_shared.so > "$report/runtime-sha256.txt"
llvm-readobj-21 --file-header --dynamic-table /opt/longreach-android-api21/lib/libc++_shared.so > "$report/runtime-elf.txt"
source /repo/scripts/build/android-api21/generic-atomics.sh
check_android_generic_atomic_exports /opt/longreach-android-api21/lib/libc++_shared.so "$report/runtime-atomic-exports.txt"
python3 /repo/scripts/build/android-api21/sdk-reports.py seal --source "$report" --qt-major 6 --abi "$abi"
echo 'Full SDK installed, checked, and staged for host APK packaging'
