#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2026 OpenKaryon
set -euo pipefail
source "$(dirname "$0")/arch.sh"
if [ ! -f /work/.toolchain-complete ]; then
    mkdir -p /work/sysroot /work/probe
    for package in /packages/*.deb; do dpkg-deb -x "$package" /work/sysroot; done
    python /scripts/relativize-sysroot.py
    python /scripts/fix-linker-script.py
    cp /scripts/probe.cpp /work/probe/probe.cpp
    bash /scripts/build-cxx-runtime.sh
    touch /work/.toolchain-complete
fi
readelf -h /work/probe/probe
readelf -V /work/probe/probe
"/work/sysroot$SARGE_LOADER" --library-path /work/sysroot/lib:/work/sysroot/usr/lib /work/probe/probe
cp /work/probe/probe /out/compiler-probe
cp /work/cxx-build/config.log /out/libstdcxx-config.log
cp "/work/cxx-build/include/$SARGE_TRIPLE/bits/c++config.h" /out/libstdcxx-config.h
