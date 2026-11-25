# SPDX-License-Identifier: GPL-3.0-or-later
"""Functional host observer metadata tests; no Android process executes."""
from pathlib import Path
import json
from unittest.mock import patch
import tempfile
import unittest
import android_extras_fixtures as fixture

state=fixture.state


class ExtrasState(unittest.TestCase):
    def setUp(self):
        directory=tempfile.TemporaryDirectory(prefix='longreach-extras-')
        self.addCleanup(directory.cleanup);self.case=Path(directory.name)

    def test_live_birth_identity_then_two_natural_service_exits(self):
        record=fixture.prepare(self.case)
        result=state.validate(self.case,fixture.PACKAGE,record)
        self.assertEqual(result['service_processes'],2)
        self.assertTrue(result['service_exits_confirmed'])
        self.assertEqual(state.read(self.case/'extras-0-live.json')['start_ticks'],800)

    def test_eight_native_successes_cannot_replace_independent_host_receipts(self):
        (self.case/'files').mkdir();(self.case/'files/selftest.stdout').write_text(fixture.transcript())
        with self.assertRaises(OSError):state.validate(self.case,fixture.PACKAGE,{})

    def test_changed_birth_command_or_dead_process_refuses_before_ack(self):
        for fault in ('birth','command','zombie'):
            with self.subTest(fault=fault),tempfile.TemporaryDirectory() as directory:
                case=Path(directory);marker=fixture.live_inputs(case,0)
                path=case/'extras-0-live-stat-b.stdout'
                if fault=='birth':path.write_text(path.read_text().replace('800','900'))
                elif fault=='zombie':path.write_text(path.read_text().replace(') S ',') Z '))
                else:(case/'extras-0-live-cmdline.stdout').write_text(fixture.PACKAGE)
                with self.assertRaises(ValueError):state.observe(case,fixture.PACKAGE,0,marker)
                self.assertFalse((case/'extras-service-0-live-ack.txt').exists())

    def test_still_present_force_stop_or_missing_death_refuses_exit_ack(self):
        for fault in ('present','forced','missing-death'):
            with self.subTest(fault=fault),tempfile.TemporaryDirectory() as directory:
                case=Path(directory);marker=fixture.live_inputs(case,0);state.observe(case,fixture.PACKAGE,0,marker)
                fixture.exit_inputs(case,0)
                path=case/'extras-0-exit-log-0.stdout'
                if fault=='present':
                    with (case/'extras-0-exit-ps-0.stdout').open('a') as stream:stream.write('u0a20 3010 1 '+fixture.PACKAGE+':longreach_extras\n')
                elif fault=='forced':path.write_text(path.read_text().replace('I/ActivityManager( 100): Process',
                    'I/ActivityManager( 100): Force stopping '+fixture.PACKAGE+':longreach_extras\nI/ActivityManager( 100): Process'))
                else:path.write_text('\n'.join(path.read_text().splitlines()[:-1])+'\n')
                with self.assertRaises(ValueError):state.finish(case,fixture.PACKAGE,0)
                self.assertFalse((case/'extras-service-0-exit-ack.txt').exists())

    def test_native_service_result_destroy_nonce_or_delivered_ack_must_match(self):
        for fault in ('native','destroy','nonce','ack'):
            with self.subTest(fault=fault),tempfile.TemporaryDirectory() as directory:
                case=Path(directory);record=fixture.prepare(case);service=case/'files/extras-service-3010'
                if fault=='native':(service/'selftest-result.txt').write_text('1\n')
                elif fault=='destroy':(service/'on-destroy.txt').write_text('3011\n')
                elif fault=='nonce':(service/'selftest.stdout').write_text((service/'selftest.stdout').read_text().replace('c'*32,'e'*32))
                else:(case/'files/extras-service-0-live-ack.txt').write_text('e'*32+'\n')
                with self.assertRaises(ValueError):state.validate(case,fixture.PACKAGE,record)

    def test_rebound_final_log_cannot_hide_late_service_crash(self):
        record=fixture.prepare(self.case)
        with (self.case/'final-logcat.log').open('a') as stream:stream.write('I/DEBUG( 99): *** *** ***\n')
        record['final_logcat_sha256']=state.digest(self.case/'final-logcat.log')
        with self.assertRaisesRegex(ValueError,'Fatal'):state.validate(self.case,fixture.PACKAGE,record)

    def test_api10_file_capture_uses_parent_readiness_and_each_service_fence(self):
        # The existing owned-capture verifier has its own process tests. Mock
        # only that boundary; exercise actual per-service snapshot/fence checks.
        for broken in (False, True):
            with self.subTest(broken=broken), tempfile.TemporaryDirectory() as directory, patch.object(state.exit_state._owned, 'validate_log_capture'):
                case=Path(directory);record=fixture.prepare(case)
                ready='READY-'+'e'*32
                ready_line='I/LongreachCapture( 321): '+ready+'\n'
                (case/'logcat-capture-ready.log').write_text(ready_line)
                capture={'schema_version':1,'serial':'emulator-5580',
                    'remote_file':'/data/local/longreach-log-'+'e'*32+'.log',
                    'ready_marker':ready,'ready_log_sha256':state.digest(case/'logcat-capture-ready.log')}
                (case/'logcat-capture.json').write_text(json.dumps(capture))
                record['log_capture_sha256']=state.digest(case/'logcat-capture.json')
                for index in (0,1):
                    for sample in (0,1):
                        name=f'extras-{index}-exit-log-{sample}'
                        path=case/(name+'.stdout');fence='CAPTURE-'+f'{index*2+sample+1:032x}'
                        path.write_text(ready_line+path.read_text()+'I/LongreachCapture( 321): '+fence+'\n')
                        observation={'schema_version':1,'serial':'emulator-5580',
                            'log_capture_sha256':record['log_capture_sha256'],
                            'snapshot_sha256':state.digest(path),'fence_marker':fence}
                        if broken and index==0 and sample==0:observation['fence_marker']='CAPTURE-'+'f'*32
                        (case/(name+'-file-capture.json')).write_text(json.dumps(observation))
                    (case/f'extras-{index}-exit.json').write_text(json.dumps(state.parse_exit(case,fixture.PACKAGE,index)))
                sealed=state.read(case/'extras-services.json')
                for index in (0,1):sealed['rounds'][index]['exit_sha256']=state.digest(case/f'extras-{index}-exit.json')
                (case/'extras-services.json').write_text(json.dumps(sealed));record['extras_services_sha256']=state.digest(case/'extras-services.json')
                if broken:
                    with self.assertRaisesRegex(ValueError,'freshness'):state.validate(case,fixture.PACKAGE,record)
                else:self.assertTrue(state.validate(case,fixture.PACKAGE,record)['service_exits_confirmed'])

    def test_named_checks_and_fresh_processes_cannot_be_replaced_by_totals(self):
        for text in (fixture.transcript().replace('activity-result=PASS','activity-result=FAIL'),
                     fixture.transcript().replace('pid=3011','pid=3010'),
                     fixture.transcript().replace('calls=8 callbacks=8','calls=7 callbacks=8')):
            with self.subTest(text=text[-100:]),self.assertRaises(ValueError):state.protocol.validate(text)


if __name__=='__main__':unittest.main()
