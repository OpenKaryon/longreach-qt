# SPDX-License-Identifier: GPL-3.0-or-later
"""Require qualified per-target smoke coverage in addition to native exit zero."""
import argparse
import json
from pathlib import Path
import re
import sys

BASELINES = Path(__file__).with_suffix('.json')
ALIASES = {'widgets-gallery-render': 'widgets-gui', 'quick-qml-gallery-render': 'qml-gui'}


def require(qt, api, abi, case, stdout):
    case = ALIASES.get(case, case)
    key = f'{qt}/{api}/{abi}'
    baseline = json.loads(BASELINES.read_text())['targets'][key][case]
    summaries = re.findall(r'^---- [^\n:]+: (\d+) passed, (\d+) failed, (\d+) skipped ----\s*$', stdout, re.M)
    if len(summaries) != 1:
        raise ValueError(f'{key}/{case}: expected one unambiguous summary')
    counts = tuple(map(int, summaries[0]))
    if counts[0] < baseline['min_pass'] or counts[1] or counts[2] > baseline['max_skip']:
        raise ValueError(f'{key}/{case}: coverage {counts}, expected at least {baseline["min_pass"]} PASS and at most {baseline["max_skip"]} SKIP')
    lines = stdout.splitlines()
    for check in baseline.get('required_pass', []):
        if not any(line == 'PASS: ' + check or line.startswith('PASS: ' + check + ' - ') for line in lines):
            raise ValueError(f'{key}/{case}: missing required PASS: {check}')
    if case in ('strict', 'strict-cxx23', 'strict-cxx23-extended') and counts != (25, 0, 0):
        raise ValueError('C++23 must pass exactly25 without SKIP')
    return counts


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--qt', type=int, required=True)
    parser.add_argument('--api', type=int, required=True)
    parser.add_argument('--abi', required=True)
    parser.add_argument('--case', required=True)
    parser.add_argument('--report', type=Path, required=True)
    args = parser.parse_args()
    counts = require(args.qt, args.api, args.abi, args.case, args.report.read_text(encoding='utf-8-sig'))
    print(f'{args.case}: coverage {counts} PASS')


if __name__ == '__main__':
    try:
        main()
    except (OSError, ValueError, KeyError) as error:
        sys.exit(f'Android coverage validation failed: {error}')
