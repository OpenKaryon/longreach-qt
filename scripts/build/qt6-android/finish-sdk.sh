#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-or-later

set -euo pipefail
build=/work/api21/qt-sdk-build
prefix=/opt/qt6-android-armeabi-v7a-llvm
export JAVA_HOME=/usr/lib/jvm/java-17-openjdk-amd64
export PATH="$JAVA_HOME/bin:$PATH"
export LANG=C.UTF-8 LC_ALL=C.UTF-8
mkdir -p /out
cp "$build/config.summary" /out/qt-sdk-config.summary
find "$prefix/lib" -maxdepth 1 -type f -name 'libQt6*.so' -printf '%f\n' | sort > /out/sdk-modules.txt
python3 /repo/scripts/build/qt6-android/validate-api21-elf.py "$prefix" --report /out/sdk-api21-elf.json
python3 /repo/scripts/build/qt6-android/input-provenance.py
"$prefix/bin/qmake" -query > /out/sdk-qmake-query.txt
test "$("$prefix/bin/qmake" -query QT_VERSION)" = 6.8.5
test "$("$prefix/bin/qmake" -query QT_INSTALL_PREFIX)" = "$prefix"
/opt/longreach-android-api21/bin/cxx --version > /out/sdk-compiler-version.txt
grep -q '21.1.8' /out/sdk-compiler-version.txt
mkdir -p /out/sdk-packaging/{jar,src/android} /out/sdk-java-audit
cp -a "$prefix/src/android/java" /out/sdk-packaging/src/android/
cp "$prefix/jar/"*.jar /out/sdk-packaging/jar/
cp "$prefix/jar/"*.jar /out/sdk-java-audit/
test "$(find "$prefix/jar" -maxdepth 1 -name '*.jar' | wc -l)" -eq 10
cp /opt/longreach-android-api21/lib/libc++_shared.so /out/libc++_shared.so
echo 'Full SDK installed, checked, and staged for host APK packaging'
