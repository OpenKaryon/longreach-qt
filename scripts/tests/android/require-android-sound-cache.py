# SPDX-License-Identifier: GPL-3.0-or-later
"""Require the WAV diagnostic's pre-exit phases, separately from process exit."""
import argparse
from pathlib import Path

EXPECTED = (
    'SOUND_CACHE: protocol=1',
    'SOUND_CACHE: wav=pcm-s16le-8000-mono',
    'SOUND_CACHE: ready=1',
    'SOUND_CACHE: playing=1',
    'SOUND_CACHE: destroyed=1',
    'SOUND_CACHE: return=0',
)


def validate(text):
    lines = [line.strip() for line in text.splitlines()]
    if any(line.startswith('FAIL:') for line in lines):
        raise ValueError('Sound-cache diagnostic reported a failure')
    if tuple(line for line in lines if line.startswith('SOUND_CACHE:')) != EXPECTED:
        raise ValueError('Missing, duplicate, unordered or incorrect sound-cache pre-exit phases')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('stdout', type=Path)
    args = parser.parse_args()
    try:
        validate(args.stdout.read_text(encoding='utf-8-sig'))
    except (OSError, ValueError) as error:
        parser.exit(1, str(error) + '\n')
    print('Sound-cache pre-exit protocol: PASS; process exit needs separate proof')


if __name__ == '__main__':
    main()
