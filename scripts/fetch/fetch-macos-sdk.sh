#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2026 OpenKaryon
#
# Fetch the macOS SDK from Apple's software-update CDN and package it as
# osxcross expects: a tarball whose one top-level entry is MacOSX<ver>.sdk.
# Run in a container by make (the SDK's symlinks do not survive a Windows
# filesystem).
#
#   CLTools_*.pkg      a xar archive (bsdtar)
#     Payload          pbzx: independently xz-compressed blocks (the python below)
#       (cpio)         bsdtar again
#
# The SDK sits under Library/Developer/CommandLineTools/SDKs/ next to a
# versioned symlink; the real directory is detected and renamed.
#
# Environment (set by make): SDK_TARBALL (relative to /work), SDK_DIR,
# SDK_PKG_URL, SDK_PKG_SHA256.
set -eu

: "${SDK_TARBALL:?}" "${SDK_DIR:?}" "${SDK_PKG_URL:?}" "${SDK_PKG_SHA256:?}"

if [ -f "/work/$SDK_TARBALL" ]; then
    echo "$SDK_TARBALL is already here, nothing to do."
    exit 0
fi

export DEBIAN_FRONTEND=noninteractive
# The tools from the archive as it was at the snapshot date (make passes
# APT_SNAPSHOT when it is set).
sh /scripts/build/apt-snapshot.sh ${APT_SNAPSHOT:+"$APT_SNAPSHOT"}
apt-get -qq update >/dev/null
apt-get -qq install -y curl ca-certificates python3 libarchive-tools xz-utils >/dev/null

mkdir -p /tmp/sdk && cd /tmp/sdk

echo "Fetching $(basename "$SDK_PKG_URL") ..."
curl -fL --retry 3 -o pkg "$SDK_PKG_URL"

# Checked before anything is unpacked, so a truncated or substituted download
# cannot reach the rest of this script.
echo "$SDK_PKG_SHA256  pkg" | sha256sum -c -

echo "Unpacking ..."
bsdtar -xf pkg
python3 - <<'PY'
import lzma, struct

with open("Payload", "rb") as f:
    data = f.read()

if data[:4] != b"pbzx":
    raise SystemExit("Payload is not pbzx: %r" % data[:4])

pos = 4 + 8                      # magic, then the flags word
with open("Payload.cpio", "wb") as out:
    while pos + 16 <= len(data):
        _flags, length = struct.unpack(">QQ", data[pos:pos + 16])
        pos += 16
        chunk = data[pos:pos + length]
        pos += length
        # Blocks small enough that compressing them would not pay are stored
        # as-is; everything else is a standalone xz stream.
        out.write(lzma.decompress(chunk) if chunk[:6] == b"\xfd7zXZ\x00" else chunk)
PY
mkdir -p root
bsdtar -xf Payload.cpio -C root

sdks=root/Library/Developer/CommandLineTools/SDKs
found=""
for d in "$sdks"/*.sdk; do
    # -d is true for a symlink to a directory as well, hence the -L test: we
    # want the real tree, not Apple's versioned alias for it.
    if [ -d "$d" ] && [ ! -L "$d" ]; then
        found="$d"
        break
    fi
done
[ -n "$found" ] || { echo "No SDK directory in $sdks:"; ls -l "$sdks"; exit 1; }

version=$(sed -n 's/.*<string>\([0-9][0-9.]*\)<\/string>.*/\1/p' \
    "$found/System/Library/CoreServices/SystemVersion.plist" | head -1)
build=$(grep -A1 ProductBuildVersion \
    "$found/System/Library/CoreServices/SystemVersion.plist" \
    | sed -n 's/.*<string>\(.*\)<\/string>.*/\1/p')
echo "Got macOS $version ($build) as $(basename "$found"), $(find "$found" -type l | wc -l) symlinks"

cd "$sdks"
if [ "$(basename "$found")" != "$SDK_DIR" ]; then
    rm -f "$SDK_DIR"                     # Apple's alias, if it is in the way
    mv "$(basename "$found")" "$SDK_DIR"
fi

echo "Packing $SDK_TARBALL ..."
# -p keeps the permissions, and writing to a temporary name means an interrupted
# run cannot leave a half-written tarball that looks finished to make.
# pipefail: a tar that fails half-way must not leave a short archive behind
# xz's success; the archive is tested before it gets its name.
set -o pipefail
tar -cpf - "$SDK_DIR" | xz -T0 -6 > "/work/$SDK_TARBALL.part"
xz -t "/work/$SDK_TARBALL.part"
mv "/work/$SDK_TARBALL.part" "/work/$SDK_TARBALL"
ls -la "/work/$SDK_TARBALL"
