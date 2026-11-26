# SPDX-License-Identifier: GPL-3.0-or-later
"""Ordinary API21 WAV metadata contracts; never execute a guest or audio code."""
from contextlib import contextmanager
import json
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

import android_api21_sound_cache_fixtures as fixture

sound = fixture.sound


class Api21Sound(unittest.TestCase):
    @contextmanager
    def ready(self, abi='x86_64', qt=5):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary) / 'artifacts with spaces'
            record = fixture.prepare(root, abi, kind='sound' if qt == 5 else 'sound6')
            with patch.object(sound._identity, 'REPO', root / 'fixture-media-repo'):
                yield root, root / 'fixture-run', record

    def test_all_four_abis_publish_only_diagnostic_and_preserve_prior_recheck(self):
        for abi in ('armeabi-v7a', 'arm64-v8a', 'x86', 'x86_64'):
            with self.subTest(abi=abi), self.ready(abi) as (root, run, record):
                report = sound.collect(root, run.name, abi)
                self.assertTrue(report['completed'])
                self.assertFalse(report['qualification'])
                self.assertEqual((report['api'], report['abi']), (21, abi))
                self.assertEqual(len(report['cases']), 1)
                self.assertIn('sound-cache diagnostic', report['diagnostic_reasons'][0])
                self.assertFalse((root / 'final-results.json').exists())
                prior = (run / 'sound-cache-result.json').read_bytes()
                self.assertEqual(sound.collect(root, run.name, abi), report)
                histories = list(run.glob('sound-cache-previous-*.json'))
                self.assertEqual(len(histories), 1)
                self.assertEqual(histories[0].read_bytes(), prior)

    def test_qt6_four_abis_use_own_core_apk_and_explicit_matching_version(self):
        for abi in ('armeabi-v7a', 'arm64-v8a', 'x86', 'x86_64'):
            with self.subTest(abi=abi), self.ready(abi, qt=6) as (root, run, record):
                report = sound.collect(root, run.name, abi, qt_major=6)
                self.assertEqual(report['qt_major'], 6)
                self.assertEqual(report['diagnostic'], 'qt6-sound-cache-teardown')
                self.assertEqual(report['cases'][0]['apk_relative'], 'apk/qt-selftest.apk')
                self.assertTrue(report['completed'])
                self.assertFalse(report['qualification'])
                self.assertFalse((root / 'final-results.json').exists())
                with self.assertRaises((OSError, ValueError, RuntimeError)):
                    sound.validate(root, run.name, abi, qt_major=5)

    def test_qt6_diagnostic_refuses_other_major_label_and_extended_apk(self):
        for fault in ('major-label', 'extended-apk'):
            with self.subTest(fault=fault), self.ready(qt=6) as (root, run, record):
                if fault == 'major-label':
                    options = json.loads((run / 'run-options.json').read_text())
                    options['diagnostic'] = 'qt5-sound-cache-teardown'
                    (run / 'run-options.json').write_text(json.dumps(options))
                    record['run_options_sha256'] = fixture.data.digest(run / 'run-options.json')
                else:
                    record['apk_relative'] = 'apk/extended/qt-selftest.apk'
                fixture.save(run, record)
                with self.assertRaises((OSError, ValueError, RuntimeError)):
                    sound.collect(root, run.name, 'x86_64', qt_major=6)
                self.assertFalse((run / 'sound-cache-result.json').exists())

    def test_recheck_does_not_move_a_directory_mistaken_for_report(self):
        with self.ready() as (root, run, record):
            output = run / 'sound-cache-result.json'
            output.mkdir()
            (output / 'retained.txt').write_text('fixture evidence, not a JSON result')
            with self.assertRaisesRegex(ValueError, 'ordinary report file'):
                sound.collect(root, run.name, 'x86_64')
            self.assertTrue((output / 'retained.txt').is_file())
            self.assertFalse(list(run.glob('sound-cache-previous-*.json')))

    def test_protocol_failure_rebinds_hashes_and_removes_stale_current_result(self):
        with self.ready() as (root, run, record):
            sound.collect(root, run.name, 'x86_64')
            prior = (run / 'sound-cache-result.json').read_bytes()
            (run / 'sound-cache-teardown/files/selftest.stdout').write_text('---- qt-selftest: 106 passed, 0 failed, 4 skipped ----')
            fixture.rebind_stdout(run, record)
            fixture.save(run, record)
            with self.assertRaisesRegex(ValueError, 'pre-exit phases'):
                sound.collect(root, run.name, 'x86_64')
            self.assertFalse((run / 'sound-cache-result.json').exists())
            self.assertEqual(next(run.glob('sound-cache-previous-*.json')).read_bytes(), prior)

    def test_explicit_mode_case_and_qualification_are_required(self):
        faults = ('mode-missing', 'mode-unknown', 'qualification', 'ordinary-arguments', 'two-cases')
        for fault in faults:
            with self.subTest(fault=fault), self.ready() as (root, run, record):
                options = json.loads((run / 'run-options.json').read_text())
                if fault == 'mode-missing':
                    del options['diagnostic']
                elif fault == 'mode-unknown':
                    options['diagnostic'] = 'other'
                elif fault == 'qualification':
                    record['qualification'] = True
                elif fault == 'ordinary-arguments':
                    record['arguments'] = '--selftest'
                (run / 'run-options.json').write_text(json.dumps(options))
                record['run_options_sha256'] = fixture.data.digest(run / 'run-options.json')
                fixture.save(run, record)
                if fault == 'two-cases':
                    (run / 'results.json').write_text(json.dumps([record, record]))
                with self.assertRaises(ValueError):
                    sound.collect(root, run.name, 'x86_64')

    def test_final_capture_missing_wrong_owner_serial_marker_pid_and_debuggerd_refuse(self):
        faults = ('missing', 'owner', 'serial', 'marker', 'pid', 'debuggerd')
        for fault in faults:
            with self.subTest(fault=fault), self.ready() as (root, run, record):
                final = run / 'final-logcat.log'
                if fault == 'owner':
                    fixture.rebind_final(run, record, host_process_owner_sha256='0' * 64)
                elif fault == 'serial':
                    fixture.rebind_final(run, record, serial='emulator-5580')
                elif fault == 'marker':
                    final.write_text('I/Qt(1234): no launch boundary\n')
                    fixture.rebind_final(run, record)
                elif fault == 'pid':
                    final.write_text(final.read_text().replace('pid=1234', 'pid=7777'))
                    fixture.rebind_final(run, record)
                elif fault == 'debuggerd':
                    with final.open('a') as stream:
                        stream.write('\nI/DEBUG(99): *** *** ***\nI/DEBUG(99): pid: 1234 >>> org.longreachqt.examples.qtselftest <<<\n')
                    fixture.rebind_final(run, record)
                else:
                    (run / 'final-logcat-capture.json').unlink()
                fixture.save(run, record)
                with self.assertRaises((OSError, ValueError)):
                    sound.collect(root, run.name, 'x86_64')

    def test_host_cpu_media_apk_and_full_native_generation_are_independent(self):
        faults = ('host', 'cpu', 'media', 'apk', 'native')
        for fault in faults:
            with self.subTest(fault=fault), self.ready() as (root, run, record):
                if fault == 'host':
                    record['host_process_exit_sha256'] = '0' * 64
                    fixture.save(run, record)
                else:
                    path = {'cpu': run / 'guest-cpuinfo.txt', 'media': root / 'media/x86_64/ramdisk.img',
                            'apk': root / 'apk/graphics-gallery.apk', 'native': root / 'native/libc++_shared.so'}[fault]
                    with path.open('ab') as out:
                        out.write(b'changed fixture evidence')
                with self.assertRaises((OSError, ValueError, RuntimeError)):
                    sound.collect(root, run.name, 'x86_64')

    def test_ordinary_launch_classification_remains_and_wrong_qt_sound_mode_refuses(self):
        for qt in (5, 6):
            with tempfile.TemporaryDirectory() as temporary:
                root = Path(temporary)
                records = fixture.data.api21(root, qt, sound.base._artifacts)
                report = sound.base._launch.validate(root / 'fixture-run', qt, 'x86_64', records)
                self.assertTrue(report['qualification'])
        with self.ready() as (root, run, record):
            options = json.loads((run / 'run-options.json').read_text())
            options['qt_major'] = 6
            (run / 'run-options.json').write_text(json.dumps(options))
            with self.assertRaisesRegex(ValueError, 'matching Qt5/Qt6'):
                sound.base._launch.validate(run, 6, 'x86_64', [record])


if __name__ == '__main__':
    unittest.main()
