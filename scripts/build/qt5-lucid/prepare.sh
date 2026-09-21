#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2026 OpenKaryon
# Lucid sysroot and toolchain (amd64 or i386): the Ubuntu 16.04 GCC 5.4 compiles,
# every header and library it links against comes from the pinned Lucid
# packages, and the C++ runtime is rebuilt against them.
set -euo pipefail
mkdir -p /work/sysroot /work/probe /out
for package in /packages/*.deb; do dpkg-deb -x "$package" /work/sysroot; done
python3 /scripts/relativize-sysroot.py
bash /scripts/build-cxx-runtime.sh
export PATH=/work/toolchain/bin:$PATH
lucid-g++ -std=gnu++14 -O2 -pthread -static-libgcc -static-libstdc++ /scripts/probe.cpp -o /work/probe/probe
# The newest glibc symbol version the probe needs must be 2.11 or older.
python3 /scripts/max-glibc.py /work/probe/probe 2.11
cp /work/probe/probe /out/lucid-probe
