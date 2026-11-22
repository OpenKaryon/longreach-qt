# SPDX-License-Identifier: GPL-3.0-or-later
"""Finalize API10 cases, including the x86 COW preflight, from launch receipts."""
import argparse
import hashlib
import importlib.util
import json
from pathlib import Path
import re
import subprocess
import sys
import zipfile

REPO = Path(__file__).resolve().parents[3]


def module(name, path):
    spec = importlib.util.spec_from_file_location(name, path)
    result = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(result)
    return result


coverage = module('android_baselines', REPO / 'scripts/run/android-baselines.py')
artifacts = module('android_artifacts', REPO / 'scripts/build/android-api21/artifact-manifest.py')
native = module('android_native_abi', REPO / 'scripts/build/android-api21/native-abi.py')


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def collect(root, run_name, abi):
    # Invalidate old aggregate success before examining the new run.
    for name in ('final-results.json', 'final-results-table.md', 'apk-native-abi-check.json'):
        (root / name).unlink(missing_ok=True)
    artifacts.check_apks(root, 5, abi)
    sdk = (root / 'sdk-image-id.txt').read_text().strip()
    if not re.fullmatch(r'sha256:[0-9a-f]{64}', sdk):
        raise ValueError('Missing SDK identity')
    runtime = digest(root / 'native/libc++_shared.so')
    apps = artifacts.APPS
    cases = [(app, 'apk/' + app + '.apk') for app in apps]
    cases += [('strict-cxx23', 'apk/qt-selftest.apk'),
              ('strict-cxx23-extended', 'apk/extended/qt-selftest.apk'),
              ('qt-selftest-extended', 'apk/extended/qt-selftest.apk'),
              ('widgets-gallery-render', 'apk/widgets-gallery.apk'),
              ('quick-qml-gallery-render', 'apk/quick-qml-gallery.apk')]
    if abi == 'x86':
        cases.insert(0, ('atomic-cow', 'apk/qt-selftest.apk'))
    records, proof = [], []
    emulator_identity = None
    for name, relative in cases:
        case = root / run_name / name
        receipt = json.loads((case / 'input-receipt.json').read_text(encoding='utf-8-sig'))
        apk = root / relative
        sha = digest(apk)
        if (receipt.get('completed') is not True or receipt.get('case') != name or
                receipt.get('sdk_image_id') != sdk or receipt.get('abi') != abi or
                receipt.get('api') != 10 or receipt.get('apk_sha256') != sha):
            raise ValueError('Missing or mismatched launch receipt: ' + name)
        if abi == 'x86':
            emulator_sha = receipt.get('emulator_sha256', '')
            if (not re.fullmatch(r'[0-9a-f]{64}', emulator_sha) or
                    (emulator_identity is not None and emulator_sha != emulator_identity)):
                raise ValueError('Different or missing emulator identity: ' + name)
            emulator_identity = emulator_sha
        power = case / 'power-before.txt'
        if digest(power) != receipt.get('guest_power_sha256') or not re.search(r'\bmStayOn(?:Conditions|Setting)=(?:3|7)\b', power.read_text(encoding='utf-8-sig')):
            raise ValueError('Missing verified guest power policy: ' + name)
        guest = (case / 'guest.txt').read_text(encoding='utf-8-sig')
        for key, value in [('ro.build.version.sdk', '10'), ('ro.product.cpu.abi', abi),
                           ('ro.build.version.release', '2.3.7' if abi == 'x86' else '2.3.3')]:
            if key + '=' + value not in guest.splitlines():
                raise ValueError('Wrong guest: ' + name + '/' + key)
        stdout_path = case / 'files/selftest.stdout'
        stdout = stdout_path.read_text(encoding='utf-8-sig')
        if digest(stdout_path) != receipt.get('stdout_sha256') or (case / 'files/selftest-result.txt').read_text().strip() != '0':
            raise ValueError('Changed report or nonzero native exit: ' + name)
        log = (case / 'logcat.log').read_text(encoding='utf-8-sig')
        if re.search(r'FATAL EXCEPTION|Fatal signal|exiting due to signal|terminated by signal|VM aborting', log):
            raise ValueError('Fatal cleanup error: ' + name)
        counts = coverage.require(5, 10, abi, name, stdout)
        if name.startswith('strict-cxx23'):
            subprocess.run([sys.executable, str(REPO / 'scripts/tests/require-modern-cpp.py'), str(stdout_path)], check=True)
        with zipfile.ZipFile(apk) as archive:
            libs = [p for p in archive.namelist() if p.startswith('lib/') and p.endswith('.so')]
            if not libs or any(p.split('/')[1] != abi for p in libs) or len(set(libs)) != len(libs):
                raise ValueError('Missing, duplicate or mixed native ABI: ' + name)
            for member in libs:
                native.inspect_header(archive.read(member)[:20], abi, member)
            if hashlib.sha256(archive.read(f'lib/{abi}/libc++_shared.so')).hexdigest() != runtime:
                raise ValueError('Wrong packaged C++ runtime: ' + name)
        record = {'name': name, 'apk_relative': relative, 'apk_sha256': sha,
                  'sdk_image_id': sdk, 'stdout_sha256': digest(stdout_path),
                  'native_exit': 0, 'passed': counts[0], 'failed': counts[1], 'skipped': counts[2],
                  'evidence': case.relative_to(root).as_posix()}
        records.append(record)
        proof.append({'case': name, 'apk': relative, 'sha256': sha, 'abi': abi,
                      'native_libraries': len(libs), 'runtime_sha256': runtime})
    report = {'qt': '5.15.19', 'llvm': '21.1.8', 'api': 10, 'abi': abi,
              'sdk_image_id': sdk, 'runtime_sha256': runtime, 'run': run_name,
              'required_cases': len(cases), 'all_required_passed': True, 'cases': records,
              'emulator_sha256': emulator_identity}
    (root / 'final-results.json').write_text(json.dumps(report, indent=2) + '\n')
    (root / 'apk-native-abi-check.json').write_text(json.dumps(proof, indent=2) + '\n')
    table = ['| Case | PASS | FAIL | SKIP |', '| --- | ---: | ---: | ---: |']
    table += [f'| {r["name"]} | {r["passed"]} | 0 | {r["skipped"]} |' for r in records]
    (root / 'final-results-table.md').write_text('\n'.join(table) + '\n')
    print('\n'.join(table))
    return report


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--root', type=Path, required=True)
    parser.add_argument('--run', required=True)
    parser.add_argument('--abi', choices=('armeabi-v7a', 'x86'), required=True)
    args = parser.parse_args()
    collect(args.root.resolve(), args.run, args.abi)
