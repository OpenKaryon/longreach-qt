#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2026 OpenKaryon
# Run in the pinned Debian 12 cross-SDK image, before either macOS probe.
set -euo pipefail
work=${LLVM_BUILD_ROOT:-/work}
prefix=$work/host-python
mkdir -p "$prefix/bin" "$prefix/lib"
cp -a /usr/bin/python3.11 "$prefix/bin/"
cp -a /usr/lib/python3.11 "$prefix/lib/"
ln -sf python3.11 "$prefix/bin/python3"
"$prefix/bin/python3.11" --version
ldd "$prefix/bin/python3.11"
