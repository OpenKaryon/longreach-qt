# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2026 OpenKaryon
"""Aggregate output lifecycle and failed collectors, without builds or guests."""
import importlib.util
import contextlib
import io
import json
from pathlib import Path
import subprocess
import sys
import shutil
import tempfile
import unittest
import struct
import zipfile
from unittest.mock import patch
from types import SimpleNamespace

import android_result_fixtures as fixtures

ROOT = Path(__file__).resolve().parents[2]
spec = importlib.util.spec_from_file_location('android_result_artifacts', ROOT / 'scripts/build/android-api21/artifact-manifest.py')
artifacts = importlib.util.module_from_spec(spec)
spec.loader.exec_module(artifacts)


def collector(qt):
    relative = ('scripts/build/qt4-android/collect-api21-results.py' if qt == 4
                else 'scripts/build/android-api21/collect-results.py')
    spec = importlib.util.spec_from_file_location(f'fixture_collector_{qt}', ROOT / relative)
    result = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(result)
    return result


def make_fixture(root, qt):
    return fixtures.qt4(root) if qt == 4 else fixtures.api21(root, qt, artifacts)


def collect(module, root, qt):
    with contextlib.redirect_stdout(io.StringIO()), patch.object(module._identity, 'REPO', root / 'fixture-media-repo'):
        return module.collect(SimpleNamespace(root=root, run='fixture-run', abi='x86_64', qt_major=qt))


REPORTS = ('final-results.json', 'final-results-table.md', 'apk-native-abi-check.json',
           'apk-architecture-final.json', 'screenshots.json')


