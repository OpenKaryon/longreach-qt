# SPDX-License-Identifier: GPL-3.0-or-later
"""Ordinary coverage regressions, including formerly successful degraded GL."""
import importlib.util
import json
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[3]
spec = importlib.util.spec_from_file_location('baselines', ROOT / 'scripts/run/android/android-baselines.py')
gate = importlib.util.module_from_spec(spec)
spec.loader.exec_module(gate)


class CoverageTests(unittest.TestCase):
    def report(self, passed=13, skipped=1):
        checks = ['qgl/widget-context', 'qgl/vertex-buffer', 'qgl/framebuffer-render-readback',
                  'qgl/shader-program', 'qgl/gallery-triangle-render']
        checks += [f'fixture/check-{index}' for index in range(max(0, passed - len(checks)))]
        lines = ['PASS: ' + c for c in checks]
        if skipped:
            lines.append('SKIP: qgl/pixel-buffer - unavailable')
        return '\n'.join(lines) + f'\n---- gl-heavy: {passed} passed, 0 failed, {skipped} skipped ----\n'

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

    def qt4_report(self, target, case, with_skips=True):
        baseline = gate.policy(*target, case)
        passed = baseline['required_pass'][:]
        passed += [f'fixture/check-{index}' for index in range(baseline['min_pass'] - len(passed))]
        skipped = baseline['allowed_skip'] if with_skips else []
        text = '\n'.join(['PASS: ' + name for name in passed] +
                         ['SKIP: ' + name + ' - expected module/platform limitation' for name in skipped])
        return text + f'\n---- fixture: {len(passed)} passed, 0 failed, {len(skipped)} skipped ----\n'

    def test_qt4_shared_named_profiles_accept_known_limits_and_fewer_skips(self):
        for target in ((4, 10, 'x86'), (4, 21, 'x86_64'), (4, 21, 'arm64-v8a')):
            for case in ('selftest', 'widgets', 'multimedia', 'network', 'gl'):
                for with_skips in (True, False):
                    with self.subTest(target=target, case=case, skips=with_skips):
                        result = gate.require(*target, case, self.qt4_report(target, case, with_skips))
                        self.assertEqual(result[1], 0)
                        self.assertEqual(gate.require(*target, case, self.qt4_report(target, case, with_skips).replace('\n', '\r\n')), result)

    def test_qt4_compensating_pass_cannot_hide_a_new_skip(self):
        target = (4, 21, 'x86_64')
        text = self.qt4_report(target, 'selftest')
        text = text.replace('PASS: fixture/check-0', 'SKIP: fixture/check-0 - lost capability')
        text = text.replace('SKIP: core/versionnumber - expected module/platform limitation',
                            'PASS: core/versionnumber')
        with self.assertRaisesRegex(ValueError, 'unexpected SKIP: fixture/check-0'):
            gate.require(*target, 'selftest', text)

    def test_qt4_required_checks_cannot_disappear_behind_another_pass(self):
        for target in ((4, 10, 'x86'), (4, 21, 'x86_64'), (4, 21, 'arm64-v8a')):
            for case in ('selftest', 'widgets', 'multimedia', 'network', 'gl'):
                baseline = gate.policy(*target, case)
                critical = baseline['required_pass'][0]
                text = self.qt4_report(target, case).replace('PASS: ' + critical + '\n', 'PASS: fixture/replacement\n')
                with self.subTest(target=target, case=case), self.assertRaisesRegex(ValueError, 'missing required PASS:'):
                    gate.require(*target, case, text)

    def test_qt4_duplicate_missing_or_falsely_summarized_named_checks_fail(self):
        target = (4, 21, 'x86_64')
        text = self.qt4_report(target, 'network')
        mutations = [text.replace('SKIP: ssl/supported - expected module/platform limitation', ''),
                     text.replace('SKIP: ssl/supported - expected module/platform limitation', 'SKIP: network/websocket-server-construct - duplicate'),
                     text.replace('SKIP: ssl/supported - expected module/platform limitation', 'FAIL: ssl/supported - falsely summarized'),
                     text.replace('PASS: network/udp-bind-construct', 'PASS: network/tcp-server-construct'),
                     text.replace('PASS: network/udp-bind-construct', 'PASS: ssl/supported').replace('\n', '\r\n')]
        for changed in mutations:
            with self.subTest(text=changed), self.assertRaisesRegex(ValueError, 'named outcomes|duplicate named'):
                gate.require(*target, 'network', changed)

    def test_qt4_named_policy_change_is_shared_but_does_not_relax_other_targets(self):
        catalog = json.loads(gate.BASELINES.read_text())
        catalog['named_profiles']['qt4-network']['allowed_skip'].append('fixture/new-common-check')
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / 'baselines.json'
            path.write_text(json.dumps(catalog))
            with patch.object(gate, 'BASELINES', path):
                for api, abi in ((10, 'x86'), (21, 'x86_64'), (21, 'arm64-v8a')):
                    self.assertEqual(gate.policy(4, api, abi, 'network')['max_skip'], 3)
                self.assertNotIn('allowed_skip', gate.policy(5, 21, 'x86_64', 'qt-selftest'))
            catalog['named_profiles']['qt4-network']['allowed_skip'].append('network/tcp-server-construct')
            path.write_text(json.dumps(catalog))
            with patch.object(gate, 'BASELINES', path), self.assertRaisesRegex(ValueError, 'Invalid named'):
                gate.policy(4, 21, 'x86_64', 'network')


if __name__ == '__main__':
    unittest.main()
