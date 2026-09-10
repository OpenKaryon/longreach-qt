#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2026 OpenKaryon
#
# Build tests/ against the installed Qt SDK with CMake and keep only the
# binaries. Run in the final stage, where the image holds just the toolchain
# and the installed SDK, so a successful build proves the SDK self-contained.
# CMake fails if an application of tests/expected-apps.txt cannot be built.
# Cross targets pass SMOKE_CMAKE_TOOLCHAIN; native ones SMOKE_OPENSSL_PREFIX.
set -eu

src=${1:-/tmp/qt-smoke-tests}
out=${2:-/opt/qt-smoke-bin}
qt_prefix=${SMOKE_QT_PREFIX:-/usr/local/Qt-5.15}
toolchain=${SMOKE_CMAKE_TOOLCHAIN:-}

# libQt5Network.prl names -lssl -lcrypto, which Qt5NetworkConfig.cmake
# resolves with find_library(); the cross targets name OpenSSL in their
# toolchain file, the native ones pass SMOKE_OPENSSL_PREFIX.
prefix_path="$qt_prefix"
if [ -n "${SMOKE_OPENSSL_PREFIX:-}" ]; then
    prefix_path="$prefix_path;${SMOKE_OPENSSL_PREFIX}"
fi

cmake_args=(
    -DCMAKE_BUILD_TYPE=Release
    -DCMAKE_PREFIX_PATH="$prefix_path"
    -DSMOKE_LICENSE_PROFILE="${SMOKE_LICENSE_PROFILE:-gpl-enabled}"
)
if [ -n "${SMOKE_OPENSSL_PREFIX:-}" ]; then
    cmake_args+=(-DCMAKE_LIBRARY_PATH="${SMOKE_OPENSSL_PREFIX}/lib64;${SMOKE_OPENSSL_PREFIX}/lib")
fi
if [ -n "$toolchain" ]; then
    test -f "$toolchain" || { echo "no such toolchain file: $toolchain" >&2; exit 2; }
    cmake_args+=(-DCMAKE_TOOLCHAIN_FILE="$toolchain")
fi

mkdir -p /tmp/smoke-build
cd /tmp/smoke-build
cmake "$src" "${cmake_args[@]}"
cmake --build . -j "${PARALLEL_JOBS:-$(nproc)}"

# Collect the binaries. `a.exe` is excluded because it is not one of ours: CMake
# leaves it behind from the compiler-identification try_compile, and it would
# otherwise be shipped as if it were part of the suite.
mkdir -p "$out"
find . -type f \
    \( -name '*.exe' -o \( -perm -u+x ! -name '*.*' \) \) \
    ! -name 'a.exe' ! -name 'a.out' \
    ! -path '*/CMakeFiles/*' \
    -exec cp {} "$out/" \;
ls -la "$out"

cd /
rm -rf "$src" /tmp/smoke-build
