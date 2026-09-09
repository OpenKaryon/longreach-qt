#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2026 OpenKaryon
set -eu

if [ "$#" -lt 3 ]; then
    echo "usage: openssl.sh <archive> <target> <prefix> [configure-arg...]" >&2
    exit 2
fi

archive="$1"
target="$2"
prefix="$3"
shift 3

work="/tmp/openssl-build"
rm -rf "$work"
mkdir -p "$work"

tar -xzf "$archive" -C "$work" --strip-components=1
cd "$work"

./Configure "$target" "$@" --prefix="$prefix"
make -j "${PARALLEL_JOBS:-$(nproc)}"
make install_sw
