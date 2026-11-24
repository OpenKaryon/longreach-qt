# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2026 OpenKaryon
"""Synthetic ELF metadata; tests never execute the library contents."""
import contextlib
import importlib.util
import io
import json
from pathlib import Path
import struct
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]
spec = importlib.util.spec_from_file_location('android_elf', ROOT / 'scripts/build/qt6-android/validate-api21-elf.py')
elf = importlib.util.module_from_spec(spec)
spec.loader.exec_module(elf)


def library(abi='x86', symbols=(), needed='libc.so', tls=False, packed=False, sysv=True):
    bits, machine = {'x86': (32, 3), 'armeabi-v7a': (32, 40),
                     'x86_64': (64, 62), 'arm64-v8a': (64, 183)}[abi]
    word, symbol_size = bits // 8, 16 if bits == 32 else 24
    data = bytearray(4096)
    ident = b'\x7fELF' + bytes((1 if bits == 32 else 2, 1, 1)) + b'\0' * 9
    header_size, segment_size = (52, 32) if bits == 32 else (64, 56)
    header_format = '<16sHHIIIIIHHHHHH' if bits == 32 else '<16sHHIQQQIHHHHHH'
    struct.pack_into(header_format, data, 0, ident, 3, machine, 1, 0, header_size, 0, 0,
                     header_size, segment_size, 3 if tls else 2, 0, 0, 0)
    dynamic_offset, hash_offset, symbol_offset, string_offset = 0x200, 0x300, 0x380, 0x500
    address = 0x1000
    strings = bytearray(b'\0')
    def string(value):
        result = len(strings)
        strings.extend(value.encode() + b'\0')
        return result
    needed_index = string(needed)
    for index, (name, defined, binding) in enumerate(symbols, 1):
        name_index = string(name)
        if bits == 32:
            struct.pack_into('<IIIBBH', data, symbol_offset + index * symbol_size,
                             name_index, 0, 0, binding << 4 | 2, 0, int(defined))
        else:
            struct.pack_into('<IBBHQQ', data, symbol_offset + index * symbol_size,
                             name_index, binding << 4 | 2, 0, int(defined), 0, 0)
    data[string_offset:string_offset + len(strings)] = strings
    struct.pack_into('<II', data, hash_offset, 1, len(symbols) + 1)
    tags = [(5, address + string_offset), (6, address + symbol_offset),
            (11, symbol_size), (1, needed_index)]
    if sysv:
        tags.append((4, address + hash_offset))
    if packed:
        tags.append((35, 8))
    tags.append((0, 0))
    for index, (tag, value) in enumerate(tags):
        struct.pack_into('<II' if bits == 32 else '<QQ', data, dynamic_offset + index * 2 * word, tag, value)
    segments = [(1, 0, address, len(data)), (2, dynamic_offset, address + dynamic_offset, len(tags) * 2 * word)]
    if tls:
        segments.append((7, 0x800, address + 0x800, 16))
    for index, (kind, offset, virtual, size) in enumerate(segments):
        if bits == 32:
            struct.pack_into('<IIIIIIII', data, header_size + index * segment_size,
                             kind, offset, virtual, virtual, size, size, 5, 0x1000)
        else:
            struct.pack_into('<IIQQQQQQ', data, header_size + index * segment_size,
                             kind, 5, offset, virtual, virtual, size, size, 0x1000)
    return data


