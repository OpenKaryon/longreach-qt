# SPDX-License-Identifier: GPL-3.0-or-later
"""Ordinary metadata checks for the explicit API10-on-API21 diagnostic."""
from contextlib import contextmanager
import json
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

import android_api21_forward_fixtures as fixture

forward = fixture.forward


class ForwardDiagnostic(unittest.TestCase):
    @contextmanager
    def ready(self, abi='x86'):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory) / 'artifacts with spaces'
            record = fixture.prepare(root, abi)
            with patch.object(forward._identity, 'REPO', root / 'fixture-media-repo'):
                yield root, root / 'fixture-run', record

    def test_both_source_abis_use_api10_coverage_on_api21_without_qualification(self):
        for abi in ('x86', 'armeabi-v7a'):
            with self.subTest(abi=abi), self.ready(abi) as (root, run, record):
                report = forward.collect(root, run.name, abi)
                self.assertEqual((report['source_api'], report['guest_api'], report['coverage_api']), (10, 21, 10))
                self.assertFalse(report['qualification'])
                self.assertTrue(report['completed'])
                self.assertTrue(report['all_observed_exits_clean'])
                self.assertEqual(report['cases'][0]['apk_relative'], 'apk/qt-selftest.apk')
                self.assertEqual(report['coverage_policy_sha256'], fixture.data.digest(forward.base._baselines.BASELINES))
                self.assertEqual(report['cases'][0]['summary'], ['---- fixture: 213 passed, 0 failed, 0 skipped ----'])
                self.assertFalse((root / 'final-results.json').exists())
                self.assertFalse((run / 'sound-cache-result.json').exists())

    def test_coverage_faults_rebind_stdout_instead_of_failing_only_its_hash(self):
        for fault, message in (('count', 'coverage'), ('required', 'missing required PASS'),
                               ('timing', 'timed|observation|OBSERVE'), ('summary', 'summary differs')):
            with self.subTest(fault=fault), self.ready() as (root, run, record):
                path = run / 'api10-selftest/files/selftest.stdout'
                text = path.read_text()
                if fault == 'count':
                    text = text.replace('213 passed', '212 passed')
                elif fault == 'required':
                    text = text.replace('PASS: sync/mutex-timed-wakeup', 'PASS: fixture/substitute-check')
                elif fault == 'timing':
                    text = text.replace('elapsed_ms=250', 'elapsed_ms=0')
                else:
                    record['summary'] = ['---- stale: 213 passed, 0 failed, 0 skipped ----']
                path.write_text(text)
                fixture.rebind_stdout(run, record)
                fixture.save(run, record)
                with self.assertRaisesRegex(ValueError, message):
                    forward.collect(root, run.name, 'x86')

    def test_mode_source_guest_policy_arguments_and_false_qualification_required(self):
        for fault in ('mode', 'source', 'guest', 'policy', 'arguments', 'apk', 'qualification', 'extra-case'):
            with self.subTest(fault=fault), self.ready() as (root, run, record):
                if fault == 'mode':
                    fixture.rebind_options(run, record, diagnostic='none')
                elif fault == 'source':
                    fixture.rebind_options(run, record, source_api=21)
                elif fault == 'guest':
                    (run / 'guest-properties.txt').write_text('[ro.build.version.sdk]: [10]\n')
                elif fault == 'policy':
                    fixture.rebind_options(run, record, coverage_policy_sha256='0' * 64)
                    record['coverage_policy_sha256'] = '0' * 64
                elif fault == 'arguments':
                    record['arguments'] = '--modern-cpp'
                elif fault == 'apk':
                    record['apk_relative'] = 'apk/extended/qt-selftest.apk'
                elif fault == 'qualification':
                    record['qualification'] = True
                fixture.save(run, record)
                if fault == 'extra-case':
                    (run / 'results.json').write_text(json.dumps([record, record]))
                with self.assertRaises(ValueError):
                    forward.collect(root, run.name, 'x86')

    def test_changed_inputs_or_late_capture_never_keep_current_success(self):
        for fault in ('stdout', 'unused-apk', 'native', 'cpu', 'final-debuggerd', 'case-debuggerd', 'capture-owner'):
            with self.subTest(fault=fault), self.ready() as (root, run, record):
                forward.collect(root, run.name, 'x86')
                output = run / 'api10-on-api21-result.json'
                prior = output.read_bytes()
                if fault in ('stdout', 'unused-apk', 'native', 'cpu'):
                    path = {'stdout':run/'api10-selftest/files/selftest.stdout','unused-apk':root/'apk/graphics-gallery.apk',
                            'native':root/'native/libc++_shared.so','cpu':run/'guest-cpuinfo.txt'}[fault]
                    with path.open('ab') as stream: stream.write(b'changed fixture evidence')
                elif fault == 'final-debuggerd':
                    with (run/'final-logcat.log').open('a') as stream:
                        stream.write('\nI/DEBUG(99): *** *** ***\nI/DEBUG(99): pid: 1234 >>> org.longreachqt.examples.qtselftest <<<\n')
                    fixture.common.rebind_final(run, record)
                elif fault == 'case-debuggerd':
                    for name in ('logcat-after-cleanup-raw.log','logcat-after-cleanup.log'):
                        with (run/'api10-selftest'/name).open('a') as stream:
                            stream.write('\nI/DEBUG(99): *** *** ***\nI/DEBUG(99): pid: 1234 >>> org.longreachqt.examples.qtselftest <<<\n')
                    record['case_cleanup_raw_logcat_sha256']=fixture.data.digest(run/'api10-selftest/logcat-after-cleanup-raw.log')
                    record['case_cleanup_logcat_sha256']=fixture.data.digest(run/'api10-selftest/logcat-after-cleanup.log')
                else:
                    fixture.common.rebind_final(run, record, host_process_owner_sha256='0'*64)
                fixture.save(run, record)
                with self.assertRaises((OSError,ValueError,RuntimeError)):
                    forward.collect(root, run.name, 'x86')
                self.assertFalse(output.exists())
                self.assertEqual(next(run.glob('api10-on-api21-previous-*.json')).read_bytes(),prior)

    def test_64bit_api21_sdks_cannot_be_relabelled_as_api10_sources(self):
        for abi in ('arm64-v8a', 'x86_64'):
            with self.subTest(abi=abi), self.ready() as (root, run, record):
                with self.assertRaisesRegex(ValueError,'only Qt5 ARMv7/x86'):
                    forward.collect(root,run.name,abi)


if __name__ == '__main__':
    unittest.main()
