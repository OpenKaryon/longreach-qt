#!/usr/bin/env python
# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2026 OpenKaryon
"""Install one locked transaction offline using CentOS 7's system Python."""

import argparse
import hashlib
import json
import os
import subprocess


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('lock')
    parser.add_argument('rpm_dir')
    parser.add_argument('transaction')
    args = parser.parse_args()
    with open(args.lock) as stream:
        lock = json.load(stream)
    transaction = next(item for item in lock['transactions'] if item['name'] == args.transaction)
    paths = []
    for item in transaction['packages']:
        path = os.path.join(args.rpm_dir, item['file'])
        digest = hashlib.sha256()
        with open(path, 'rb') as stream:
            for chunk in iter(lambda: stream.read(1024 * 1024), b''):
                digest.update(chunk)
        if digest.hexdigest() != item['sha256']:
            raise SystemExit('SHA256 does not match the lock: ' + path)
        paths.append(path)
    subprocess.check_call(['yum', '-y', '--disablerepo=*', '--setopt=localpkg_gpgcheck=1',
                           'install'] + paths)


if __name__ == '__main__':
    main()
