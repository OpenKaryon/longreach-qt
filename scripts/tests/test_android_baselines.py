# SPDX-License-Identifier: GPL-3.0-or-later
"""Ordinary coverage regressions, including formerly successful degraded GL."""
import importlib.util
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[2]
spec = importlib.util.spec_from_file_location('baselines', ROOT / 'scripts/run/android-baselines.py')
gate = importlib.util.module_from_spec(spec)
spec.loader.exec_module(gate)


class CoverageTests(unittest.TestCase):
    def report(self, passed=13, skipped=1):
        checks = ['qgl/widget-context', 'qgl/vertex-buffer', 'qgl/framebuffer-render-readback',
                  'qgl/shader-program', 'qgl/gallery-triangle-render']
        return '\n'.join('PASS: ' + c for c in checks) + f'\n---- gl-heavy: {passed} passed, 0 failed, {skipped} skipped ----\n'

    def test_qualified_gl(self):
        self.assertEqual(gate.require(4, 10, 'x86', 'gl', self.report()), (13, 0, 1))

    def test_degraded_gl_is_rejected(self):
        for report in (self.report(2, 12), self.report().replace('PASS: qgl/shader-program', 'SKIP: qgl/shader-program')):
            with self.assertRaises(ValueError):
                gate.require(4, 10, 'x86', 'gl', report)

    def test_strict_and_ordinary_limits(self):
        for report in ('---- cpp23: 25 passed, 0 failed, 1 skipped ----',
                       '---- cpp23: 26 passed, 0 failed, 0 skipped ----'):
            with self.assertRaises(ValueError):
                gate.require(6, 21, 'x86', 'strict-cxx23', report)
        with self.assertRaises(ValueError):
            gate.require(5, 10, 'x86', 'qt-selftest', '---- qt-selftest: 213 passed, 0 failed, 63 skipped ----')

    def test_unknown_target_and_ambiguous_report(self):
        with self.assertRaises(KeyError):
            gate.require(4, 21, 'unknown', 'gl', self.report())
        with self.assertRaises(ValueError):
            gate.require(4, 10, 'x86', 'gl', self.report() * 2)


if __name__ == '__main__':
    unittest.main()
