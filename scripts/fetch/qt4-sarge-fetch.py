#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2026 OpenKaryon
"""Fetch the pinned Debian Sarge sysroot (i386 or amd64) and the sources the build needs."""
import argparse
import hashlib
import json
from pathlib import Path
import urllib.request

ROOT = Path(__file__).resolve().parents[2]
LOCKS = ROOT / 'scripts/fetch/locks'
GCC = {
    'file': 'gcc-5.5.0.tar.xz',
    'url': 'https://ftp.gnu.org/gnu/gcc/gcc-5.5.0/gcc-5.5.0.tar.xz',
    'sha256': '530cea139d82fe542b358961130c69cfde8b3d14556370b65823d2f91f0ced87',
}
SOURCES = [GCC, {
    'file': 'qt-everywhere-opensource-src-4.8.7.tar.gz',
    'url': 'https://download.qt.io/archive/qt/4.8/4.8.7/qt-everywhere-opensource-src-4.8.7.tar.gz',
    'sha256': 'e2882295097e47fe089f8ac741a95fef47e0a73a3f3cdf21b56990638f626ea0',
}, {
    'file': 'openssl-1.0.2u.tar.gz',
    'url': 'https://www.openssl.org/source/old/1.0.2/openssl-1.0.2u.tar.gz',
    'sha256': 'ecd0c6ffb493dd06707d38b14bb4d8c2288bb7033735606569d8f90f89669d16',
}]


def fetch(item, directory):
    path = directory / item['file']
    if not path.is_file():
        directory.mkdir(parents=True, exist_ok=True)
        pending = path.with_suffix(path.suffix + '.pending')
        with urllib.request.urlopen(item['url'], timeout=120) as response:
            with pending.open('wb') as output:
                while chunk := response.read(1024 * 1024):
                    output.write(chunk)
        verify(pending, item)
        pending.replace(path)
    verify(path, item)
    print('verified ' + path.name, flush=True)


def verify(path, item):
    with path.open('rb') as stream:
        digest = hashlib.file_digest(stream, 'sha256').hexdigest()
    if digest != item['sha256'] or ('bytes' in item and path.stat().st_size != item['bytes']):
        raise SystemExit('SHA256/size mismatch: ' + str(path))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--download-dir', type=Path, default=ROOT / 'downloads')
    parser.add_argument('--arch', choices=['i386', 'amd64'], default='i386')
    parser.add_argument('--vm', action='store_true', help='also fetch Sarge kernel/VM utilities (i386)')
    args = parser.parse_args()
    lock = json.loads((LOCKS / f'qt4-sarge-{args.arch}-packages.json').read_text(encoding='utf-8'))
    for item in lock['packages']:
        fetch(item, args.download_dir / f'debian-sarge-{args.arch}')
    for item in SOURCES:
        fetch(item, args.download_dir)
    if args.vm:
        vm_lock = json.loads((LOCKS / 'qt4-sarge-vm-packages.json').read_text(encoding='utf-8'))
        for item in vm_lock['packages']:
            fetch(item, args.download_dir / 'debian-sarge-kernel')


if __name__ == '__main__':
    main()
