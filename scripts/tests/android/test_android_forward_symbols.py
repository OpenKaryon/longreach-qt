# SPDX-License-Identifier: GPL-3.0-or-later
"""Ordinary synthetic ELF/archive fixtures; no target code or compiler runs."""
import contextlib
import copy
import importlib.util
import io
import json
from pathlib import Path
import struct
import tempfile
import unittest
from unittest.mock import patch
import zipfile

from test_android_elf import library
import android_sdk_report_fixtures as report_fixtures

ROOT = Path(__file__).resolve().parents[3]
SPEC = importlib.util.spec_from_file_location('forward_symbols', ROOT / 'scripts/build/qt6-android/check-api10-api21-symbols.py')
check = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(check)


def binary(abi='x86', symbols=(), needed='libc.so', hidden=(), versions=None):
    data = library(abi=abi, symbols=symbols, needed=needed)
    count = len(symbols) + 1
    struct.pack_into('<I', data, 32, 0xd00)
    struct.pack_into('<HH', data, 46, 40, 4 if versions is not None else 3)
    # Three regular ELF sections: null, dynstr, dynsym. Optional GNU versym.
    struct.pack_into('<10I', data, 0xd00 + 40, 0, 3, 2, 0x1500, 0x500, 0x200, 0, 0, 1, 0)
    struct.pack_into('<10I', data, 0xd00 + 80, 0, 11, 2, 0x1380, 0x380, count * 16, 1, 1, 4, 16)
    for index in hidden:
        data[0x380 + index * 16 + 13] = 2
    if versions is not None:
        assert len(versions) == count
        for index, version in enumerate(versions):
            struct.pack_into('<H', data, 0xe00 + index * 2, version)
        struct.pack_into('<10I', data, 0xd00 + 120, 0, 0x6fffffff, 2, 0x1e00, 0xe00, count * 2, 2, 0, 2, 2)
    return data


