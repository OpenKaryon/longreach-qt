# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2026 OpenKaryon
"""Observed process termination from synthetic scoped logs and ps snapshots."""
import importlib.util
import json
from pathlib import Path
import tempfile
import unittest

import android_result_fixtures as fixtures

spec = importlib.util.spec_from_file_location('android_exit', fixtures.ROOT / 'scripts/run/android-process-exit.py')
exits = importlib.util.module_from_spec(spec)
spec.loader.exec_module(exits)
PACKAGE = 'org.longreachqt.examples.qtselftest'
MARKER = 'BEGIN-0123456789abcdef0123456789abcdef'


def refresh(case, record):
    proof = json.loads((case / 'process-exit.json').read_text())
    for key, name in (('logcat_sha256', 'logcat.log'), ('raw_logcat_sha256', 'logcat-raw.log'), ('ps_sha256', 'process-exit-ps.txt')):
        proof[key] = fixtures.digest(case / name)
    (case / 'process-exit.json').write_text(json.dumps(proof))
    record['process_exit_proof_sha256'] = fixtures.digest(case / 'process-exit.json')


class ProcessExit(unittest.TestCase):
    def test_pid_pair_and_absent_process_are_required_for_both_log_formats(self):
        with tempfile.TemporaryDirectory() as directory:
            case = Path(directory)
            record = fixtures.exit_evidence(case, PACKAGE, MARKER)
            for modern in (False, True):
                if modern:
                    start = f'I/ActivityManager( 100): Start proc 1234:{PACKAGE}/u0a1 for activity'
                    for name in ('logcat.log', 'logcat-raw.log'):
                        lines = (case / name).read_text().splitlines()
                        index = 0 if name == 'logcat.log' else 1
                        lines[index] = start
                        (case / name).write_text('\n'.join(lines) + '\n')
                    proof = json.loads((case / 'process-exit.json').read_text())
                    proof['start_line'] = start
                    (case / 'process-exit.json').write_text(json.dumps(proof))
                    refresh(case, record)
                self.assertEqual(exits.require_exit(case, PACKAGE, record)['process_id'], 1234)
            # AndroidRuntime's ordinary banner is not a debuggerd tombstone.
            exits.lifecycle(['D/AndroidRuntime( 123): >>>>>> AndroidRuntime START com.android.internal.os.RuntimeInit <<<<<<'], PACKAGE)

    def test_a_zero_return_or_unrelated_death_does_not_prove_process_exit(self):
        for changed in ('alive', 'wrong-pid', 'death-before-launch', 'missing-proof', 'missing-flag'):
            with self.subTest(changed=changed), tempfile.TemporaryDirectory() as directory:
                case = Path(directory)
                (case / 'selftest-result.txt').write_text('0')
                record = fixtures.exit_evidence(case, PACKAGE, MARKER)
                reason = 'Application remained'
                if changed == 'alive':
                    (case / 'process-exit-ps.txt').write_text('USER PID PPID NAME\nroot 1 0 /init\napp 1234 1 '+PACKAGE+'\n')
                elif changed in ('wrong-pid', 'death-before-launch'):
                    lines = (case / 'logcat.log').read_text().splitlines()
                    if changed == 'wrong-pid':
                        lines[-1] = lines[-1].replace('pid 1234', 'pid 9999')
                    else:
                        lines = [lines[-1]] + lines[:-1]
                    (case / 'logcat.log').write_text('\n'.join(lines) + '\n')
                    (case / 'logcat-raw.log').write_text(f'I/LongreachCase( 100): {MARKER}\n'+'\n'.join(lines)+'\n')
                    reason = 'Matching application PID'
                elif changed == 'missing-proof':
                    (case / 'process-exit.json').unlink()
                    with self.assertRaises(FileNotFoundError):
                        exits.require_exit(case, PACKAGE, record)
                    continue
                else:
                    record['process_exit_confirmed'] = False
                    reason = 'Missing or mismatched'
                refresh(case, record)
                with self.assertRaisesRegex(ValueError, reason):
                    exits.require_exit(case, PACKAGE, record)

    def test_late_crashes_and_external_termination_cannot_be_clean_teardown(self):
        for detail, reason in (('F/DEBUG( 1234): *** *** *** ***', 'Fatal cleanup'),
                               (f'F/DEBUG( 1234): >>> {PACKAGE} <<<', 'Fatal cleanup'),
                               ('F/libc( 1234): Fatal signal 11', 'Fatal cleanup'),
                               (f'I/ActivityManager( 100): Force stopping package {PACKAGE} uid=10001', 'force-stopped'),
                               (f'I/ActivityManager( 100): Killing 1234:{PACKAGE}/u0a1: timeout', 'killed')):
            with self.subTest(detail=detail), tempfile.TemporaryDirectory() as directory:
                case = Path(directory)
                record = fixtures.exit_evidence(case, PACKAGE, MARKER)
                lines = (case / 'logcat.log').read_text().splitlines()
                lines.insert(-1, detail)
                (case / 'logcat.log').write_text('\n'.join(lines) + '\n')
                (case / 'logcat-raw.log').write_text(f'I/LongreachCase( 100): {MARKER}\n'+'\n'.join(lines)+'\n')
                # Reach the lifecycle policy rather than stopping at a checksum.
                refresh(case, record)
                with self.assertRaisesRegex(ValueError, reason):
                    exits.require_exit(case, PACKAGE, record)

    def test_missing_ps_and_restarted_main_or_remote_process_are_rejected(self):
        for lines in ([], ['adb: closed'], ['USER PID PPID NAME'], ['USER PID PPID NAME', 'root invalid 0 init']):
            with self.subTest(lines=lines), self.assertRaisesRegex(ValueError, 'ps'):
                exits.present(lines, PACKAGE, 1234)
        self.assertTrue(exits.present(['USER PID PPID NAME', 'app 2222 1 '+PACKAGE+':service'], PACKAGE, 1234))
        self.assertTrue(exits.present(['USER PID PPID NAME', 'app 1234 1 other-process'], PACKAGE, 1234))
        lines = [f'I/ActivityManager( 100): Start proc 1234:{PACKAGE}/u0a1 for activity',
                 f'I/ActivityManager( 100): Start proc 1235:{PACKAGE}/u0a1 for activity']
        with self.assertRaisesRegex(ValueError, 'Ambiguous application process launch'):
            exits.lifecycle(lines, PACKAGE)

    def test_changed_observation_or_out_of_policy_bounds_cannot_be_accepted(self):
        for changed in ('snapshot', 'scope', 'observation-order', 'timeout'):
            with self.subTest(changed=changed), tempfile.TemporaryDirectory() as directory:
                case = Path(directory)
                record = fixtures.exit_evidence(case, PACKAGE, MARKER)
                reason = 'evidence changed'
                if changed == 'snapshot':
                    (case / 'process-exit-ps.txt').write_text('replaced observation')
                elif changed == 'scope':
                    (case / 'log-marker.txt').write_text('BEGIN-'+'f'*32)
                    reason = 'launch boundary'
                else:
                    proof = json.loads((case / 'process-exit.json').read_text())
                    if changed == 'observation-order':
                        proof['observation_order'] = 'ps-then-logcat'
                        reason = 'Missing or mismatched'
                    else:
                        proof['elapsed_ms'] = 60001
                        reason = 'observation bounds'
                    (case / 'process-exit.json').write_text(json.dumps(proof))
                    record['process_exit_proof_sha256'] = fixtures.digest(case / 'process-exit.json')
                with self.assertRaisesRegex(ValueError, reason):
                    exits.require_exit(case, PACKAGE, record)


if __name__ == '__main__':
    unittest.main()
