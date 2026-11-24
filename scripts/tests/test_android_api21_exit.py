# SPDX-License-Identifier: GPL-3.0-or-later
"""Ordinary natural-exit/cleanup metadata regressions; no guests or native code."""
import contextlib
import os
import importlib.util
import io
import json
from pathlib import Path
import tempfile
import subprocess
import sys
from types import SimpleNamespace
import unittest
from unittest.mock import patch

import android_result_fixtures as fixture

ROOT = Path(__file__).resolve().parents[2]
spec = importlib.util.spec_from_file_location('api21_exit_collector', ROOT / 'scripts/build/android-api21/collect-results.py')
collector = importlib.util.module_from_spec(spec)
spec.loader.exec_module(collector)


def package(qt, app):
    return ('org.longreachqt.examples.qt6.' + app.replace('-', '_') if qt == 6
            else 'org.longreachqt.examples.' + app.replace('-', ''))


def final_capture(root, records, text=None, **changed):
    run = root / 'fixture-run'
    if text is not None:
        (run / 'final-logcat.log').write_text(text)
    capture = {'schema_version': 1, 'captured': True, 'serial': 'emulator-5582',
               'logcat_sha256': fixture.digest(run / 'final-logcat.log'),
               'host_process_owner_sha256': records[0]['host_process_owner_sha256'],
               'host_process_request_sha256': records[0]['host_process_request_sha256']}
    capture.update(changed)
    (run / 'final-logcat-capture.json').write_text(json.dumps(capture))
    for record in records:
        record.update(final_logcat_sha256=capture['logcat_sha256'],
                      final_logcat_capture_sha256=fixture.digest(run / 'final-logcat-capture.json'))
    (run / 'results.json').write_text(json.dumps(records))


def collect(root, qt, abi='x86_64'):
    with patch.object(collector._identity, 'REPO', root / 'fixture-media-repo'), contextlib.redirect_stdout(io.StringIO()):
        return collector.collect(SimpleNamespace(root=root, run='fixture-run', abi=abi, qt_major=qt))


