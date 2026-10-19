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

import fetch as fetch_py

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


COUNTS = {'verified': 0, 'absent': 0}
VERIFY_ONLY = False


def fetch(item, directory):
    path = directory / item['file']
    if not path.is_file() and VERIFY_ONLY:
        COUNTS['absent'] += 1
        return
    if not path.is_file():
        directory.mkdir(parents=True, exist_ok=True)
        with fetch_py.downloading(path):
            if not path.is_file():
                # fetch.py: the OpenKaryonLab copy for a file sources.json lists, else upstream.
                pending = Path(fetch_py.download(item['url'], str(path)))
                verify(pending, item)
                pending.replace(path)
    verify(path, item)
    COUNTS['verified'] += 1
    if not VERIFY_ONLY:
        print('verified ' + path.name, flush=True)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--download-dir', type=Path, default=ROOT / 'downloads')
    parser.add_argument('--arch', choices=['amd64', 'i386'], default='amd64')
    parser.add_argument('--sources-only', action='store_true',
                        help='only the X sources (qt5-linux-arm64 builds them over its own sysroot)')
    parser.add_argument('--verify-only', action='store_true',
                        help='check what is already downloaded, for every architecture; fetch nothing')
    args = parser.parse_args()
    if args.verify_only:
        global VERIFY_ONLY
        VERIFY_ONLY = True
        for arch in ('amd64', 'i386'):
            lock = json.loads((LOCKS / f'qt5-lucid-{arch}-packages.json').read_text(encoding='utf-8'))
            for item in lock['packages']:
                fetch(item, args.download_dir / f'ubuntu-lucid-{arch}')
        for item in json.loads(SOURCES.read_text(encoding='utf-8'))['sources']:
            fetch(item, args.download_dir / 'lucid-xsrc')
        fetch(GCC, args.download_dir)
        print(f"qt5-lucid-fetch.py: {COUNTS['verified']} verified, {COUNTS['absent']} not downloaded")
        return
    if not args.sources_only:
        lock = json.loads((LOCKS / f'qt5-lucid-{args.arch}-packages.json').read_text(encoding='utf-8'))
        for item in lock['packages']:
            fetch(item, args.download_dir / f'ubuntu-lucid-{args.arch}')
    for item in json.loads(SOURCES.read_text(encoding='utf-8'))['sources']:
        fetch(item, args.download_dir / 'lucid-xsrc')
    if not args.sources_only:
        fetch(GCC, args.download_dir)


if __name__ == '__main__':
    main()
