# SPDX-License-Identifier: GPL-3.0-or-later
"""Require qualified per-target smoke coverage in addition to native exit zero."""
import argparse
import importlib.util
import json
from pathlib import Path
import re
import sys

BASELINES = Path(__file__).with_suffix('.json')
ALIASES = {'widgets-gallery-render': 'widgets-gui', 'quick-qml-gallery-render': 'qml-gui'}
NATIVE_SENSOR_CHECKS = ('sensors/android-acceleration-input', 'sensors/android-queue-lifecycle',
                        'sensors/android-compass-queue-lifecycle')
_spec = importlib.util.spec_from_file_location('android_timed_sync', Path(__file__).with_name('android-timed-sync.py'))
TIMED_SYNC = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(TIMED_SYNC)


def policy(qt, api, abi, case):
    """Resolve a target's shared named policy without duplicating capability lists."""
    catalog = json.loads(BASELINES.read_text(encoding='utf-8'))
    if catalog.get('schema') not in (1, 2):
        raise ValueError('Unsupported Android coverage policy schema')
    baseline = dict(catalog['targets'][f'{qt}/{api}/{abi}'][ALIASES.get(case, case)])
    profile = baseline.pop('named_profile', None)
    if profile is not None:
        names = catalog['named_profiles'][profile]
        allowed = names['allowed_skip']
        required = list(dict.fromkeys(baseline.get('required_pass', []) + names['required_pass']))
        if (not all(isinstance(name, str) and name for name in allowed + required)
                or len(allowed) != len(set(allowed)) or set(allowed) & set(required)):
            raise ValueError('Invalid named Android coverage policy: ' + profile)
        baseline.update(allowed_skip=allowed, required_pass=required, max_skip=len(allowed))
    return baseline


def native_sensor_evidence(stdout):
    inventories = re.findall(r'^OBSERVE: sensors/android-native-inventory - count=(-?\d+)\s*$', stdout, re.M)
    if len(inventories) != 1 or int(inventories[0]) < 0:
        raise ValueError('Missing, ambiguous or failed native Android sensor inventory')
    count = int(inventories[0])
    expected = 'PASS' if count else 'SKIP'
    for name in NATIVE_SENSOR_CHECKS:
        states = re.findall(r'^(PASS|FAIL|SKIP): ' + re.escape(name) + r'(?: - .*|)\s*$', stdout, re.M)
        if states != [expected]:
            raise ValueError('Native Android sensor inventory requires ' + expected + ': ' + name)
    return {'native_sensor_count': count,
            'native_sensor_coverage': 'native-queues-exercised' if count else 'unavailable'}


def require(qt, api, abi, case, stdout):
    case = ALIASES.get(case, case)
    key = f'{qt}/{api}/{abi}'
    baseline = policy(qt, api, abi, case)
    summaries = re.findall(r'^---- [^\n:]+: (\d+) passed, (\d+) failed, (\d+) skipped ----\s*$', stdout, re.M)
    if len(summaries) != 1:
        raise ValueError(f'{key}/{case}: expected one unambiguous summary')
    counts = tuple(map(int, summaries[0]))
    if counts[0] < baseline['min_pass'] or counts[1] or counts[2] > baseline['max_skip']:
        raise ValueError(f'{key}/{case}: coverage {counts}, expected at least {baseline["min_pass"]} PASS and at most {baseline["max_skip"]} SKIP')
    lines = stdout.splitlines()
    if 'allowed_skip' in baseline:
        outcomes = re.findall(r'^(PASS|FAIL|SKIP): (.+?)(?: - .*)?$', '\n'.join(lines), re.M)
        names = [name for status, name in outcomes]
        if len(names) != len(set(names)):
            raise ValueError(f'{key}/{case}: duplicate named check outcomes')
        actual = tuple(sum(status == value for status, name in outcomes) for value in ('PASS', 'FAIL', 'SKIP'))
        if actual != counts:
            raise ValueError(f'{key}/{case}: named outcomes {actual} differ from summary {counts}')
        unexpected = sorted(name for status, name in outcomes
                            if status == 'SKIP' and name not in baseline['allowed_skip'])
        if unexpected:
            raise ValueError(f'{key}/{case}: unexpected SKIP: ' + ', '.join(unexpected))
    for check in baseline.get('required_pass', []):
        if not any(line == 'PASS: ' + check or line.startswith('PASS: ' + check + ' - ') for line in lines):
            raise ValueError(f'{key}/{case}: missing required PASS: {check}')
    if baseline.get('require_timed_sync_evidence'):
        TIMED_SYNC.require(stdout)
    if baseline.get('require_native_sensor_inventory'):
        sensor = native_sensor_evidence(stdout)
        native_passes = len(NATIVE_SENSOR_CHECKS) if sensor['native_sensor_count'] else 0
        if counts[0] - native_passes < baseline['min_pass']:
            raise ValueError('Native sensor PASS cannot replace the ordinary coverage floor')
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
