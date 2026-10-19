#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2026 OpenKaryon
set -euo pipefail
source "$(dirname "$0")/arch.sh"
if [ ! -f /work/.toolchain-complete ]; then
    mkdir -p /work/sysroot /work/probe
    # Only the packages the lock names, each checked against its SHA256: a .deb
    # left in the folder by an older lock does not reach the sysroot. Sorted by
    # name, the order the glob used to give.
    python - /packages-lock.json /packages > /tmp/locked-packages <<'EOF'
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
