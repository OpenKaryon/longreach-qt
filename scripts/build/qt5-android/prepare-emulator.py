#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later

"""Prepare the API 10 ARMv7 boot ramdisk without modifying system.img."""

import argparse
import gzip
import hashlib
import io
from pathlib import Path
import zipfile

SDK_SHA256 = "54bdb0f1ca06ba5747061ddeea20f431af72c448334fd4d3d7f84ea2ccd29fea"


def unpack_newc(data):
    records = []
    offset = 0
    while True:
        header = data[offset:offset + 110]
        if len(header) != 110 or header[:6] != b"070701":
            raise ValueError("Expected a newc initramfs archive")
        fields = [int(header[6 + i * 8:14 + i * 8], 16) for i in range(13)]
        name_size, file_size = fields[11], fields[6]
        name = data[offset + 110:offset + 110 + name_size]
        if len(name) != name_size or not name.endswith(b"\0"):
            raise ValueError("Invalid newc filename")
        start = (offset + 110 + name_size + 3) & ~3
        payload = data[start:start + file_size]
        if len(payload) != file_size:
            raise ValueError("Truncated newc payload")
        records.append((header, name, payload))
        offset = (start + file_size + 3) & ~3
        if name == b"TRAILER!!!\0":
            return records


def pack_newc(records):
    data = bytearray()
    for header, name, payload in records:
        updated = bytearray(header)
        updated[54:62] = f"{len(payload):08x}".encode("ascii")
        data.extend(updated)
        data.extend(name)
        data.extend(b"\0" * (-len(data) % 4))
        data.extend(payload)
        data.extend(b"\0" * (-len(data) % 4))
    data.extend(b"\0" * (-len(data) % 512))
    return bytes(data)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("sdk_archive", type=Path)
    parser.add_argument("output", type=Path)
    args = parser.parse_args()
    digest = hashlib.sha256()
    with args.sdk_archive.open("rb") as source:
        for chunk in iter(lambda: source.read(1024 * 1024), b""):
            digest.update(chunk)
    if digest.hexdigest() != SDK_SHA256:
        raise ValueError("SHA256 mismatch for Android 2.3.3 SDK")
    with zipfile.ZipFile(args.sdk_archive) as sdk:
        source = sdk.read("android-2.3.3_r02-linux/images/ramdisk.img")
    original = unpack_newc(gzip.decompress(source))
    updated = []
    changed = 0
    for header, name, payload in original:
        if name.rstrip(b"\0") == b"default.prop":
            lines = payload.decode("ascii").splitlines()
            lines = [line for line in lines if not line.startswith(
                ("ro.product.cpu.abi=", "ro.product.cpu.abi2="))]
            lines.extend(("ro.product.cpu.abi=armeabi-v7a", "ro.product.cpu.abi2=armeabi"))
            payload = ("\n".join(lines) + "\n").encode("ascii")
            changed += 1
        updated.append((header, name, payload))
    if changed != 1:
        raise ValueError("Expected exactly one default.prop")
    archive = pack_newc(updated)
    decoded = unpack_newc(archive)
    if [(name, payload) for _, name, payload in decoded] != [
            (name, payload) for _, name, payload in updated]:
        raise ValueError("Ramdisk round-trip validation failed")
    output = io.BytesIO()
    with gzip.GzipFile(fileobj=output, mode="wb", filename="", mtime=0) as compressed:
        compressed.write(archive)
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_bytes(output.getvalue())
    print(f"Prepared {args.output}: ARMv7 ABI properties; system.img unchanged")


if __name__ == "__main__":
    main()
