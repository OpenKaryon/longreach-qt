#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2026 OpenKaryon
"""Reject binaries with a wrong CPU, newer OS floor or external SDK libraries."""
import argparse
import hashlib
import json
from pathlib import Path
import plistlib
import struct


def inspect(path, arch='i386'):
    info = plistlib.loads((path.parent.parent / 'Info.plist').read_bytes())
    if (info.get('CFBundleExecutable') != path.name
            or info.get('CFBundlePackageType') != 'APPL'
            or info.get('LSMinimumSystemVersion') != '10.4'):
        raise ValueError(f'{path}: missing or incompatible application bundle metadata')
    if not path.stat().st_mode & 0o111:
        raise ValueError(f'{path}: executable permissions missing')
    data = path.read_bytes()
    endian, expected_cpu = ('>', 18) if arch == 'ppc' else ('<', 7)
    magic, cpu, subtype, kind, count, size, flags = struct.unpack_from(endian + '7I', data)
    if magic != 0xfeedface or cpu != expected_cpu or kind != 2:
        raise ValueError(f'{path}: expected a 32-bit {arch} Mach-O executable')
    # Tiger runs on the G3. A PowerPC subtype above 750 (9), such as the G4's
    # 7400 (10), makes the loader refuse the executable on a G3 Mac.
    if arch == 'ppc' and subtype > 9:
        raise ValueError(f'{path}: PowerPC CPU subtype {subtype} excludes G3 Macs')
    if 28 + size > len(data):
        raise ValueError(f'{path}: truncated Mach-O command area')
    position = 28
    floor = None
    libraries = []
    legacy_entry = False
    for _ in range(count):
        command, length = struct.unpack_from(endian + 'II', data, position)
        if length < 8 or position + length > 28 + size:
            raise ValueError(f'{path}: invalid Mach-O load command')
        if command in (0xc, 0x80000018, 0x8000001f):
            start = struct.unpack_from(endian + 'I', data, position + 8)[0]
            if not 24 <= start < length:
                raise ValueError(f'{path}: invalid library name offset')
            library = data[position + start:position + length].split(b'\0')[0].decode()
            if not library.startswith(('/System/Library/Frameworks/', '/usr/lib/')):
                raise ValueError(f'{path}: non-system library dependency {library}')
            if any(name in library for name in ('libstdc++', 'libc++', 'libssl', 'libcrypto', 'Qt')):
                raise ValueError(f'{path}: expected static library, found {library}')
            libraries.append(library)
        if command == 0x24:
            version = struct.unpack_from(endian + 'I', data, position + 8)[0]
            floor = [version >> 16, (version >> 8) & 255, version & 255]
        if command == 5:
            legacy_entry = True
        # Tiger loader.h only permits LC_LOAD_WEAK_DYLIB with LC_REQ_DYLD.
        if command == 0x32 or (command & 0x80000000 and command != 0x80000018):
            raise ValueError(f'{path}: load command introduced after Tiger: {command:#x}')
        position += length
    # ld_classic predates LC_VERSION_MIN_MACOSX. Do not invent a binary floor:
    # record the bundle declaration separately, and require its old entry form.
    legacy_ppc = arch == 'ppc' and floor is None and legacy_entry
    if (floor is None and not legacy_ppc) or (floor is not None and floor > [10, 4, 0]):
        raise ValueError(f'{path}: missing or newer deployment floor: {floor}')
    return {'binary': path.name, 'sha256': hashlib.sha256(data).hexdigest(),
            'bytes': len(data), 'arch': arch, 'cpu_subtype': subtype,
            'minimum_os': '.'.join(map(str, floor)) if floor else None,
            'bundle_minimum_os': info['LSMinimumSystemVersion'],
            'legacy_unixthread_entry': legacy_entry,
            'libraries': libraries}


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('root', type=Path)
    parser.add_argument('report', type=Path)
    parser.add_argument('--arch', choices=['i386', 'ppc'], default='i386')
    parser.add_argument('--expected', type=Path, default=Path('/work/suite/expected-apps.txt'),
                        help='tests/expected-apps.txt: the applications the suite must have')
    args = parser.parse_args()
    rows = [inspect(path, args.arch) for path in sorted(args.root.glob('*.app/Contents/MacOS/*')) if path.is_file()]
    expected = sorted(line.strip() for line in args.expected.read_text().splitlines()
                      if line.strip() and not line.startswith('#'))
    built = sorted(row['binary'] for row in rows)
    if built != expected:
        raise SystemExit(f'built {built}, expected {expected} (tests/expected-apps.txt)')
    args.report.write_text(json.dumps({'target': 'Mac OS X 10.4 Tiger ' + args.arch,
                                          'runtime_tested': False, 'binaries': rows}, indent=2) + '\n')
    print(f'Mach-O audit passed: {len(rows)} Tiger {args.arch} executables; runtime testing pending')
