#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2026 OpenKaryon
"""Fetch the pinned Debian Sarge sysroot (i386 or amd64) and the sources the build needs."""
import argparse
import hashlib
import json
from pathlib import Path

import fetch as fetch_py

ROOT = Path(__file__).resolve().parents[2]
LOCKS = ROOT / 'scripts/fetch/locks'
CRT_VERSION = '5.4.0-6ubuntu1~16.04.12'
CRT_SHA256 = {
    'i386': 'f6bf03d89454db46ab222ef6cc809b9012dec2fe2b024d196ab1f527359756dc',
    'amd64': '9fcd5a457cc7f001c62767720953ee8f133744db48b73be2008573768034a684',
}
SOURCES = [{
    'file': 'qt-everywhere-opensource-src-4.8.7.tar.gz',
    'url': 'https://download.qt.io/archive/qt/4.8/4.8.7/qt-everywhere-opensource-src-4.8.7.tar.gz',
    'sha256': 'e2882295097e47fe089f8ac741a95fef47e0a73a3f3cdf21b56990638f626ea0',
}, {
    'file': 'openssl-1.0.2u.tar.gz',
    'url': 'https://www.openssl.org/source/old/1.0.2/openssl-1.0.2u.tar.gz',
    'sha256': 'ecd0c6ffb493dd06707d38b14bb4d8c2288bb7033735606569d8f90f89669d16',
}]


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
                # fetch.py uses the configured mirror for files listed in sources.json.
                pending = Path(fetch_py.download(item['url'], str(path)))
                fetch_py.checked(str(pending), lambda p: verify(Path(p), item))
                fetch_py.finish(str(pending), str(path))
    elif not VERIFY_ONLY:
        fetch_py.tidy(str(path))
    verify(path, item)
    COUNTS['verified'] += 1
    if not VERIFY_ONLY:
        print('verified ' + path.name, flush=True)


def verify(path, item):
    with path.open('rb') as stream:
        digest = hashlib.file_digest(stream, 'sha256').hexdigest()
    if digest != item['sha256'] or ('bytes' in item and path.stat().st_size != item['bytes']):
        raise SystemExit('SHA256/size mismatch: ' + str(path))


def fetch_vm(arch, download_dir):
    lock_name = 'qt4-sarge-vm-packages.json' if arch == 'i386' else 'qt4-sarge-amd64-vm-packages.json'
    directory = 'debian-sarge-kernel' if arch == 'i386' else 'debian-sarge-kernel-amd64'
    lock = json.loads((LOCKS / lock_name).read_text(encoding='utf-8'))
    for item in lock['packages']:
        fetch(item, download_dir / directory)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--download-dir', type=Path, default=ROOT / 'downloads')
    parser.add_argument('--arch', choices=['i386', 'amd64'], default='i386')
    parser.add_argument('--vm', action='store_true', help='also fetch the selected Sarge kernel and VM utilities')
    parser.add_argument('--verify-only', action='store_true',
                        help='check the packages already downloaded, for every architecture and the VM; '
                             'fetch nothing (make verify-downloads checks the archives)')
    parser.add_argument('--crt-sha256', action='store_true', help='print the pinned CRT package hash')
    args = parser.parse_args()
    if args.crt_sha256:
        print(CRT_SHA256[args.arch])
        return
    if args.verify_only:
        global VERIFY_ONLY
        VERIFY_ONLY = True
        for arch in ('i386', 'amd64'):
            lock = json.loads((LOCKS / f'qt4-sarge-{arch}-packages.json').read_text(encoding='utf-8'))
            for item in lock['packages']:
                fetch(item, args.download_dir / f'debian-sarge-{arch}')
            fetch_vm(arch, args.download_dir)
        print(f"qt4-sarge-fetch.py: {COUNTS['verified']} verified, {COUNTS['absent']} not downloaded")
        return
    lock = json.loads((LOCKS / f'qt4-sarge-{args.arch}-packages.json').read_text(encoding='utf-8'))
    for item in lock['packages']:
        fetch(item, args.download_dir / f'debian-sarge-{args.arch}')
    filename = f'libgcc-5-dev_{CRT_VERSION}_{args.arch}.deb'
    fetch({
        'file': filename,
        'url': 'https://archive.ubuntu.com/ubuntu/pool/main/g/gcc-5/' + filename,
        'sha256': CRT_SHA256[args.arch],
    }, args.download_dir)
    for item in SOURCES:
        fetch(item, args.download_dir)
    if args.vm:
        fetch_vm(args.arch, args.download_dir)


if __name__ == '__main__':
    main()
