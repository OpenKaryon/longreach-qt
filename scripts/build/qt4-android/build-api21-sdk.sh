#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-or-later
set -euo pipefail
source /repo/scripts/build/qt4-android/target-config.sh
[[ "$api" == 10 || "$api" == 21 ]] || { echo 'This producer requires API10 or API21' >&2; exit 1; }
echo 'e2882295097e47fe089f8ac741a95fef47e0a73a3f3cdf21b56990638f626ea0  /inputs/qt-everywhere-opensource-src-4.8.7.tar.gz' | sha256sum -c -
phase=${1:-core}
case "$phase" in
    core) tree=$core_tree; prefix=$core_prefix ;;
    quick) tree=$quick_tree; prefix=$quick_prefix ;;
    *) echo "Unknown Qt4 SDK phase: $phase" >&2; exit 1 ;;
esac
bash /repo/scripts/build/qt4-android/build-qtcore.sh "$phase"
if [[ "$phase" == core ]]; then
    make -C "$tree/src/corelib" install
else
    for module in corelib network gui sql xml svg script declarative testlib multimedia opengl scripttools xmlpatterns qt3support; do
        make -C "$tree/src/$module" install
    done
    for module in folderlistmodel gestures particles shaders; do
        make -C "$tree/src/imports/$module" -j"${PARALLEL_JOBS:-2}"
        make -C "$tree/src/imports/$module" install
    done
    make -C "$tree/src/plugins/platforms/minimal" install
    make -C "$tree/src/plugins/imageformats/svg" -j"${PARALLEL_JOBS:-2}"
    make -C "$tree/src/plugins/imageformats/svg" install
fi
mkdir -p "$prefix/bin" /out/qt4-sdk
for tool in qmake moc rcc uic; do
    if [[ -f "$tree/bin/$tool" ]]; then cp "$tree/bin/$tool" "$prefix/bin/"; fi
done
# Export installed mkspecs independently of retained /work build wrappers.
python3 /repo/scripts/build/qt4-android/export-mkspecs.py export \
    --source "$tree" --prefix "$prefix" --runtime "$runtime"
cat > "$prefix/longreach-target.cmake" <<EOF
set(LONGREACH_ANDROID_API "$api")
set(LONGREACH_ANDROID_ABI "$abi")
set(LONGREACH_ANDROID_RUNTIME "$runtime")
EOF
"$prefix/bin/qmake" -query > /out/qt4-sdk/qmake-$phase.txt
test "$("$prefix/bin/qmake" -query QT_VERSION)" = 4.8.7
"$prefix/bin/qmake" -query QT_INSTALL_PREFIX | grep -Fx "$prefix"
llvm-readobj-21 --file-headers "$prefix/lib/libQtCore.a" > /out/qt4-sdk/qtcore-$phase-elf.txt
if [[ "$phase" == quick ]]; then
    python3 /repo/scripts/build/qt4-android/sdk-provenance.py --prefix "$prefix" --source "$tree" --output /out/qt4-sdk
    cp /repo/scripts/build/qt4-android/toolchain.cmake "$prefix/toolchain.cmake"
    rm -rf -- "$prefix/longreach-reports"
    mkdir -p "$prefix/longreach-reports" "$prefix/licenses"
    for report in sdk-modules.txt sdk-static-elf.json sdk-provenance.json; do
        cp "/out/qt4-sdk/$report" "$prefix/longreach-reports/"
    done
    cp /out/qt4-sdk/qmake-quick.txt "$prefix/longreach-reports/sdk-qmake-query.txt"
    sha256sum "$runtime/lib/libc++_shared.so" > "$prefix/longreach-reports/runtime-sha256.txt"
    "$runtime/bin/cxx" --version > "$prefix/longreach-reports/sdk-compiler-version.txt"
    if [[ "$api" == 10 ]]; then
        cp "$runtime/runtime-input-provenance.json" "$prefix/longreach-reports/"
    fi
    llvm-readobj-21 --file-header --dynamic-table "$runtime/lib/libc++_shared.so" > "$prefix/longreach-reports/runtime-elf.txt"
    source /repo/scripts/build/android-api21/generic-atomics.sh
    check_android_generic_atomic_exports "$runtime/lib/libc++_shared.so" "$prefix/longreach-reports/runtime-atomic-exports.txt"
    python3 /repo/scripts/build/android-api21/sdk-reports.py seal --source "$prefix/longreach-reports" --qt-major 4 --abi "$abi"
    cp "$tree"/LICENSE* "$tree/LGPL_EXCEPTION.txt" "$prefix/licenses/"
fi
echo "Qt4 $abi/API$api $phase SDK phase passed"

if [[ "$phase" == core ]]; then bash /repo/scripts/build/qt4-android/build-api21-examples.sh core; fi
