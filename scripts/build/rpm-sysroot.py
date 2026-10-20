#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2026 OpenKaryon
"""Unpack packages of a yum repository into a sysroot for cross-building.

    rpm-sysroot.py --write-lock LOCK --arch ARCH --repo URL [--repo URL]... PACKAGE...
    rpm-sysroot.py --lock LOCK --dest DIR [--merged-usr]

The first, run when the package list changes: reads each repository's
primary index, takes the newest build of every named package for ARCH (or
noarch) across the repositories, downloads it, checks it against the SHA256
the index records and writes the URL and SHA256 of each to LOCK.

The second, in the build: downloads exactly the packages LOCK names, checks
each against the SHA256 in LOCK (not against an index fetched with it) and
unpacks it into DIR with rpm2cpio and cpio. Nothing is installed and no
scriptlet runs; absolute symbolic links are made relative to DIR, so that
they resolve inside it. Packages are named exactly: dependencies are not
followed.
"""
import json
import argparse
import gzip
import hashlib
import os
import re
import subprocess
import sys
import tempfile
import time
import urllib.request
import xml.etree.ElementTree as ET

REPO = '{http://linux.duke.edu/metadata/repo}'
COMMON = '{http://linux.duke.edu/metadata/common}'


def fetch(url):
    """The body at url; three tries, as one failed request should not end a build."""
    for attempt in range(1, 4):
        try:
            with urllib.request.urlopen(url, timeout=120) as response:
                return response.read()
        except OSError as error:
            if attempt == 3 or getattr(error, 'code', None) == 404:
                raise
            print(f'{url}: {error}; retrying', file=sys.stderr)
            time.sleep(30 * attempt)


def rpmvercmp(a, b):
    """rpm's version comparison, enough for one distribution's updates."""
    xs, ys = re.findall(r'\d+|[a-zA-Z]+', a), re.findall(r'\d+|[a-zA-Z]+', b)
    for x, y in zip(xs, ys):
        if x.isdigit() and y.isdigit():
            x, y = int(x), int(y)
        elif x.isdigit() != y.isdigit():
            return 1 if x.isdigit() else -1
        if x != y:
            return 1 if x > y else -1
    return (len(xs) > len(ys)) - (len(xs) < len(ys))


def newer(p, q):
    epoch = int(p['epoch']) - int(q['epoch'])
    if epoch:
        return epoch > 0
    return (rpmvercmp(p['ver'], q['ver']) or rpmvercmp(p['rel'], q['rel'])) > 0


def packages(repo, arch):
    repomd = ET.fromstring(fetch(repo + '/repodata/repomd.xml'))
    for data in repomd.findall(REPO + 'data'):
        if data.get('type') == 'primary':
            href = data.find(REPO + 'location').get('href')
            break
    else:
        raise SystemExit('%s: no primary index' % repo)
    primary = ET.fromstring(gzip.decompress(fetch(repo + '/' + href)))
    for package in primary.findall(COMMON + 'package'):
        if package.findtext(COMMON + 'arch') not in (arch, 'noarch'):
            continue
        version = package.find(COMMON + 'version')
        checksum = package.find(COMMON + 'checksum')
        yield {
            'name': package.findtext(COMMON + 'name'),
            'epoch': version.get('epoch') or '0', 'ver': version.get('ver'), 'rel': version.get('rel'),
            'url': repo + '/' + package.find(COMMON + 'location').get('href'),
            'sha256': checksum.text if checksum.get('type') == 'sha256' else None,
        }


def relativize(root):
    for parent, dirs, files in os.walk(root):
        for name in dirs + files:
            path = os.path.join(parent, name)
            if os.path.islink(path) and os.readlink(path).startswith('/'):
                target = os.path.join(root, os.readlink(path).lstrip('/'))
                os.unlink(path)
                os.symlink(os.path.relpath(target, parent), path)


def write_lock(args):
    if not (args.arch and args.repo and args.names):
        raise SystemExit('--write-lock needs --arch, --repo and the package names')
    wanted = set(args.names)
    best = {}
    for repo in args.repo:
        for package in packages(repo.rstrip('/'), args.arch):
            name = package['name']
            if name in wanted and (name not in best or newer(package, best[name])):
                best[name] = package
    missing = sorted(wanted - set(best))
    if missing:
        raise SystemExit('not in the repositories: %s' % ', '.join(missing))
    locked = []
    for name in sorted(best):
        package = best[name]
        digest = hashlib.sha256(fetch(package['url'])).hexdigest()
        if package['sha256'] and digest != package['sha256']:
            raise SystemExit('%s: SHA256 does not match the index' % package['url'])
        locked.append({'name': name, 'version': '%s-%s' % (package['ver'], package['rel']),
                       'url': package['url'], 'sha256': digest})
        print('locked %s-%s-%s' % (name, package['ver'], package['rel']), flush=True)
    with open(args.write_lock, 'w', encoding='utf-8', newline='\n') as out:
        json.dump({'purpose': 'packages of the sysroot rpm-sysroot.py --lock unpacks, '
                              'from rpm-sysroot.py --write-lock ' + ' '.join('--repo ' + r for r in args.repo),
                   'arch': args.arch, 'packages': locked}, out, indent=1)
        out.write('\n')


def unpack_lock(args):
    if not args.dest:
        raise SystemExit('--lock needs --dest')
    with open(args.lock, encoding='utf-8') as stream:
        locked = json.load(stream)['packages']
    dest = os.path.abspath(args.dest)
    os.makedirs(dest, exist_ok=True)
    if args.merged_usr:
        for name in ('bin', 'sbin', 'lib', 'lib64'):
            os.makedirs(os.path.join(dest, 'usr', name), exist_ok=True)
            if not os.path.lexists(os.path.join(dest, name)):
                os.symlink('usr/' + name, os.path.join(dest, name))
    with tempfile.TemporaryDirectory() as work:
        for package in locked:
            data = fetch(package['url'])
            if hashlib.sha256(data).hexdigest() != package['sha256']:
                raise SystemExit('%s: SHA256 does not match the lock' % package['url'])
            path = os.path.join(work, os.path.basename(package['url']))
            with open(path, 'wb') as out:
                out.write(data)
            rpm2cpio = subprocess.Popen(['rpm2cpio', path], stdout=subprocess.PIPE)
            subprocess.check_call(['cpio', '-idm', '--quiet', '--no-absolute-filenames'],
                                  stdin=rpm2cpio.stdout, cwd=dest)
            if rpm2cpio.wait():
                raise SystemExit('%s: rpm2cpio failed' % path)
            os.unlink(path)
            print('%s-%s' % (package['name'], package['version']))
            sys.stdout.flush()
    relativize(dest)


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    mode = parser.add_mutually_exclusive_group(required=True)
    mode.add_argument('--write-lock', metavar='LOCK', help='resolve the packages and write LOCK')
    mode.add_argument('--lock', metavar='LOCK', help='unpack the packages LOCK names')
    parser.add_argument('--dest')
    parser.add_argument('--arch')
    parser.add_argument('--repo', action='append')
    parser.add_argument('--merged-usr', action='store_true',
                        help='/bin, /sbin, /lib and /lib64 link into /usr, as from RHEL 7 on')
    parser.add_argument('names', nargs='*', metavar='PACKAGE')
    args = parser.parse_args()
    if args.write_lock:
        write_lock(args)
    else:
        unpack_lock(args)


if __name__ == '__main__':
    main()
