#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2026 OpenKaryon
"""Fetch or verify the locked CentOS 7 RPMs for Qt 6 Linux amd64."""

import argparse
import json
from pathlib import Path

import fetch

ROOT = Path(__file__).resolve().parents[2]
LOCK = ROOT / 'scripts/fetch/locks/qt6-centos7-x86_64-packages.json'


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--rpm-dir', type=Path, default=ROOT / 'downloads/centos7-x86_64')
    parser.add_argument('--check', action='store_true', help='verify the complete set without downloading')
    args = parser.parse_args()
    lock = json.loads(LOCK.read_text(encoding='utf-8'))
    for transaction in lock['transactions']:
        for item in transaction['packages']:
            path = str(args.rpm_dir / item['file'])
            if args.check:
                fetch.verify(path, item['sha256'])
            else:
                fetch.main([item['url'], path, item['sha256']])


if __name__ == '__main__':
    main()
