# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2026 OpenKaryon
"""TTS report contracts only; no speech engine, compiler or guest executes."""
import importlib.util
from pathlib import Path
import unittest

spec = importlib.util.spec_from_file_location('tts_protocol', Path(__file__).with_name('require-android-tts.py'))
protocol = importlib.util.module_from_spec(spec)
spec.loader.exec_module(protocol)


def fixture():
    # Independent sample of an explicit eight-case diagnostic transcript.
    phases = (
        ('android-ready-and-voices', (), 'engines=android voices=2 state=Ready callback_thread_ok=1'),
        ('short-completion', ('Speaking', 'Ready'), None),
        ('repeated-short-completions', ('Speaking', 'Ready') * 4, 'completed_requests=4'),
        ('stop-active-request', ('Speaking', 'Ready'), 'observation_ms=250 final=Ready callback_thread_ok=1'),
        ('pause-stable-before-resume', ('Speaking', 'Paused'), 'observation_ms=250 final=Paused callback_thread_ok=1'),
        ('resume-to-completion', ('Speaking', 'Ready'), None),
        ('replace-active-request', ('Speaking', 'Ready', 'Speaking', 'Ready'), None),
    )
    lines = []
    for name, states, extra in phases:
        lines += ['OBSERVE: speech/' + name + ' - state=' + state for state in states]
        if extra:
            lines.append('OBSERVE: speech/' + name + ' - ' + extra)
        lines.append('PASS: speech/' + name)
    lines += ['OBSERVE: speech/destroy-active-and-recreate/old - state=Speaking',
              'OBSERVE: speech/destroy-active-and-recreate/new - state=Ready',
              'OBSERVE: speech/destroy-active-and-recreate/new - state=Speaking',
              'OBSERVE: speech/destroy-active-and-recreate/new - state=Ready',
              'PASS: speech/destroy-active-and-recreate',
              '---- tts-behavior: 8 passed, 0 failed, 0 skipped ----']
    return '\n'.join(lines) + '\n'


class SpeechProtocol(unittest.TestCase):
    def test_complete_eight_case_transcript(self):
        protocol.validate(fixture())

    def test_old_smoke_and_compensating_unknown_or_duplicate_pass_do_not_qualify(self):
        for text in ('---- multimedia-lab: 4 passed, 0 failed, 0 skipped ----\n',
                     fixture().replace('PASS: speech/short-completion', 'PASS: speech/platform-backend-and-voices'),
                     fixture() + 'PASS: speech/short-completion\n'):
            with self.subTest(text=text[:80]), self.assertRaises(ValueError):
                protocol.validate(text)

    def test_matching_totals_cannot_hide_missing_or_reordered_engine_callbacks(self):
        for old, new in (('OBSERVE: speech/short-completion - state=Speaking\n', ''),
                         ('OBSERVE: speech/pause-stable-before-resume - state=Paused',
                          'OBSERVE: speech/pause-stable-before-resume - state=Ready'),
                         ('OBSERVE: speech/resume-to-completion - state=Speaking',
                          'OBSERVE: speech/resume-to-completion - state=Ready')):
            with self.subTest(old=old), self.assertRaisesRegex(ValueError, 'state order'):
                protocol.validate(fixture().replace(old, new))

    def test_missing_voices_wrong_owner_thread_and_short_observation_fail(self):
        for old, new in (('voices=2', 'voices=0'), ('callback_thread_ok=1', 'callback_thread_ok=0'),
                         ('observation_ms=250', 'observation_ms=249'), ('completed_requests=4', 'completed_requests=3')):
            with self.subTest(old=old), self.assertRaises(ValueError):
                protocol.validate(fixture().replace(old, new))

    def test_explicit_failure_skip_and_false_summary_fail(self):
        for text in (fixture() + 'FAIL: audio service stopped\n', fixture() + 'SKIP: speech/engine\n',
                     fixture().replace('8 passed', '7 passed')):
            with self.subTest(text=text[-100:]), self.assertRaises(ValueError):
                protocol.validate(text)


if __name__ == '__main__':
    unittest.main()
