# SPDX-License-Identifier: GPL-3.0-or-later
"""Ordinary timed-sync report fixtures, without native compilation or execution."""
import importlib.util
from pathlib import Path
import unittest

import android_result_fixtures as fixtures

ROOT = Path(__file__).resolve().parents[3]
spec = importlib.util.spec_from_file_location('timed_sync_gate', ROOT / 'scripts/run/android/android-baselines.py')
gate = importlib.util.module_from_spec(spec)
spec.loader.exec_module(gate)
TARGETS = {(5, 10, 'x86'): 213, (5, 10, 'armeabi-v7a'): 213,
           (5, 21, 'x86_64'): 212, (5, 21, 'arm64-v8a'): 212,
           (6, 21, 'armeabi-v7a'): 296, (6, 21, 'arm64-v8a'): 296,
           (6, 21, 'x86'): 297, (6, 21, 'x86_64'): 296}
WAKEUP = 'sync/mutex-timed-wakeup'


def observation(name, attempt=1, verdict='pass', **values):
    data = dict(ready=1, unavailable=1, armed=1, released_before_call=0,
                acquired=0 if name.endswith('-timeout') else 1,
                elapsed_ms=200 if name.endswith('-timeout') else 250, joined=1)
    data.update(values)
    return (f'OBSERVE: {name} - attempt={attempt} ' +
            ' '.join(f'{key}={value}' for key, value in data.items()) + f' verdict={verdict}')


class TimedSyncEvidence(unittest.TestCase):
    def test_all_eight_targets_require_four_checks_observations_and_new_floors(self):
        for target, minimum in TARGETS.items():
            with self.subTest(target=target):
                policy = gate.policy(*target, 'qt-selftest')
                self.assertEqual(policy['min_pass'], minimum)
                self.assertTrue(policy['require_timed_sync_evidence'])
                self.assertTrue(set(gate.TIMED_SYNC.CHECKS) <= set(policy['required_pass']))
                text = fixtures.stdout(*target, 'qt-selftest')
                self.assertEqual(gate.require(*target, 'qt-selftest', text), (minimum, 0, 0))
                self.assertEqual(gate.require(*target, 'qt-selftest', text.replace('\n', '\r\n')), (minimum, 0, 0))
                if target != (5, 10, 'x86'):
                    with self.assertRaisesRegex(ValueError, 'coverage'):
                        gate.require(*target, 'qt-selftest', text.replace(f'{minimum} passed,', f'{minimum - 4} passed,'))

    def test_named_passes_alone_cannot_qualify_old_or_fast_path_reports(self):
        for target in TARGETS:
            text = fixtures.stdout(*target, 'qt-selftest')
            old = '\n'.join(line for line in text.splitlines() if not line.startswith('OBSERVE: '))
            with self.subTest(target=target), self.assertRaisesRegex(ValueError, 'Missing or ambiguous timed-sync'):
                gate.require(*target, 'qt-selftest', old)
            for check in gate.TIMED_SYNC.CHECKS:
                with self.subTest(target=target, check=check), self.assertRaisesRegex(ValueError, 'missing required PASS'):
                    gate.require(*target, 'qt-selftest', text.replace('PASS: ' + check + '\n', 'PASS: fixture/compensating-check\n'))

    def test_each_check_requires_observed_unavailability_delay_and_completion(self):
        target = (6, 21, 'arm64-v8a')
        text = fixtures.stdout(*target, 'qt-selftest')
        for name in gate.TIMED_SYNC.CHECKS:
            wrong = [dict(ready=0), dict(unavailable=0), dict(armed=0),
                     dict(released_before_call=1), dict(joined=0), dict(elapsed_ms=0),
                     dict(elapsed_ms=99 if name.endswith('-wakeup') else 149),
                     dict(elapsed_ms=4500), dict(acquired=1 if name.endswith('-timeout') else 0),
                     dict(verdict='fail'), dict(verdict='retry')]
            for values in wrong:
                changed = text.replace(observation(name), observation(name, **values))
                self.assertNotEqual(changed, text)
                with self.subTest(name=name, values=values), self.assertRaisesRegex(ValueError, 'Unqualified timed-sync waiting'):
                    gate.require(*target, 'qt-selftest', changed)

    def test_bounded_fast_path_retries_need_a_later_qualified_attempt(self):
        target = (5, 10, 'x86')
        text = fixtures.stdout(*target, 'qt-selftest')
        retry = observation(WAKEUP, verdict='retry', elapsed_ms=0)
        replacement = retry + '\n' + observation(WAKEUP, attempt=2)
        qualified = text.replace(observation(WAKEUP), replacement)
        self.assertEqual(gate.TIMED_SYNC.require(qualified)[WAKEUP], 2)
        self.assertEqual(gate.require(*target, 'qt-selftest', qualified), (213, 0, 0))
        three = text.replace(observation(WAKEUP), retry + '\n' +
                             observation(WAKEUP, attempt=2, verdict='retry', released_before_call=1) + '\n' +
                             observation(WAKEUP, attempt=3))
        self.assertEqual(gate.TIMED_SYNC.require(three)[WAKEUP], 3)
        for changed, error in (
            (text.replace(observation(WAKEUP), retry), 'Unqualified'),
            (text.replace(observation(WAKEUP), retry + '\n' + observation(WAKEUP, attempt=3)), 'Noncontiguous'),
            (text.replace(observation(WAKEUP), observation(WAKEUP, verdict='retry') + '\n' + observation(WAKEUP, attempt=2)), 'Invalid timed-sync retry'),
            (three.replace('attempt=3', 'attempt=2'), 'Noncontiguous'),
        ):
            with self.subTest(changed=changed), self.assertRaisesRegex(ValueError, error):
                gate.require(*target, 'qt-selftest', changed)

    def test_duplicate_missing_malformed_or_timeout_retry_evidence_is_rejected(self):
        target = (5, 21, 'x86_64')
        text = fixtures.stdout(*target, 'qt-selftest')
        timeout = 'sync/semaphore-timed-timeout'
        mutations = [text + '\nPASS: ' + WAKEUP,
                     text + '\nOBSERVE: ' + WAKEUP,
                     text.replace(observation(WAKEUP), ''),
                     text.replace(observation(WAKEUP), observation(WAKEUP) + '\n' + observation(WAKEUP)),
                     text.replace('elapsed_ms=250', 'elapsed_ms=unknown', 1),
                     text.replace(observation(timeout), observation(timeout, verdict='retry') + '\n' + observation(timeout, attempt=2)),
                     text.replace(observation(WAKEUP), observation(WAKEUP) + '\n' + observation(WAKEUP, attempt=2, verdict='retry'))]
        for changed in mutations:
            with self.subTest(changed=changed), self.assertRaisesRegex(ValueError, 'timed-sync'):
                gate.require(*target, 'qt-selftest', changed)


if __name__ == '__main__':
    unittest.main()
