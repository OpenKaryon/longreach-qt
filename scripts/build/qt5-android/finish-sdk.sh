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
# Host behavior supplements producer metadata; guest qualification stays separate.
host_checks=/out/host-regressions
mkdir -p "$host_checks"
python3 /repo/scripts/tests/android/qt5-android-condition-clock.py \
    /work/qt5-sdk-src/qtbase/src/corelib/thread/qwaitcondition_unix.cpp "$host_checks/clock"
python3 /repo/scripts/tests/android/qt5-android-sensor-callback.py \
    /work/qt5-sdk-src/qtsensors/src/plugins/sensors/android/sensoreventqueue.h "$host_checks/sensors" \
    --manager /work/qt5-sdk-src/qtsensors/src/plugins/sensors/android/sensormanager.cpp
if [[ "$abi" == x86 && "$api" == 10 ]]; then
    python3 /repo/scripts/tests/android/qt5-android-futex.py \
        /repo/patches/qt5/android/x86/01-api10-futex-stub.patch "$host_checks/futex"
    bash /repo/scripts/tests/android/test-qt5-api10-x86-compat.sh "$host_checks/wait4"
fi
echo "Qt5 $abi API$api installed SDK checks passed"
