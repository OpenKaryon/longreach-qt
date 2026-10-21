#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2026 OpenKaryon
"""Download a build input and check it against its pinned SHA256.

    fetch.py <url> <file> <sha256>          download unless present, then verify
    fetch.py --check <file> <sha256>        verify a file that is already there
    fetch.py --locked <file> <command>...   run a command that makes <file>,
                                            unless it is there, under the same
                                            lock as a download of <file>

Every archive the kit builds from is pinned this way in the Makefile, so a
changed upstream file, a truncated download or a swapped mirror stops the
build instead of reaching it. The download goes to a <file>.part outside the
folders an image COPYs whole (downloads/debian-sarge-*, where a leftover would
be built in): build/partial/, or downloads/.partial/ when downloads/ is linked
to another drive; only a folder linked to a drive of its own gets it beside
the file. It is moved into place in one rename once it verifies.

A file sources.json lists as copied comes from the OpenKaryonLab copy, then
from <url> unless <url> is on GitHub too (the copy is, so that would be no
fallback). Anything else (Apple SDKs, Debian and Ubuntu packages) comes from
<url> only. LONGREACH_MIRROR names another copy; LONGREACH_UPSTREAM_FIRST=1
tries <url> first, for a new pin before its file is copied.
"""
import hashlib
import http.client
import json
import os
import subprocess
import sys
import time
import urllib.parse
import urllib.request
from contextlib import contextmanager
from pathlib import Path

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


def try_lock(stream) -> bool:
    """Lock an open file's first byte without waiting: False if another process holds it."""
    stream.seek(0)
    if sys.platform == "win32":
        import msvcrt
        try:
            msvcrt.locking(stream.fileno(), msvcrt.LK_NBLCK, 1)
            return True
        except OSError:
            return False
    import fcntl
    try:
        fcntl.flock(stream.fileno(), fcntl.LOCK_EX | fcntl.LOCK_NB)
        return True
    except OSError:
        return False


def unlock(stream) -> None:
    stream.seek(0)
    if sys.platform == "win32":
        import msvcrt
        msvcrt.locking(stream.fileno(), msvcrt.LK_UNLCK, 1)
    else:
        import fcntl
        fcntl.flock(stream.fileno(), fcntl.LOCK_UN)


@contextmanager
def held(path: Path, wait: bool, busy: str):
    """Hold the lock file at path; if another process has it, wait (printing
    busy once) or exit with busy as the error."""
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("a+b") as stream:
        if path.stat().st_size == 0:
            stream.write(b"0")
            stream.flush()
        if not try_lock(stream):
            if not wait:
                raise SystemExit(busy)
            print(busy + "; waiting", flush=True)
            while not try_lock(stream):
                time.sleep(1)
        try:
            yield
        finally:
            unlock(stream)


def downloading(path):
    """Held while <path> is downloaded: two targets that need the same input
    (qt6-host and qt6-linux-amd64, both the Qt archive) do not both write
    its partial(); the second waits, then finds the file there."""
    # Under build/locks/, not beside the file: downloads/ folders are COPYed
    # into images whole.
    lock = Path(__file__).resolve().parents[2] / 'build' / 'locks' / f'download-{os.path.basename(path)}.lock'
    return held(lock, wait=True, busy=f'{os.path.basename(path)} is being downloaded by another build')


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


def complete(response, received):
    """A connection closed before the end of a sized response is an error:
    response.read(n) just returns what came, without IncompleteRead.
    response.length is what http.client still expected (None when chunked)."""
    remaining = getattr(response, 'length', None)
    if remaining:
        raise ConnectionError(f'the connection closed after {received} bytes, {remaining} short')


ROOT = Path(__file__).resolve().parents[2]
# Folders no image COPYs, tried in order: the first on the drive of the file
# keeps finish() one rename.
PARTIALS = (ROOT / 'build' / 'partial', ROOT / 'downloads' / '.partial')


def partial(path):
    """Where a file for path is written until it is complete and checked."""
    folder = os.path.dirname(os.path.abspath(path))
    os.makedirs(folder, exist_ok=True)
    for candidate in PARTIALS:
        candidate.mkdir(parents=True, exist_ok=True)
        if os.stat(candidate).st_dev == os.stat(folder).st_dev:
            return str(candidate / (os.path.basename(path) + '.part'))
    # A folder linked to a drive of its own: beside the file is the only rename.
    return path + '.part'


def tidy(path, locked=False):
    """Remove a <path>.part an earlier version left beside the file: in a
    folder an image COPYs whole it would be built in. Under the download
    lock of path (locked: the caller holds it already; taking it again in
    the same process would wait for ever). Leftovers only: one that cannot
    be removed, or locked, is reported and the build goes on."""
    legacy = path + '.part'
    if not os.path.exists(legacy):
        return
    if not locked:
        try:
            with downloading(path):
                tidy(path, locked=True)
        except OSError as error:
            print(f'WARNING: {legacy} was not removed ({error}); delete it by hand', flush=True)
        return
    try:
        if os.path.exists(legacy) and legacy != partial(path):
            os.remove(legacy)
    except OSError as error:
        print(f'WARNING: {legacy} was not removed ({error}); delete it by hand', flush=True)


def checked(part, check):
    """check(part); a part that fails it is removed before the error goes on."""
    try:
        check(part)
    except BaseException:
        if os.path.exists(part):
            os.remove(part)
        raise


def finish(part, path):
    """Put a checked part in place, in one rename."""
    os.replace(part, path)


def download(url, path, order=None):
    """Download to partial(path) from the sources(), or the URLs in order; exits
    when none works."""
    part = partial(path)
    tidy(path, locked=True)  # every caller holds downloading(path)
    errors = []
    order = order or sources(url, path)
    for source in order:
        if source != order[0]:
            print(f'WARNING: {os.path.basename(path)} is not at {order[0]}; '
                  'falling back (copy it: python scripts/fetch/mirror.py archives)')
        for attempt in range(1, 4):
            try:
                print(f'downloading {source}')
                # A .part left behind may be a hard link to another file
                # (qt6-fetch-source.py links QT6_SOURCE there): replace, never
                # write into it.
                if os.path.exists(part):
                    os.remove(part)
                with urllib.request.urlopen(source, timeout=120) as response, open(part, 'wb') as out:
                    for chunk in iter(lambda: response.read(1 << 20), b''):
                        out.write(chunk)
                    complete(response, out.tell())
                return part
            except (OSError, http.client.HTTPException) as error:
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
    if len(argv) >= 3 and argv[0] == '--locked':
        path, command = argv[1], argv[2:]
        with downloading(path):
            if not os.path.exists(path):
                sys.exit(subprocess.call(command))
        return
    if len(argv) != 3:
        sys.exit(__doc__)
    url, path, expected = argv
    if os.path.exists(path):
        tidy(path)
        verify(path, expected)
        return
    os.makedirs(os.path.dirname(path) or '.', exist_ok=True)
    with downloading(path):
        if not os.path.exists(path):
            part = download(url, path)
            checked(part, lambda p: verify(p, expected))
            finish(part, path)
    verify(path, expected)


if __name__ == '__main__':
    main(sys.argv[1:])
