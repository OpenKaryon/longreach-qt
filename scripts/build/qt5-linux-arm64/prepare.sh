#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2026 OpenKaryon
#
# The Ubuntu 14.04 arm64 toolchain: the sysroot's absolute links made
# relative, and a probe proving the C++ runtime needs no glibc newer than
# 14.04's 2.19. The X libraries newer than 14.04's come next, from
# scripts/build/qt5-lucid/build-xdeps.sh as for Lucid.
set -euo pipefail
python3 /scripts/relativize-sysroot.py
mkdir -p /work/probe
aarch64-trusty-g++ -std=gnu++14 -O2 -pthread -static-libgcc -static-libstdc++ /scripts/probe.cpp -o /work/probe/probe
python3 /scripts/max-glibc.py /work/probe/probe 2.19
