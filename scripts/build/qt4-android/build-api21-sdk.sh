#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-or-later
set -euo pipefail
source /repo/scripts/build/qt4-android/target-config.sh
[[ "$api" == 21 ]] || { echo 'This producer requires API21' >&2; exit 1; }
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
        make -C "$tree/src/imports/$module" -j2
        make -C "$tree/src/imports/$module" install
    done
    make -C "$tree/src/plugins/platforms/minimal" install
    make -C "$tree/src/plugins/imageformats/svg" -j2
    make -C "$tree/src/plugins/imageformats/svg" install
fi
mkdir -p "$prefix/bin" /out/qt4-sdk
for tool in qmake moc rcc uic; do
    if [[ -f "$tree/bin/$tool" ]]; then cp "$tree/bin/$tool" "$prefix/bin/"; fi
done
if [[ ! -d "$prefix/mkspecs" ]]; then cp -a "$tree/mkspecs" "$prefix/"; fi
for metadata in qconfig.pri qmodule.pri; do
    if [[ -f "$tree/mkspecs/$metadata" ]] && ! cmp -s "$tree/mkspecs/$metadata" "$prefix/mkspecs/$metadata"; then
        cp -p "$tree/mkspecs/$metadata" "$prefix/mkspecs/$metadata"
    fi
done
spec="$prefix/mkspecs/android-longreach-clang"
mkdir -p "$spec"
cp "$tree/mkspecs/linux-donut-llvm/qplatformdefs.h" "$spec/"
cat > "$spec/qmake.conf" <<'EOF'
include(../linux-g++/qmake.conf)
QMAKE_CC = /opt/longreach-android-api21/bin/cc -fgnu89-inline
QMAKE_CXX = /opt/longreach-android-api21/bin/cxx -DQT_NO_SHAREDMEMORY -DQT_NO_SYSTEMSEMAPHORE
QMAKE_LINK = $$QMAKE_CXX
QMAKE_LINK_SHLIB = $$QMAKE_CXX
QMAKE_AR = llvm-ar-21 cqs
QMAKE_RANLIB = llvm-ranlib-21
QMAKE_LIBS_THREAD =
QMAKE_CFLAGS_THREAD =
QMAKE_CXXFLAGS_THREAD =
DEFINES += QT_NO_LINUX_FUTEX
EOF
"$prefix/bin/qmake" -query > /out/qt4-sdk/qmake-$phase.txt
test "$("$prefix/bin/qmake" -query QT_VERSION)" = 4.8.7
"$prefix/bin/qmake" -query QT_INSTALL_PREFIX | grep -Fx "$prefix"
llvm-readobj-21 --file-headers "$prefix/lib/libQtCore.a" > /out/qt4-sdk/qtcore-$phase-elf.txt
if [[ "$phase" == quick ]]; then
    python3 /repo/scripts/build/qt4-android/sdk-provenance.py --prefix "$prefix" --source "$tree" --output /out/qt4-sdk
    cp /repo/scripts/build/qt4-android/toolchain.cmake "$prefix/toolchain.cmake"
    mkdir -p "$prefix/longreach-reports" "$prefix/licenses"
    for report in sdk-modules.txt sdk-static-elf.json sdk-provenance.json; do
        cp "/out/qt4-sdk/$report" "$prefix/longreach-reports/"
    done
    cp /out/qt4-sdk/qmake-quick.txt "$prefix/longreach-reports/sdk-qmake-query.txt"
    sha256sum "$runtime/lib/libc++_shared.so" > "$prefix/longreach-reports/runtime-sha256.txt"
    "$runtime/bin/cxx" --version > "$prefix/longreach-reports/sdk-compiler-version.txt"
    cp "$tree"/LICENSE* "$tree/LGPL_EXCEPTION.txt" "$prefix/licenses/"
fi
echo "Qt4 $abi/API$api $phase SDK phase passed"

if [[ "$phase" == core ]]; then bash /repo/scripts/build/qt4-android/build-api21-examples.sh core; fi
