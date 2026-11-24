# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2026 OpenKaryon
"""Shared-library ELF/ARM metadata fixtures; no native compilation or execution."""
import importlib.util
from pathlib import Path
import struct
import tempfile
import unittest
import warnings
import zipfile

import android_native_abi_fixtures as fixtures

spec = importlib.util.spec_from_file_location('native_abi', Path(__file__).resolve().parents[2] / 'build/android-api21/native-abi.py')
abi = importlib.util.module_from_spec(spec)
spec.loader.exec_module(abi)


class NativeAbi(unittest.TestCase):
    def test_matching_and_mismatched_library_bytes(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / 'client.so'
            for name in abi.SETTINGS:
                path.write_bytes(fixtures.elf(name))
                result = abi.inspect(path, name)
                self.assertEqual(result['elf_type'], 3)
                other = 'x86' if name != 'x86' else 'arm64-v8a'
                with self.assertRaisesRegex(ValueError, 'does not match'):
                    abi.inspect(path, other)

    def test_shared_library_type_both_versions_and_header_size_are_required(self):
        for name, (elf_class, _) in abi.SETTINGS.items():
            for offset, form, value, error in ((16, '<H', 1, 'ET_DYN'),
                                                (16, '<H', 2, 'ET_DYN'),
                                                (6, '<B', 0, 'does not match'),
                                                (20, '<I', 0, 'ELF version'),
                                                (40 if elf_class == 1 else 52, '<H', 20, 'header size')):
                data = bytearray(fixtures.elf(name))
                struct.pack_into(form, data, offset, value)
                with self.subTest(abi=name, offset=offset, value=value), self.assertRaisesRegex(ValueError, error):
                    abi.inspect_bytes(data, name)
            with self.assertRaisesRegex(ValueError, 'does not match'):
                abi.inspect_bytes(fixtures.elf(name)[:20], name)

    def test_arm_eabi5_and_base_float_calling_convention(self):
        for name in ('armeabi', 'armeabi-v7a'):
            for flags in (0x05000000, 0x05000200):
                abi.inspect_bytes(fixtures.elf(name, flags=flags), name)
            for flags, error in ((0x04000000, 'EABI5'), (0x05000400, 'hard-float'),
                                  (0x05800000, 'Big-endian')):
                with self.subTest(abi=name, flags=flags), self.assertRaisesRegex(ValueError, error):
                    abi.inspect_bytes(fixtures.elf(name, flags=flags), name)
            for vfp, valid in ((0, True), (3, True), (1, False), (2, False)):
                data = fixtures.elf(name, attrs=fixtures.attributes(4 if name == 'armeabi' else 10, vfp_args=vfp))
                if valid:
                    abi.inspect_bytes(data, name)
                else:
                    with self.assertRaisesRegex(ValueError, 'VFP argument'):
                        abi.inspect_bytes(data, name)

    def test_armv5_and_armv7_are_distinguished_without_rejecting_older_compatible_code(self):
        for arch in range(6):
            data = fixtures.elf('armeabi', arch=arch)
            abi.inspect_bytes(data, 'armeabi')
            abi.inspect_bytes(data, 'armeabi-v7a')
        for arch in (6, 7, 8, 9, 10):
            data = fixtures.elf('armeabi-v7a', arch=arch)
            abi.inspect_bytes(data, 'armeabi-v7a')
            with self.assertRaisesRegex(ValueError, 'CPU architecture'):
                abi.inspect_bytes(data, 'armeabi')
        for arch in (11, 12, 13, 14, 18):
            with self.assertRaisesRegex(ValueError, 'CPU architecture'):
                abi.inspect_bytes(fixtures.elf('armeabi-v7a', arch=arch), 'armeabi-v7a')

    def test_profile_and_thumb_requirements_cannot_hide_behind_a_low_cpu_tag(self):
        for extra, error in ((b'\x40\x00', 'Undefined ARM'), (b'\x1d\x01', 'WMMX argument')):
            with self.assertRaisesRegex(ValueError, error):
                abi.inspect_bytes(fixtures.elf('armeabi-v7a', attrs=fixtures.attributes(extra=extra)), 'armeabi-v7a')
        for profile in (0x4d, 0x52):
            with self.assertRaisesRegex(ValueError, 'Non-application'):
                abi.inspect_bytes(fixtures.elf('armeabi-v7a', attrs=fixtures.attributes(profile=profile)), 'armeabi-v7a')
        with self.assertRaisesRegex(ValueError, 'Thumb2'):
            abi.inspect_bytes(fixtures.elf('armeabi', attrs=fixtures.attributes(4, 0, extra=b'\x09\x02')), 'armeabi')

    def test_missing_cpu_file_scope_or_section_metadata_is_not_assumed_compatible(self):
        original = fixtures.elf('armeabi')
        mutations = [fixtures.elf('armeabi', attrs=b'A'),
                     fixtures.elf('armeabi', attrs=b'B' + fixtures.attributes()[1:])]
        no_table = bytearray(original)
        struct.pack_into('<I', no_table, 32, 0)
        mutations.append(no_table)
        no_cpu = fixtures.attributes().replace(b'\x06\x0a', b'\x08\x01')
        mutations.append(fixtures.elf('armeabi-v7a', attrs=no_cpu))
        for changed in mutations:
            with self.subTest(changed=changed), self.assertRaises(ValueError):
                abi.inspect_bytes(changed, 'armeabi-v7a')

    def test_attributes_handle_strings_vendor_blocks_and_extended_section_count(self):
        vendor = b'vendor\0ignored'
        attrs = fixtures.attributes(extra=b'\x20\x00toolchain\0\x41\x06\x04\0\x43conformance\0')
        attrs = b'A' + struct.pack('<I', 4 + len(vendor)) + vendor + attrs[1:]
        data = bytearray(fixtures.elf('armeabi-v7a', attrs=attrs))
        table = struct.unpack_from('<I', data, 32)[0]
        struct.pack_into('<H', data, 48, 0)
        struct.pack_into('<I', data, table + 20, 2)
        self.assertEqual(abi.inspect_bytes(data, 'armeabi-v7a')['arm_cpu_arch'], [10])

    def test_conflicting_or_incomplete_arm_attributes_are_rejected(self):
        attrs = fixtures.attributes()
        variants = [attrs[:-1], attrs[:2], b'A\0\0\0\0',
                    fixtures.attributes(extra=b'\x06\x04'),
                    fixtures.attributes(extra=b'\x05unterminated'),
                    fixtures.attributes(extra=b'\x64\x80'),
                    attrs.replace(b'aeabi\0\x01', b'aeabi\0\x02')]
        for changed in variants:
            with self.subTest(changed=changed), self.assertRaises(ValueError):
                abi.inspect_bytes(fixtures.elf('armeabi-v7a', attrs=changed), 'armeabi-v7a')
        for offset in (32,):
            data = bytearray(fixtures.elf('armeabi'))
            struct.pack_into('<I', data, offset, len(data) + 40)
            with self.assertRaisesRegex(ValueError, 'Truncated ELF'):
                abi.inspect_bytes(data, 'armeabi')

    def test_apks_validate_every_native_member_and_reject_mixed_or_duplicate_entries(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / 'fixture.apk'
            for name in abi.SETTINGS:
                with zipfile.ZipFile(path, 'w') as archive:
                    archive.writestr(f'lib/{name}/libone.so', fixtures.elf(name))
                    archive.writestr(f'lib/{name}/libtwo.so', fixtures.elf(name))
                self.assertEqual(len(abi.inspect_apk(path, name)), 2)
            for kind in ('empty', 'mixed', 'duplicate', 'bad-second-library'):
                with warnings.catch_warnings(), zipfile.ZipFile(path, 'w') as archive:
                    warnings.simplefilter('ignore', UserWarning)
                    if kind != 'empty':
                        archive.writestr('lib/x86/libone.so', fixtures.elf('x86'))
                        member = 'lib/arm64-v8a/libtwo.so' if kind == 'mixed' else 'lib/x86/libone.so' if kind == 'duplicate' else 'lib/x86/libtwo.so'
                        archive.writestr(member, b'not ELF' if kind == 'bad-second-library' else fixtures.elf('x86'))
                with self.subTest(kind=kind), self.assertRaises(ValueError):
                    abi.inspect_apk(path, 'x86')


if __name__ == '__main__':
    unittest.main()
