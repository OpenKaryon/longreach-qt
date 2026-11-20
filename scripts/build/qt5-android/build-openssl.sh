#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-or-later

set -euo pipefail
repo=${REPO_ROOT:-/repo}
source "$repo/scripts/build/qt5-android/target-config.sh"
archive="$repo/downloads/openssl-3.5.7.tar.gz"
echo 'a8c0d28a529ca480f9f36cf5792e2cd21984552a3c8e4aa11a24aa31aeac98e8  '"$archive" | sha256sum -c -
CC=/opt/longreach-android/bin/cc AR=llvm-ar-21 RANLIB=llvm-ranlib-21 \
    PARALLEL_JOBS="${PARALLEL_JOBS:-2}" \
    bash "$repo/scripts/build/openssl.sh" "$archive" "$openssl_target" "$openssl_prefix" \
        no-asm no-async no-tests no-shared no-module no-apps --libdir=lib
test -s "$openssl_prefix/lib/libssl.a"
test -s "$openssl_prefix/lib/libcrypto.a"