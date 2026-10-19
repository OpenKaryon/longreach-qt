#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2026 OpenKaryon
"""Download a build input and check it against its pinned SHA256.

    fetch.py <url> <file> <sha256>          download unless present, then verify
    fetch.py --check <file> <sha256>        verify a file that is already there

Every archive the kit builds from is pinned this way in the Makefile, so a
changed upstream file, a truncated download or a swapped mirror stops the
build instead of reaching it. The download goes to <file>.part and is renamed
only once it verifies.

A file sources.json lists as copied comes from the OpenKaryonLab copy, then
from <url> unless <url> is on GitHub too (the copy is, so that would be no
fallback). Anything else (Apple SDKs, Debian and Ubuntu packages) comes from
<url> only. LONGREACH_MIRROR names another copy; LONGREACH_UPSTREAM_FIRST=1
tries <url> first, for a new pin before its file is copied.
"""
import hashlib
import json
import os
import sys
import time
import urllib.parse
import urllib.request

MIRROR = os.environ.get('LONGREACH_MIRROR',
                        'https://github.com/OpenKaryonLab/longreach-qt-sources/releases/download/sources/')
COPIED = {a['file'] for a in json.load(open(os.path.join(os.path.dirname(os.path.abspath(__file__)),
                                                           'sources.json'), encoding='utf-8'))['archives']}
GITHUB = ('github.com', 'raw.githubusercontent.com', 'codeload.github.com', 'objects.githubusercontent.com')


def sha256(path):
    digest = hashlib.sha256()
    with open(path, 'rb') as f:
        for chunk in iter(lambda: f.read(1 << 20), b''):
            digest.update(chunk)
    return digest.hexdigest()


def verify(path, expected):
    actual = sha256(path)
    if actual != expected.lower():
        sys.exit(f'{path}: SHA256 {actual}, expected {expected}')
    print(f'{path}: SHA256 ok')


def sources(url, path):
    """Where to download the file from, in the order to try."""
    name = os.path.basename(path)
    if name not in COPIED:
        return [url]
    copy = MIRROR.rstrip('/') + '/' + name
    if os.environ.get('LONGREACH_UPSTREAM_FIRST') == '1':
        return [url, copy]
    if urllib.parse.urlparse(url).hostname in GITHUB:
        return [copy]
    return [copy, url]


def download(url, path, order=None):
    """Download to <path>.part from the sources(), or the URLs in order; exits
    when none works."""
    part = path + '.part'
    errors = []
    order = order or sources(url, path)
    for source in order:
        if source != order[0]:
            print(f'WARNING: {os.path.basename(path)} is not at {order[0]}; '
                  'falling back (copy it: python scripts/fetch/mirror.py archives)')
        for attempt in range(1, 4):
            try:
                print(f'downloading {source}')
                with urllib.request.urlopen(source, timeout=120) as response, open(part, 'wb') as out:
                    for chunk in iter(lambda: response.read(1 << 20), b''):
                        out.write(chunk)
                return part
            except OSError as error:
                if os.path.exists(part):
                    os.remove(part)
                # A missing file stays missing: go on to the next source.
                if attempt == 3 or getattr(error, 'code', None) == 404:
                    errors.append(f'{source}: {error}')
                    break
                print(f'  {error}; retrying')
                time.sleep(10 * attempt)
    sys.exit('\n'.join(errors))


def main(argv):
    if len(argv) == 3 and argv[0] == '--check':
        verify(argv[1], argv[2])
        return
    if len(argv) != 3:
        sys.exit(__doc__)
    url, path, expected = argv
    if os.path.exists(path):
        verify(path, expected)
        return
    os.makedirs(os.path.dirname(path) or '.', exist_ok=True)
    part = download(url, path)
    verify(part, expected)
    os.replace(part, path)


if __name__ == '__main__':
    main(sys.argv[1:])