class Api21Exit(unittest.TestCase):
    def test_full_collector_refuses_late_own_pid_debuggerd_with_rebound_capture(self):
        for qt in (5, 6):
            with self.subTest(qt=qt), tempfile.TemporaryDirectory() as temporary:
                root = Path(temporary)
                records = fixture.api21(root, qt, collector._artifacts)
                last = records[-1]
                text = (root / 'fixture-run' / last['name'] / 'logcat-raw.log').read_text()
                text += ('\nI/DEBUG(99): *** *** ***\nI/DEBUG(99): pid: ' + str(last['process_id'])
                         + ' >>> ' + package(qt, last['app']) + ' <<<\n')
                final_capture(root, records, text)
                with self.assertRaisesRegex((ValueError, RuntimeError), 'Fatal cleanup'):
                    collect(root, qt)


    def test_all_six_supported_api21_targets_keep_required_case_counts_and_final_capture(self):
        for qt in (5, 6):
            abis = ('arm64-v8a', 'x86_64') if qt == 5 else ('armeabi-v7a', 'arm64-v8a', 'x86', 'x86_64')
            for abi in abis:
                with self.subTest(qt=qt, abi=abi), tempfile.TemporaryDirectory() as temporary:
                    root = Path(temporary)
                    fixture.api21(root, qt, collector._artifacts, abi)
                    report = collect(root, qt, abi)
                    self.assertTrue(report['qualification'])
                    self.assertTrue(report['all_observed_exits_clean'])
                    self.assertEqual(report['required_cases'], 13 if qt == 5 else 11)
                    self.assertEqual(len(report['case_cleanup_evidence']), report['required_cases'])
                    self.assertEqual(report['final_logcat_capture_sha256'], fixture.digest(root / 'fixture-run/final-logcat-capture.json'))

    def test_earlier_case_debuggerd_is_refused_even_when_last_capture_is_clean(self):
        for qt in (5, 6):
            with self.subTest(qt=qt), tempfile.TemporaryDirectory() as temporary:
                root = Path(temporary)
                records = fixture.api21(root, qt, collector._artifacts)
                first = records[0]
                case = root / 'fixture-run' / first['name']
                extra = ('\nI/DEBUG(99): *** *** ***\nI/DEBUG(99): pid: ' + str(first['process_id'])
                         + ' >>> ' + package(qt, first['app']) + ' <<<\n')
                for name in ('logcat-after-cleanup-raw.log', 'logcat-after-cleanup.log'):
                    with (case / name).open('a') as out:
                        out.write(extra)
                first['case_cleanup_raw_logcat_sha256'] = fixture.digest(case / 'logcat-after-cleanup-raw.log')
                first['case_cleanup_logcat_sha256'] = fixture.digest(case / 'logcat-after-cleanup.log')
                (root / 'fixture-run/results.json').write_text(json.dumps(records))
                self.assertNotIn('DEBUG', (root / 'fixture-run/final-logcat.log').read_text())
                with self.assertRaisesRegex(ValueError, 'Fatal cleanup'):
                    collect(root, qt)

    def test_missing_or_wrong_final_receipts_and_case_capture_never_keep_prior_pass(self):
        for fault in ('missing-final', 'owner', 'serial', 'case-missing', 'case-boundary', 'case-pid'):
            with self.subTest(fault=fault), tempfile.TemporaryDirectory() as temporary:
                root = Path(temporary)
                records = fixture.api21(root, 5, collector._artifacts)
                collect(root, 5)
                run = root / 'fixture-run'
                case = run / records[0]['name']
                if fault == 'missing-final':
                    (run / 'final-logcat-capture.json').unlink()
                elif fault == 'owner':
                    final_capture(root, records, host_process_owner_sha256='0' * 64)
                elif fault == 'serial':
                    final_capture(root, records, serial='emulator-5580')
                elif fault == 'case-missing':
                    (case / 'logcat-after-cleanup-raw.log').unlink()
                else:
                    raw = case / 'logcat-after-cleanup-raw.log'
                    content = raw.read_text()
                    if fault == 'case-boundary':
                        content = content.replace(records[0]['log_marker'], 'BEGIN-' + 'f' * 32)
                    else:
                        content = content.replace('pid=' + str(records[0]['process_id']), 'pid=7777')
                    raw.write_text(content)
                    # Rebind both file hashes so this reaches scope/PID policy.
                    lines = content.splitlines()[1:]
                    (case / 'logcat-after-cleanup.log').write_text('\n'.join(lines) + '\n')
                    records[0]['case_cleanup_raw_logcat_sha256'] = fixture.digest(raw)
                    records[0]['case_cleanup_logcat_sha256'] = fixture.digest(case / 'logcat-after-cleanup.log')
                    (run / 'results.json').write_text(json.dumps(records))
                with self.assertRaises((OSError, ValueError, RuntimeError)):
                    collect(root, 5)
                self.assertFalse((root / 'final-results.json').exists())

    def test_stdout_bytes_remain_bound_even_with_the_same_ordinary_summary(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            records = fixture.api21(root, 6, collector._artifacts)
            collect(root, 6)
            stdout = root / 'fixture-run' / records[0]['name'] / 'files/selftest.stdout'
            with stdout.open('a') as out:
                out.write('\nlate replacement without changing the summary\n')
            with self.assertRaisesRegex(ValueError, 'stdout or native return'):
                collect(root, 6)
            self.assertFalse((root / 'final-results.json').exists())

    def test_shared_cli_validates_selected_case_without_claiming_full_coverage(self):
        for qt in (5, 6):
            with self.subTest(qt=qt), tempfile.TemporaryDirectory() as temporary:
                root = Path(temporary)
                records = fixture.api21(root, qt, collector._artifacts)
                selected = [r for r in records if r['name'] == 'network-gui']
                fixture.api21_cleanup_evidence(root, selected)
                (root / 'fixture-run/results.json').write_text(json.dumps(selected))
                command = [sys.executable, str(ROOT / 'scripts/run/android-api21-exit.py'), '--root', str(root),
                           '--run', 'fixture-run', '--qt-major', str(qt), '--abi', 'x86_64']
                good = subprocess.run(command, capture_output=True, text=True, timeout=10)
                self.assertEqual(good.returncode, 0, good.stderr)
                self.assertIn('does not qualify full-suite coverage', good.stdout)
                if os.name == 'nt':
                    # Windows resolves this spelling to the same retained run.
                    mixed_case = list(command)
                    mixed_case[mixed_case.index('--run') + 1] = 'Fixture-Run'
                    compatible = subprocess.run(mixed_case, capture_output=True, text=True, timeout=10)
                    self.assertEqual(compatible.returncode, 0, compatible.stderr)
                self.assertFalse((root / 'final-results.json').exists())
                final = root / 'fixture-run/final-logcat.log'
                with final.open('a') as out:
                    out.write('\nI/DEBUG(99): *** *** ***\n')
                final_capture(root, selected)
                bad = subprocess.run(command, capture_output=True, text=True, timeout=10)
                self.assertNotEqual(bad.returncode, 0)
                self.assertIn('Fatal cleanup', bad.stderr)
                self.assertFalse((root / 'final-results.json').exists())


if __name__ == '__main__':
    unittest.main()
