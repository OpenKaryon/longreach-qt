#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-or-later
set -euo pipefail
source /repo/scripts/build/qt5-android/target-config.sh
report=/out/qt5-sdk
rm -rf -- "$report"
mkdir -p "$report"
cp "$sdk_prefix/qt-config.summary" "$report/qt-sdk-config.summary"
cp /work/qt5-sdk-src/.longreach-patches.json "$report/qt-patch-state.json"
find "$sdk_prefix/lib" -maxdepth 1 -type f -name 'libQt5*.so' -printf '%f\n' | sort > "$report/sdk-modules.txt"
"$sdk_prefix/bin/qmake" -query > "$report/sdk-qmake-query.txt"
test "$("$sdk_prefix/bin/qmake" -query QT_VERSION)" = 5.15.19
test "$("$sdk_prefix/bin/qmake" -query QT_INSTALL_PREFIX)" = "$sdk_prefix"
/opt/longreach-android/bin/cxx --version > "$report/sdk-compiler-version.txt"
grep -q '21.1.8' "$report/sdk-compiler-version.txt"
sha256sum /opt/longreach-android/lib/libc++_shared.so > "$report/runtime-sha256.txt"
python3 /repo/scripts/build/qt6-android/validate-api21-elf.py "$sdk_prefix" --api "$api" --abi "$abi" --report "$report/sdk-api${api}-elf.json"
if [[ "$api" == 21 ]]; then
    python3 /repo/scripts/build/qt6-android/input-provenance.py
    cp /out/platform-input-provenance.json "$report/"
else
    cp /opt/longreach-android/runtime-input-provenance.json "$report/"
    python3 /repo/scripts/build/android-api21/check-api10-api21-symbols.py "$sdk_prefix" \
        --abi "$abi" --archive /inputs/android-ndk-r27-linux.zip \
        --lock /repo/scripts/fetch/locks/qt6-android-api21-inputs.json \
        --qt-wait-source /work/qt5-sdk-src/qtbase/src/corelib/thread/qwaitcondition_unix.cpp \
        --openssl-rand-source /tmp/openssl-build/providers/implementations/rands/seeding/rand_unix.c \
        --report "$report/sdk-api21-forward-symbols.json"
fi
llvm-readobj-21 --file-header --dynamic-table /opt/longreach-android/lib/libc++_shared.so > "$report/runtime-elf.txt"
source /repo/scripts/build/android-api21/generic-atomics.sh
check_android_generic_atomic_exports /opt/longreach-android/lib/libc++_shared.so "$report/runtime-atomic-exports.txt"
python3 /repo/scripts/build/android-api21/sdk-reports.py seal --source "$report" --qt-major 5 --abi "$abi"
echo "Qt5 $abi API$api installed SDK checks passed"
