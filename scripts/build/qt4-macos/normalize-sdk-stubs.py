#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2026 OpenKaryon
"""Normalize empty i386 MH_DYLIB_STUB symbol tables for the newer ld64 reader.

Tiger umbrella stubs can have symoff=0, nsyms=0 while __LINKEDIT starts
after the load commands. The newer reader rejects that offset even though
there are no symbols. Move only empty table offsets into __LINKEDIT;
preserve all exported symbols, other architectures and install names.
"""
from pathlib import Path
import struct
import sys


def normalize(data):
    slices = [(0, len(data))]
    if data[:4] == b'\xca\xfe\xba\xbe':
        count = struct.unpack_from('>I', data, 4)[0]
        slices = []
        for index in range(count):
            cpu, subtype, offset, size, alignment = struct.unpack_from('>5I', data, 8 + 20 * index)
            if cpu == 7:
                slices.append((offset, size))
    changed = False
    for base, size in slices:
        if size < 28 or data[base:base + 4] != b'\xce\xfa\xed\xfe':
            continue
        magic, cpu, subtype, kind, count, commands_size, flags = struct.unpack_from('<7I', data, base)
        if cpu != 7 or kind != 9:  # Only i386 MH_DYLIB_STUB, never runtime libraries.
            continue
        position = base + 28
        linkedit = None
        symtab = None
        for _ in range(count):
            command, length = struct.unpack_from('<II', data, position)
            if length < 8 or position + length > base + 28 + commands_size:
                raise ValueError('Malformed SDK stub load command')
            if command == 1 and data[position + 8:position + 24].rstrip(b'\0') == b'__LINKEDIT':
                linkedit = struct.unpack_from('<II', data, position + 32)
            if command == 2:
                symtab = position
            position += length
        if linkedit is None or symtab is None:
            continue
        fileoff, filesize = linkedit
        if fileoff + filesize > size:
            raise ValueError('SDK stub __LINKEDIT exceeds its slice')
        symoff, nsyms, stroff, strsize = struct.unpack_from('<4I', data, symtab + 8)
        if nsyms == 0 and symoff == 0 and fileoff:
            struct.pack_into('<I', data, symtab + 8, fileoff)
            changed = True
        if strsize == 0 and stroff == 0 and fileoff:
            struct.pack_into('<I', data, symtab + 16, fileoff)
            changed = True
    return changed


if __name__ == '__main__':
    root = Path(sys.argv[1]).resolve()
    count = 0
    for path in sorted(root.rglob('*')):
        if path.is_symlink() or not path.is_file():
            continue
        with path.open('rb') as stream:
            magic = stream.read(4)
        if magic not in (b'\xca\xfe\xba\xbe', b'\xce\xfa\xed\xfe'):
            continue
        data = bytearray(path.read_bytes())
        if normalize(data):
            path.write_bytes(data)
            print('Normalized empty SDK stub table:', path.relative_to(root))
            count += 1
    print('Normalized Tiger SDK stubs:', count)
