# SPDX-License-Identifier: GPL-3.0-or-later
"""Ordinary output-gate fixtures; no Qt, sound backend or guest executes."""
import importlib.util
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]
CLI = ROOT / 'scripts/tests/require-android-sound-cache.py'
spec = importlib.util.spec_from_file_location('sound_cache_output', CLI)
gate = importlib.util.module_from_spec(spec)
spec.loader.exec_module(gate)

# Independent protocol expectations: do not obtain the fixture from gate.EXPECTED.
PHASES = (
    'SOUND_CACHE: protocol=1',
    'SOUND_CACHE: wav=pcm-s16le-8000-mono',
    'SOUND_CACHE: ready=1',
    'SOUND_CACHE: playing=1',
    'SOUND_CACHE: destroyed=1',
    'SOUND_CACHE: return=0',
)


class SoundCacheOutput(unittest.TestCase):
    def test_current_phases_accept_unrelated_qt_diagnostics_and_crlf(self):
        gate.validate('Qt: fixture note\r\n' + '\r\n'.join(PHASES) + '\r\n')

    def test_every_missing_duplicate_and_wrong_phase_is_refused(self):
        for index in range(len(PHASES)):
            wrong = list(PHASES)
            wrong[index] += '-wrong'
            for lines in (PHASES[:index] + PHASES[index + 1:],
                          PHASES[:index] + (PHASES[index],) + PHASES[index:], wrong):
                with self.subTest(index=index, lines=lines), self.assertRaisesRegex(ValueError, 'pre-exit phases'):
                    gate.validate('\n'.join(lines))

    def test_reordered_unknown_and_explicit_failure_records_are_refused(self):
        for lines in (tuple(reversed(PHASES)), PHASES + ('SOUND_CACHE: exit=0',),
                      PHASES + ('FAIL: sample did not become Ready',)):
            with self.subTest(lines=lines), self.assertRaises(ValueError):
                gate.validate('\n'.join(lines))

    def test_old_selftest_output_and_native_zero_are_not_this_diagnostic(self):
        for text in ('0', '---- qt-selftest: 106 passed, 0 failed, 4 skipped ----',
                     'PASS: multimedia/soundeffect-construct\nSOUND_CACHE: return=0'):
            with self.subTest(text=text), self.assertRaisesRegex(ValueError, 'pre-exit phases'):
                gate.validate(text)

    def test_actual_cli_requires_current_phases_and_existing_report(self):
        with tempfile.TemporaryDirectory() as temporary:
            path = Path(temporary) / 'stdout with spaces.txt'
            path.write_text('\n'.join(PHASES), encoding='utf-8-sig')
            result = subprocess.run([sys.executable, str(CLI), str(path)], capture_output=True, text=True, timeout=10)
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertIn('process exit needs separate proof', result.stdout)
            path.write_text('0', encoding='utf-8')
            result = subprocess.run([sys.executable, str(CLI), str(path)], capture_output=True, text=True, timeout=10)
            self.assertNotEqual(result.returncode, 0)
            self.assertIn('pre-exit phases', result.stderr)
            path.unlink()
            result = subprocess.run([sys.executable, str(CLI), str(path)], capture_output=True, text=True, timeout=10)
            self.assertNotEqual(result.returncode, 0)


if __name__ == '__main__':
    unittest.main()
