# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2026 OpenKaryon
"""Require explicit real-service TTS observations; process exit is separate."""
import argparse
from pathlib import Path
import re

CASES = ('android-ready-and-voices', 'short-completion', 'repeated-short-completions',
         'stop-active-request', 'pause-stable-before-resume', 'resume-to-completion',
         'replace-active-request', 'destroy-active-and-recreate')
EXPECTED_STATES = {
    'short-completion': ('Speaking', 'Ready'),
    'repeated-short-completions': ('Speaking', 'Ready') * 4,
    'stop-active-request': ('Speaking', 'Ready'),
    'pause-stable-before-resume': ('Speaking', 'Paused'),
    'resume-to-completion': ('Speaking', 'Ready'),
    'replace-active-request': ('Speaking', 'Ready', 'Speaking', 'Ready'),
    'destroy-active-and-recreate/old': ('Speaking',),
    'destroy-active-and-recreate/new': ('Speaking', 'Ready'),
}


def validate(text):
    if re.search(r'^(FAIL|SKIP):', text, re.M):
        raise ValueError('TTS behavior requires all eight checks without FAIL/SKIP')
    outcomes = re.findall(r'^PASS: (.+?)\s*$', text, re.M)
    if outcomes != ['speech/' + name for name in CASES]:
        raise ValueError('Missing, duplicate, unordered or unknown TTS behavior result')
    if re.findall(r'^(---- [^\r\n]+ ----)[ \t]*$', text, re.M) != ['---- tts-behavior: 8 passed, 0 failed, 0 skipped ----']:
        raise ValueError('TTS behavior summary differs from eight explicit results')
    ready = re.findall(r'^OBSERVE: speech/android-ready-and-voices - engines=([^\n]*) voices=([1-9][0-9]*) state=Ready callback_thread_ok=1\s*$', text, re.M)
    if len(ready) != 1 or 'android' not in ready[0][0].split(','):
        raise ValueError('TTS behavior has no ready Android engine with voices on its owner thread')
    for name, expected in EXPECTED_STATES.items():
        actual = re.findall(r'^OBSERVE: speech/' + re.escape(name) + r' - state=(.+?)\s*$', text, re.M)
        # Each freshly created engine can emit Ready before its request.
        if name.startswith('destroy-active-and-recreate/'):
            while actual and actual[0] == 'Ready':
                actual.pop(0)
        if actual != list(expected):
            raise ValueError('TTS observed state order differs: ' + name)
    for name, state in (('stop-active-request', 'Ready'), ('pause-stable-before-resume', 'Paused')):
        observed = re.findall(r'^OBSERVE: speech/' + name + r' - observation_ms=([0-9]+) final=' + state + r' callback_thread_ok=1\s*$', text, re.M)
        if len(observed) != 1 or int(observed[0]) < 250:
            raise ValueError('TTS bounded stop/pause observation differs: ' + name)
    if re.findall(r'^OBSERVE: speech/repeated-short-completions - completed_requests=([0-9]+)\s*$', text, re.M) != ['4']:
        raise ValueError('TTS repeated completion count differs')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('stdout', type=Path)
    args = parser.parse_args()
    try:
        validate(args.stdout.read_text(encoding='utf-8-sig'))
    except (OSError, ValueError) as error:
        parser.exit(1, str(error) + '\n')
    print('TTS behavior observations: PASS; native/host exit and audible output need separate evidence')


if __name__ == '__main__':
    main()