def relocated_library(abi='x86', operations=(8,), plt=(), extra_tags=(), writable=True):
    """Tiny in-memory tables, not compiled objects or installed SDK input."""
    data = library(abi)
    bits = 32 if abi in ('x86', 'armeabi-v7a') else 64
    word, address = bits // 8, 0x1000
    header_size = 52 if bits == 32 else 64
    tags = []
    for position in range(0x200, 0x300, word * 2):
        tag, value = struct.unpack_from('<II' if bits == 32 else '<QQ', data, position)
        if not tag:
            break
        tags.append((tag, value))
    for name, values, start in (('dynamic', operations, 0x700), ('plt', plt, 0x900)):
        if not values:
            continue
        for index, value in enumerate(values):
            kind, symbol, target = (value, 0, 0x1b00) if isinstance(value, int) else value
            info = symbol << (8 if bits == 32 else 32) | kind
            struct.pack_into('<II' if bits == 32 else '<QQq', data,
                             start + index * (8 if bits == 32 else 24),
                             *((target, info) if bits == 32 else (target, info, 0)))
        size = len(values) * (8 if bits == 32 else 24)
        if name == 'dynamic':
            tags.extend(((17, address + start), (18, size), (19, 8)) if bits == 32 else
                        ((7, address + start), (8, size), (9, 24)))
        else:
            tags.extend(((23, address + start), (2, size), (20, 17 if bits == 32 else 7)))
    tags.extend(extra_tags)
    tags.append((0, 0))
    for index, (tag, value) in enumerate(tags):
        struct.pack_into('<II' if bits == 32 else '<QQ', data, 0xc00 + index * word * 2, tag, value)
    # Keep one file-backed LOAD plus BSS, with a separate PT_DYNAMIC header.
    flags = 6 if writable else 5
    if bits == 32:
        struct.pack_into('<IIIIIIII', data, header_size, 1, 0, address, address, len(data), len(data) + 0x100, flags, 0x1000)
        struct.pack_into('<IIIIIIII', data, header_size + 32, 2, 0xc00, address + 0xc00,
                         address + 0xc00, len(tags) * word * 2, len(tags) * word * 2, 6, 4)
    else:
        struct.pack_into('<IIQQQQQQ', data, header_size, 1, flags, 0, address, address, len(data), len(data) + 0x100, 0x1000)
        struct.pack_into('<IIQQQQQQ', data, header_size + 56, 2, 6, 0xc00, address + 0xc00,
                         address + 0xc00, len(tags) * word * 2, len(tags) * word * 2, 8)
    return data


