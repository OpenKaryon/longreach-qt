# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2026 OpenKaryon
"""Source-bound API21 TTS evidence fixtures; no engine or guest executes."""
from contextlib import contextmanager
import importlib.util
import json
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

import android_api21_sound_cache_fixtures as fixture

ROOT = Path(__file__).resolve().parents[3]
spec = importlib.util.spec_from_file_location('tts_collector', ROOT / 'scripts/run/android/android-api21-tts.py')
tts = importlib.util.module_from_spec(spec)
spec.loader.exec_module(tts)


class Api21Speech(unittest.TestCase):
    @contextmanager
    def ready(self, abi='arm64-v8a', qt_major=5):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary) / 'TTS artifacts with spaces'
            record = fixture.prepare(root, abi, kind='tts' if qt_major == 5 else 'tts6')
            with patch.object(tts._identity, 'REPO', root / 'fixture-media-repo'):
                yield root, root / 'fixture-run', record

    def test_all_abis_publish_only_tts_diagnostic_and_preserve_rechecked_history(self):
        for abi in ('armeabi-v7a', 'arm64-v8a', 'x86', 'x86_64'):
            with self.subTest(abi=abi), self.ready(abi) as (root, run, record):
                report = tts.collect(root, run.name, abi)
                self.assertTrue(report['completed'])
                self.assertFalse(report['qualification'])
                self.assertEqual(report['cases'][0]['app'], 'multimedia-lab')
                self.assertEqual(report['cases'][0]['apk_relative'], 'apk/multimedia-lab.apk')
                self.assertFalse((root / 'final-results.json').exists())
                prior = (run / 'tts-behavior-result.json').read_bytes()
                self.assertEqual(tts.collect(root, run.name, abi), report)
                self.assertEqual(next(run.glob('tts-behavior-previous-*.json')).read_bytes(), prior)

    def test_matching_totals_and_rebound_digests_cannot_hide_false_state_order(self):
        with self.ready() as (root, run, record):
            tts.collect(root, run.name, 'arm64-v8a')
            stdout = run / 'tts-behavior/files/selftest.stdout'
            stdout.write_text(stdout.read_text().replace('speech/pause-stable-before-resume - state=Paused',
                                                       'speech/pause-stable-before-resume - state=Ready'))
            fixture.rebind_stdout(run, record)
            fixture.save(run, record)
            with self.assertRaisesRegex(ValueError, 'state order'):
                tts.collect(root, run.name, 'arm64-v8a')
            self.assertFalse((run / 'tts-behavior-result.json').exists())
            self.assertTrue(list(run.glob('tts-behavior-previous-*.json')))

    def test_explicit_mode_apk_arguments_single_case_and_qualification_are_required(self):
        for fault in ('mode', 'apk', 'arguments', 'two-cases', 'qualification'):
            with self.subTest(fault=fault), self.ready() as (root, run, record):
                if fault == 'mode':
                    options = json.loads((run / 'run-options.json').read_text())
                    options.pop('diagnostic')
                    (run / 'run-options.json').write_text(json.dumps(options))
                    record['run_options_sha256'] = fixture.data.digest(run / 'run-options.json')
                elif fault == 'apk': record['apk_relative'] = 'apk/qt-selftest.apk'
                elif fault == 'arguments': record['arguments'] = '--selftest'
                elif fault == 'qualification': record['qualification'] = True
                fixture.save(run, record)
                if fault == 'two-cases': (run / 'results.json').write_text(json.dumps([record, record]))
                with self.assertRaises(ValueError): tts.collect(root, run.name, 'arm64-v8a')

    def test_valid_tts_phases_cannot_hide_late_multimedia_process_crash_or_host_failure(self):
        for fault in ('debuggerd', 'host', 'capture-owner'):
            with self.subTest(fault=fault), self.ready() as (root, run, record):
                if fault == 'debuggerd':
                    with (run / 'final-logcat.log').open('a') as stream:
                        stream.write('\nI/DEBUG(99): *** *** ***\nI/DEBUG(99): pid: 1234 >>> org.longreachqt.examples.multimedialab <<<\n')
                    fixture.rebind_final(run, record)
                elif fault == 'host': record['host_process_exit_sha256'] = '0' * 64
                else: fixture.rebind_final(run, record, host_process_owner_sha256='0' * 64)
                fixture.save(run, record)
                with self.assertRaises((OSError, ValueError)): tts.collect(root, run.name, 'arm64-v8a')

    def test_qt6_all_abis_keep_diagnostic_scope_and_matching_major(self):
        for abi in ('armeabi-v7a', 'arm64-v8a', 'x86', 'x86_64'):
            with self.subTest(abi=abi), self.ready(abi, 6) as (root, run, record):
                report = tts.collect(root, run.name, abi, qt_major=6)
                self.assertEqual(report['qt_major'], 6)
                self.assertEqual(report['diagnostic'], 'qt6-tts-behavior')
                self.assertFalse(report['qualification'])
                self.assertFalse((root / 'final-results.json').exists())
                with self.assertRaises(ValueError): tts.validate(root, run.name, abi, qt_major=5)

    def test_qt6_state_order_and_late_process_failure_are_still_rejected(self):
        for fault in ('state', 'death'):
            with self.subTest(fault=fault), self.ready(qt_major=6) as (root, run, record):
                if fault == 'state':
                    stdout = run / 'tts-behavior/files/selftest.stdout'
                    stdout.write_text(stdout.read_text().replace('speech/pause-stable-before-resume - state=Paused',
                                                               'speech/pause-stable-before-resume - state=Ready'))
                    fixture.rebind_stdout(run, record)
                else:
                    with (run / 'final-logcat.log').open('a') as stream:
                        stream.write('\nI/DEBUG(99): *** *** ***\nI/DEBUG(99): pid: 1234 >>> org.longreachqt.examples.qt6.multimedia_lab <<<\n')
                    fixture.rebind_final(run, record)
                fixture.save(run, record)
                with self.assertRaises(ValueError): tts.collect(root, run.name, 'arm64-v8a', qt_major=6)

    def test_tts_major_cannot_be_relabelled_without_matching_inputs(self):
        with self.ready() as (root, run, record):
            with self.assertRaises(ValueError): tts.collect(root, run.name, 'arm64-v8a', qt_major=6)
        for unsupported in (4, 7, '6', True):
            with self.assertRaises(ValueError): tts.kind(unsupported)


if __name__ == '__main__':
    unittest.main()
