#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2026 OpenKaryon
"""Scan the tracked tree for things a public repository must not carry.

    python3 scripts/audit/repo_scan.py            # leak scan
    python3 scripts/audit/repo_scan.py --spdx     # also require SPDX headers
    python3 scripts/audit/repo_scan.py --exclude DIR/   # skip a tracked prefix

Leaks: host paths of a developer machine, e-mail addresses other than
noreply ones, private keys, passwords handed to tools, torrent and magnet
links. Exits 1 when anything is found.
"""
import argparse
import re
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]

LEAKS = [
    ('host path', re.compile(r'(?i)\b[A-Z]:[\\/](?:Users|Projects|Virtual Machines|YandexDisk)\b')),
    ('host path', re.compile(r'(?i)/(?:mnt/)?[cd]/(?:Users|Projects)/')),
    ('host path', re.compile(r'(?i)/Users/[A-Za-z][\w.-]*/(?:Desktop|Documents|Downloads)\b')),
    ('e-mail', re.compile(r'\b[\w.+-]+@(?!users\.noreply\.github\.com|anthropic\.com|example\.(?:com|org))[\w-]+(?:\.[\w-]+)+\b')),
    ('private key', re.compile(r'-----BEGIN [A-Z ]*PRIVATE KEY-----')),
    ('password', re.compile(r'(?i)(?:\s-gp\s+\S|\bpassword\s*[:=]\s*["\']?[^\s"\'<>$%{]{4,})')),
    ('torrent', re.compile(r'(?i)magnet:\?xt=|\.torrent\b|\brutracker\b|\bthepiratebay\b')),
]
# Matches that are not leaks: SPDX/licence boilerplate and placeholders.
ALLOW = re.compile(r'(?i)<[^>]*password[^>]*>|password\s*[:=]\s*["\']?(?:\$|%|\{|<|none|null|empty|required)')

# Files allowed one kind of match, with the reason.
ALLOW_FILES = {
    ('tests/common/tls-loopback-fixture.h', 'private key'):
        'a throwaway self-signed key the TLS loopback check serves to itself',
    ('patches/qt6/all/01-qtopcua-isolate-openssl-symbols.patch', 'private key'):
        'the PEM marker as a string literal in Qt OPC UA code',
}

TEXT_SUFFIXES = {'', '.c', '.cc', '.cpp', '.h', '.hpp', '.m', '.mm', '.qml', '.js', '.py', '.sh', '.ps1',
                 '.cmake', '.txt', '.md', '.json', '.yml', '.yaml', '.pro', '.pri', '.prf', '.conf',
                 '.patch', '.diff', '.s', '.ui', '.qrc', '.xml', '.html', '.css', '.in', '.toml', '.ini',
                 '.mk'}
SPDX_SUFFIXES = {'.c', '.cc', '.cpp', '.h', '.hpp', '.m', '.mm', '.qml', '.js', '.py', '.sh', '.ps1',
                 '.cmake', '.pro', '.pri', '.yml', '.yaml', '.s', '.patch', '.conf', '.mk'}


def tracked(exclude=()):
    out = subprocess.run(['git', 'ls-files', '-z'], cwd=ROOT, capture_output=True, check=True).stdout
    for name in out.decode('utf-8', 'surrogateescape').split('\0'):
        if name and not name.startswith(tuple(exclude)):
            yield name


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument('--spdx', action='store_true', help='require an SPDX-License-Identifier in source files')
    parser.add_argument('--exclude', action='append', default=[], metavar='PREFIX',
                        help='skip tracked paths that start with PREFIX (repeatable)')
    args = parser.parse_args()
    problems = 0
    for name in tracked(args.exclude):
        path = ROOT / name
        if path.suffix.lower() not in TEXT_SUFFIXES and path.name not in ('Dockerfile', 'Makefile'):
            continue
        try:
            text = path.read_text(encoding='utf-8')
        except (UnicodeDecodeError, OSError):
            continue
        # This file spells the patterns it looks for.
        for number, line in enumerate(text.splitlines() if name != 'scripts/audit/repo_scan.py' else [], 1):
            for kind, pattern in LEAKS:
                match = pattern.search(line)
                if match and not ALLOW.search(line) and (name, kind) not in ALLOW_FILES:
                    print(f'{name}:{number}: {kind}: {match.group(0)}')
                    problems += 1
        if args.spdx and (path.suffix.lower() in SPDX_SUFFIXES or path.name in ('Dockerfile', 'Makefile')
                          or 'Dockerfile' in path.name):
            if 'SPDX-License-Identifier:' not in '\n'.join(text.splitlines()[:15]):
                print(f'{name}:1: no SPDX-License-Identifier in the first 15 lines')
                problems += 1
    if problems:
        print(f'{problems} problem(s)', file=sys.stderr)
        return 1
    print('repository scan: clean')
    return 0


if __name__ == '__main__':
    sys.exit(main())
