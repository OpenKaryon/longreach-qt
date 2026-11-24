#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-or-later

set -euo pipefail
source /repo/scripts/build/qt6-android/target-config.sh
repo=/repo
build=/work/api21/tests-qt6-android
prefix=$sdk_prefix
export JAVA_HOME=/usr/lib/jvm/java-17-openjdk-amd64
export PATH="$JAVA_HOME/bin:$PATH"
export LANG=C.UTF-8
export LC_ALL=C.UTF-8
python3 /repo/scripts/build/android-api21/sdk-reports.py export \
    --source /opt/longreach-reports --output /out --qt-major 6 --abi "$abi" --artifact-lease-held
cmake -S "$repo/tests" -B "$build" -G Ninja \
    -DCMAKE_TOOLCHAIN_FILE=/opt/longreach-android-api21/toolchain.cmake \
    -DCMAKE_PREFIX_PATH="$prefix" -DQT_HOST_PATH=/opt/qt6-host-llvm21 \
    -DCMAKE_BUILD_TYPE=Release -DCMAKE_CXX_STANDARD=23 \
    -DCMAKE_CXX_FLAGS=-fexperimental-library -DSMOKE_REQUIRE_CXX23=ON
while IFS= read -r app || [[ -n "$app" ]]; do
    app=${app%$'\r'}
    case "$app" in
        ""|"#"*|smoke-runner) continue ;;
    esac
    cmake --build "$build" --target "$app" --parallel "${PARALLEL_JOBS:-2}"
    python3 /repo/scripts/build/qt6-android/deploy-examples.py --app "$app" --build "$build" --output /out/deployment --abi "$abi"
done < "$repo/tests/expected-apps.txt"
# Java packaging inputs must come entirely from this SDK, including on rebuilds.
packaging=/out/sdk-packaging
if [[ -e "$packaging" || -L "$packaging" ]]; then
    if [[ -L "$packaging" || ! -d "$packaging" || ! -f "$packaging/.longreach-qt6-packaging" ]]; then
        echo "Refusing to replace an unowned packaging export: $packaging" >&2
        exit 1
    fi
    rm -rf -- "$packaging"
fi
cp -a /opt/longreach-packaging "$packaging"
cp /opt/longreach-android-api21/lib/libc++_shared.so /out/libc++_shared.so
touch "$packaging/.longreach-qt6-packaging"