class ResultState(unittest.TestCase):
    def test_qt4_collectors_require_final_capture_for_resident_jni_all_abis(self):
        for abi in ('x86', 'x86_64', 'arm64-v8a'):
            for mutation in ('missing', 'empty', 'placeholder', 'fatal-rebound', 'wrong-owner',
                             'wrong-serial', 'case-binding', 'case-fatal-rebound', 'lost-case-prefix', 'cleanup-binding'):
                with self.subTest(abi=abi, mutation=mutation), tempfile.TemporaryDirectory() as folder:
                    root = Path(folder)
                    records = fixtures.qt4(root, abi)
                    module = collector(4)
                    arguments = SimpleNamespace(root=root, run='fixture-run', abi=abi, qt_major=4)
                    def perform():
                        with contextlib.redirect_stdout(io.StringIO()), patch.object(module._identity, 'REPO', root / 'fixture-media-repo'):
                            return module.collect(arguments)
                    perform()
                    run = root / 'fixture-run'
                    capture = json.loads((run / 'final-logcat-capture.json').read_text())
                    if mutation == 'missing':
                        (run / 'final-logcat-capture.json').unlink()
                        expected = 'final-logcat-capture'
                    elif mutation in ('empty', 'placeholder', 'fatal-rebound'):
                        text = {'empty': '', 'placeholder': 'Owned tree exited before final log capture.',
                                'fatal-rebound': (run / 'final-logcat.log').read_text() + 'I/DEBUG: *** *** ***\n'}[mutation]
                        (run / 'final-logcat.log').write_text(text)
                        capture['logcat_sha256'] = fixtures.digest(run / 'final-logcat.log')
                        expected = 'Missing or mismatched final' if mutation != 'fatal-rebound' else 'Fatal cleanup'
                    elif mutation in ('wrong-owner', 'wrong-serial'):
                        capture['host_process_owner_sha256' if mutation == 'wrong-owner' else 'serial'] = '0'*64 if mutation == 'wrong-owner' else 'emulator-5999'
                        expected = 'Missing or mismatched final'
                    elif mutation == 'case-binding':
                        records[0]['final_logcat_sha256'] = '0'*64
                        expected = 'different final log'
                    elif mutation == 'cleanup-binding':
                        records[0]['case_cleanup_logcat_sha256'] = '0'*64
                        expected = 'different cleanup log'
                    else:
                        case = run / 'core'
                        raw_path, scoped_path = case / 'logcat-after-cleanup-raw.log', case / 'logcat-after-cleanup.log'
                        if mutation == 'case-fatal-rebound':
                            for path in (raw_path, scoped_path):
                                path.write_text(path.read_text() + 'I/DEBUG: *** *** ***\n')
                            expected = 'Fatal cleanup'
                        else:
                            raw_path.write_text(raw_path.read_text().splitlines()[0] + '\n')
                            scoped_path.write_text('')
                            expected = 'lost its original launch'
                        record = next(row for row in records if row['profile'] == 'core')
                        record.update(case_cleanup_raw_logcat_sha256=fixtures.digest(raw_path),
                                      case_cleanup_logcat_sha256=fixtures.digest(scoped_path))
                    if mutation in ('empty', 'placeholder', 'fatal-rebound', 'wrong-owner', 'wrong-serial'):
                        (run / 'final-logcat-capture.json').write_text(json.dumps(capture))
                        for record in records:
                            record.update(final_logcat_sha256=fixtures.digest(run / 'final-logcat.log'),
                                          final_logcat_capture_sha256=fixtures.digest(run / 'final-logcat-capture.json'))
                    (run / 'results.json').write_text(json.dumps(records))
                    with self.assertRaisesRegex((ValueError, RuntimeError, OSError), expected):
                        perform()
                    for name in REPORTS:
                        self.assertFalse((root / name).exists(), name)

    def test_host_process_tree_receipts_are_mandatory_and_case_bound(self):
        for qt in (4, 5, 6):
            for mutation in ('missing', 'active', 'case-binding', 'arguments', 'program', 'log', 'lease-missing', 'lease-root', 'lease-proof'):
                with self.subTest(qt=qt, mutation=mutation), tempfile.TemporaryDirectory() as folder:
                    root=Path(folder)
                    make_fixture(root,qt)
                    module=collector(qt)
                    collect(module,root,qt)
                    run=root/'fixture-run'
                    records=json.loads((run/'results.json').read_text())
                    if mutation=='missing':
                        (run/'host-process-exit.json').unlink()
                        expected='host-process-exit.json'
                    elif mutation=='active':
                        proof=json.loads((run/'host-process-exit.json').read_text())
                        proof['active_processes']=1
                        (run/'host-process-exit.json').write_text(json.dumps(proof))
                        for record in records:
                            record['host_process_exit_sha256']=fixtures.digest(run/'host-process-exit.json')
                        expected='not confirmed'
                    elif mutation=='case-binding':
                        records[0]['host_process_owner_sha256']='0'*64
                        expected='different owned-process evidence'
                    elif mutation in ('lease-missing','lease-root','lease-proof'):
                        launch=json.loads((run/'emulator-launch.json').read_text())
                        if mutation=='lease-proof':
                            proof=json.loads((run/'host-process-exit.json').read_text())
                            proof['artifact_lease_held_until_exit']=False
                            (run/'host-process-exit.json').write_text(json.dumps(proof))
                            for record in records:
                                record['host_process_exit_sha256']=fixtures.digest(run/'host-process-exit.json')
                            expected='Artifact lease was not held'
                        else:
                            bindings=fixtures.host_fixtures.capture(run,launch['emulator'],launch['arguments'],artifact_root=None if mutation=='lease-missing' else root.parent)
                            for record in records:
                                record.update(bindings)
                            expected='Missing or mismatched emulator artifact lease'
                    elif mutation in ('arguments','program'):
                        launch=json.loads((run/'emulator-launch.json').read_text())
                        program=Path(launch['emulator'])
                        arguments=launch['arguments']
                        if mutation=='program':
                            program=root/'unrelated-host-program'
                            program.write_text('synthetic substitute, not executable')
                        else:
                            arguments=arguments+['--different-recording-invocation']
                        bindings=fixtures.host_fixtures.capture(run,program,arguments,artifact_root=root)
                        for record in records:
                            record.update(bindings)
                        expected='not the recorded emulator' if mutation=='program' else 'differs from the emulator invocation'
                    else:
                        with (run/'emulator.stdout').open('a') as stream:
                            stream.write('changed host log')
                        expected='logs changed'
                    (run/'results.json').write_text(json.dumps(records))
                    with self.assertRaisesRegex((ValueError,FileNotFoundError),expected):
                        collect(module,root,qt)
                    self.assertFalse(any((root/name).exists() for name in REPORTS))

    def test_guest_cpu_evidence_is_required_and_bound_for_all_qt_collectors(self):
        for qt in (4, 5, 6):
            for mutation in ('missing-feature', 'changed-source', 'case-binding', 'missing-report'):
                with self.subTest(qt=qt, mutation=mutation), tempfile.TemporaryDirectory() as directory:
                    root = Path(directory)
                    make_fixture(root, qt)
                    module = collector(qt)
                    collect(module, root, qt)
                    run = root / 'fixture-run'
                    source, report = run / 'guest-cpuinfo.txt', run / 'guest-cpu-baseline.json'
                    if mutation == 'missing-feature':
                        source.write_bytes(source.read_bytes().replace(b'popcnt', b'no_popcnt'))
                        data = json.loads(report.read_text())
                        data['guest_cpuinfo_sha256'] = artifacts.digest(source)
                        data['common_flags'] = sorted('no_popcnt' if flag == 'popcnt' else flag for flag in data['common_flags'])
                        report.write_text(json.dumps(data))
                        records = json.loads((run / 'results.json').read_text())
                        for record in records:
                            record.update(guest_cpuinfo_sha256=artifacts.digest(source), guest_cpu_baseline_sha256=artifacts.digest(report))
                        (run / 'results.json').write_text(json.dumps(records))
                        expected = 'lacks required evidence flags'
                    elif mutation == 'changed-source':
                        source.write_bytes(source.read_bytes() + b'\n')
                        expected = 'current evidence/policy'
                    elif mutation == 'case-binding':
                        records = json.loads((run / 'results.json').read_text())
                        records[0]['guest_cpu_baseline_sha256'] = '0' * 64
                        (run / 'results.json').write_text(json.dumps(records))
                        expected = 'different guest CPU evidence'
                    else:
                        report.unlink()
                        expected = 'guest-cpu-baseline.json'
                    with self.assertRaisesRegex((ValueError, FileNotFoundError), expected):
                        collect(module, root, qt)
                    for name in REPORTS:
                        self.assertFalse((root / name).exists(), name)

    def test_invalid_elf_with_a_matching_apk_digest_cannot_leave_final_qualification(self):
        for qt in (5, 6):
            with self.subTest(qt=qt), tempfile.TemporaryDirectory() as directory:
                root = Path(directory)
                make_fixture(root, qt)
                module = collector(qt)
                collect(module, root, qt)
                relative = 'apk/qt-selftest.apk'
                path = root / relative
                with zipfile.ZipFile(path) as archive:
                    entries = {name: archive.read(name) for name in archive.namelist()}
                member = 'lib/x86_64/libfixture.so'
                data = bytearray(entries[member])
                struct.pack_into('<H', data, 16, 1)
                entries[member] = data
                with zipfile.ZipFile(path, 'w') as archive:
                    for name, value in entries.items():
                        archive.writestr(name, value)
                manifest = root / 'apk-manifest.json'
                receipt = json.loads(manifest.read_text())
                receipt['files'][relative] = artifacts.digest(path)
                manifest.write_text(json.dumps(receipt))
                with self.assertRaisesRegex(ValueError, 'ET_DYN'):
                    collect(module, root, qt)
                for report in REPORTS:
                    self.assertFalse((root / report).exists(), report)

    def test_unobserved_timed_sync_cannot_leave_api21_qualification(self):
        for qt in (5, 6):
            for mutation in ('missing-observation', 'fast-path'):
                with self.subTest(qt=qt, mutation=mutation), tempfile.TemporaryDirectory() as directory:
                    root = Path(directory)
                    make_fixture(root, qt)
                    module = collector(qt)
                    collect(module, root, qt)
                    path = root / 'fixture-run/qt-selftest/files/selftest.stdout'
                    text = path.read_text()
                    if mutation == 'missing-observation':
                        text = '\n'.join(line for line in text.splitlines() if not line.startswith('OBSERVE: '))
                        expected = 'Missing or ambiguous timed-sync'
                    else:
                        text = text.replace('elapsed_ms=250', 'elapsed_ms=0', 1)
                        expected = 'Unqualified timed-sync waiting'
                    path.write_text(text)
                    # Exercise waiting policy beyond the independent byte seal.
                    records_path = root / 'fixture-run/results.json'
                    records = json.loads(records_path.read_text())
                    for record in records:
                        if record['name'] == 'qt-selftest':
                            record['stdout_sha256'] = artifacts.digest(path)
                    records_path.write_text(json.dumps(records))
                    with self.assertRaisesRegex(ValueError, expected):
                        collect(module, root, qt)
                    for report in REPORTS:
                        self.assertFalse((root / report).exists(), report)

    def test_qt4_named_coverage_cannot_leave_a_previous_final_pass(self):
        for mutation in ('unexpected-skip', 'missing-required'):
            with self.subTest(mutation=mutation), tempfile.TemporaryDirectory() as directory:
                root = Path(directory)
                make_fixture(root, 4)
                module = collector(4)
                collect(module, root, 4)
                self.assertTrue((root / 'final-results.json').exists())
                path = root / 'fixture-run/selftest/files/suite.log'
                text = path.read_text()
                if mutation == 'unexpected-skip':
                    text = text.replace('PASS: fixture/check-0',
                                        'SKIP: fixture/check-0 - lost capability\nPASS: fixture/compensating-pass')
                    text = text.replace('0 failed, 0 skipped', '0 failed, 1 skipped')
                    receipt = root / 'fixture-run/results.json'
                    records = json.loads(receipt.read_text())
                    record = next(item for item in records if item['profile'] == 'selftest')
                    record.update(summary=[text.splitlines()[-1]], skipped=1)
                    receipt.write_text(json.dumps(records))
                    expected = 'unexpected SKIP'
                else:
                    text = text.replace('PASS: core/metaobject+enum+invoke', 'PASS: fixture/compensating-pass')
                    expected = 'missing required PASS'
                path.write_text(text)
                with self.assertRaisesRegex(ValueError, expected):
                    collect(module, root, 4)
                for report in REPORTS:
                    self.assertFalse((root / report).exists(), report)

    def test_failed_api21_collectors_cannot_leave_a_previous_pass(self):
        for qt in (4, 5, 6):
            with self.subTest(qt=qt), tempfile.TemporaryDirectory() as directory:
                root = Path(directory)
                for name in REPORTS:
                    (root / name).write_text('old PASS')
                old_run = root / 'old-run'
                old_run.mkdir()
                (old_run / 'stdout.txt').write_text('retained evidence')
                if qt == 4:
                    run = root / 'incomplete-run'
                    run.mkdir()
                    (run / 'results.json').write_text('[]')
                    command = [sys.executable, str(ROOT / 'scripts/build/qt4-android/collect-api21-results.py'),
                               '--root', str(root), '--run', run.name, '--abi', 'x86_64']
                    reason = 'all twelve cases'
                else:
                    command = [sys.executable, str(ROOT / 'scripts/build/android-api21/collect-results.py'),
                               '--root', str(root), '--run', 'incomplete-run', '--abi', 'x86_64', '--qt-major', str(qt)]
                    reason = 'examples-manifest.json'
                result = subprocess.run(command, text=True, capture_output=True, timeout=30)
                self.assertNotEqual(result.returncode, 0)
                self.assertIn(reason, result.stderr)
                self.assertFalse(any((root / name).exists() for name in REPORTS))
                self.assertEqual((old_run / 'stdout.txt').read_text(), 'retained evidence')

    def test_complete_collectors_publish_bound_reports_for_all_qt_versions(self):
        for qt, cases in ((4, 12), (5, 13), (6, 11)):
            with self.subTest(qt=qt), tempfile.TemporaryDirectory() as directory:
                root = Path(directory)
                make_fixture(root, qt)
                result = collect(collector(qt), root, qt)
                self.assertEqual(result['required_cases'], cases)
                self.assertTrue(result['all_required_passed'])
                if qt != 4:
                    self.assertTrue(result['qualification'])
                self.assertEqual(json.loads((root / 'final-results.json').read_text()), result)
                self.assertTrue((root / 'final-results-table.md').is_file())
                manifest = 'apk-packages.json' if qt == 4 else 'apk-manifest.json'
                self.assertEqual(result['apk_manifest_sha256'], artifacts.digest(root / manifest))
                self.assertEqual(result['examples_manifest_sha256'], artifacts.digest(root / 'examples-manifest.json'))
                self.assertTrue(all(record['apk_manifest_sha256'] == result['apk_manifest_sha256'] for record in result['cases']))

    def test_changed_manifest_binding_and_recorded_apk_are_rejected_after_a_valid_run(self):
        for qt in (4, 5, 6):
            mutations = [('apk_manifest_sha256', 'different.*APK manifest'),
                         ('apk_sha256', 'APK.*changed|Failed case')]
            if qt == 4:
                mutations += [(field, 'different Qt4 native/APK generation')
                              for field in ('apk_generation_manifest_sha256', 'examples_manifest_sha256')]
            for field, message in mutations:
                with self.subTest(qt=qt, field=field), tempfile.TemporaryDirectory() as directory:
                    root = Path(directory)
                    records = make_fixture(root, qt)
                    module = collector(qt)
                    collect(module, root, qt)
                    records[0][field] = '0' * 64
                    (root / 'fixture-run/results.json').write_text(json.dumps(records))
                    with self.assertRaisesRegex(RuntimeError, message):
                        collect(module, root, qt)
                    self.assertFalse(any((root / name).exists() for name in REPORTS))

    def test_api21_collectors_require_observed_exit_after_a_zero_result(self):
        for qt in (5, 6):
            for mutation, message in (('missing', 'process-exit.json'),
                                      ('unconfirmed', 'process-exit receipt'),
                                      ('still-present', 'remained'),
                                      ('debuggerd', 'Fatal cleanup error')):
                with self.subTest(qt=qt, mutation=mutation), tempfile.TemporaryDirectory() as directory:
                    root = Path(directory)
                    records = make_fixture(root, qt)
                    module = collector(qt)
                    collect(module, root, qt)
                    case = root / 'fixture-run' / records[0]['name']
                    fixtures.invalidate_exit(case, records[0], mutation)
                    (root / 'fixture-run/results.json').write_text(json.dumps(records))
                    with self.assertRaisesRegex((ValueError, FileNotFoundError), message):
                        collect(module, root, qt)
                    self.assertFalse(any((root / name).exists() for name in REPORTS))

    def test_api21_collectors_bind_emulator_and_media_for_all_qt_versions(self):
        for qt in (4, 5, 6):
            for changed, message in (('case-binding', 'different API21 emulator/media identity'),
                                     ('system', 'bytes or inventory changed'),
                                     ('engine', 'bytes or inventory changed'),
                                     ('missing', 'emulator-identity.json')):
                with self.subTest(qt=qt, changed=changed), tempfile.TemporaryDirectory() as directory:
                    root = Path(directory)
                    records = make_fixture(root, qt)
                    module = collector(qt)
                    collect(module, root, qt)
                    run = root / 'fixture-run'
                    if changed == 'missing':
                        (run / 'emulator-identity.json').unlink()
                    elif changed == 'case-binding':
                        records[0]['emulator_identity_sha256'] = '0' * 64
                        (run / 'results.json').write_text(json.dumps(records))
                    else:
                        ready = json.loads((run / 'emulator-media.json').read_text())
                        path = ready['roles']['system'] if changed == 'system' else ready['roles']['engine_candidates'][0]
                        (root / 'media' / path).write_text('changed synthetic media')
                    with self.assertRaisesRegex((ValueError, FileNotFoundError), message):
                        collect(module, root, qt)
                    self.assertFalse(any((root / name).exists() for name in REPORTS))

    def test_changed_or_missing_sdk_report_snapshot_invalidates_final_reports(self):
        for qt in (4, 5, 6):
            for changed, message in (('bytes', 'report bytes changed'), ('missing-binding', 'sdk-report-source.json')):
                with self.subTest(qt=qt, changed=changed), tempfile.TemporaryDirectory() as directory:
                    root = Path(directory)
                    make_fixture(root, qt)
                    module = collector(qt)
                    collect(module, root, qt)
                    reports = root / 'sdk-reports' if qt == 4 else root
                    if changed == 'bytes':
                        (reports / 'runtime-elf.txt').write_text('changed SDK producer report')
                    else:
                        (reports / 'sdk-report-source.json').unlink()
                    with self.assertRaisesRegex((ValueError, FileNotFoundError), message):
                        collect(module, root, qt)
                    self.assertFalse(any((root / name).exists() for name in REPORTS))

    def test_python_lease_refuses_contenders_and_releases_after_failure(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            with self.assertRaisesRegex(ValueError, 'fixture failure'):
                with artifacts.artifact_lease(root):
                    with self.assertRaisesRegex(RuntimeError, 'Another Longreach operation'):
                        with artifacts.artifact_lease(root):
                            self.fail('Concurrent lease was accepted')
                    raise ValueError('fixture failure')
            with artifacts.artifact_lease(root):
                pass

    @unittest.skipUnless(shutil.which('pwsh'), 'PowerShell needed for cross-language lease fixture')
    def test_powershell_producer_cannot_enter_a_python_collector_lease(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            script = root / 'contender.ps1'
            helper = str(ROOT / 'scripts/build/android-api21/artifact-lock.ps1').replace("'", "''")
            script.write_text("param($Root)\n. '" + helper + "'\ntry { Enter-AndroidArtifactLock $Root | Out-Null; exit 2 } catch { if ($_.Exception.Message -like 'Another Longreach operation*') { exit 0 }; throw }", encoding='utf-8')
            with artifacts.artifact_lease(root):
                result = subprocess.run(['pwsh', '-NoProfile', '-File', str(script), '-Root', str(root)],
                                        capture_output=True, text=True, timeout=30)
                self.assertEqual(result.returncode, 0, result.stderr)

    def test_atomic_report_write_failure_preserves_previous_file_and_cleans_temporary(self):
        with tempfile.TemporaryDirectory() as directory:
            target = Path(directory) / 'report.json'
            target.write_text('previous complete data')
            with patch.object(Path, 'replace', side_effect=OSError('fixture replace failure')):
                with self.assertRaisesRegex(OSError, 'fixture replace failure'):
                    artifacts.write_json(target, {'complete': True})
            self.assertEqual(target.read_text(), 'previous complete data')
            self.assertEqual(list(Path(directory).iterdir()), [target])

    def test_reports_are_utf8_and_written_as_complete_files(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            artifacts.write_json(root / 'report.json', {'result': 'готово'})
            artifacts.write_text_atomic(root / 'report.md', 'готово\n')
            self.assertEqual((root / 'report.md').read_bytes(), 'готово\n'.encode())
            self.assertEqual(len(list(root.iterdir())), 2)

    def test_api21_diagnostic_options_are_reported_without_default_qualification(self):
        for qt in (5, 6):
            for field, value, reason in (('debug_qt_plugins', True, 'plugin diagnostics'),
                                         ('qt_quick_backend', 'software', 'software backend'),
                                         ('gpu_requested', 'mesa', 'GPU option')):
                with self.subTest(qt=qt, option=field), tempfile.TemporaryDirectory() as directory:
                    root = Path(directory)
                    records = make_fixture(root, qt)
                    run = root / 'fixture-run'
                    options = json.loads((run / 'run-options.json').read_text())
                    options[field] = value
                    (run / 'run-options.json').write_text(json.dumps(options))
                    emulator = json.loads((run / 'emulator-launch.json').read_text())
                    if field == 'gpu_requested':
                        emulator['gpu_requested'] = value
                        # Both Intel requests use the same actual SwiftShader GPU.
                        (run / 'emulator-launch.json').write_text(json.dumps(emulator))
                    for record in records:
                        record['run_options_sha256'] = artifacts.digest(run / 'run-options.json')
                        record['emulator_launch_sha256'] = artifacts.digest(run / 'emulator-launch.json')
                        if field == 'debug_qt_plugins':
                            record['launch_arguments'] += ['--ez', 'debugQtPlugins', 'true']
                        if field == 'qt_quick_backend':
                            record['launch_arguments'] += ['--es', 'qtQuickBackend', 'software']
                    (run / 'results.json').write_text(json.dumps(records))
                    result = collect(collector(qt), root, qt)
                    self.assertTrue(result['all_required_passed'])
                    self.assertFalse(result['qualification'])
                    self.assertIn(reason, '; '.join(result['diagnostic_reasons']))
                    self.assertEqual(result['launch_options'][field], value)
                    self.assertIn('Qualification: false', (root / 'final-results-table.md').read_text())

    def test_api21_launch_evidence_cannot_be_changed_or_assumed_default(self):
        for qt in (5, 6):
            for changed in ('options', 'application-argv', 'apk-relative', 'emulator-gpu', 'missing-options'):
                with self.subTest(qt=qt, changed=changed), tempfile.TemporaryDirectory() as directory:
                    root = Path(directory)
                    records = make_fixture(root, qt)
                    module = collector(qt)
                    collect(module, root, qt)
                    run = root / 'fixture-run'
                    error, reason = ValueError, ''
                    if changed == 'options':
                        options = json.loads((run / 'run-options.json').read_text())
                        options['debug_qt_plugins'] = True
                        (run / 'run-options.json').write_text(json.dumps(options))
                        reason = 'different API21 launch options'
                    elif changed == 'application-argv':
                        records[0]['launch_arguments'] += ['--es', 'qtQuickBackend', 'software']
                        reason = 'application launch differs'
                    elif changed == 'apk-relative':
                        records[0]['apk_relative'] = 'apk/widgets-gallery.apk'
                        reason = 'Unexpected API21 APK for case'
                    elif changed == 'emulator-gpu':
                        emulator = json.loads((run / 'emulator-launch.json').read_text())
                        emulator['arguments'] = ['-gpu', 'mesa']
                        (run / 'emulator-launch.json').write_text(json.dumps(emulator))
                        for record in records:
                            record['emulator_launch_sha256'] = artifacts.digest(run / 'emulator-launch.json')
                        reason = 'GPU does not match'
                    else:
                        (run / 'run-options.json').unlink()
                        error, reason = FileNotFoundError, 'run-options.json'
                    (run / 'results.json').write_text(json.dumps(records))
                    with self.assertRaisesRegex(error, reason):
                        collect(module, root, qt)
                    self.assertFalse((root / 'final-results.json').exists())


if __name__ == '__main__':
    unittest.main()
