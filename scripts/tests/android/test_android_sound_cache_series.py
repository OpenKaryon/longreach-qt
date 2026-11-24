# SPDX-License-Identifier: GPL-3.0-or-later
"""Ordinary saved-evidence fixtures; all guest output and host ownership are synthetic."""
import json
from pathlib import Path
import tempfile
import subprocess
import sys
import unittest

import android_sound_cache_fixtures as fixture

series = fixture.series


class SoundSeries(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name) / 'artifacts with spaces'
        self.options = fixture.prepare(self.root)
        self.directory = self.root / 'diagnostics/fixture-series'

    def begin(self):
        return series.begin(directory=self.directory, **self.options)

    def fill(self, count=20):
        for index in range(1, count + 1):
            series.checkpoint(self.directory, index)
            fixture.case(self.directory, index)
            series.record(self.directory, index)

    def test_twenty_separate_host_launches_accept_repeated_android_pid(self):
        self.begin()
        self.fill()
        report = series.finish(self.directory)
        self.assertFalse(report['qualification'])
        self.assertEqual(report['completed_processes'], 20)
        self.assertEqual({x['process_id'] for x in report['cases']}, {1234})
        self.assertEqual(len({x['host_run_id'] for x in report['cases']}), 20)
        self.assertEqual(series.verify(self.directory), report)
        with self.assertRaisesRegex(ValueError, 'already exists'):
            self.begin()

    def test_other_api10_abi_and_classic_option_use_their_frozen_cpu_arguments(self):
        self.options['classic'] = False
        self.begin()
        case, receipt = fixture.case(self.directory, 1)
        self.assertEqual(receipt['emulator_arguments'][-4:], ['-no-accel', '-qemu', '-cpu', 'core2duo'])
        series.record(self.directory, 1)
        arm = self.root.parent / 'arm artifacts'
        options = fixture.prepare(arm, 'armeabi-v7a')
        directory = arm / 'diagnostics/arm-series'
        series.begin(directory=directory, **options)
        case, receipt = fixture.case(directory, 1)
        self.assertEqual(receipt['emulator_arguments'][-3:], ['-qemu', '-cpu', 'cortex-a8'])
        series.record(directory, 1)

    def test_incomplete_prefix_existing_case_and_out_of_order_record_refuse(self):
        self.begin()
        for index in (0, 21, 2):
            with self.subTest(index=index), self.assertRaises(ValueError):
                series.checkpoint(self.directory, index)
        fixture.case(self.directory, 1)
        with self.assertRaisesRegex(ValueError, 'already exists'):
            series.checkpoint(self.directory, 1)
        series.record(self.directory, 1)
        with self.assertRaisesRegex(ValueError, 'accepted attempts'):
            series.record(self.directory, 1)
        with self.assertRaisesRegex(ValueError, 'accepted attempts'):
            series.finish(self.directory)

    def test_protocol_and_late_debuggerd_are_rechecked_instead_of_trusting_completed(self):
        self.begin()
        case, record = fixture.case(self.directory, 1)
        report = case / 'files/selftest.stdout'
        report.write_text('---- qt-selftest: 106 passed, 0 failed, 4 skipped ----')
        record['stdout_sha256'] = record['diagnostic_stdout_sha256'] = series.digest(report)
        (case / 'input-receipt.json').write_text(json.dumps(record))
        with self.assertRaisesRegex(ValueError, 'pre-exit phases'):
            series.record(self.directory, 1)
        report.write_text('\n'.join(fixture.PHASES))
        record['stdout_sha256'] = record['diagnostic_stdout_sha256'] = series.digest(report)
        final = case / 'final-logcat.log'
        with final.open('a') as out:
            out.write('\nI/DEBUG(99): *** *** ***\nI/DEBUG(99): pid: 1234, tid: 1234 >>> org.longreachqt.examples.qtselftest <<<\n')
        record['final_logcat_sha256'] = series.digest(final)
        (case / 'input-receipt.json').write_text(json.dumps(record))
        with self.assertRaisesRegex(ValueError, '[Ff]atal'):
            series.record(self.directory, 1)

    def test_separate_process_attempt_and_frontend_identities_are_required(self):
        self.begin()
        first, first_record = fixture.case(self.directory, 1)
        series.record(self.directory, 1)
        second, record = fixture.case(self.directory, 2)
        original_id = record['case_attempt_id']
        record['case_attempt_id'] = first_record['case_attempt_id']
        (second / 'input-receipt.json').write_text(json.dumps(record))
        with self.assertRaisesRegex(ValueError, 'case_attempt_id'):
            series.record(self.directory, 2)
        record['case_attempt_id'] = original_id
        record.update(fixture.host.capture(second, self.options['emulator'], record['emulator_arguments'],
                                           supervisor_pid=5002, frontend_pid=6001,
                                           artifact_root=self.root, adb_endpoint=record['adb_endpoint']))
        (second / 'input-receipt.json').write_text(json.dumps(record))
        with self.assertRaisesRegex(ValueError, 'frontend_birth'):
            series.record(self.directory, 2)

    def test_media_change_and_incomplete_generation_stop_before_another_attempt(self):
        self.begin()
        fixture.case(self.directory, 1)
        series.record(self.directory, 1)
        media = self.options['system_directory'] / 'system.img'
        saved = media.read_bytes()
        media.write_bytes(saved + b'changed')
        with self.assertRaisesRegex(ValueError, 'inputs changed'):
            series.checkpoint(self.directory, 2)
        media.write_bytes(saved)
        (self.root / 'apk-in-progress.json').write_text('{}')
        with self.assertRaisesRegex(ValueError, 'generation became incomplete'):
            series.checkpoint(self.directory, 2)
        self.assertFalse((self.directory / 'run-02').exists())

    def test_previously_accepted_case_and_full_native_generation_are_rechecked(self):
        self.begin()
        self.fill()
        native = self.root / 'native/libc++_shared.so'
        saved = native.read_bytes()
        native.write_bytes(saved + b'changed native input')
        with self.assertRaisesRegex(ValueError, 'bytes changed'):
            series.finish(self.directory)
        native.write_bytes(saved)
        report = self.directory / 'run-01/files/selftest.stdout'
        report.write_text('0')
        with self.assertRaisesRegex(ValueError, 'stdout or native return'):
            series.finish(self.directory)
        self.assertFalse((self.directory / 'series-result.json').exists())

    def test_actual_cli_refuses_root_directory_mismatch_before_creating_a_lease(self):
        self.begin()
        other = self.root.parent / 'unrelated root'
        other.mkdir()
        path = self.directory / 'series-inputs.json'
        data = json.loads(path.read_text())
        data['root'] = str(other)
        path.write_text(json.dumps(data))
        completed = subprocess.run([sys.executable, str(fixture.ROOT / 'scripts/run/android/android-sound-cache-series.py'),
                                    'verify', '--directory', str(self.directory)],
                                   capture_output=True, text=True, timeout=10)
        self.assertNotEqual(completed.returncode, 0)
        self.assertIn('named child', completed.stderr)
        self.assertFalse((other / '.longreach-artifacts.lock').exists())

    def test_failure_preserves_evidence_and_quarantines_a_later_rejected_result(self):
        self.begin()
        self.fill()
        series.finish(self.directory)
        old = (self.directory / 'series-result.json').read_bytes()
        series.failure(self.directory, 20, 'verify', 'fixture late verification failure')
        self.assertFalse((self.directory / 'series-result.json').exists())
        self.assertEqual((self.directory / 'series-result-before-failure.json').read_bytes(), old)
        self.assertEqual(len(list(self.directory.glob('run-*'))), 20)
        with self.assertRaisesRegex(ValueError, 'failed attempt'):
            series.verify(self.directory)
        with self.assertRaises(FileExistsError):
            series.failure(self.directory, 20, 'verify', 'must not overwrite failure')


if __name__ == '__main__':
    unittest.main()
