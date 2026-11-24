# SPDX-License-Identifier: GPL-3.0-or-later
"""Require the current cross-DSO generic atomic protocol, not historical output."""
import argparse
from pathlib import Path

EXPECTED = {
    'ATOMIC_PROVIDER:': 'ATOMIC_PROVIDER: libc++_shared.so',
    'ATOMIC_WORKERS:': 'ATOMIC_WORKERS: 2',
    'ATOMIC_EXIT:': 'ATOMIC_EXIT:0',
    'PASS:': 'PASS: generic 24-byte cross-DSO atomic store/load/exchange/CAS/thread handoff',
}


def validate(text):
    lines = [line.strip() for line in text.splitlines()]
    if any(line.startswith('FAIL:') for line in lines):
        raise ValueError('Atomic probe reported a failure')
    for prefix, expected in EXPECTED.items():
        if [line for line in lines if line.startswith(prefix)] != [expected]:
            raise ValueError('Missing, duplicate or incorrect atomic probe output: ' + prefix)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('stdout', type=Path)
    args = parser.parse_args()
    try:
        validate(args.stdout.read_text(encoding='utf-8-sig'))
    except (OSError, ValueError) as error:
        parser.exit(1, str(error) + '\n')
    print('Atomic output: generic 24-byte cross-DSO protocol PASS')


if __name__ == '__main__':
    main()
