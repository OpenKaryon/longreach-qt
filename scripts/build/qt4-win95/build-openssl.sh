#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2026 OpenKaryon
set -euo pipefail

archive=/src/openssl.tar.gz
prefix=/opt/openssl-1.0.2u
echo "ecd0c6ffb493dd06707d38b14bb4d8c2288bb7033735606569d8f90f89669d16  $archive" | sha256sum -c -
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
tar -xzf "$archive" --strip-components=1 -C "$work"
cd "$work"
CC=i686-w64-mingw32-clang ./Configure mingw --prefix="$prefix" no-shared no-ssl2 no-asm no-capieng no-hw-padlock
sed -i 's/-mno-cygwin //g' Makefile
tools=(CC=i686-w64-mingw32-clang MAKEDEPPROG=i686-w64-mingw32-clang AR="/opt/llvm-21/bin/llvm-ar r" RANLIB=/opt/llvm-21/bin/llvm-ranlib)
make "${tools[@]}" depend
make -j"${PARALLEL_JOBS:-3}" "${tools[@]}"
make "${tools[@]}" install_sw
install -m 644 LICENSE "$prefix/LICENSE"
