# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2026 OpenKaryon
"""Atomic result metadata only; no kernel helper or target binary executes."""
import importlib.util
from pathlib import Path
import unittest

spec = importlib.util.spec_from_file_location('armv5_protocol', Path(__file__).with_name('require-armv5-atomic.py'))
protocol = importlib.util.module_from_spec(spec)
spec.loader.exec_module(protocol)


def fixture():
    return 'ARMV5_ATOMIC: helper_version=3\n' + '\n'.join(
        'ARMV5_ATOMIC: ' + text for text in (
            'barrier-call=PASS', 'word-cas=PASS', 'word-fetch-add=PASS',
            'word-fetch-sub=PASS', 'word-fetch-and=PASS', 'word-exchange=PASS',
            'byte-cas-lanes=PASS', 'byte-exchange-lanes=PASS',
            'word-contention=PASS workers=4 iterations=1024 final=4096',
            'byte-contention=PASS workers=4 iterations=1024 final=a3a2a1a0')) + '\n'


class Armv5Atomic(unittest.TestCase):
    def test_complete_direct_operations_and_contention(self):
        self.assertEqual(protocol.validate(fixture()), 10)
        self.assertEqual(protocol.validate(fixture().replace('helper_version=3', 'helper_version=5')), 10)

    def test_cpp23_totals_do_not_replace_atomic_evidence(self):
        with self.assertRaisesRegex(ValueError, 'helper version'):
            protocol.validate('SUMMARY: 25 passed, 0 failed, 0 skipped\n')

    def test_failed_missing_duplicate_and_wrong_contended_results_refuse(self):
        for changed in (fixture().replace('word-cas=PASS', 'word-cas=FAIL'),
                        fixture().replace('ARMV5_ATOMIC: byte-cas-lanes=PASS\n', ''),
                        fixture() + 'ARMV5_ATOMIC: barrier-call=PASS\n',
                        fixture().replace('final=4096', 'final=4095'),
                        fixture().replace('final=a3a2a1a0', 'final=a3a20000')):
            with self.subTest(changed=changed[-100:]), self.assertRaisesRegex(ValueError, 'observations differ'):
                protocol.validate(changed)

    def test_old_or_ambiguous_kernel_version_refuses(self):
        for changed in (fixture().replace('helper_version=3', 'helper_version=2'),
                        fixture().replace('helper_version=3', 'helper_version=unknown'),
                        fixture() + 'ARMV5_ATOMIC: helper_version=3\n'):
            with self.subTest(changed=changed[:80]), self.assertRaises(ValueError):
                protocol.validate(changed)


if __name__ == '__main__':
    unittest.main()
