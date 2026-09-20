#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2026 OpenKaryon
"""Fetch the pinned Ubuntu 10.04 Lucid sysroot packages (amd64 or i386), the X client
sources built over Lucid's libxcb (sources-lock.json) and the GCC source for
the static C++ runtime, checking each against its pinned SHA256.

Packages land in downloads/ubuntu-lucid-<arch>/; regenerate the pins with
scripts/fetch/qt5-lucid-lock.py.
"""
import argparse
import hashlib
import json
from pathlib import Path
import urllib.request

ROOT = Path(__file__).resolve().parents[2]
LOCKS = ROOT / 'scripts/fetch/locks'
SOURCES = ROOT / 'scripts/fetch/locks/qt5-lucid-sources.json'
GCC = {
    'file': 'gcc-5.5.0.tar.xz',
    'url': 'https://ftp.gnu.org/gnu/gcc/gcc-5.5.0/gcc-5.5.0.tar.xz',
    'sha256': '530cea139d82fe542b358961130c69cfde8b3d14556370b65823d2f91f0ced87',
}


def verify(path, item):
    with path.open('rb') as stream:
        digest = hashlib.file_digest(stream, 'sha256').hexdigest()
    if digest != item['sha256'] or ('bytes' in item and path.stat().st_size != item['bytes']):
        raise SystemExit('SHA256/size mismatch: ' + str(path))


def fetch(item, directory):
    path = directory / item['file']
    if not path.is_file():
        directory.mkdir(parents=True, exist_ok=True)
        pending = path.with_suffix(path.suffix + '.pending')
        with urllib.request.urlopen(item['url'], timeout=120) as response, pending.open('wb') as output:
            while chunk := response.read(1024 * 1024):
                output.write(chunk)
        verify(pending, item)
        pending.replace(path)
    verify(path, item)
    print('verified ' + path.name, flush=True)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--download-dir', type=Path, default=ROOT / 'downloads')
    parser.add_argument('--arch', choices=['amd64', 'i386'], default='amd64')
    args = parser.parse_args()
    lock = json.loads((LOCKS / f'qt5-lucid-{args.arch}-packages.json').read_text(encoding='utf-8'))
    for item in lock['packages']:
        fetch(item, args.download_dir / f'ubuntu-lucid-{args.arch}')
    for item in json.loads(SOURCES.read_text(encoding='utf-8'))['sources']:
        fetch(item, args.download_dir / 'lucid-xsrc')
    fetch(GCC, args.download_dir)


if __name__ == '__main__':
    main()
