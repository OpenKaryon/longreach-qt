# SPDX-License-Identifier: GPL-3.0-or-later

"""Collect complete API21 example evidence and bind each result to its current APK."""
import argparse
import hashlib
import importlib.util
import json
from pathlib import Path
import re
import subprocess
import sys


_spec = importlib.util.spec_from_file_location('android_baselines', Path(__file__).resolve().parents[2] / 'run/android/android-baselines.py')
_baselines = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(_baselines)

_spec = importlib.util.spec_from_file_location('android_artifacts', Path(__file__).with_name('artifact-manifest.py'))
_artifacts = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(_artifacts)

_spec = importlib.util.spec_from_file_location('android_launch', Path(__file__).resolve().parents[2] / 'run/android/android-api21-launch.py')
_launch = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(_launch)

_spec = importlib.util.spec_from_file_location('android_process_exit', Path(__file__).resolve().parents[2] / 'run/android/android-process-exit.py')
_process_exit = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(_process_exit)

_spec = importlib.util.spec_from_file_location('android_emulator_identity', Path(__file__).resolve().parents[2] / 'run/android/android-api21-identity.py')
_identity = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(_identity)

_spec = importlib.util.spec_from_file_location('android_guest_cpu', Path(__file__).resolve().parents[2] / 'run/android/android-cpu.py')
_cpu = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(_cpu)

_spec = importlib.util.spec_from_file_location('android_api21_exit_evidence', Path(__file__).resolve().parents[2] / 'run/android/android-api21-exit.py')
_exit_evidence = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(_exit_evidence)

_spec = importlib.util.spec_from_file_location('android_owned_process', Path(__file__).resolve().parents[2] / 'run/android/android-owned-process.py')
_owned = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(_owned)


