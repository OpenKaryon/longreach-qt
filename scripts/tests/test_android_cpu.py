# SPDX-License-Identifier: GPL-3.0-or-later
"""Ordinary guest-CPU evidence policy fixtures, without ADB or execution probes."""
import json
from pathlib import Path
import tempfile
import unittest

import android_cpu_fixtures as fixtures

cpu = fixtures.cpu


def text(flags, processor=0):
    return f'processor\t: {processor}\nflags\t\t: {" ".join(flags)}\n'


class GuestCpu(unittest.TestCase):
    def test_old_adb_carriage_returns_do_not_split_one_processor_into_many_records(self):
        plain = text(['ssse3', 'sse2']) + text(['ssse3'], 1)
        for ending in ('\n', '\r\n', '\r\r\n', '\n\n'):
            with self.subTest(ending=ending):
                data = plain.replace('\n', ending).encode()
                result = cpu.inspect(data, 'x86')
                self.assertEqual(result['processor_ids'], [0, 1])
                self.assertEqual(result['common_flags'], ['ssse3'])

    def test_selected_x86_compiler_additions_need_no_sse4_or_avx_on_i386(self):
        result = cpu.inspect(text(['ssse3']).encode(), 'x86')
        self.assertEqual(result['required_flags'], ['ssse3'])
        self.assertEqual(result['processor_ids'], [0])
        self.assertNotIn('avx', result['common_flags'])
        flags = ['cx16', 'lahf_lm', 'pni', 'popcnt', 'ssse3', 'sse4_1', 'sse4_2']
        self.assertEqual(set(cpu.inspect(text(flags).encode(), 'x86_64')['required_flags']), set(flags))
        for flag in flags:
            with self.subTest(flag=flag), self.assertRaisesRegex(ValueError, 'lacks required evidence flags'):
                cpu.inspect(text([item for item in flags if item != flag]).encode(), 'x86_64')

    def test_every_processor_must_supply_flags_instead_of_the_union(self):
        data = (text(['ssse3', 'sse2']) + '\n' + text(['ssse3'], 2)).encode()
        result = cpu.inspect(data, 'x86')
        self.assertEqual(result['processor_ids'], [0, 2])
        self.assertEqual(result['common_flags'], ['ssse3'])
        with self.assertRaisesRegex(ValueError, 'CPU 2 lacks'):
            cpu.inspect(data.replace(b'flags\t\t: ssse3\n', b'flags\t\t: sse2\n'), 'x86')

    def test_missing_duplicate_or_nonprocessor_flags_cannot_qualify(self):
        samples = [b'', b'flags: ssse3\n', b'model name: ssse3\n',
                   b'processor: 0\nflags: ssse3fake\n', b'processor: 0\n',
                   b'processor: name\nflags: ssse3\n', b'processor: 0\nflags: sse3\n',
                   b'processor: 0\nflags: ssse3\nflags: ssse3\n',
                   (text(['ssse3']) + '\n' + text(['ssse3'])).encode(),
                   (text(['ssse3']) + '\nprocessor: 1\n').encode()]
        for data in samples:
            with self.subTest(data=data), self.assertRaises(ValueError):
                cpu.inspect(data, 'x86')

    def test_windows_line_endings_and_arm_policy_scope_are_explicit(self):
        result = cpu.inspect(('\ufeff' + text(['SSSE3']).replace('\n', '\r\n')).encode('utf-8'), 'x86')
        self.assertEqual(result['common_flags'], ['ssse3'])
        for abi in ('armeabi', 'armeabi-v7a', 'arm64-v8a'):
            result = cpu.inspect(b'Processor: retained ARM evidence\n', abi)
            self.assertFalse(result['checked_x86_flags'])
            self.assertEqual(result['required_flags'], [])
        with self.assertRaises(ValueError):
            cpu.inspect(b'nonempty', 'other')

    def test_report_and_both_case_hashes_bind_exact_cpu_evidence(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory)
            bindings = fixtures.capture(path, 'x86_64')
            result = cpu.validate(path, 'x86_64', bindings)
            self.assertEqual(result['guest_cpuinfo_sha256'], bindings['guest_cpuinfo_sha256'])
            report = path / 'guest-cpu-baseline.json'
            original = report.read_bytes()
            report.write_bytes(original + b'\n')
            with self.assertRaisesRegex(ValueError, 'different guest CPU'):
                cpu.validate(path, 'x86_64', bindings)
            report.write_bytes(original)
            for field in cpu.FIELDS:
                with self.subTest(field=field), self.assertRaisesRegex(ValueError, 'different guest CPU'):
                    cpu.validate(path, 'x86_64', {**bindings, field: '0' * 64})
            data = json.loads(report.read_text())
            data['required_flags'] = ['ssse3']
            report.write_text(json.dumps(data))
            with self.assertRaisesRegex(ValueError, 'current evidence/policy'):
                cpu.validate(path, 'x86_64')

    def test_changed_or_missing_source_cannot_reuse_a_prior_report(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory)
            fixtures.capture(path, 'x86')
            source = path / 'guest-cpuinfo.txt'
            source.write_text(text(['ssse3', 'extra']))
            with self.assertRaisesRegex(ValueError, 'current evidence/policy'):
                cpu.validate(path, 'x86')
            source.write_text(text(['sse2']))
            with self.assertRaisesRegex(ValueError, 'lacks required evidence flags'):
                cpu.validate(path, 'x86')
            source.unlink()
            with self.assertRaises(FileNotFoundError):
                cpu.validate(path, 'x86')


if __name__ == '__main__':
    unittest.main()