class AndroidElf(unittest.TestCase):

    def inspect_bytes(self, data, abi='x86', api=10):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / 'library.so'
            path.write_bytes(data)
            return elf.inspect(path, abi, api)

    def test_dynamic_and_plt_relocation_types_for_supported_abi_api_pairs(self):
        # Explicit baseline values: the API10 i386 loader has no NONE branch.
        profiles = [('x86', 10, [1, 2, 6, 7, 8]),
                    ('x86', 21, [0, 1, 2, 6, 7, 8]),
                    ('armeabi-v7a', 10, [0, 2, 3, 21, 22, 23]),
                    ('armeabi-v7a', 21, [0, 2, 3, 21, 22, 23]),
                    ('x86_64', 21, [0, 1, 2, 6, 7, 8, 10]),
                    ('arm64-v8a', 21, [0, 257, 258, 259, 260, 261, 262, 1025, 1026, 1027])]
        for abi, api, kinds in profiles:
            with self.subTest(abi=abi, api=api):
                metadata = self.inspect_bytes(relocated_library(abi, kinds, kinds[-2:]), abi, api)['relocations']
                self.assertEqual(metadata['types'], kinds)
                self.assertEqual(metadata['table_entries'], {'dynamic': len(kinds), 'plt': 2})
                self.assertEqual(metadata['format'], 'REL' if abi in ('x86', 'armeabi-v7a') else 'RELA')
                self.assertFalse(metadata['textrel_markers'])
                self.assertTrue(metadata['targets_writable'])

    def test_unsupported_ifunc_tls_copy_and_unknown_operations_are_refused(self):
        for abi, api, kinds in [('x86', 10, (0, 5, 14, 42, 255)),
                                ('armeabi-v7a', 10, (20, 17, 160, 255)),
                                ('x86_64', 21, (5, 16, 37, 255)),
                                ('arm64-v8a', 21, (1024, 1028, 1032, 65535))]:
            for kind in kinds:
                for plt in (False, True):
                    with self.subTest(abi=abi, kind=kind, plt=plt):
                        data = relocated_library(abi, () if plt else (kind,), (kind,) if plt else ())
                        with self.assertRaisesRegex(RuntimeError, 'Unsupported.*relocation type'):
                            self.inspect_bytes(data, abi, api)

    def test_packed_table_address_size_and_entry_tags_are_all_excluded(self):
        for tag in (35, 36, 37, 0x6000000f, 0x60000010, 0x60000011, 0x60000012,
                    0x6fffe000, 0x6fffe001, 0x6fffe003):
            with self.subTest(tag=tag):
                with self.assertRaisesRegex(RuntimeError, 'Packed relocations'):
                    self.inspect_bytes(relocated_library(operations=(), extra_tags=((tag, 8),)))

    def test_textrel_markers_are_refused_by_stricter_sdk_policy(self):
        for abi in ('x86', 'armeabi-v7a', 'x86_64', 'arm64-v8a'):
            for tag in ((22, 0), (30, 4)):
                with self.subTest(abi=abi, tag=tag):
                    data = relocated_library(abi, (), extra_tags=(tag,))
                    with self.assertRaisesRegex(RuntimeError, 'TEXTREL markers'):
                        self.inspect_bytes(data, abi, 21)
            self.inspect_bytes(relocated_library(abi, (), extra_tags=((30, 2),)), abi, 21)

    def test_writes_require_mapped_writable_memory_but_bss_is_valid(self):
        for abi, kind in (('x86', 8), ('arm64-v8a', 1027)):
            for target, writable in ((0x1b00, False), (0x4000, True), (0x20ff, True)):
                with self.subTest(abi=abi, target=target, writable=writable):
                    data = relocated_library(abi, ((kind, 0, target),), writable=writable)
                    with self.assertRaisesRegex(RuntimeError, 'not writable mapped memory'):
                        self.inspect_bytes(data, abi, 21)
            self.inspect_bytes(relocated_library(abi, ((kind, 0, 0x2000),)), abi, 21)
            # NONE performs no write; its target need not be mapped.
            self.inspect_bytes(relocated_library(abi, ((0, 0, 0),), writable=False), abi, 21)

    def test_wrong_table_format_and_entry_size_are_refused(self):
        for abi, api, extra, reason in [
            ('x86', 10, ((7, 0x1700), (8, 12), (9, 12)), 'table format'),
            ('x86_64', 21, ((17, 0x1700), (18, 16), (19, 16)), 'table format'),
            ('x86', 21, ((19, 12),), 'entry size'),
            ('arm64-v8a', 21, ((9, 16),), 'entry size'),
            ('x86', 10, ((23, 0x1900), (2, 8), (20, 7)), 'PLT.*format'),
            ('x86_64', 21, ((23, 0x1900), (2, 24), (20, 17)), 'PLT.*format'),
            ('x86', 10, ((17, 0x1700),), 'Incomplete'),
            ('x86', 10, ((17, 0x1700), (18, 9)), 'table size'),
            ('x86_64', 21, ((7, 0x1ff8), (8, 24)), 'Unmapped'),
            ('x86', 10, ((17, 0x1700), (17, 0x1700), (18, 8)), 'Duplicate')]:
            with self.subTest(abi=abi, reason=reason):
                with self.assertRaisesRegex(RuntimeError, reason):
                    self.inspect_bytes(relocated_library(abi, (), extra_tags=extra), abi, api)

    def test_relative_relocation_must_have_zero_symbol(self):
        for abi, kind in (('x86', 8), ('armeabi-v7a', 23), ('x86_64', 8), ('arm64-v8a', 1027)):
            with self.subTest(abi=abi):
                with self.assertRaisesRegex(RuntimeError, 'RELATIVE.*symbol'):
                    self.inspect_bytes(relocated_library(abi, ((kind, 1, 0x1b00),)), abi, 21)

    def test_ifunc_symbol_is_refused_even_without_irelative(self):
        for abi in ('x86', 'arm64-v8a'):
            with self.subTest(abi=abi):
                data = library(abi, [('resolver', True, 1)])
                data[0x380 + (16 + 12 if abi == 'x86' else 24 + 4)] = 0x1a
                with self.assertRaisesRegex(RuntimeError, 'GNU IFUNC'):
                    self.inspect_bytes(data, abi, 21)

    def test_report_does_not_claim_runtime_or_symbol_resolution_and_invalidates_old_pass(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            core, runtime = root / 'sdk/lib/libQt6Core.so', root / 'runtime.so'
            core.parent.mkdir(parents=True)
            for path in (core, runtime):
                path.write_bytes(relocated_library())
            report = root / 'report.json'
            argv = [str(root / 'sdk'), '--abi', 'x86', '--api', '10', '--runtime', str(runtime), '--report', str(report)]
            with contextlib.redirect_stdout(io.StringIO()) as output:
                metadata = elf.main(argv)
            self.assertEqual(metadata['validation_scope'], 'selected-elf-metadata-v1')
            self.assertIs(metadata['runtime_loading_verified'], False)
            self.assertIs(metadata['symbol_resolution_verified'], False)
            self.assertIn('selected ELF metadata', output.getvalue())
            self.assertNotIn('loader compatibility', output.getvalue())
            core.write_bytes(relocated_library(operations=(42,)))
            with self.assertRaisesRegex(RuntimeError, 'relocation type'):
                elf.main(argv)
            self.assertFalse(report.exists())

    def test_supported_loader_formats_for_all_target_abis(self):
        for abi in ('x86', 'armeabi-v7a', 'x86_64', 'arm64-v8a'):
            with self.subTest(abi=abi), tempfile.TemporaryDirectory() as directory:
                path = Path(directory) / 'library.so'
                path.write_bytes(library(abi, [('pthread_mutex_lock', False, 1)]))
                result = elf.inspect(path, abi, 10 if abi in ('x86', 'armeabi-v7a') else 21)
                self.assertTrue(result['sysv_hash'])
                self.assertEqual(result['needed'], ['libc.so'])
                self.assertEqual(result['legacy_x86_futex_import_checked'], abi == 'x86')

    def test_api10_x86_rejects_strong_and_weak_undefined_futex(self):
        for binding in (1, 2):
            with self.subTest(binding=binding), tempfile.TemporaryDirectory() as directory:
                path = Path(directory) / 'libQt5Core.so'
                path.write_bytes(library(symbols=[('futex', False, binding)]))
                with self.assertRaisesRegex(RuntimeError, 'must not import libc futex.*API21'):
                    elf.inspect(path, 'x86', 10)
                # This check concerns a dynamic import, not another symbol with
                # the same name supplied inside this library.
                path.write_bytes(library(symbols=[('futex', True, binding)]))
                self.assertTrue(elf.inspect(path, 'x86', 10)['legacy_x86_futex_import_checked'])

    def test_existing_loader_and_runtime_guards_remain_active(self):
        mutations = [(dict(tls=True), 'Native ELF TLS'),
                     (dict(packed=True), 'Packed relocations'),
                     (dict(sysv=False), 'SysV DT_HASH'),
                     (dict(needed='libc.so.6'), 'GNU/host runtime'),
                     (dict(symbols=[('_ZNSt6__ndk16vectorE', False, 1)]), 'Stock NDK libc')]
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / 'library.so'
            for arguments, reason in mutations:
                with self.subTest(reason=reason):
                    path.write_bytes(library(**arguments))
                    with self.assertRaisesRegex(RuntimeError, reason):
                        elf.inspect(path, 'x86', 10)

    def test_library_type_and_elf_versions_are_required(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / 'library.so'
            for offset, value in ((6, 0), (16, 2), (20, 0), (18, 40)):
                with self.subTest(offset=offset):
                    data = library()
                    data[offset] = value
                    path.write_bytes(data)
                    with self.assertRaises(RuntimeError):
                        elf.inspect(path, 'x86', 10)

    def test_prefix_plugins_and_runtime_use_the_gate_and_failed_report_is_removed(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            prefix = root / 'sdk'
            core = prefix / 'lib/libQt5Core.so'
            plugin = prefix / 'plugins/platforms/libexample.so'
            runtime = root / 'runtime/libc++_shared.so'
            for path in (core, plugin, runtime):
                path.parent.mkdir(parents=True, exist_ok=True)
                path.write_bytes(library())
            report = root / 'report.json'
            argv = [str(prefix), '--abi', 'x86', '--api', '10', '--runtime', str(runtime), '--report', str(report)]
            with contextlib.redirect_stdout(io.StringIO()):
                result = elf.main(argv)
            self.assertEqual(json.loads(report.read_text()), result)
            self.assertEqual(len(result['libraries']), 3)
            for changed in (core, plugin, runtime):
                with self.subTest(changed=changed.name):
                    report.write_text('previous PASS')
                    changed.write_bytes(library(symbols=[('futex', False, 1)]))
                    with self.assertRaisesRegex(RuntimeError, 'must not import libc futex'):
                        elf.main(argv)
                    self.assertFalse(report.exists())
                    changed.write_bytes(library())


if __name__ == '__main__':
    unittest.main()
