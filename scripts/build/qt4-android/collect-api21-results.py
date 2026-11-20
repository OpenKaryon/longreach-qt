# SPDX-License-Identifier: GPL-3.0-or-later
"""Verify a complete Qt4 Android run against its current SDK/APKs/raw reports."""
import argparse
import hashlib
import json
from pathlib import Path
import re
import struct
import subprocess
import sys
import zipfile

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--root', type=Path, required=True)
parser.add_argument('--run', required=True)
parser.add_argument('--abi', choices=('x86_64',), required=True)
args = parser.parse_args()
root = args.root.resolve()
run = root / args.run
required = {'bootstrap', 'strict', 'core', 'quick', 'selftest', 'widgets', 'graphics', 'painting', 'multimedia', 'gl', 'qml', 'network'}
records = json.loads((run / 'results.json').read_text(encoding='utf-8-sig'))
if len(records) != len(required) or {r['profile'] for r in records} != required:
    raise RuntimeError('Qt4 final evidence must contain all twelve cases and all eight shared applications')
packages = json.loads((root / 'apk-packages.json').read_text(encoding='utf-8-sig'))
if len(packages) != len(required) or {r['profile'] for r in packages} != required:
    raise RuntimeError('Missing or duplicate package manifests')
packages = {p['profile']: p for p in packages}
sdk_id = (root / 'sdk-image-id.txt').read_text().strip()
if not re.fullmatch(r'sha256:[0-9a-f]{64}', sdk_id) or (root / 'examples-sdk-image-id.txt').read_text().strip() != sdk_id:
    raise RuntimeError('SDK/example identity differs')
properties = (run / 'guest-properties.txt').read_text(encoding='utf-8-sig')
for key, value in [('ro.build.version.sdk', '21'), ('ro.build.version.release', '5.0.2'), ('ro.product.cpu.abi', args.abi)]:
    if f'[{key}]: [{value}]' not in properties:
        raise RuntimeError('Wrong guest: ' + key)
rt = hashlib.sha256((root / 'native/libc++_shared.so').read_bytes()).hexdigest()
probe_rt = hashlib.sha256((root / 'probe/libc++_shared.so').read_bytes()).hexdigest()
if rt != probe_rt:
    raise RuntimeError('Packaged runtime differs from separately tested C++23 runtime')
labels = {'selftest': 'qt-selftest', 'widgets': 'widgets-gallery', 'graphics': 'graphics', 'painting': 'painting-lab',
          'multimedia': 'multimedia-lab', 'gl': 'gl-heavy', 'qml': 'quick-qml', 'network': 'network-gui'}
checks = ['PASS: qrc and first frame', 'PASS: Android tap updates QML and frame',
          'PASS: Android pause and resume preserve input and rendering',
          'PASS: shared Qt Quick Gallery renders and navigates',
          'PASS: shared Widgets Gallery toggles a checkbox and changes tabs']
