#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2026 OpenKaryon
# Lucid sysroot and toolchain (amd64 or i386): the Ubuntu 16.04 GCC 5.4 compiles,
# every header and library it links against comes from the pinned Lucid
# packages, and the C++ runtime is rebuilt against them.
set -euo pipefail
mkdir -p /work/sysroot /work/probe /out
# Only the packages the lock names, each checked against its SHA256: a .deb
# left in the folder by an older lock does not reach the sysroot. Sorted by
# name, the order the glob used to give.
python3 - /packages-lock.json /packages > /tmp/locked-packages <<'EOF'
import hashlib, json, os, sys
lock, folder = sys.argv[1], sys.argv[2]
paths = []
for item in json.load(open(lock))['packages']:
    path = os.path.join(folder, item['file'])
    digest = hashlib.sha256(open(path, 'rb').read()).hexdigest()
    if digest != item['sha256']:
        sys.exit('%s: SHA256 %s, expected %s' % (path, digest, item['sha256']))
    paths.append(path)
for path in sorted(paths):
    print(path)
EOF
while read -r package; do dpkg-deb -x "$package" /work/sysroot; done < /tmp/locked-packages
python3 /scripts/relativize-sysroot.py
bash /scripts/build-cxx-runtime.sh
export PATH=/work/toolchain/bin:$PATH
lucid-g++ -std=gnu++14 -O2 -pthread -static-libgcc -static-libstdc++ /scripts/probe.cpp -o /work/probe/probe
# The newest glibc symbol version the probe needs must be 2.11 or older.
python3 /scripts/max-glibc.py /work/probe/probe 2.11
cp /work/probe/probe /out/lucid-probe
