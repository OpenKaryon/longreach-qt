# SPDX-License-Identifier: GPL-3.0-or-later
"""Verify a complete Qt4 Android run against its current SDK/APKs/raw reports."""
import argparse
import hashlib
import importlib.util
import json
from pathlib import Path
import re
import struct
import subprocess
import sys
import zipfile


_spec = importlib.util.spec_from_file_location('android_baselines', Path(__file__).resolve().parents[2] / 'run/android-baselines.py')
_baselines = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(_baselines)

_spec = importlib.util.spec_from_file_location('android_artifacts', Path(__file__).resolve().parents[1] / 'android-api21/artifact-manifest.py')
_artifacts = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(_artifacts)

_spec = importlib.util.spec_from_file_location('qt4_artifacts', Path(__file__).with_name('artifact-manifest.py'))
_qt4_artifacts = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(_qt4_artifacts)

_spec = importlib.util.spec_from_file_location('android_emulator_identity', Path(__file__).resolve().parents[2] / 'run/android-api21-identity.py')
_identity = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(_identity)

_spec = importlib.util.spec_from_file_location('android_guest_cpu', Path(__file__).resolve().parents[2] / 'run/android-cpu.py')
_cpu = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(_cpu)

_spec = importlib.util.spec_from_file_location('android_owned_process', Path(__file__).resolve().parents[2] / 'run/android-owned-process.py')
_owned = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(_owned)


_spec = importlib.util.spec_from_file_location('qt4_final_log', Path(__file__).resolve().parents[2] / 'run/android-final-log.py')
_final = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(_final)


