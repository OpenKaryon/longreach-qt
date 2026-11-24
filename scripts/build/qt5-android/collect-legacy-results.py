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


coverage = module('android_baselines', REPO / 'scripts/run/android/android-baselines.py')
artifacts = module('android_artifacts', REPO / 'scripts/build/android-api21/artifact-manifest.py')
native = module('android_native_abi', REPO / 'scripts/build/android-api21/native-abi.py')
process_exit = module('android_process_exit', REPO / 'scripts/run/android/android-process-exit.py')
cpu = module('android_guest_cpu', REPO / 'scripts/run/android/android-cpu.py')
owned = module('android_owned_process', REPO / 'scripts/run/android/android-owned-process.py')


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def _collect(root, run_name, abi):
    # Invalidate old aggregate success before examining the new run.
    artifacts.invalidate_results(root)
    artifacts.check_apks(root, 5, abi)
    sdk = (root / 'sdk-image-id.txt').read_text().strip()
    if not re.fullmatch(r'sha256:[0-9a-f]{64}', sdk):
        raise ValueError('Missing SDK identity')
    if not re.fullmatch(r'[a-z0-9-]+', run_name):
        raise ValueError('Invalid API10 run name')
    batch_path = root / run_name / 'batch-receipt.json'
    batch = json.loads(batch_path.read_text(encoding='utf-8-sig'))
    batch_sha = digest(batch_path)
    apk_manifest_sha = digest(root / 'apk-manifest.json')
    if (batch.get('schema_version') != 1 or not re.fullmatch(r'[0-9a-f]{32}', batch.get('batch_id', '')) or
            batch.get('api') != 10 or batch.get('abi') != abi or batch.get('run') != run_name or
            batch.get('sdk_image_id') != sdk or batch.get('apk_manifest_sha256') != apk_manifest_sha or
            not re.fullmatch(r'[0-9a-f]{64}', batch.get('emulator_sha256', ''))):
        raise ValueError('Missing or mismatched API10 batch receipt')
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
    emulator_identity = batch['emulator_sha256']
    for name, relative in cases:
        case = root / run_name / name
        if any(case.glob('attempt-*.pending.json')):
            raise ValueError('API10 case attempt is incomplete: ' + name)
        receipt = json.loads((case / 'input-receipt.json').read_text(encoding='utf-8-sig'))
        apk = root / relative
        sha = digest(apk)
        if (receipt.get('schema_version') != 3 or receipt.get('completed') is not True or receipt.get('case') != name or
                receipt.get('sdk_image_id') != sdk or receipt.get('abi') != abi or
                receipt.get('api') != 10 or receipt.get('apk_sha256') != sha):
            raise ValueError('Missing or mismatched launch receipt: ' + name)
        if (not re.fullmatch(r'[0-9a-f]{32}', receipt.get('case_attempt_id', '')) or
                receipt.get('apk_manifest_bound') is not True or receipt.get('apk_relative') != relative or
                receipt.get('apk_manifest_sha256') != apk_manifest_sha):
            raise ValueError('Missing or mismatched API10 case/APK manifest binding: ' + name)
        if receipt.get('batch_id') != batch['batch_id'] or receipt.get('batch_receipt_sha256') != batch_sha:
            raise ValueError('Case belongs to a different API10 batch: ' + name)
        if receipt.get('emulator_sha256') != emulator_identity:
            raise ValueError('Different or missing emulator identity: ' + name)
        power = case / 'power-before.txt'
        if digest(power) != receipt.get('guest_power_sha256') or not re.search(r'\bmStayOn(?:Conditions|Setting)=(?:3|7)\b', power.read_text(encoding='utf-8-sig')):
            raise ValueError('Missing verified guest power policy: ' + name)
        cpu_evidence = cpu.validate(case, abi, receipt)
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
        app = Path(relative).stem
        package = 'org.longreachqt.examples.' + app.replace('-', '')
        if receipt.get('package') != package or receipt.get('emulator_exit_confirmed') is not True:
            raise ValueError('Wrong package or unconfirmed legacy emulator exit: ' + name)
        exit_proof = process_exit.require_exit(case, package, receipt)
        host_evidence = owned.validate_emulator(case, bindings=receipt, program_sha256=emulator_identity,
                                               arguments=receipt.get('emulator_arguments', []), artifact_root=root)
        final = case / 'final-logcat.log'
        if digest(final) != receipt.get('final_logcat_sha256'):
            raise ValueError('Final cleanup log changed: ' + name)
        final_state = process_exit.lifecycle(process_exit.scoped(final.read_text(encoding='utf-8-sig').splitlines(), receipt['log_marker']), package)
        if not final_state or final_state != {key: exit_proof[key] for key in ('process_id', 'start_line', 'death_line')}:
            raise ValueError('Final cleanup log lost its application exit evidence: ' + name)
        counts = coverage.require(5, 10, abi, name, stdout)
        if name.startswith('strict-cxx23'):
            subprocess.run([sys.executable, str(REPO / 'scripts/tests/require-modern-cpp.py'), str(stdout_path)], check=True)
        with zipfile.ZipFile(apk) as archive:
            libs = [p for p in archive.namelist() if p.startswith('lib/') and p.endswith('.so')]
            if not libs or any(p.split('/')[1] != abi for p in libs) or len(set(libs)) != len(libs):
                raise ValueError('Missing, duplicate or mixed native ABI: ' + name)
            for member in libs:
                native.inspect_bytes(archive.read(member), abi, member)
            if hashlib.sha256(archive.read(f'lib/{abi}/libc++_shared.so')).hexdigest() != runtime:
                raise ValueError('Wrong packaged C++ runtime: ' + name)
        record = {'name': name, 'apk_relative': relative, 'apk_sha256': sha,
                  'sdk_image_id': sdk, 'batch_id': batch['batch_id'], 'batch_receipt_sha256': batch_sha,
                  'case_attempt_id': receipt['case_attempt_id'], 'apk_manifest_sha256': apk_manifest_sha,
                  'stdout_sha256': digest(stdout_path),
                  'native_exit': 0, 'process_exit_confirmed': True, 'process_id': exit_proof['process_id'],
                  'process_exit_proof_sha256': receipt['process_exit_proof_sha256'], 'passed': counts[0], 'failed': counts[1], 'skipped': counts[2],
                  'evidence': case.relative_to(root).as_posix()}
        record.update(cpu_evidence)
        record.update(host_evidence)
        records.append(record)
        proof.append({'case': name, 'apk': relative, 'sha256': sha, 'abi': abi,
                      'native_libraries': len(libs), 'runtime_sha256': runtime})
    report = {'qt': '5.15.19', 'llvm': '21.1.8', 'api': 10, 'abi': abi,
              'sdk_image_id': sdk, 'runtime_sha256': runtime, 'run': run_name,
              'batch_id': batch['batch_id'], 'batch_receipt_sha256': batch_sha, 'apk_manifest_sha256': apk_manifest_sha,
              'required_cases': len(cases), 'all_required_passed': True, 'all_process_exits_confirmed': True, 'cases': records,
              'emulator_sha256': emulator_identity}
    report['all_host_process_trees_exited'] = True
    report['required_guest_cpu_flags'] = list(cpu.REQUIRED.get(abi, ()))
    artifacts.write_json(root / 'apk-native-abi-check.json', proof)
    table = ['| Case | PASS | FAIL | SKIP |', '| --- | ---: | ---: | ---: |']
    table += [f'| {r["name"]} | {r["passed"]} | 0 | {r["skipped"]} |' for r in records]
    artifacts.write_text_atomic(root / 'final-results-table.md', '\n'.join(table) + '\n')
    artifacts.write_json(root / 'final-results.json', report)
    print('\n'.join(table))
    return report


def collect(root, run_name, abi, artifact_lease_held=False):
    with artifacts.artifact_lease(root, artifact_lease_held):
        return _collect(root, run_name, abi)


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--root', type=Path, required=True)
    parser.add_argument('--run', required=True)
    parser.add_argument('--abi', choices=('armeabi-v7a', 'x86'), required=True)
    parser.add_argument('--artifact-lease-held', action='store_true',
                        help='internal: the runner already holds the artifact lease')
    args = parser.parse_args()
    collect(args.root.resolve(), args.run, args.abi, args.artifact_lease_held)
