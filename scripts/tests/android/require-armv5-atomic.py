# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2026 OpenKaryon
"""Require API4's direct compatibility calls; guest/host exit remains separate."""
import argparse
from pathlib import Path
import re

EXPECTED = ('barrier-call=PASS', 'word-cas=PASS', 'word-fetch-add=PASS',
            'word-fetch-sub=PASS', 'word-fetch-and=PASS', 'word-exchange=PASS',
            'byte-cas-lanes=PASS', 'byte-exchange-lanes=PASS',
            'word-contention=PASS workers=4 iterations=1024 final=4096',
            'byte-contention=PASS workers=4 iterations=1024 final=a3a2a1a0')


def validate(text):
    lines = re.findall(r'^ARMV5_ATOMIC: ([^\r\n]+)', text, re.M)
    if not lines or not re.fullmatch(r'helper_version=[0-9]+', lines[0]):
        raise ValueError('API4 atomic probe has no kernel helper version')
    if int(lines[0].split('=')[1]) < 3:
        raise ValueError('API4 atomic probe requires kernel helpers version3 or later')
    if lines[1:] != list(EXPECTED):
        raise ValueError('API4 atomic operations or contention observations differ')
    return len(EXPECTED)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('stdout', type=Path)
    args = parser.parse_args()
    try:
        count = validate(args.stdout.read_text(encoding='utf-8-sig'))
    except (OSError, ValueError) as error:
        parser.exit(1, str(error) + '\n')
    print(f'API4 atomic compatibility: {count} direct/contended observations; exit evidence is separate')


if __name__ == '__main__':
    main()