def _collect(args):
    api, release, bits, machine = {'x86': (10, '2.3.7', 32, 3),
                                   'x86_64': (21, '5.0.2', 64, 62),
                                   'arm64-v8a': (21, '5.0.2', 64, 183)}[args.abi]
    root = args.root.resolve()
    _artifacts.invalidate_results(root)
    run = root / args.run
    required = {'bootstrap', 'strict', 'core', 'quick', 'selftest', 'widgets', 'graphics', 'painting', 'multimedia', 'gl', 'qml', 'network'}
    records = json.loads((run / 'results.json').read_text(encoding='utf-8-sig'))
    if len(records) != len(required) or {r['profile'] for r in records} != required:
        raise RuntimeError('Qt4 final evidence must contain all twelve cases and all eight shared applications')
    identity = _identity.validate(root, run, args.abi) if api == 21 else {}
    cpu_evidence = _cpu.validate(run, args.abi)
    host_evidence = _owned.validate_emulator(run, artifact_root=root)
    final_evidence = _final.capture(run, 'emulator-5580' if api == 10 else 'emulator-5582', host_evidence, last_case=run / records[-1]['profile'])
    for record in records:
        if any(record.get(key) != value for key, value in final_evidence.items()):
            raise ValueError('Case belongs to different final log capture evidence')
        if any(record.get(key) != host_evidence[key] for key in host_evidence):
            raise ValueError('Case belongs to different owned-process evidence')
        if any(record.get(key) != cpu_evidence[key] for key in _cpu.FIELDS):
            raise ValueError('Case belongs to different guest CPU evidence: ' + record.get('name', record.get('profile', '?')))
        if any(record.get(key) != identity[key] for key in identity if key.endswith('_sha256')):
            raise ValueError('Case belongs to a different API21 emulator/media identity: ' + record['profile'])
    packages = _qt4_artifacts.check_apks(root, args.abi)
    apk_manifest_sha256 = _artifacts.digest(root / 'apk-packages.json')
    apk_generation_sha256 = _artifacts.digest(root / 'apk-manifest.json')
    examples_manifest_sha256 = _artifacts.digest(root / 'examples-manifest.json')
    if len(packages) != len(required) or {r['profile'] for r in packages} != required:
        raise RuntimeError('Missing or duplicate package manifests')
    packages = {p['profile']: p for p in packages}
    sdk_id = (root / 'sdk-image-id.txt').read_text().strip()
    if not re.fullmatch(r'sha256:[0-9a-f]{64}', sdk_id) or (root / 'examples-sdk-image-id.txt').read_text().strip() != sdk_id:
        raise RuntimeError('SDK/example identity differs')
    properties = (run / 'guest-properties.txt').read_text(encoding='utf-8-sig')
    for key, value in [('ro.build.version.sdk', str(api)), ('ro.build.version.release', release), ('ro.product.cpu.abi', args.abi)]:
        if f'[{key}]: [{value}]' not in properties:
            raise RuntimeError('Wrong guest: ' + key)
    rt = hashlib.sha256((root / 'native/libc++_shared.so').read_bytes()).hexdigest()
    producer_rt = (root / 'sdk-reports/runtime-sha256.txt').read_text().split()[0]
    if rt != producer_rt:
        raise RuntimeError('Packaged runtime differs from installed SDK provenance')
    # Older qualification workflows also retained a platform-only runtime probe.
    probe = root / 'probe/libc++_shared.so'
    if probe.exists() and rt != hashlib.sha256(probe.read_bytes()).hexdigest():
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
        if record.get('apk_manifest_sha256') != apk_manifest_sha256:
            raise RuntimeError('Case belongs to a different Qt4 APK manifest: ' + record.get('profile', '?'))
        if (record.get('apk_generation_manifest_sha256') != apk_generation_sha256 or
                record.get('examples_manifest_sha256') != examples_manifest_sha256):
            raise RuntimeError('Case belongs to a different Qt4 native/APK generation: ' + record.get('profile', '?'))
        name = record['profile']
        case = run / name
        package = packages[name]
        apk = root / (name + '.apk')
        if package['apk'] != apk.name or package['abi'] != args.abi or package['api'] != api or package['sdk_image_id'] != sdk_id:
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
        if re.search(r'Fatal signal|FATAL EXCEPTION|VM aborting|terminated by signal|exiting due to signal|\*\*\*\s+\*\*\*\s+\*\*\*', log):
            raise RuntimeError('Fatal cleanup error: ' + name)
        _final.case_cleanup(case, marker, record)
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
        if name in labels:
            _baselines.require(4, api, args.abi, name, stdout)
        if tuple(record[field] for field in ('passed', 'failed', 'skipped')) != counts:
            raise RuntimeError('Counts differ from captured report: ' + name)
        with zipfile.ZipFile(apk) as archive:
            libs = [p for p in archive.namelist() if p.startswith('lib/') and p.endswith('.so')]
            if set(libs) != {f'lib/{args.abi}/libc++_shared.so', f'lib/{args.abi}/libdonut_probe.so'}:
                raise RuntimeError('Unexpected packaged native libraries: ' + name)
            for member in libs:
                _artifacts.native_abi().inspect_bytes(archive.read(member), args.abi, member)
            if hashlib.sha256(archive.read(f'lib/{args.abi}/libc++_shared.so')).hexdigest() != rt:
                raise RuntimeError('APK contains another C++ runtime: ' + name)
        proof.append({'profile': name, 'apk': apk.name, 'sha256': sha, 'native_libraries': len(libs), 'elf_bits': bits, 'elf_machine': machine, 'runtime_sha256': rt})
        table.append(f'| {name} | {counts[0]} | 0 | {counts[2]} |')
    report = {'qt': '4.8.7', 'llvm': '21.1.8', 'abi': args.abi, 'api': api, 'android_release': release,
              'sdk_image_id': sdk_id, 'run': args.run, 'required_cases': 12, 'all_required_passed': True, 'cases': records}
    report.update(identity)
    report.update(cpu_evidence)
    report.update(host_evidence)
    report.update(final_evidence)
    report['all_host_process_trees_exited'] = True
    report['apk_manifest_sha256'] = apk_manifest_sha256
    report['apk_generation_manifest_sha256'] = apk_generation_sha256
    report['examples_manifest_sha256'] = examples_manifest_sha256
    _artifacts.write_json(root / 'apk-architecture-final.json', proof)
    _artifacts.write_json(root / 'screenshots.json', shots)
    _artifacts.write_text_atomic(root / 'final-results-table.md', '\n'.join(table) + '\n')
    _artifacts.write_json(root / 'final-results.json', report)
    print('\n'.join(table))
    print('All12 cases, current SDK/APKs, exact runtime and launch evidence passed')

    return report


def collect(args):
    root = args.root.resolve()
    with _artifacts.artifact_lease(root, getattr(args, 'artifact_lease_held', False)):
        return _collect(args)


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--root', type=Path, required=True)
    parser.add_argument('--run', required=True)
    parser.add_argument('--abi', choices=('x86', 'x86_64', 'arm64-v8a'), required=True)
    parser.add_argument('--artifact-lease-held', action='store_true',
                        help='internal: the runner already holds the artifact lease')
    args = parser.parse_args(argv)
    collect(args)
    return 0


if __name__ == '__main__':
    sys.exit(main())
