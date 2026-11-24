#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-or-later
set -euo pipefail
cache_lock=/repo/scripts/build/qt4-android/client-cache-lock.py
if [[ "${LONGREACH_QT4_CLIENT_CACHE_HELD:-}" != 1 ]]; then
    exec python3 "$cache_lock" --root /work -- bash "$0" "$@"
fi
python3 "$cache_lock" --root /work --verify-inherited
source /repo/scripts/build/qt4-android/target-config.sh
[[ "$api" == 10 || "$api" == 21 ]] || { echo 'This client producer requires API10 or API21' >&2; exit 1; }
phase=${1:-core}
case "$phase" in
    core) installed_prefix=$core_prefix ;;
    all) installed_prefix=$quick_prefix ;;
    *) echo "Unknown Qt4 example phase: $phase" >&2; exit 1 ;;
esac
# Refuse stale/default build-tree specs before the first native command or copy.
python3 "$installed_prefix/libexec/longreach-export-mkspecs.py" verify \
    --prefix "$installed_prefix" --runtime "$runtime"
cxx=$runtime/bin/cxx
mkdir -p /out /work/qt4-android-$abi/clients
cp "$runtime/lib/libc++_shared.so" /out/
if [[ "$phase" == core ]]; then
    "$cxx" -O2 -std=c++23 -fexperimental-library -shared \
        -I/repo/scripts/tests/qt6-llvm-probes /repo/tests/android-donut/strict-jni.cpp -o /out/strict.so
    client=/work/qt4-android-$abi/clients/core
    mkdir -p "$client"
    cd "$client"
    cat >core.pro <<'EOF'
TEMPLATE = lib
TARGET = core
CONFIG += dll release
CONFIG -= staticlib
QT = core
SOURCES = /repo/tests/android-donut/qtcore-jni.cpp
QMAKE_CXXFLAGS += -std=gnu++23 -fexperimental-library
QMAKE_LFLAGS += -Wl,--exclude-libs,ALL,-soname,libdonut_probe.so
EOF
    python3 /repo/scripts/build/qt4-android/cache-inputs.py --runtime "$runtime" \
        --mkspec "$core_prefix/mkspecs/android-longreach-clang" --prefix "$core_prefix" \
        --client-project "$client/core.pro" --profile core --abi "$abi" --jobs "${PARALLEL_JOBS:-2}"
    cp libcore.so /out/core.so
    llvm-readobj-21 --file-header --dynamic-table /out/core.so > /out/core-elf.txt
    echo 'Qt4 core client built through the installed SDK qmake in C++23'
elif [[ "$phase" == all ]]; then
    python3 /repo/scripts/build/qt4-android/build-api21-examples.py --prefix "$quick_prefix" --output /out
else
    echo "Unknown Qt4 example phase: $phase" >&2
    exit 1
fi