class ForwardSymbols(unittest.TestCase):
    def fixture(self, root, abi='x86'):
        prefix = root / 'sdk'
        runtime = root / 'libc++_shared.so'
        for directory in ('lib', 'plugins', 'qml'):
            (prefix / directory).mkdir(parents=True)
        (prefix / 'lib/libQt5Core.so').write_bytes(binary(abi, [('puts', False, 1), ('shared_atomic', False, 1)], 'libdependency.so'))
        (prefix / 'plugins/libdependency.so').write_bytes(binary(abi, [('dependency', True, 1)], 'libc++_shared.so'))
        runtime.write_bytes(binary(abi, [('shared_atomic', True, 1), ('malloc', False, 1)]))
        archive = root / check.ARCHIVE
        self.platform(archive, abi)
        lock = root / 'lock.json'
        self.pin(lock, archive)
        return prefix, runtime, abi, archive, lock

    def platform(self, archive, abi, libc=None):
        prefix = 'android-ndk-r27/toolchains/llvm/prebuilt/linux-x86_64/sysroot/usr/lib/' + check.TRIPLES[abi] + '/21/'
        with zipfile.ZipFile(archive, 'w') as package:
            for name in sorted(check.REQUIRED_PLATFORM):
                value = libc if libc is not None and name == 'libc.so' else binary(abi, [('puts', True, 1), ('malloc', True, 1)])
                package.writestr(prefix + name, value)

    def pin(self, lock, archive):
        lock.write_text(json.dumps({'sources': [{'file': check.ARCHIVE, 'sha256': check.digest(archive)}]}))

    def test_both_abis_check_all_sdk_roots_and_dependency_closure(self):
        for abi in check.TRIPLES:
            with self.subTest(abi=abi), tempfile.TemporaryDirectory() as directory:
                args = self.fixture(Path(directory), abi)
                (args[0] / 'qml/libqml.so').write_bytes(binary(abi, [('puts', False, 2)]))
                report = check.validate(*args)
                self.assertEqual(len(report['libraries']), 4)
                self.assertFalse(report['symbol_resolution_verified'])
                self.assertFalse(report['runtime_loading_verified'])
                self.assertFalse(report['unresolved_weak_imports_ignored'])
                core = next(item for item in report['libraries'] if item['path'] == 'lib/libQt5Core.so')
                self.assertEqual(core['needed_closure'], ['libc++_shared.so', 'libc.so', 'libdependency.so'])
                self.assertEqual(core['checked_import_names'], ['puts', 'shared_atomic'])

    def test_removed_strong_or_weak_import_is_not_excused_by_unrelated_plugin(self):
        for abi in check.TRIPLES:
            for binding in (1, 2):
                for location in ('core', 'dependency', 'runtime', 'qml'):
                    with self.subTest(abi=abi, binding=binding, location=location), tempfile.TemporaryDirectory() as directory:
                        args = self.fixture(Path(directory), abi)
                        prefix, runtime = args[:2]
                        targets = {'core': (prefix / 'lib/libQt5Core.so', 'libdependency.so'),
                                   'dependency': (prefix / 'plugins/libdependency.so', 'libc++_shared.so'),
                                   'runtime': (runtime, 'libc.so'), 'qml': (prefix / 'qml/libqml.so', 'libc.so')}
                        path, needed = targets[location]
                        entries = [('removed_on_api21', False, binding)]
                        if location == 'runtime':
                            entries.append(('shared_atomic', True, 1))
                        path.write_bytes(binary(abi, entries, needed))
                        (prefix / 'plugins/libunrelated.so').write_bytes(binary(abi, [('removed_on_api21', True, 1)]))
                        with self.assertRaisesRegex(ValueError, 'API21 symbol names unavailable.*removed_on_api21'):
                            check.validate(*args)

    def guarded_fixture(self, root, abi, name):
        args = self.fixture(root, abi)
        policy = copy.deepcopy(check.GUARDED_WEAK_IMPORTS[name])
        source = root / 'audited-source.c'
        source.write_text('ordinary fixture: ' + policy['guard'] + '\n')
        policy['source_sha256'] = check.digest(source)
        target = args[0] / f'lib/libQt5{policy["module"]}_{abi}.so'
        target.write_bytes(binary(abi, [(name, False, 2)]))
        return args, target, source, policy

    def test_named_optional_weak_imports_require_source_and_report_the_exemption(self):
        for abi in check.TRIPLES:
            for name in check.GUARDED_WEAK_IMPORTS:
                with self.subTest(abi=abi, name=name), tempfile.TemporaryDirectory() as directory:
                    args, target, source, policy = self.guarded_fixture(Path(directory), abi, name)
                    with patch.dict(check.GUARDED_WEAK_IMPORTS, {name: policy}):
                        report = check.validate(*args, guard_sources={policy['source_key']: source})
                    entry = next(item for item in report['libraries'] if item['path'] == target.relative_to(args[0]).as_posix())
                    self.assertEqual([item['name'] for item in entry['guarded_optional_weak_imports']], [name])
                    self.assertEqual(entry['guarded_optional_weak_imports'][0]['source_sha256'], check.digest(source))
                    self.assertTrue(report['unresolved_weak_imports_ignored'])
                    self.assertFalse(report['blanket_weak_import_exemption'])
                    self.assertFalse(report['runtime_loading_verified'])

    def test_optional_name_cannot_excuse_strong_duplicate_wrong_library_or_changed_guard(self):
        for name in check.GUARDED_WEAK_IMPORTS:
            for fault in ('strong', 'duplicate-strong', 'wrong-library', 'wrong-abi-filename', 'changed-source', 'missing-source'):
                with self.subTest(name=name, fault=fault), tempfile.TemporaryDirectory() as directory:
                    args, target, source, policy = self.guarded_fixture(Path(directory), 'x86', name)
                    if fault == 'strong':
                        target.write_bytes(binary(symbols=[(name, False, 1)]))
                    elif fault == 'duplicate-strong':
                        target.write_bytes(binary(symbols=[(name, False, 2), (name, False, 1)]))
                    elif fault == 'wrong-library':
                        target.rename(args[0] / 'plugins' / target.name)
                    elif fault == 'wrong-abi-filename':
                        target.rename(target.with_name(target.name.replace('_x86', '_armeabi-v7a')))
                    elif fault == 'changed-source':
                        source.write_text('changed guard')
                    sources = {} if fault == 'missing-source' else {policy['source_key']: source}
                    message = 'guard source' if fault in ('changed-source', 'missing-source') else 'symbol names unavailable'
                    with patch.dict(check.GUARDED_WEAK_IMPORTS, {name: policy}):
                        with self.assertRaisesRegex(ValueError, message):
                            check.validate(*args, guard_sources=sources)

    def test_cli_changed_optional_guard_invalidates_previous_report(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            name = '__pthread_cond_timedwait_relative'
            args, target, source, policy = self.guarded_fixture(root, 'x86', name)
            prefix, runtime, abi, archive, lock = args
            report = root / 'report.json'
            argv = [str(prefix), '--runtime', str(runtime), '--abi', abi, '--archive', str(archive),
                    '--lock', str(lock), '--report', str(report), '--qt-wait-source', str(source)]
            with patch.dict(check.GUARDED_WEAK_IMPORTS, {name: policy}):
                with contextlib.redirect_stdout(io.StringIO()):
                    check.main(argv)
                self.assertTrue(report.is_file())
                source.write_text('guard removed')
                with self.assertRaisesRegex(ValueError, 'guard source'):
                    check.main(argv)
            self.assertFalse(report.exists())
            self.assertFalse(report.with_suffix('.json.tmp').exists())

    def test_missing_dependency_and_conflicting_filename_fail(self):
        for fault, message in (('missing', 'Missing API21 dependency'), ('ambiguous', 'Ambiguous SDK dependency filename')):
            with self.subTest(fault=fault), tempfile.TemporaryDirectory() as directory:
                args = self.fixture(Path(directory))
                if fault == 'missing':
                    (args[0] / 'plugins/libdependency.so').unlink()
                else:
                    (args[0] / 'qml/libdependency.so').write_bytes(binary(symbols=[('other', True, 1)]))
                with self.assertRaisesRegex(ValueError, message):
                    check.validate(*args)

    def test_default_versions_export_and_hidden_or_nondefault_exports_do_not(self):
        for fault in ('default', 'hidden', 'nondefault'):
            with self.subTest(fault=fault), tempfile.TemporaryDirectory() as directory:
                root = Path(directory)
                args = self.fixture(root)
                value = binary(symbols=[('puts', True, 1), ('malloc', True, 1)],
                               hidden=(1,) if fault == 'hidden' else (),
                               versions=[0, 0x8002 if fault == 'nondefault' else 2, 2])
                self.platform(args[3], args[2], value)
                self.pin(args[4], args[3])
                # Only libc is in the dependency closure. Identically named
                # exports in libm/libdl/liblog cannot compensate for its loss.
                if fault == 'default':
                    self.assertEqual(len(check.validate(*args)['libraries']), 3)
                else:
                    with self.assertRaisesRegex(ValueError, 'symbol names unavailable.*puts'):
                        check.validate(*args)

    def test_archive_hash_missing_platform_and_wrong_abi_fail(self):
        for fault, message in (('hash', 'SHA256 mismatch'), ('platform', 'required libc'), ('abi', 'Expected target ELF32')):
            with self.subTest(fault=fault), tempfile.TemporaryDirectory() as directory:
                args = self.fixture(Path(directory))
                if fault == 'hash':
                    args[3].write_bytes(args[3].read_bytes() + b'changed')
                elif fault == 'platform':
                    with zipfile.ZipFile(args[3], 'w') as package:
                        package.writestr('ignored', b'empty')
                    self.pin(args[4], args[3])
                else:
                    self.platform(args[3], args[2], binary(abi='armeabi-v7a'))
                    self.pin(args[4], args[3])
                with self.assertRaisesRegex(ValueError, message):
                    check.validate(*args)

    def test_truncated_tables_and_versioned_imports_fail_explicitly(self):
        for fault, message in (('sections', 'sections required'), ('truncated', 'Truncated ELF'),
                               ('name', 'dynamic-symbol name'), ('version', 'Versioned API10 imports')):
            with self.subTest(fault=fault), tempfile.TemporaryDirectory() as directory:
                root = Path(directory)
                value = binary(symbols=[('puts', False, 1)], versions=[0, 2] if fault == 'version' else None)
                if fault == 'sections':
                    struct.pack_into('<I', value, 32, 0)
                elif fault == 'truncated':
                    del value[0xd10:]
                elif fault == 'name':
                    struct.pack_into('<I', value, 0x390, 0x9000)
                path = root / 'metadata.so'
                path.write_bytes(value)
                with self.assertRaisesRegex(ValueError, message):
                    check.symbols(path, 'x86')

    def test_pinned_libcxx_linker_script_is_not_an_export_provider(self):
        for value in (b'INPUT(-lc++_shared)', b'INPUT(-lunreviewed)'):
            with self.subTest(value=value), tempfile.TemporaryDirectory() as directory:
                args = self.fixture(Path(directory))
                prefix = 'android-ndk-r27/toolchains/llvm/prebuilt/linux-x86_64/sysroot/usr/lib/i686-linux-android/21/'
                with zipfile.ZipFile(args[3], 'a') as package:
                    package.writestr(prefix + 'libc++.so', value)
                self.pin(args[4], args[3])
                if value == b'INPUT(-lc++_shared)':
                    report = check.validate(*args)
                    self.assertEqual(set(report['excluded_platform_linker_scripts_sha256']), {'libc++.so'})
                    self.assertNotIn('libc++.so', report['platform_stub_sha256'])
                else:
                    with self.assertRaisesRegex(ValueError, 'Expected target ELF32'):
                        check.validate(*args)

    def test_api10_report_is_mandatory_after_rebinding_inventory(self):
        reports = report_fixtures.reports
        for abi in check.TRIPLES:
            with self.subTest(abi=abi), tempfile.TemporaryDirectory() as directory:
                root = report_fixtures.producer(Path(directory), 5, abi)
                name = 'sdk-api21-forward-symbols.json'
                self.assertIn(name, reports.required(5, abi))
                (root / name).unlink()
                inventory_path = root / reports.INVENTORY
                inventory = json.loads(inventory_path.read_text())
                del inventory['files'][name]
                inventory_path.write_text(json.dumps(inventory))
                with self.assertRaisesRegex(ValueError, 'report set differs'):
                    reports.verify_producer(root, 5, abi)
        for qt, abi in ((4, 'x86'), (5, 'arm64-v8a'), (5, 'x86_64'), (6, 'x86')):
            self.assertNotIn('sdk-api21-forward-symbols.json', reports.required(qt, abi))

    def test_cli_recheck_removes_stale_success(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            prefix, runtime, abi, archive, lock = self.fixture(root)
            report = root / 'report.json'
            argv = [str(prefix), '--runtime', str(runtime), '--abi', abi, '--archive', str(archive), '--lock', str(lock), '--report', str(report)]
            with contextlib.redirect_stdout(io.StringIO()):
                check.main(argv)
            self.assertEqual(json.loads(report.read_text())['platform_archive_sha256'], check.digest(archive))
            (prefix / 'lib/libQt5Core.so').write_bytes(binary(symbols=[('missing_api21', False, 1)]))
            with self.assertRaisesRegex(ValueError, 'symbol names unavailable'):
                check.main(argv)
            self.assertFalse(report.exists())
            self.assertFalse(report.with_suffix('.json.tmp').exists())


if __name__ == '__main__':
    unittest.main()
