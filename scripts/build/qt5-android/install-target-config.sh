#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-or-later
set -euo pipefail
source /repo/scripts/build/qt5-android/target-config.sh
prefix=/opt/longreach-android
cat > "$prefix/qt5-target.cmake" <<EOF
set(LONGREACH_ANDROID_ABI "$abi")
set(LONGREACH_ANDROID_API "$api")
set(LONGREACH_ANDROID_PROCESSOR "$processor")
set(LONGREACH_ANDROID_NDK_TRIPLE "$ndk_triple")
set(LONGREACH_QT_PREFIX "$sdk_prefix")
EOF
if [[ "$api" == 21 ]]; then
    # The common API21 external toolchain also searches this Qt generation.
    sed -i "s|/opt/qt6-android-${abi}-llvm|$sdk_prefix|g" "$prefix/target.cmake" "$prefix/target.sh"
fi
