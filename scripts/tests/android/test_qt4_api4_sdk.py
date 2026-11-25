# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2026 OpenKaryon
"""Data-only API4 installed-SDK contracts; never a native or guest qualification."""
import importlib.util
import json
from pathlib import Path
import struct
import shutil
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch

import android_native_abi_fixtures as native
from test_qt4_android_mkspecs import seed_source

ROOT = Path(__file__).resolve().parents[3]
spec = importlib.util.spec_from_file_location('fixture_api4_sdk', ROOT / 'scripts/build/qt4-android/api4-sdk.py')
sdk = importlib.util.module_from_spec(spec)
spec.loader.exec_module(sdk)


def archive(path, abi='armeabi'):
    body = bytearray(native.elf(abi))
    struct.pack_into('<H', body, 16, 1)
    header = ('fixture.o/'.ljust(16) + '0'.ljust(12) + '0'.ljust(6) + '0'.ljust(6) +
              '100644'.ljust(8) + str(len(body)).ljust(10) + '`\n').encode()
    assert len(header) == 60
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_bytes(b'!<arch>\n' + header + body + (b'\n' if len(body) % 2 else b''))


class Api4Sdk(unittest.TestCase):
    def setUp(self):
        temporary = tempfile.TemporaryDirectory(prefix='api4-sdk-contract-')
        self.addCleanup(temporary.cleanup)
        self.base = Path(temporary.name).resolve()
        self.source, self.prefix = seed_source(self.base)
        self.runtime = self.base / 'installed runtime'
        self.runtime.mkdir()
        for name in (*('lib/libQt' + n + '.a' for n in sdk.MODULES), *sdk.PLUGINS):
            archive(self.prefix / name)
        for name in sdk.MODULES:
            path = self.prefix / ('include/Qt' + name + '/fixture.h')
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_text('data-only installed header')
        for name in ('qmake', 'moc', 'rcc', 'uic'):
            path = self.prefix / ('bin/' + name)
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_bytes(native.elf('x86_64'))
        (self.prefix / 'bin/qt.conf').write_text('[Paths]\nPrefix=' + sdk.SDK + '\n')
        report = self.prefix / 'longreach-reports/qmake-query.txt'
        report.parent.mkdir()
        report.write_text('QT_VERSION:4.8.7\nQT_INSTALL_PREFIX:' + sdk.SDK + '\nQT_INSTALL_HEADERS:' +
                          sdk.SDK + '/include\nQT_INSTALL_LIBS:' + sdk.SDK + '/lib\n')
        for name in sdk.LIBRARIES:
            archive(self.runtime / 'lib' / name)
        for name in sdk.OBJECTS:
            path = self.runtime / 'lib' / name
            body = bytearray(native.elf('armeabi'))
            struct.pack_into('<H', body, 16, 1)
            path.write_bytes(body)
        for name in ('bin/cc', 'bin/cxx', 'target.sh', 'include/c++/v1/__config',
                     'sysroot/usr/include/stdlib.h', 'sysroot/usr/lib/libc.so',
                     'sysroot/usr/lib/crtbegin_dynamic.o', 'sysroot/usr/lib/crtbegin_static.o',
                     'sysroot/usr/lib/crtend_android.o'):
            path = self.runtime / name
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_text('data-only toolchain fixture/' + name)
        sdk.provenance.mkspec_helper.export(self.source, self.prefix, sdk.RUNTIME)
        self.compiler = self.base / 'recorded host compiler'
        self.compiler.write_bytes(native.elf('x86_64'))
        self.qt_archive = self.base / 'qt-source.tar.gz'
        self.qt_archive.write_bytes(b'data-only pinned-source fixture')
        for context in (patch.object(sdk, 'QT_ARCHIVE', sdk.digest(self.qt_archive)),
                        patch.object(sdk.provenance.source_helper, 'verify_prepared',
                                     return_value={'recipe': {'data-only fixture': True}})):
            context.start()
            self.addCleanup(context.stop)

    def seal(self):
        return sdk.seal(self.prefix, self.runtime, ROOT, self.source, self.qt_archive, compiler=self.compiler)

    def test_complete_static_payload_seals_without_claiming_guest_qualification(self):
        result = self.seal()
        self.assertEqual(result, sdk.verify(self.prefix, self.runtime))
        self.assertEqual(result['api'], 4)
        self.assertEqual(result['abi'], 'armeabi')
        self.assertEqual(result['runtime_linkage'], 'static')
        self.assertFalse(result['guest_qualification'])
        self.assertEqual(len(result['payload']['static_archives']), 18)
        self.assertNotIn(sdk.REPORT, result['payload']['sdk_files'])

    def test_each_configured_module_plugin_and_runtime_archive_is_required(self):
        names = [('sdk', 'lib/libQtXml.a'), ('sdk', sdk.PLUGINS[0]),
                 ('runtime', 'lib/libc++.a'), ('runtime', 'lib/libclang_rt.builtins-arm-android.a')]
        for root, relative in names:
            path = (self.prefix if root == 'sdk' else self.runtime) / relative
            data = path.read_bytes()
            path.unlink()
            with self.subTest(relative=relative), self.assertRaises((ValueError, OSError)):
                self.seal()
            self.assertFalse((self.prefix / sdk.REPORT).exists())
            path.write_bytes(data)

    def test_wrong_target_archives_and_missing_compat_objects_do_not_seal(self):
        path = self.prefix / 'lib/libQtCore.a'
        previous = path.read_bytes()
        archive(path, 'x86')
        with self.assertRaisesRegex(RuntimeError, 'Wrong ABI'):
            self.seal()
        path.write_bytes(previous)
        (self.runtime / 'lib/armv5-compat.o').unlink()
        with self.assertRaises(OSError):
            self.seal()

    def test_host_tools_and_qmake_query_must_select_the_installed_sdk(self):
        for fault in ('tool', 'prefix', 'query'):
            path = self.prefix / {'tool': 'bin/qmake', 'prefix': 'bin/qt.conf',
                                  'query': 'longreach-reports/qmake-query.txt'}[fault]
            previous = path.read_bytes()
            path.write_bytes(native.elf('armeabi') if fault == 'tool' else b'/work/old-build-prefix\n')
            with self.subTest(fault=fault), self.assertRaisesRegex(ValueError, 'ABI differs|qt.conf|qmake query'):
                self.seal()
            path.write_bytes(previous)

    def test_mutated_header_runtime_and_extra_files_invalidate_a_sealed_payload(self):
        self.seal()
        for path in (self.prefix / 'include/QtCore/fixture.h', self.runtime / 'bin/cxx', self.prefix / 'unexpected.txt'):
            previous = path.read_bytes() if path.exists() else None
            path.write_text('changed payload')
            with self.subTest(path=path), self.assertRaisesRegex(ValueError, 'bytes changed'):
                sdk.verify(self.prefix, self.runtime)
            if previous is None:
                path.unlink()
            else:
                path.write_bytes(previous)

    def test_failed_reseal_invalidates_an_earlier_success(self):
        self.seal()
        self.qt_archive.write_text('changed source archive')
        with self.assertRaisesRegex(ValueError, 'pinned source'):
            self.seal()
        self.assertFalse((self.prefix / sdk.REPORT).exists())

    def test_changed_host_compiler_identity_does_not_verify(self):
        self.seal()
        self.compiler.write_bytes(native.elf('x86_64', b'changed compiler bytes'))
        with self.assertRaisesRegex(ValueError, 'compiler identity differs'):
            sdk.verify(self.prefix, self.runtime)

    def test_source_binding_requires_the_same_producer_and_archive_inputs(self):
        result = self.seal()
        captured = {'inputs': {'sources': dict(result['recipe_inputs']),
                              'archives': {'downloads/qt-everywhere-opensource-src-4.8.7.tar.gz': result['qt_archive_sha256']}}}
        for name, sha in result['runtime_source_archives'].items():
            key = ('android-inputs/' if name == 'aosp-ndk-r7-api4-arm.tar.gz' else 'downloads/') + name
            captured['inputs']['archives'][key] = sha
        self.assertTrue(sdk.check_source_binding(result, captured))
        source = next(iter(captured['inputs']['sources']))
        for key, name in (('sources', source), ('archives', 'downloads/qt-everywhere-opensource-src-4.8.7.tar.gz'),
                          ('archives', 'android-inputs/aosp-ndk-r7-api4-arm.tar.gz')):
            changed = json.loads(json.dumps(captured))
            changed['inputs'][key][name] = '0' * 64
            with self.subTest(key=key, name=name), self.assertRaisesRegex(ValueError, 'differs from capture|differs from captured'):
                sdk.check_source_binding(result, changed)

    def test_metadata_relocation_preserves_sealed_mkspecs_and_changes_only_link_paths(self):
        # The producer's real module, platform and QML .prl files use its
        # source-tree lib directory, rather than the configured install prefix.
        names = ('lib/QtCore.prl', 'plugins/platforms/libqminimal.prl',
                 'imports/Qt/labs/particles/libqmlparticlesplugin.prl')
        for name in names:
            path = self.prefix / name
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_text('QMAKE_PRL_BUILD_DIR = /work/qt4-donut-quick/src/corelib\n'
                            'QMAKE_PRL_LIBS = -L/work/qt4-donut-quick/lib -lQtCore '
                            '-L/work/qtquick-donut-sdk/lib -L/work/runtime-build/lib\n')
        specs = sdk.provenance.mkspec_helper.verify(self.prefix, sdk.RUNTIME)
        sdk.normalize_metadata(self.prefix, Path(sdk.RUNTIME))
        self.assertEqual(specs, sdk.provenance.mkspec_helper.verify(self.prefix, sdk.RUNTIME))
        for name in names:
            text = (self.prefix / name).read_text()
            self.assertIn('-L' + sdk.SDK + '/lib', text)
            self.assertIn('-L' + sdk.RUNTIME + '/lib', text)
            link = next(line for line in text.splitlines() if line.startswith('QMAKE_PRL_LIBS'))
            self.assertNotIn('/work/', link)
            self.assertIn('QMAKE_PRL_BUILD_DIR = /work/qt4-donut-quick', text)
        path = self.prefix / names[0]
        before = path.read_bytes()
        with self.assertRaisesRegex(ValueError, 'declared installed runtime'):
            sdk.normalize_metadata(self.prefix, self.runtime)
        self.assertEqual(path.read_bytes(), before)
        path.write_text('QMAKE_PRL_LIBS = -L/work/unexported-component/lib\n')
        with self.assertRaisesRegex(ValueError, 'build-tree link input'):
            sdk.normalize_metadata(self.prefix, Path(sdk.RUNTIME))

    def test_installed_verifier_closure_is_read_only(self):
        installed = self.prefix / 'libexec/api4-sdk'
        installed.mkdir(parents=True)
        for name in ('api4-sdk.py', 'sdk-provenance.py', 'prepare-source.py', 'export-mkspecs.py'):
            shutil.copyfile(ROOT / 'scripts/build/qt4-android' / name, installed / name)
        # Keep the real verifier logic; only the source pin is adapted to the
        # data-only archive fixture, as in the in-process producer contracts.
        script = installed / 'api4-sdk.py'
        text = script.read_text()
        original = next(line for line in text.splitlines() if line.startswith('QT_ARCHIVE = '))
        script.write_text(text.replace(original, 'QT_ARCHIVE = ' + repr(sdk.QT_ARCHIVE)), encoding='utf-8')
        record = self.seal()
        record['exporter_sha256'] = sdk.digest(script)
        (self.prefix / sdk.REPORT).write_text(json.dumps(record))
        before = sdk.inventory(self.prefix)
        result = subprocess.run([sys.executable, str(script), 'verify', '--prefix', str(self.prefix),
                                 '--runtime', str(self.runtime)], text=True, capture_output=True, timeout=20,
                                creationflags=getattr(subprocess, 'CREATE_NO_WINDOW', 0))
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertEqual(before, sdk.inventory(self.prefix))
        self.assertFalse(list(installed.rglob('__pycache__')))

    def test_forged_guest_status_or_exporter_does_not_verify(self):
        result = self.seal()
        path = self.prefix / sdk.REPORT
        for key, value in (('guest_qualification', True), ('exporter_sha256', '0' * 64)):
            changed = dict(result, **{key: value})
            path.write_text(json.dumps(changed))
            with self.subTest(key=key), self.assertRaisesRegex(ValueError, 'identity/exporter'):
                sdk.verify(self.prefix, self.runtime)


if __name__ == '__main__':
    unittest.main()
