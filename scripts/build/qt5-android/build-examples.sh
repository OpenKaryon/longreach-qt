#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-or-later

set -euo pipefail
repo=${REPO_ROOT:-/repo}
build=${EXAMPLES_BUILD_DIR:-/work/tests-qt5-android}
output=${DEPLOYMENT_OUTPUT_DIR:-/out/deployment}
export ANDROID_SDK_ROOT=${ANDROID_SDK_ROOT:-/work/android-sdk}
cmake -S "$repo/tests" -B "$build" -G Ninja \
    -DCMAKE_TOOLCHAIN_FILE="$repo/scripts/build/qt5-android/toolchain.cmake" \
    -DCMAKE_BUILD_TYPE=Release -DCMAKE_CXX_STANDARD=23 -DSMOKE_REQUIRE_CXX23=ON \
    -DSMOKE_ANDROID_SELFTEST_PROFILE=core
while IFS= read -r app || [[ -n "$app" ]]; do
    app=${app%$'\r'}
    case "$app" in
        ""|"#"*|smoke-runner) continue ;;
    esac
    cmake --build "$build" --target "$app" --parallel "${PARALLEL_JOBS:-2}"
    python3 "$repo/scripts/build/qt5-android/deploy-examples.py" \
        --repo "$repo" --build "$build" --android-sdk "$ANDROID_SDK_ROOT" --output "$output" \
        --apps "$app"
done < "$repo/tests/expected-apps.txt"

# Keep all remaining selftest groups below Gingerbread's 96-DSO limit.
# The native entry point and all checks still come from the shared sources.
extended="$build-extended"
cmake -S "$repo/tests" -B "$extended" -G Ninja \
    -DCMAKE_TOOLCHAIN_FILE="$repo/scripts/build/qt5-android/toolchain.cmake" \
    -DCMAKE_BUILD_TYPE=Release -DCMAKE_CXX_STANDARD=23 -DSMOKE_REQUIRE_CXX23=ON \
    -DSMOKE_ANDROID_SELFTEST_PROFILE=extended
cmake --build "$extended" --target qt-selftest --parallel "${PARALLEL_JOBS:-2}"
python3 "$repo/scripts/build/qt5-android/deploy-examples.py" \
    --repo "$repo" --build "$extended" --android-sdk "$ANDROID_SDK_ROOT" \
    --output "$output-extended" --apps qt-selftest
