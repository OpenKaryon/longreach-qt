# SPDX-License-Identifier: GPL-3.0-or-later

"""Collect complete API21 example evidence and bind each result to its current APK."""
import argparse
import hashlib
import json
from pathlib import Path
import re
import subprocess
import sys

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--run', default='sdk-suite')
parser.add_argument('--root', type=Path, required=True)
args = parser.parse_args()
root = args.root.resolve()
run = root / args.run
apps = [line.strip() for line in (Path(__file__).resolve().parents[3] / 'tests/expected-apps.txt').read_text().splitlines()
        if line.strip() and not line.startswith('#') and line.strip() != 'smoke-runner']
expected = set(apps + ['strict-cxx23', 'widgets-gui', 'qml-gui'])
subprocess.run([sys.executable, str(Path(__file__).parent.parent / 'android-api21/artifact-manifest.py'),
                'check-apks', '--root', str(root), '--qt-major', str(6), '--abi', 'armeabi-v7a'], check=True)
records = json.loads((run / 'results.json').read_text(encoding='utf-8-sig'))
if not isinstance(records, list):
    records = [records]
if len(records) != 11 or {record['name'] for record in records} != expected:
    raise RuntimeError('The final run must contain exactly all eleven required cases')
properties = (run / 'guest-properties.txt').read_text(encoding='utf-8-sig')
for name, value in [('ro.build.version.release', '5.0.2'), ('ro.build.version.sdk', '21'),
                    ('ro.product.cpu.abi', 'armeabi-v7a')]:
    if f'[{name}]: [{value}]' not in properties:
        raise RuntimeError(f'Wrong guest: {name}')

table = ['| Case | PASS | FAIL | SKIP |', '| --- | ---: | ---: | ---: |']
for record in records:
    name = record['name']
    apk = root / 'apk' / (record['app'] + '.apk')
    actual = hashlib.sha256(apk.read_bytes()).hexdigest()
    if record['result'] != 0 or record['apk_sha256'] != actual:
        raise RuntimeError(f'Failed case or APK changed after testing: {name}')
    case = run / name
    if (case / 'files/selftest-result.txt').read_text().strip() != '0':
        raise RuntimeError(f'Native result is not zero: {name}')
    log = (case / 'logcat.log').read_text(encoding='utf-8-sig')
    if re.search(r'FATAL EXCEPTION|Fatal signal|exiting due to signal|terminated by signal|VM aborting', log):
        raise RuntimeError(f'Fatal cleanup error: {name}')
    counts = [tuple(map(int, match.groups())) for line in record['summary']
              if (match := re.search(r'(\d+) passed,\s*(\d+) failed,\s*(\d+) skipped', line))]
    if len(counts) != 1 or counts[0][0] < 1 or counts[0][1] != 0:
        raise RuntimeError(f'Ambiguous or failed report: {name}: {counts}')
    if name == 'strict-cxx23' and counts[0] != (25, 0, 0):
        raise RuntimeError('Strict C++23 must pass exactly25 without FAIL/SKIP')
    record.update(zip(('passed', 'failed', 'skipped'), counts[0]))
    record['evidence'] = str(case.relative_to(root)).replace('\\', '/')
    table.append(f'| {name} | {counts[0][0]} | {counts[0][1]} | {counts[0][2]} |')

report = {
    'qt': '6.8.5', 'llvm': '21.1.8', 'android_release': '5.0.2', 'api': 21,
    'abi': 'armeabi-v7a', 'run': args.run, 'required_cases': 11,
    'all_eleven_passed': True,
    'sdk_module_libraries': len((root / 'sdk-modules.txt').read_text().splitlines()),
    'sdk_elf_libraries': len(json.loads((root / 'sdk-api21-elf.json').read_text())['libraries']),
    'cases': records,
}
(root / 'final-results.json').write_text(json.dumps(report, indent=2) + '\n')
(root / 'final-results-table.md').write_text('\n'.join(table) + '\n')
print('\n'.join(table))
print('All eleven cases matched their current APK SHA256 and native result0')
