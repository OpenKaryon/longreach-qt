#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-or-later

set -euo pipefail
source=/work/api21/openssl-3.5.7
prefix=/opt/openssl-api21
archive=/repo/downloads/openssl-3.5.7.tar.gz
echo 'a8c0d28a529ca480f9f36cf5792e2cd21984552a3c8e4aa11a24aa31aeac98e8  '"$archive" | sha256sum -c -
if [[ ! -f "$source/Configure" ]]; then
    tar -xzf "$archive" -C /work/api21
fi
export CC=/opt/longreach-android-api21/bin/cc
export AR=/usr/bin/llvm-ar-21
export RANLIB=/usr/bin/llvm-ranlib-21
export ANDROID_NDK_ROOT=/opt/longreach-android-api21/ndk
export PATH="$ANDROID_NDK_ROOT/toolchains/llvm/prebuilt/linux-x86_64/bin:$PATH"
cd "$source"
./Configure android-arm no-async no-shared no-tests no-module no-apps \
    -D__ANDROID_API__=21 -fPIC --prefix="$prefix" --libdir=lib
make -j"${PARALLEL_JOBS:-2}"
make install_sw
