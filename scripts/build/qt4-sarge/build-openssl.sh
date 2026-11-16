#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2026 OpenKaryon
set -euo pipefail
source "$(dirname "$0")/arch.sh"

archive=/src/openssl.tar.gz
echo "ecd0c6ffb493dd06707d38b14bb4d8c2288bb7033735606569d8f90f89669d16  $archive" | sha256sum -c -
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
tar -xzf "$archive" --strip-components=1 -C "$work"
cd "$work"
toolchain=/work/sarge-llvm/runtimes/linux-sarge-${SARGE_ARCH:?}/bin
./Configure "$SARGE_OPENSSL_TARGET" --prefix=/opt/sarge-openssl no-shared no-capieng
tools=(CC="$toolchain/clang-c -fgnu89-inline" AR="/opt/llvm-21/bin/llvm-ar r" RANLIB="/opt/llvm-21/bin/llvm-ranlib")
make -j"${PARALLEL_JOBS:-3}" "${tools[@]}"
make "${tools[@]}" install_sw
install -Dm644 LICENSE /opt/qt4-sarge/licenses/OPENSSL-LICENSE.txt
