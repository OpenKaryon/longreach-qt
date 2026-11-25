# SPDX-License-Identifier: GPL-3.0-or-later
"""Ordinary API10 evidence finalization without an SDK, build or guest."""
import hashlib
import importlib.util
import json
from pathlib import Path
import re
import tempfile
import unittest
from unittest.mock import patch
import zipfile

import android_result_fixtures as fixtures
import android_cpu_fixtures as cpu_fixtures

ROOT = Path(__file__).resolve().parents[3]
spec = importlib.util.spec_from_file_location('legacy', ROOT / 'scripts/build/qt5-android/collect-legacy-results.py')
legacy = importlib.util.module_from_spec(spec)
spec.loader.exec_module(legacy)


def sha(data):
    return hashlib.sha256(data).hexdigest()


class LegacyResultsTests(unittest.TestCase):
    def test_recorded_sensor_inputs_are_bound_to_the_extended_case_and_owned_launch(self):
        for changed in (None, 'rounding', 'request', 'values', 'bytes'):
            with self.subTest(changed=changed), tempfile.TemporaryDirectory() as tmp, patch.object(legacy.artifacts, 'check_apks'), patch.object(legacy.subprocess, 'run'), patch('builtins.print'):
                root = Path(tmp)
                self.fixture(root, 'armeabi-v7a')
                case = root / 'run/qt-selftest-extended'
                receipt_path = case / 'input-receipt.json'
                receipt = json.loads(receipt_path.read_text())
                sensor = {'schema_version': 1, 'fixture': 'nonparallel-compass-v1',
                          'status': 'applied-and-readback-verified',
                          'host_process_request_sha256': receipt['host_process_request_sha256'],
                          'settings': [{'sensor': kind, 'chosen': vector, 'after': vector}
                                       for kind, vector in [('acceleration', [0.0, 0.0, 9.81]), ('magnetic-field', [-20.0, 20.0, -40.0])]]}
                if changed == 'request':
                    sensor['host_process_request_sha256'] = '0' * 64
                if changed == 'values':
                    sensor['settings'][1]['after'] = [0, 0, 0]
                if changed == 'rounding':
                    sensor['settings'][0]['after'] = [0, 0, 9.8101]
                path = case / 'native-sensor-inputs.json'
                path.write_text(json.dumps(sensor))
                receipt.update(native_sensor_fixture=sensor['fixture'], native_sensor_fixture_sha256=legacy.digest(path))
                receipt_path.write_text(json.dumps(receipt))
                if changed == 'bytes':
                    path.write_text(path.read_text() + '\n')
                if changed and changed != 'rounding':
                    with self.assertRaisesRegex(ValueError, 'Native sensor input'):
                        legacy.collect(root, 'run', 'armeabi-v7a')
                else:
                    report = legacy.collect(root, 'run', 'armeabi-v7a')
                    record = next(value for value in report['cases'] if value['name'] == 'qt-selftest-extended')
                    self.assertEqual(record['native_sensor_fixture_sha256'], receipt['native_sensor_fixture_sha256'])

    def test_host_tree_and_invocation_are_required_for_both_api10_abis(self):
        for abi in ('x86','armeabi-v7a'):
            for mutation in ('missing','active','case-binding','arguments','lease-missing','lease-root','lease-proof'):
                with self.subTest(abi=abi,mutation=mutation), tempfile.TemporaryDirectory() as tmp, patch.object(legacy.artifacts,'check_apks'), patch.object(legacy.subprocess,'run'), patch('builtins.print'):
                    root=Path(tmp)
                    self.fixture(root,abi)
                    legacy.collect(root,'run',abi)
                    case=root/'run/qt-selftest'
                    path=case/'input-receipt.json'
                    receipt=json.loads(path.read_text())
                    if mutation=='missing':
                        (case/'host-process-exit.json').unlink()
                        expected='host-process-exit.json'
                    elif mutation=='active':
                        proof=json.loads((case/'host-process-exit.json').read_text())
                        proof['active_processes']=1
                        (case/'host-process-exit.json').write_text(json.dumps(proof))
                        receipt['host_process_exit_sha256']=sha((case/'host-process-exit.json').read_bytes())
                        expected='not confirmed'
                    elif mutation in ('lease-missing','lease-root','lease-proof'):
                        if mutation=='lease-proof':
                            proof=json.loads((case/'host-process-exit.json').read_text())
                            proof['artifact_lease_held_until_exit']=False
                            (case/'host-process-exit.json').write_text(json.dumps(proof))
                            receipt['host_process_exit_sha256']=sha((case/'host-process-exit.json').read_bytes())
                            expected='Artifact lease was not held'
                        else:
                            receipt.update(fixtures.host_fixtures.capture(case,root/'fixture-emulator.exe',receipt['emulator_arguments'],artifact_root=None if mutation=='lease-missing' else root.parent))
                            expected='Missing or mismatched emulator artifact lease'
                    elif mutation=='case-binding':
                        receipt['host_process_owner_sha256']='0'*64
                        expected='different owned-process evidence'
                    else:
                        receipt['emulator_arguments'].append('--wrong-invocation')
                        expected='differs from the emulator invocation'
                    path.write_text(json.dumps(receipt))
                    with self.assertRaisesRegex((ValueError,FileNotFoundError),expected):
                        legacy.collect(root,'run',abi)
                    for name in ('final-results.json','final-results-table.md','apk-native-abi-check.json'):
                        self.assertFalse((root/name).exists())

    def test_pending_case_attempt_and_selected_manifest_binding_are_mandatory(self):
        for abi in ('x86', 'armeabi-v7a'):
            for mutation in ('pending', 'attempt-id', 'unbound', 'relative', 'manifest-digest'):
                with self.subTest(abi=abi, mutation=mutation), tempfile.TemporaryDirectory() as tmp, patch.object(legacy.artifacts, 'check_apks'), patch.object(legacy.subprocess, 'run'), patch('builtins.print'):
                    root = Path(tmp)
                    self.fixture(root, abi)
                    legacy.collect(root, 'run', abi)
                    case = root / 'run/qt-selftest'
                    path = case / 'input-receipt.json'
                    receipt = json.loads(path.read_text())
                    if mutation == 'pending':
                        (case / ('attempt-' + 'd' * 32 + '.pending.json')).write_text('{"failed": true}')
                        expected = 'case attempt is incomplete'
                    else:
                        field, value = {'attempt-id': ('case_attempt_id', 'old-run'),
                                        'unbound': ('apk_manifest_bound', False),
                                        'relative': ('apk_relative', 'apk/different.apk'),
                                        'manifest-digest': ('apk_manifest_sha256', '0' * 64)}[mutation]
                        receipt[field] = value
                        path.write_text(json.dumps(receipt))
                        expected = 'case/APK manifest binding'
                    with self.assertRaisesRegex(ValueError, expected):
                        legacy.collect(root, 'run', abi)
                    for name in ('final-results.json', 'final-results-table.md', 'apk-native-abi-check.json'):
                        self.assertFalse((root / name).exists())

    def test_guest_cpu_evidence_is_required_for_both_api10_abis(self):
        for abi in ('x86', 'armeabi-v7a'):
            mutations = ['changed-source', 'case-binding', 'missing-report'] + (['missing-feature'] if abi == 'x86' else [])
            for mutation in mutations:
                with self.subTest(abi=abi, mutation=mutation), tempfile.TemporaryDirectory() as tmp, patch.object(legacy.artifacts, 'check_apks'), patch.object(legacy.subprocess, 'run'), patch('builtins.print'):
                    root = Path(tmp)
                    self.fixture(root, abi)
                    legacy.collect(root, 'run', abi)
                    case = root / 'run/qt-selftest'
                    source, report = case / 'guest-cpuinfo.txt', case / 'guest-cpu-baseline.json'
                    receipt_path = case / 'input-receipt.json'
                    receipt = json.loads(receipt_path.read_text())
                    if mutation == 'changed-source':
                        source.write_bytes(source.read_bytes() + b'\n')
                        expected = 'current evidence/policy'
                    elif mutation == 'case-binding':
                        receipt['guest_cpuinfo_sha256'] = '0' * 64
                        receipt_path.write_text(json.dumps(receipt))
                        expected = 'different guest CPU evidence'
                    elif mutation == 'missing-report':
                        report.unlink()
                        expected = 'guest-cpu-baseline.json'
                    else:
                        source.write_bytes(source.read_bytes().replace(b'ssse3', b'sse2'))
                        data = json.loads(report.read_text())
                        data.update(guest_cpuinfo_sha256=sha(source.read_bytes()), common_flags=['sse2'])
                        report.write_text(json.dumps(data))
                        receipt.update(guest_cpuinfo_sha256=sha(source.read_bytes()), guest_cpu_baseline_sha256=sha(report.read_bytes()))
                        receipt_path.write_text(json.dumps(receipt))
                        expected = 'lacks required evidence flags'
                    with self.assertRaisesRegex((ValueError, FileNotFoundError), expected):
                        legacy.collect(root, 'run', abi)
                    for name in ('final-results.json', 'final-results-table.md', 'apk-native-abi-check.json'):
                        self.assertFalse((root / name).exists())

    def fixture(self, root, abi='x86'):
        sdk = 'sha256:' + 'a' * 64
        (root / 'sdk-image-id.txt').write_text(sdk)
        elf = fixtures.elf(abi)
        (root / 'native').mkdir()
        (root / 'native/libc++_shared.so').write_bytes(elf)
        targets = json.loads(legacy.coverage.BASELINES.read_text())['targets'][f'5/10/{abi}']
        for app in legacy.artifacts.APPS + ['extended/qt-selftest']:
            apk = root / 'apk' / (app + '.apk')
            apk.parent.mkdir(parents=True, exist_ok=True)
            with zipfile.ZipFile(apk, 'w') as z:
                z.writestr(f'lib/{abi}/libc++_shared.so', elf)
                z.writestr(f'lib/{abi}/libexample.so', elf)
        (root / 'apk-manifest.json').write_text('{}')
        (root / 'run').mkdir()
        program = root / 'fixture-emulator.exe'
        program.write_text('synthetic metadata only')
        emulator_sha = sha(program.read_bytes())
        batch = {'schema_version': 1, 'batch_id': 'e' * 32, 'run': 'run', 'abi': abi, 'api': 10,
                 'sdk_image_id': sdk, 'emulator_sha256': emulator_sha,
                 'apk_manifest_sha256': sha((root / 'apk-manifest.json').read_bytes())}
        batch_path = root / 'run/batch-receipt.json'
        batch_path.write_text(json.dumps(batch))
        for index, (name, baseline) in enumerate(targets.items()):
            name = {'widgets-gui': 'widgets-gallery-render', 'qml-gui': 'quick-qml-gallery-render'}.get(name, name)
            case = root / 'run' / name
            (case / 'files').mkdir(parents=True)
            cpu_evidence = cpu_fixtures.capture(case, abi)
            stdout = '\n'.join('PASS: ' + check for check in baseline.get('required_pass', []))
            if baseline.get('require_timed_sync_evidence'):
                for check in legacy.coverage.TIMED_SYNC.CHECKS:
                    acquired, elapsed = (0, 200) if check.endswith('-timeout') else (1, 250)
                    stdout += f'\nOBSERVE: {check} - attempt=1 ready=1 unavailable=1 armed=1 released_before_call=0 acquired={acquired} elapsed_ms={elapsed} joined=1 verdict=pass'
            stdout += f'\n---- fixture: {baseline["min_pass"]} passed, 0 failed, {baseline["max_skip"]} skipped ----\n'
            (case / 'files/selftest.stdout').write_text(stdout)
            (case / 'files/selftest-result.txt').write_text('0')
            (case / 'logcat.log').write_text('native returned zero')
            (case / 'power-before.txt').write_text('mStayOnConditions=3\n')
            (case / 'guest.txt').write_text(f'ro.build.version.sdk=10\nro.product.cpu.abi={abi}\nro.build.version.release={"2.3.7" if abi == "x86" else "2.3.3"}\n')
            relative = {'atomic-cow': 'qt-selftest', 'strict-cxx23': 'qt-selftest', 'strict-cxx23-extended': 'extended/qt-selftest',
                        'qt-selftest-extended': 'extended/qt-selftest', 'widgets-gallery-render': 'widgets-gallery',
                        'quick-qml-gallery-render': 'quick-qml-gallery'}.get(name, name)
            receipt = {'schema_version': 3, **cpu_evidence, 'batch_id': batch['batch_id'], 'batch_receipt_sha256': sha(batch_path.read_bytes()), 'completed': True, 'case': name, 'sdk_image_id': sdk, 'abi': abi, 'api': 10,
                       'emulator_sha256': emulator_sha,
                       'apk_sha256': sha((root / 'apk' / (relative + '.apk')).read_bytes()),
                       'stdout_sha256': sha((case / 'files/selftest.stdout').read_bytes()),
                       'guest_power_sha256': sha((case / 'power-before.txt').read_bytes())}
            receipt.update(case_attempt_id=f'{index:032x}', apk_manifest_bound=True, apk_relative='apk/' + relative + '.apk',
                           apk_manifest_sha256=sha((root / 'apk-manifest.json').read_bytes()))
            package = 'org.longreachqt.examples.' + Path(relative).name.replace('-', '')
            receipt.update(fixtures.exit_evidence(case, package, f'BEGIN-{index:032x}', 2000 + index, final=True))
            arguments = ['-datadir', str(case), '-port', '5580']
            receipt['emulator_arguments'] = arguments
            receipt.update(fixtures.host_fixtures.capture(case, program, arguments, artifact_root=root))
            (case / 'input-receipt.json').write_text(json.dumps(receipt))

    def test_complete_and_changed_launch_inputs(self):
        with tempfile.TemporaryDirectory() as tmp, patch.object(legacy.artifacts, 'check_apks'), patch.object(legacy.subprocess, 'run'), patch('builtins.print'):
            root = Path(tmp)
            self.fixture(root)
            self.assertEqual(legacy.collect(root, 'run', 'x86')['required_cases'], 14)
            path = root / 'run/qt-selftest/input-receipt.json'
            receipt = json.loads(path.read_text())
            receipt['apk_sha256'] = 'b' * 64
            path.write_text(json.dumps(receipt))
            with self.assertRaisesRegex(ValueError, 'launch receipt'):
                legacy.collect(root, 'run', 'x86')
            for name in ('final-results.json', 'final-results-table.md', 'apk-native-abi-check.json'):
                self.assertFalse((root / name).exists(), name)

    def test_unobserved_timed_sync_cannot_leave_either_api10_qualification(self):
        for abi in ('x86', 'armeabi-v7a'):
            for mutation in ('missing-observation', 'fast-path'):
                with self.subTest(abi=abi, mutation=mutation), tempfile.TemporaryDirectory() as tmp, patch.object(legacy.artifacts, 'check_apks'), patch.object(legacy.subprocess, 'run'), patch('builtins.print'):
                    root = Path(tmp)
                    self.fixture(root, abi)
                    legacy.collect(root, 'run', abi)
                    path = root / 'run/qt-selftest/files/selftest.stdout'
                    text = path.read_text()
                    if mutation == 'missing-observation':
                        text = '\n'.join(line for line in text.splitlines() if not line.startswith('OBSERVE: '))
                        expected = 'Missing or ambiguous timed-sync'
                    else:
                        text = text.replace('elapsed_ms=250', 'elapsed_ms=0', 1)
                        expected = 'Unqualified timed-sync waiting'
                    path.write_text(text)
                    receipt_path = root / 'run/qt-selftest/input-receipt.json'
                    receipt = json.loads(receipt_path.read_text())
                    receipt['stdout_sha256'] = sha(path.read_bytes())
                    receipt_path.write_text(json.dumps(receipt))
                    with self.assertRaisesRegex(ValueError, expected):
                        legacy.collect(root, 'run', abi)
                    for name in ('final-results.json', 'final-results-table.md', 'apk-native-abi-check.json'):
                        self.assertFalse((root / name).exists())

    def test_preflight_and_emulator_identity_are_required(self):
        for changed in ('missing-preflight', 'different-emulator'):
            with self.subTest(changed=changed), tempfile.TemporaryDirectory() as tmp, patch.object(legacy.artifacts, 'check_apks'), patch.object(legacy.subprocess, 'run'), patch('builtins.print'):
                root = Path(tmp)
                self.fixture(root)
                if changed == 'missing-preflight':
                    (root / 'run/atomic-cow/input-receipt.json').unlink()
                else:
                    path = root / 'run/qt-selftest/input-receipt.json'
                    receipt = json.loads(path.read_text())
                    receipt['emulator_sha256'] = 'd' * 64
                    path.write_text(json.dumps(receipt))
                with self.assertRaises((ValueError, FileNotFoundError)):
                    legacy.collect(root, 'run', 'x86')
                self.assertFalse((root / 'final-results.json').exists())

    def test_batches_cannot_mix_runs_or_emulators_on_either_api10_abi(self):
        for abi in ('x86', 'armeabi-v7a'):
            for mutation, message in (('batch-id', 'different API10 batch'),
                                      ('batch-digest', 'different API10 batch'),
                                      ('emulator', 'emulator identity'),
                                      ('rotated-batch', 'different API10 batch'),
                                      ('manifest', 'batch receipt')):
                with self.subTest(abi=abi, mutation=mutation), tempfile.TemporaryDirectory() as tmp, patch.object(legacy.artifacts, 'check_apks'), patch.object(legacy.subprocess, 'run'), patch('builtins.print'):
                    root = Path(tmp)
                    self.fixture(root, abi)
                    result = legacy.collect(root, 'run', abi)
                    self.assertEqual(result['required_cases'], 14 if abi == 'x86' else 13)
                    self.assertEqual(result['emulator_sha256'], sha((root / 'fixture-emulator.exe').read_bytes()))
                    case_path = root / 'run/qt-selftest/input-receipt.json'
                    receipt = json.loads(case_path.read_text())
                    if mutation == 'rotated-batch':
                        batch_path = root / 'run/batch-receipt.json'
                        batch = json.loads(batch_path.read_text())
                        batch['batch_id'] = 'f' * 32
                        batch_path.write_text(json.dumps(batch))
                    elif mutation == 'manifest':
                        (root / 'apk-manifest.json').write_text('{"changed": true}')
                    else:
                        field = {'batch-id': 'batch_id', 'batch-digest': 'batch_receipt_sha256',
                                 'emulator': 'emulator_sha256'}[mutation]
                        receipt[field] = '0' * 64
                        case_path.write_text(json.dumps(receipt))
                    with self.assertRaisesRegex(ValueError, message):
                        legacy.collect(root, 'run', abi)
                    self.assertFalse((root / 'final-results.json').exists())

    def test_report_and_cleanup_are_required(self):
        mutations = {
            'stdout': ('files/selftest.stdout', 'stdout_sha256', 'Changed report'),
            'logcat': ('logcat.log', None, 'Fatal cleanup error'),
            'power': ('power-before.txt', 'guest_power_sha256', 'Missing verified guest power policy'),
            'coverage': ('files/selftest.stdout', 'stdout_sha256', 'coverage'),
            'named-pass': ('files/selftest.stdout', 'stdout_sha256', 'missing required PASS'),
        }
        for changed, (relative, receipt_field, reason) in mutations.items():
            with self.subTest(changed=changed), tempfile.TemporaryDirectory() as tmp, patch.object(legacy.artifacts, 'check_apks'), patch.object(legacy.subprocess, 'run'):
                root = Path(tmp)
                self.fixture(root)
                case = root / 'run/qt-selftest'
                path = case / relative
                text = path.read_text()
                if changed == 'coverage':
                    text = re.sub(r'\d+ passed,', '1 passed,', text)
                elif changed == 'named-pass':
                    text = text.replace('PASS: ', 'SKIP: ', 1)
                else:
                    text = {'stdout': 'changed report', 'logcat': 'Fatal signal 11',
                            'power': 'mStayOnConditions=1'}[changed]
                path.write_text(text)
                # Policy mutations must pass receipt integrity to exercise
                # the named coverage or power guard, not only the digest guard.
                if receipt_field and changed != 'stdout':
                    receipt_path = case / 'input-receipt.json'
                    receipt = json.loads(receipt_path.read_text())
                    receipt[receipt_field] = sha(path.read_bytes())
                    receipt_path.write_text(json.dumps(receipt))
                with self.assertRaisesRegex(ValueError, reason):
                    legacy.collect(root, 'run', 'x86')

    def test_legacy_collector_requires_exit_and_completed_emulator_cleanup(self):
        for mutation, message in (('missing', 'process-exit.json'),
                                  ('unconfirmed', 'process-exit receipt'),
                                  ('still-present', 'remained'),
                                  ('debuggerd', 'Fatal cleanup error'),
                                  ('emulator-running', 'unconfirmed legacy emulator exit')):
            with self.subTest(mutation=mutation), tempfile.TemporaryDirectory() as tmp, patch.object(legacy.artifacts, 'check_apks'), patch.object(legacy.subprocess, 'run'), patch('builtins.print'):
                root = Path(tmp)
                self.fixture(root)
                legacy.collect(root, 'run', 'x86')
                case = root / 'run/qt-selftest'
                path = case / 'input-receipt.json'
                receipt = json.loads(path.read_text())
                if mutation == 'emulator-running':
                    receipt['emulator_exit_confirmed'] = False
                else:
                    fixtures.invalidate_exit(case, receipt, mutation)
                path.write_text(json.dumps(receipt))
                with self.assertRaisesRegex((ValueError, FileNotFoundError), message):
                    legacy.collect(root, 'run', 'x86')
                self.assertFalse((root / 'final-results.json').exists())

    def test_failed_final_publication_cannot_leave_success(self):
        with tempfile.TemporaryDirectory() as tmp, patch.object(legacy.artifacts, 'check_apks'), patch.object(legacy.subprocess, 'run'):
            root = Path(tmp)
            self.fixture(root)
            write = legacy.artifacts.write_json

            def fail_final(path, value):
                if path.name == 'final-results.json':
                    raise OSError('fixture final publication failure')
                write(path, value)

            with patch.object(legacy.artifacts, 'write_json', side_effect=fail_final):
                with self.assertRaisesRegex(OSError, 'fixture final publication failure'):
                    legacy.collect(root, 'run', 'x86')
            self.assertFalse((root / 'final-results.json').exists())
            self.assertTrue((root / 'final-results-table.md').exists())
            self.assertTrue((root / 'apk-native-abi-check.json').exists())


if __name__ == '__main__':
    unittest.main()
