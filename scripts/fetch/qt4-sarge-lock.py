#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2026 OpenKaryon
"""Pin the Debian 3.1 Sarge packages of the Qt 4 sysroot for one architecture.

Takes the package names of the i386 lock (scripts/fetch/locks/
qt4-sarge-i386-packages.json), reads the archived Packages index of the
architecture - archive.debian.org/debian for i386, the unofficial amd64 port
archived at archive.debian.org/debian-amd64 - and writes
scripts/fetch/locks/qt4-sarge-<arch>-packages.json. Sarge's indexes record MD5
only, so every package is downloaded once, checked against that MD5, and its
SHA256 is recorded; fetching later checks the SHA256.

    qt4-sarge-lock.py --arch amd64 [--download-dir downloads]
"""
import argparse
import gzip
import hashlib
import json
from pathlib import Path
import urllib.request

ROOT = Path(__file__).resolve().parents[2]
LOCKS = ROOT / 'scripts/fetch/locks'
ARCHIVES = {
    'i386': 'https://archive.debian.org/debian/',
    'amd64': 'https://archive.debian.org/debian-amd64/',
}


def get(url):
    with urllib.request.urlopen(url, timeout=300) as response:
        return response.read()


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument('--arch', choices=sorted(ARCHIVES), required=True)
    parser.add_argument('--download-dir', type=Path, default=ROOT / 'downloads')
    args = parser.parse_args()
    archive = ARCHIVES[args.arch]
    names = [p['package'] for p in json.loads((LOCKS / 'qt4-sarge-i386-packages.json').read_text())['packages']]
    index_url = f'{archive}dists/sarge/main/binary-{args.arch}/Packages.gz'
    raw = get(index_url)
    index = {}
    for stanza in gzip.decompress(raw).decode('utf-8', 'replace').split('\n\n'):
        fields = {}
        for line in stanza.splitlines():
            if line and not line.startswith(' ') and ':' in line:
                key, _, value = line.partition(':')
                fields[key] = value.strip()
        if 'Package' in fields:
            index[fields['Package']] = fields
    missing = [n for n in names if n not in index]
    if missing:
        raise SystemExit('not in the Sarge index: ' + ', '.join(missing))
    directory = args.download_dir / f'debian-sarge-{args.arch}'
    directory.mkdir(parents=True, exist_ok=True)
    packages = []
    for name in names:
        fields = index[name]
        url = archive + fields['Filename']
        path = directory / fields['Filename'].rsplit('/', 1)[1]
        data = path.read_bytes() if path.is_file() else get(url)
        if hashlib.md5(data).hexdigest() != fields['MD5sum'] or len(data) != int(fields['Size']):
            raise SystemExit(f'{name}: MD5/size does not match the archive index')
        path.write_bytes(data)
        packages.append({'package': name, 'version': fields['Version'], 'url': url, 'file': path.name,
                         'bytes': len(data), 'sha256': hashlib.sha256(data).hexdigest(),
                         'archive_md5': fields['MD5sum']})
        print(f"  {name} {fields['Version']}", flush=True)
    lock = LOCKS / f'qt4-sarge-{args.arch}-packages.json'
    lock.write_text(json.dumps({
        'distribution': 'Debian 3.1 Sarge',
        'architecture': args.arch,
        'index_url': index_url,
        'index_sha256': hashlib.sha256(raw).hexdigest(),
        'packages': packages,
    }, indent=2) + '\n', encoding='utf-8', newline='\n')
    print(f'pinned {len(packages)} packages -> {lock.relative_to(ROOT)}')


if __name__ == '__main__':
    main()
