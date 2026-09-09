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
"""
import hashlib
import os
import sys
import time
import urllib.request


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


def download(url, path):
    part = path + '.part'
    for attempt in range(1, 4):
        try:
            print(f'downloading {url}')
            with urllib.request.urlopen(url, timeout=120) as response, open(part, 'wb') as out:
                for chunk in iter(lambda: response.read(1 << 20), b''):
                    out.write(chunk)
            return part
        except OSError as error:
            if os.path.exists(part):
                os.remove(part)
            if attempt == 3:
                sys.exit(f'{url}: {error}')
            print(f'  {error}; retrying')
            time.sleep(10 * attempt)


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
