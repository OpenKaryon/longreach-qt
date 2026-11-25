# SPDX-License-Identifier: GPL-3.0-or-later
"""Require explicit AndroidExtras observations; host process proofs are separate."""
import argparse
from pathlib import Path
import re

CHECKS = ('context-and-ui-thread', 'intent-values', 'activity-result',
          'cross-process-service', 'parcel-binder-echo', 'reverse-binder-callbacks',
          'service-unbind-exit', 'service-restart-exit')


def validate(text):
    checks = re.findall(r'^ANDROID_EXTRAS: ([a-z-]+)=(PASS|FAIL)\s*$', text, re.M)
    if checks != [(name, 'PASS') for name in CHECKS]:
        raise ValueError('AndroidExtras requires all eight named behavioral checks')
    rows = re.findall(r'^ANDROID_EXTRAS: service-round=([01]) pid=([1-9][0-9]*) nonce=([0-9a-f]{32}) '
                      r'calls=8 callbacks=8 native_result=0 exited=1\s*$', text, re.M)
    if len(rows) != 2 or [row[0] for row in rows] != ['0', '1']:
        raise ValueError('AndroidExtras requires two completed service rounds')
    if rows[0][1] == rows[1][1] or rows[0][2] == rows[1][2]:
        raise ValueError('AndroidExtras requires fresh service PID and nonce')
    summary = re.findall(r'^ANDROID_EXTRAS: summary=([^\r\n]+)', text, re.M)
    if summary != ['PASS checks=8 service_processes=2 transactions=16 callbacks=16']:
        raise ValueError('AndroidExtras summary differs from its explicit scenario')
    return [{'round': int(index), 'pid': int(pid), 'nonce': nonce} for index, pid, nonce in rows]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('stdout', type=Path)
    args = parser.parse_args()
    try:
        validate(args.stdout.read_text(encoding='utf-8-sig'))
    except (OSError, ValueError) as error:
        parser.exit(1, str(error) + '\n')
    print('AndroidExtras:8 observations; two service processes; independent host exit evidence is still required')


if __name__ == '__main__':
    main()