proof, shots = [], []
table = ['| Case | PASS | FAIL | SKIP |', '| --- | ---: | ---: | ---: |']
for record in records:
    name = record['profile']
    case = run / name
    package = packages[name]
    apk = root / (name + '.apk')
    if package['apk'] != apk.name or package['abi'] != args.abi or package['api'] != 21 or package['sdk_image_id'] != sdk_id:
        raise RuntimeError('Wrong APK metadata: ' + name)
    sha = hashlib.sha256(apk.read_bytes()).hexdigest()
    if sha != package['sha256'] or sha != record['apk_sha256'] or record['sdk_image_id'] != sdk_id:
        raise RuntimeError('APK or SDK changed after testing: ' + name)
    marker = record['log_marker']
    if not re.fullmatch(r'BEGIN-[0-9a-f]{32}', marker) or (case / 'log-marker.txt').read_text().strip() != marker:
        raise RuntimeError('Invalid launch marker: ' + name)
    raw = (case / 'logcat-raw.log').read_text(encoding='utf-8-sig').splitlines()
    log = (case / 'logcat.log').read_text(encoding='utf-8-sig')
    pattern = r'^[VDIWEF]/LongreachCase\s*\(\s*\d+\):\s*' + re.escape(marker) + r'\s*$'
    indices = [i for i, line in enumerate(raw) if re.fullmatch(pattern, line)]
    if len(indices) != 1 or raw[indices[0] + 1:] != log.splitlines():
        raise RuntimeError('Scoped log differs from its raw launch boundary: ' + name)
    if re.search(r'Fatal signal|FATAL EXCEPTION|VM aborting|terminated by signal|exiting due to signal', log):
        raise RuntimeError('Fatal cleanup error: ' + name)
    if name != 'quick':
        expected = 42 if name == 'bootstrap' else 0
        if record['native_return'] != expected or int((case / 'files/probe-result.txt').read_text()) != expected:
            raise RuntimeError('Wrong native return: ' + name)
    if name == 'strict':
        gate = Path(__file__).resolve().parents[2] / 'tests/require-modern-cpp.py'
        subprocess.run([sys.executable, str(gate), str(case / 'files/strict-cxx23.log')], check=True)
        counts = (25, 0, 0)
    elif name == 'quick':
        if record['native_return'] is not None or record['instrumentation_code'] != -1:
            raise RuntimeError('Wrong GUI instrumentation result')
        instrument = (case / 'instrumentation.log').read_text(encoding='utf-8-sig')
        if not re.search(r'^INSTRUMENTATION_CODE: -1\s*$', instrument, re.M):
            raise RuntimeError('Missing successful Android instrumentation completion')
        stdout = (case / 'files/quick-smoke.txt').read_text(encoding='utf-8-sig').splitlines()
        if not all(check in stdout for check in checks):
            raise RuntimeError('Incomplete input/lifecycle/gallery checks')
        counts = (5, 0, 0)
        for png in ('qml-gallery.png', 'widgets-gallery.png'):
            path = case / 'files' / png
            data = path.read_bytes()
            if data[:8] != b'\x89PNG\r\n\x1a\n':
                raise RuntimeError('Invalid gallery PNG')
            width, height = struct.unpack('>II', data[16:24])
            if width < 200 or height < 200:
                raise RuntimeError('Gallery PNG is too small')
            shots.append({'path': str(path.relative_to(root)), 'width': width, 'height': height,
                          'sha256': hashlib.sha256(data).hexdigest()})
    elif name in labels:
        stdout = (case / 'files/suite.log').read_text(encoding='utf-8-sig')
        summaries = [line for line in stdout.splitlines() if re.search(r'passed,.*failed,.*skipped', line)]
        if summaries != record['summary'] or len(summaries) != 1:
            raise RuntimeError('Ambiguous ordinary stdout: ' + name)
        match = re.fullmatch(r'---- ' + re.escape(labels[name]) + r': ([1-9][0-9]*) passed, 0 failed, ([0-9]+) skipped ----\s*', summaries[0])
        if not match:
            raise RuntimeError('Failed ordinary summary: ' + name)
        counts = (int(match[1]), 0, int(match[2]))
    else:
        if name == 'core' and 'QtCore 4.8.7 PASS' not in log:
            raise RuntimeError('Missing QtCore behavior check')
        counts = (1, 0, 0)
    if tuple(record[field] for field in ('passed', 'failed', 'skipped')) != counts:
        raise RuntimeError('Counts differ from captured report: ' + name)
    with zipfile.ZipFile(apk) as archive:
        libs = [p for p in archive.namelist() if p.startswith('lib/') and p.endswith('.so')]
        if set(libs) != {f'lib/{args.abi}/libc++_shared.so', f'lib/{args.abi}/libdonut_probe.so'}:
            raise RuntimeError('Unexpected packaged native libraries: ' + name)
        for member in libs:
            header = archive.read(member)[:20]
            if header[:6] != b'\x7fELF\x02\x01' or struct.unpack_from('<H', header, 18)[0] != 62:
                raise RuntimeError('Wrong native ABI: ' + member)
        if hashlib.sha256(archive.read(f'lib/{args.abi}/libc++_shared.so')).hexdigest() != rt:
            raise RuntimeError('APK contains another C++ runtime: ' + name)
    proof.append({'profile': name, 'apk': apk.name, 'sha256': sha, 'elf64_x86_64_libraries': len(libs), 'runtime_sha256': rt})
    table.append(f'| {name} | {counts[0]} | 0 | {counts[2]} |')
report = {'qt': '4.8.7', 'llvm': '21.1.8', 'abi': args.abi, 'api': 21, 'android_release': '5.0.2',
          'sdk_image_id': sdk_id, 'run': args.run, 'required_cases': 12, 'all_required_passed': True, 'cases': records}
(root / 'final-results.json').write_text(json.dumps(report, indent=2) + '\n')
(root / 'final-results-table.md').write_text('\n'.join(table) + '\n')
(root / 'apk-architecture-final.json').write_text(json.dumps(proof, indent=2) + '\n')
(root / 'screenshots.json').write_text(json.dumps(shots, indent=2) + '\n')
print('\n'.join(table))
print('All12 cases, current SDK/APKs, exact runtime and launch evidence passed')
