#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2026 OpenKaryon
#
# Install a pinned CMake into a build image: Qt 5.15's CMake packages need 3.15
# or newer for their static plugin imports, and several images ship older ones.
#
#   binary  Kitware's release tarball, for x86_64 and aarch64
#   source  ./bootstrap && make, for i386 (about 4 minutes at -j4)
#
# Usage:
#   bash cmake.sh <version> [prefix]
#   CMAKE_BUILD_FROM_SOURCE=1 bash cmake.sh <version>
set -eu

version=${1:?usage: cmake.sh <version> [prefix]}
prefix=${2:-/opt/cmake}
jobs=${PARALLEL_JOBS:-$(nproc)}

# wget, or curl where the image has that instead.
if command -v wget >/dev/null 2>&1; then
    fetch() { wget -q "$1" -O "$2"; }
elif command -v curl >/dev/null 2>&1; then
    fetch() { curl -fsSL "$1" -o "$2"; }
else
    echo "cmake.sh: neither wget nor curl is installed in this image" >&2
    exit 1
fi

# The compiler's target, not uname: the i386 image runs on a 64-bit kernel.
host_triple=$(gcc -dumpmachine)
case "$host_triple" in
    x86_64-*)             binary_arch=x86_64  ;;
    aarch64-*|arm64-*)    binary_arch=aarch64 ;;
    *)                    binary_arch=""      ;;
esac

use_source=0
[ -z "$binary_arch" ] && use_source=1
[ "${CMAKE_BUILD_FROM_SOURCE:-0}" = 1 ] && use_source=1

echo "cmake.sh: version=$version host=$host_triple prefix=$prefix source=$use_source"

# The OpenKaryonLab copy of the file (scripts/fetch/sources.json). Kitware's
# release is on GitHub too, so it would be no fallback.
mirror=${LONGREACH_MIRROR:-https://github.com/OpenKaryonLab/longreach-qt-sources/releases/download/sources/}
release() {
    fetch "${mirror%/}/$1" "$2"
}

# Every archive is checked against Kitware's published SHA-256 list. Another
# version needs its own line here (from cmake-<version>-SHA-256.txt).
expected_sha256() {
    case "$1" in
        cmake-3.28.6-linux-x86_64.tar.gz)  echo 931e3c0d546ee03ca72bb147ccd9b49e3b6252f765f66bf21b9d165519940458 ;;
        cmake-3.28.6-linux-aarch64.tar.gz) echo 7909cc2128ce9442c63ce674a0bfb0e4f4ce04cef667d887e15ad5670d594ba7 ;;
        cmake-3.28.6.tar.gz)               echo c39c733900affc4eb0e9688b4d1a45435a732105d9bf9cc1e75dd2b9b81a36bb ;;
        *) echo "cmake.sh: no pinned SHA-256 for $1" >&2; exit 1 ;;
    esac
}
check() {
    sum=$(expected_sha256 "$1") || exit 1
    echo "$sum  $2" | sha256sum -c -
}

mkdir -p "$prefix"
cd /tmp

if [ "$use_source" = 0 ]; then
    archive="cmake-${version}-linux-${binary_arch}.tar.gz"
    echo "cmake.sh: fetching official binary $archive"
    release "$archive" cmake-bin.tar.gz
    check "$archive" cmake-bin.tar.gz
    tar -xzf cmake-bin.tar.gz -C "$prefix" --strip-components=1
    rm -f cmake-bin.tar.gz
else
    echo "cmake.sh: building from source"
    release "cmake-${version}.tar.gz" cmake-src.tar.gz
    check "cmake-${version}.tar.gz" cmake-src.tar.gz
    tar -xzf cmake-src.tar.gz
    cd "cmake-${version}"

    # CMake vendors its own curl, libarchive, expat and zlib; OpenSSL is off (no
    # https use here). CMake's tests and Qt dialog are off too, so a Qt already on
    # PATH is not picked up by its Tests/.
    ./bootstrap --parallel="$jobs" --prefix="$prefix" -- -DCMAKE_USE_OPENSSL=OFF \
        -DBUILD_TESTING=OFF -DBUILD_QtDialog=OFF \
        -DCMAKE_DISABLE_FIND_PACKAGE_Qt5Core=ON -DCMAKE_DISABLE_FIND_PACKAGE_Qt5Widgets=ON
    make -j"$jobs"
    make install
    cd /tmp
    rm -rf "cmake-${version}" cmake-src.tar.gz
fi

"$prefix/bin/cmake" --version | head -1

# A too-old CMake fails here, not in Qt's configure.
have=$("$prefix/bin/cmake" --version | head -1 | grep -oE '[0-9]+\.[0-9]+')
major=${have%%.*}
minor=${have##*.}
if [ "$major" -lt 3 ] || { [ "$major" -eq 3 ] && [ "$minor" -lt 15 ]; }; then
    echo "cmake.sh: $have is too old; Qt 5.15's static plugin import needs 3.15+" >&2
    exit 1
fi
