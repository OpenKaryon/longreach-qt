# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2026 OpenKaryon
"""Check the actual native ABI before copying shared libraries into an APK."""
import argparse
from pathlib import Path
import struct
import sys

SETTINGS = {'armeabi': (1, 40), 'armeabi-v7a': (1, 40), 'arm64-v8a': (2, 183),
            'x86': (1, 3), 'x86_64': (2, 62)}


def inspect(path, abi):
    with Path(path).open('rb') as stream:
        header = stream.read(20)
    inspect_header(header, abi, str(path))


def inspect_header(header, abi, label='native library'):
    bits, machine = SETTINGS[abi]
    if len(header) != 20 or header[:6] != b'\x7fELF' + bytes((bits, 1)) or struct.unpack_from('<H', header, 18)[0] != machine:
        raise ValueError(f'Native library does not match {abi}: {label}')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--abi', choices=SETTINGS, required=True)
    parser.add_argument('libraries', type=Path, nargs='+')
    args = parser.parse_args()
    for path in args.libraries:
        inspect(path, args.abi)
    print(f'Native ABI {args.abi}: {len(args.libraries)} libraries PASS')


if __name__ == '__main__':
    try:
        main()
    except (OSError, ValueError) as error:
        sys.exit(f'Native ABI validation failed: {error}')
