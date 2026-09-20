#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2026 OpenKaryon
"""Pin the Ubuntu 10.04 Lucid packages that make up the Qt 5 sysroot (amd64 or i386).

Reads the archived Packages indexes of lucid, lucid-updates and
lucid-security (main and universe), takes the newest version of each
requested package, and writes scripts/fetch/locks/qt5-lucid-<arch>-packages.json
with the archive URL, size and SHA256 that the index itself records.
Only development and runtime packages are pinned; nothing is installed on the
build host. Fetch them with scripts/fetch/qt5-lucid-fetch.py.
"""
import argparse
import gzip
import json
from pathlib import Path
import urllib.request

ROOT = Path(__file__).resolve().parents[2]
LOCKS = ROOT / 'scripts/fetch/locks'
ARCHIVE = 'http://old-releases.ubuntu.com/ubuntu/'
POCKETS = ['lucid', 'lucid-updates', 'lucid-security']
COMPONENTS = ['main', 'universe']

# The C library, kernel headers and the X11, GL and font libraries the xcb
# plugin links against; the xcb extensions and xkbcommon are built statically
# from newer sources instead.
PACKAGES = [
    'libc6', 'libc6-dev', 'linux-libc-dev',
    'zlib1g', 'zlib1g-dev',
    'libx11-6', 'libx11-dev', 'libx11-xcb1', 'libx11-xcb-dev',
    'libxau6', 'libxau-dev', 'libxdmcp6', 'libxdmcp-dev',
    'libxcb1', 'libxcb1-dev',
    'libxext6', 'libxext-dev', 'libxrender1', 'libxrender-dev',
    'libxfixes3', 'libxdamage1', 'libxxf86vm1', 'libdrm2',
    'x11proto-core-dev', 'x11proto-xext-dev', 'x11proto-kb-dev',
    'x11proto-input-dev', 'x11proto-render-dev', 'x11proto-gl-dev',
    'x11proto-dri2-dev', 'xtrans-dev',
    'libgl1-mesa-glx', 'libgl1-mesa-dev', 'mesa-common-dev',
    'libfontconfig1', 'libfontconfig1-dev', 'libexpat1', 'libexpat1-dev',
    'libfreetype6', 'libfreetype6-dev',
    'libice6', 'libice-dev', 'libsm6', 'libsm-dev', 'libuuid1',
]


def version_key(version):
    """Debian version ordering, enough for comparing pocket updates."""
    import re

    def parts(text):
        out = []
        for chunk in re.findall(r'\d+|[a-zA-Z]+|~|[^\da-zA-Z~]', text):
            if chunk.isdigit():
                out.append((2, int(chunk)))
            elif chunk == '~':
                out.append((0, 0))
            else:
                out.append((1, chunk))
        return out
    epoch, _, rest = version.rpartition(':') if ':' in version else ('0', '', version)
    upstream, _, revision = rest.rpartition('-') if '-' in rest else (rest, '', '0')
    return (int(epoch or 0), parts(upstream), parts(revision))


def read_index(pocket, component, arch):
    url = f'{ARCHIVE}dists/{pocket}/{component}/binary-{arch}/Packages.gz'
    with urllib.request.urlopen(url, timeout=120) as response:
        text = gzip.decompress(response.read()).decode('utf-8', 'replace')
    for stanza in text.split('\n\n'):
        fields = {}
        for line in stanza.splitlines():
            if line and not line.startswith(' ') and ':' in line:
                key, _, value = line.partition(':')
                fields[key] = value.strip()
        if 'Package' in fields:
            fields['Pocket'] = pocket
            yield fields


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--arch', choices=['amd64', 'i386'], default='amd64')
    args = parser.parse_args()
    lock = LOCKS / f'qt5-lucid-{args.arch}-packages.json'
    best = {}
    for pocket in POCKETS:
        for component in COMPONENTS:
            for fields in read_index(pocket, component, args.arch):
                name = fields['Package']
                if name not in PACKAGES:
                    continue
                if name not in best or version_key(fields['Version']) > version_key(best[name]['Version']):
                    best[name] = fields
    missing = [name for name in PACKAGES if name not in best]
    if missing:
        raise SystemExit('not in the Lucid indexes: ' + ', '.join(missing))
    packages = []
    for name in PACKAGES:
        fields = best[name]
        packages.append({
            'package': name,
            'version': fields['Version'],
            'pocket': fields['Pocket'],
            'url': ARCHIVE + fields['Filename'],
            'file': fields['Filename'].rsplit('/', 1)[1],
            'bytes': int(fields['Size']),
            'sha256': fields['SHA256'],
        })
    lock.parent.mkdir(parents=True, exist_ok=True)
    lock.write_text(json.dumps({
        'distribution': 'Ubuntu 10.04 LTS (Lucid Lynx)',
        'architecture': args.arch,
        'archive': ARCHIVE,
        'pockets': POCKETS,
        'packages': packages,
    }, indent=2) + '\n', encoding='utf-8', newline='\n')
    print(f'pinned {len(packages)} packages -> {lock.relative_to(ROOT)}')
    for item in packages:
        print(f"  {item['package']} {item['version']} ({item['pocket']})")


if __name__ == '__main__':
    main()