def _collect(args):
    root = args.root.resolve()
    _artifacts.invalidate_results(root)
    run = root / args.run
    apps = [line.strip() for line in (Path(__file__).resolve().parents[3] / 'tests/expected-apps.txt').read_text().splitlines()
            if line.strip() and not line.startswith('#') and line.strip() != 'smoke-runner']
    expected = set(apps + ['strict-cxx23', 'widgets-gui', 'qml-gui'])
    if args.qt_major == 5:
        expected.update(('strict-cxx23-extended', 'qt-selftest-extended'))
    _artifacts.check_apks(root, args.qt_major, args.abi)
    records = json.loads((run / 'results.json').read_text(encoding='utf-8-sig'))
    apk_manifest_sha256 = _artifacts.digest(root / 'apk-manifest.json')
    if not isinstance(records, list):
        records = [records]
    if len(records) != len(expected) or {record['name'] for record in records} != expected:
        raise RuntimeError(f'The final run must contain exactly all {len(expected)} required cases')
    launch = _launch.validate(run, args.qt_major, args.abi, records)
    identity = _identity.validate(root, run, args.abi)
    cpu_evidence = _cpu.validate(run, args.abi)
    host_evidence = _owned.validate_emulator(run, artifact_root=root)
    for record in records:
        if any(record.get(key) != host_evidence[key] for key in host_evidence):
            raise ValueError('Case belongs to different owned-process evidence')
        if any(record.get(key) != cpu_evidence[key] for key in _cpu.FIELDS):
            raise ValueError('Case belongs to different guest CPU evidence: ' + record.get('name', record.get('profile', '?')))
        if any(record.get(key) != identity[key] for key in ('emulator_identity_sha256', 'emulator_media_sha256')):
            raise ValueError('Case belongs to a different API21 emulator/media identity: ' + record['name'])
    exit_evidence = _exit_evidence.validate(root, run, args.qt_major, args.abi, records, host_evidence=host_evidence)
    properties = (run / 'guest-properties.txt').read_text(encoding='utf-8-sig')
    for name, value in [('ro.build.version.release', '5.0.2'), ('ro.build.version.sdk', '21'),
                        ('ro.product.cpu.abi', args.abi)]:
        if f'[{name}]: [{value}]' not in properties:
            raise RuntimeError(f'Wrong guest: {name}')

    sdk_id = (root / 'sdk-image-id.txt').read_text().strip()
    if not re.fullmatch(r'sha256:[0-9a-f]{64}', sdk_id) or (root / 'examples-sdk-image-id.txt').read_text().strip() != sdk_id:
        raise RuntimeError('SDK and example image identities are missing or differ')

    table = ['| Case | PASS | FAIL | SKIP |', '| --- | ---: | ---: | ---: |']
    for record in records:
        if record.get('apk_manifest_sha256') != apk_manifest_sha256:
            raise RuntimeError('Case belongs to a different APK manifest: ' + record.get('name', '?'))
        name = record['name']
        apk = root / record.get('apk_relative', 'apk/' + record['app'] + '.apk')
        actual = hashlib.sha256(apk.read_bytes()).hexdigest()
        if record['result'] != 0 or record['apk_sha256'] != actual:
            raise RuntimeError(f'Failed case or APK changed after testing: {name}')
        case = run / name
        if (case / 'files/selftest-result.txt').read_text().strip() != '0':
            raise RuntimeError(f'Native result is not zero: {name}')
        log = (case / 'logcat.log').read_text(encoding='utf-8-sig')
        if 'log_marker' in record or (case / 'log-marker.txt').exists():
            marker = record.get('log_marker', '')
            if not re.fullmatch(r'BEGIN-[0-9a-f]{32}', marker):
                raise RuntimeError(f'Invalid case log marker: {name}')
            if (case / 'log-marker.txt').read_text(encoding='utf-8-sig').strip() != marker:
                raise RuntimeError(f'Case log marker differs from recorded run: {name}')
            raw = (case / 'logcat-raw.log').read_text(encoding='utf-8-sig').splitlines()
            pattern = r'^[VDIWEF]/LongreachCase\s*\(\s*\d+\):\s*' + re.escape(marker) + r'\s*$'
            indices = [i for i, line in enumerate(raw) if re.fullmatch(pattern, line)]
            if len(indices) != 1 or raw[indices[0] + 1:] != log.splitlines():
                raise RuntimeError(f'Case log does not match its raw launch boundary: {name}')
        if re.search(r'FATAL EXCEPTION|Fatal signal|exiting due to signal|terminated by signal|VM aborting', log):
            raise RuntimeError(f'Fatal cleanup error: {name}')
        app = record['app']
        package = ('org.longreachqt.examples.qt6.' + app.replace('-', '_') if args.qt_major == 6
                   else 'org.longreachqt.examples.' + app.replace('-', ''))
        _process_exit.require_exit(case, package, record)
        stdout_path = case / 'files/selftest.stdout'
        stdout = stdout_path.read_text(encoding='utf-8-sig')
        summaries = [line for line in stdout.splitlines()
                     if re.search(r'passed,.*failed,.*skipped', line)]
        if summaries != record['summary']:
            raise RuntimeError(f'Summary differs from captured stdout: {name}')
        if name.startswith('strict-cxx23'):
            gate = Path(__file__).resolve().parents[2] / 'tests/require-modern-cpp.py'
            subprocess.run([sys.executable, str(gate), str(stdout_path)], check=True)
        counts = [tuple(map(int, match.groups())) for line in record['summary']
                  if (match := re.search(r'(\d+) passed,\s*(\d+) failed,\s*(\d+) skipped', line))]
        if len(counts) != 1 or counts[0][0] < 1 or counts[0][1] != 0:
            raise RuntimeError(f'Ambiguous or failed report: {name}: {counts}')
        if name.startswith('strict-cxx23') and counts[0] != (25, 0, 0):
            raise RuntimeError('Strict C++23 must pass exactly25 without FAIL/SKIP')
        _baselines.require(args.qt_major, 21, args.abi, name, stdout)
        record.update(zip(('passed', 'failed', 'skipped'), counts[0]))
        record['evidence'] = str(case.relative_to(root)).replace('\\', '/')
        table.append(f'| {name} | {counts[0][0]} | {counts[0][1]} | {counts[0][2]} |')

    report = {
        'qt': {5: '5.15.19', 6: '6.8.5'}[args.qt_major], 'llvm': '21.1.8', 'android_release': '5.0.2', 'api': 21,
        'sdk_image_id': sdk_id, 'abi': args.abi, 'run': args.run, 'required_cases': len(expected),
        'all_required_passed': True, 'all_process_exits_confirmed': True,
        'sdk_module_libraries': len((root / 'sdk-modules.txt').read_text().splitlines()),
        'sdk_elf_libraries': len(json.loads((root / 'sdk-api21-elf.json').read_text())['libraries']),
        'cases': records,
    }
    if args.qt_major == 6:
        report['all_eleven_passed'] = True

    report.update(launch)
    report.update(identity)
    report.update(cpu_evidence)
    report.update(host_evidence)
    report.update(exit_evidence)
    report['all_host_process_trees_exited'] = True
    report['apk_manifest_sha256'] = apk_manifest_sha256
    report['examples_manifest_sha256'] = _artifacts.digest(root / 'examples-manifest.json')
    status = ('Qualification: true (validated launch options)' if report['qualification']
              else 'Qualification: false (diagnostic launch): ' + '; '.join(report['diagnostic_reasons']))
    table = [status, ''] + table
    _artifacts.write_text_atomic(root / 'final-results-table.md', '\n'.join(table) + '\n')
    _artifacts.write_json(root / 'final-results.json', report)
    print('\n'.join(table))
    print(f'All {len(expected)} cases matched their current APK SHA256 and native result0')

    return report


def collect(args):
    root = args.root.resolve()
    with _artifacts.artifact_lease(root, getattr(args, 'artifact_lease_held', False)):
        return _collect(args)


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--qt-major', choices=(5, 6), type=int, default=6)
    parser.add_argument('--abi', choices=('armeabi-v7a', 'arm64-v8a', 'x86', 'x86_64'), default='armeabi-v7a')
    parser.add_argument('--run', default='sdk-suite')
    parser.add_argument('--root', type=Path, required=True)
    parser.add_argument('--artifact-lease-held', action='store_true',
                        help='internal: the runner already holds the artifact lease')
    args = parser.parse_args(argv)
    collect(args)
    return 0


if __name__ == '__main__':
    sys.exit(main())
