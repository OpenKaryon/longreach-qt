# SPDX-License-Identifier: GPL-3.0-or-later
"""Actual collector contracts with synthetic transport/native boundaries only."""
from contextlib import contextmanager
import importlib.util
import json
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch
import android_api21_sound_cache_fixtures as base_fixture
import android_extras_fixtures as service_fixture

ROOT=Path(__file__).resolve().parents[3]
spec=importlib.util.spec_from_file_location('extras_api21_test',ROOT/'scripts/run/android/android-api21-extras.py')
collector=importlib.util.module_from_spec(spec);spec.loader.exec_module(collector)


class Api21Extras(unittest.TestCase):
    @contextmanager
    def ready(self,abi='arm64-v8a'):
        with tempfile.TemporaryDirectory() as directory:
            root=Path(directory)/'Extras artifacts with spaces'
            record=base_fixture.prepare(root,abi,kind='extras');run=root/'fixture-run';case=run/'android-extras'
            parent=json.loads((case/'process-exit.json').read_text())
            service_fixture.prepare(case,record['log_marker'])
            raw=(f'I/LongreachCase( 100): {record["log_marker"]}\n'+parent['start_line']+'\n'
                + '\n'.join(service_fixture.service_log(0,record['log_marker']).splitlines()[1:])+'\n'
                +service_fixture.service_log(1)+parent['death_line']+'\n')
            (case/'logcat-raw.log').write_text(raw)
            (case/'logcat.log').write_text('\n'.join(raw.splitlines()[1:])+'\n')
            (case/'logcat-after-cleanup-raw.log').write_text(raw)
            (case/'logcat-after-cleanup.log').write_bytes((case/'logcat.log').read_bytes())
            parent.update(raw_logcat_sha256=service_fixture.state.digest(case/'logcat-raw.log'),
                          logcat_sha256=service_fixture.state.digest(case/'logcat.log'))
            (case/'process-exit.json').write_text(json.dumps(parent))
            record['process_exit_proof_sha256']=service_fixture.state.digest(case/'process-exit.json')
            for field,file in [('case_cleanup_raw_logcat_sha256','logcat-after-cleanup-raw.log'),('case_cleanup_logcat_sha256','logcat-after-cleanup.log')]:
                record[field]=service_fixture.state.digest(case/file)
            record['extras_services_sha256']=service_fixture.state.digest(case/'extras-services.json')
            (run/'final-logcat.log').write_text(raw)
            base_fixture.rebind_stdout(run,record);base_fixture.rebind_final(run,record);base_fixture.save(run,record)
            with patch.object(collector._identity,'REPO',root/'fixture-media-repo'):
                yield root,run,case,record

    def test_all_abis_keep_source_bound_extras_diagnostic_separate_from_full_suite(self):
        for abi in ('armeabi-v7a','arm64-v8a','x86','x86_64'):
            with self.subTest(abi=abi),self.ready(abi) as (root,run,case,record):
                report=collector.collect(root,run.name,abi)
                self.assertTrue(report['completed']);self.assertFalse(report['qualification'])
                self.assertTrue(report['service_exits_confirmed']);self.assertEqual(report['service_processes'],2)
                self.assertFalse((root/'final-results.json').exists())
                previous=(run/'android-extras-result.json').read_bytes()
                self.assertEqual(collector.collect(root,run.name,abi),report)
                self.assertEqual(next(run.glob('android-extras-previous-*.json')).read_bytes(),previous)

    def test_native_success_does_not_replace_live_service_proof_and_failed_recheck_preserves_history(self):
        with self.ready() as (root,run,case,record):
            collector.collect(root,run.name,'arm64-v8a')
            (case/'extras-0-live.json').unlink()
            with self.assertRaises(OSError):collector.collect(root,run.name,'arm64-v8a')
            self.assertFalse((run/'android-extras-result.json').exists())
            self.assertTrue(list(run.glob('android-extras-previous-*.json')))

    def test_extended_apk_or_nonexplicit_mode_cannot_publish_service_success(self):
        for fault in ('extended-apk','mode','qualified'):
            with self.subTest(fault=fault),self.ready() as (root,run,case,record):
                if fault=='extended-apk':record['apk_relative']='apk/extended/qt-selftest.apk'
                elif fault=='qualified':record['qualification']=True
                else:
                    options=json.loads((run/'run-options.json').read_text());options.pop('diagnostic')
                    (run/'run-options.json').write_text(json.dumps(options));record['run_options_sha256']=service_fixture.state.digest(run/'run-options.json')
                base_fixture.save(run,record)
                with self.assertRaises(ValueError):collector.collect(root,run.name,'arm64-v8a')

    def test_service_native_failure_or_late_owned_crash_refuses_even_with_parent_native_zero(self):
        for fault in ('service-native','late-crash','host-owner'):
            with self.subTest(fault=fault),self.ready() as (root,run,case,record):
                if fault=='service-native':(case/'files/extras-service-3010/selftest-result.txt').write_text('1\n')
                elif fault=='host-owner':record['host_process_exit_sha256']='0'*64
                else:
                    with (run/'final-logcat.log').open('a') as stream:stream.write('I/DEBUG( 99): *** *** ***\n')
                    base_fixture.rebind_final(run,record)
                base_fixture.save(run,record)
                with self.assertRaises((OSError,ValueError)):collector.collect(root,run.name,'arm64-v8a')


if __name__=='__main__':unittest.main()
