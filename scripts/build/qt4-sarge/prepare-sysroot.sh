#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2026 OpenKaryon
set -euo pipefail
source "$(dirname "$0")/arch.sh"

mkdir -p /work/sysroot /opt/sarge-crt
# Only the packages the lock names, each checked against its SHA256: a .deb
# left in the folder by an older lock does not reach the sysroot. Sorted by
# name, the order the glob used to give.
python3 - /packages-lock.json /packages > /tmp/locked-packages <<'EOF'
import hashlib
import json
from pathlib import Path
import sys

lock, folder = map(Path, sys.argv[1:])
paths = []
for item in json.loads(lock.read_text())["packages"]:
    path = folder / item["file"]
    with path.open("rb") as stream:
        digest = hashlib.file_digest(stream, "sha256").hexdigest()
    if digest != item["sha256"]:
        sys.exit("SHA256 mismatch: " + str(path))
    paths.append(path)
for path in sorted(paths):
    print(path)
EOF
while read -r package; do dpkg-deb -x "$package" /work/sysroot; done < /tmp/locked-packages
python3 /scripts/relativize-sysroot.py
python3 /scripts/fix-linker-script.py

# Keep the startup objects used by the validated Sarge LLVM link path.
echo "${SARGE_CRT_SHA256:?}  /tmp/sarge-crt.deb" | sha256sum -c -
crt=$(mktemp -d)
dpkg-deb -x /tmp/sarge-crt.deb "$crt"
install -m 644 "$crt/usr/lib/gcc/$SARGE_TRIPLE/5/"crt{begin,end}.o /opt/sarge-crt/
rm -rf "$crt" /tmp/locked-packages
