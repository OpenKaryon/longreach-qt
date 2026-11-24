# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2026 OpenKaryon
"""Installed Qt4 spec/provenance file fixtures; no native tools execute."""
from contextlib import nullcontext
import importlib.util
import io
import json
import os
from pathlib import Path
import shlex
import shutil
import struct
import subprocess
import sys
import tarfile
import tempfile
import unittest
from unittest.mock import patch

from test_android_clang_wrapper import BASH

ROOT = Path(__file__).resolve().parents[2]
spec = importlib.util.spec_from_file_location('fixture_qt4_sdk_provenance', ROOT / 'scripts/build/qt4-android/sdk-provenance.py')
provenance = importlib.util.module_from_spec(spec)
spec.loader.exec_module(provenance)
exporter = provenance.mkspec_helper
TARGETS = {'x86': (10, 32, 3, '/opt/longreach-android'),
           'x86_64': (21, 64, 62, '/opt/longreach-android-api21'),
           'arm64-v8a': (21, 64, 183, '/opt/longreach-android-api21')}


def seed_source(root):
    source, prefix = root / 'source with spaces', root / 'installed SDK'
    prefix.mkdir()
    files = {'mkspecs/linux-g++/qmake.conf': 'include(../common/linux.conf)\n',
             'mkspecs/common/linux.conf': 'MAKEFILE_GENERATOR = UNIX\n',
             'mkspecs/features/qt_config.prf': 'fixture installed feature\n',
             'mkspecs/features/obsolete.prf': 'obsolete optional feature\n',
             'mkspecs/qconfig.pri': 'QT_VERSION = 4.8.7\n',
             'mkspecs/modules/qt_fixture.pri': 'fixture module metadata\n',
             'mkspecs/linux-donut-llvm/qmake.conf': 'QMAKE_CXX = /work/donut-bin/donut-cxx\n',
             'mkspecs/linux-donut-llvm/qplatformdefs.h': '#define QT_SOCKLEN_T socklen_t\n',
             'mkspecs/linux-donut-host/qmake.conf': 'fixture build-only host spec\n',
             'mkspecs/default/qmake.conf': 'QMAKE_CXX = /work/donut-bin/donut-cxx\n',
             'mkspecs/default-host/qmake.conf': 'fixture old host default\n',
             'retained.o': 'retained object bytes\n'}
    for name, text in files.items():
        path = source / name
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(text, encoding='utf-8')
    return source, prefix


class Mkspecs(unittest.TestCase):
    def test_export_replaces_build_specs_and_default_for_both_runtime_prefixes(self):
        for runtime in sorted(exporter.RUNTIMES):
            with self.subTest(runtime=runtime), tempfile.TemporaryDirectory() as temporary:
                source, prefix = seed_source(Path(temporary))
                before = {str(path): path.read_bytes() for path in source.rglob('*') if path.is_file()}
                record = exporter.export(source, prefix, runtime)
                self.assertEqual(exporter.verify(prefix, runtime), record)
                self.assertIn('modules/qt_fixture.pri', record['files'])
                self.assertIn('qconfig.pri', record['files'])
                for name in ('default', exporter.SPEC):
                    config = (prefix / 'mkspecs' / name / 'qmake.conf').read_text()
                    self.assertIn(runtime + '/bin/cxx', config)
                    self.assertIn('CONFIG += android-longreach-clang', config)
                    self.assertNotIn('/work/', config)
                    self.assertEqual((prefix / 'mkspecs' / name / 'qplatformdefs.h').read_bytes(),
                                     (source / 'mkspecs/linux-donut-llvm/qplatformdefs.h').read_bytes())
                for name in ('linux-donut-host', 'linux-donut-llvm', 'default-host'):
                    self.assertFalse((prefix / 'mkspecs' / name).exists())
                self.assertEqual(before, {str(path): path.read_bytes() for path in source.rglob('*') if path.is_file()})

    def test_warm_export_keeps_installed_file_timestamps(self):
        with tempfile.TemporaryDirectory() as temporary:
            source, prefix = seed_source(Path(temporary))
            runtime = '/opt/longreach-android-api21'
            record = exporter.export(source, prefix, runtime)
            before = {str(path): path.stat().st_mtime_ns for path in (prefix / 'mkspecs').rglob('*') if path.is_file()}
            self.assertEqual(exporter.export(source, prefix, runtime), record)
            self.assertEqual(before, {str(path): path.stat().st_mtime_ns for path in (prefix / 'mkspecs').rglob('*') if path.is_file()})
            self.assertFalse(list(prefix.glob('.longreach-mkspec-*')))

    def test_removed_features_and_changed_headers_are_reconciled_without_touching_objects(self):
        with tempfile.TemporaryDirectory() as temporary:
            source, prefix = seed_source(Path(temporary))
            runtime = '/opt/longreach-android'
            exporter.export(source, prefix, runtime)
            (source / 'mkspecs/features/obsolete.prf').unlink()
            (source / 'mkspecs/features/new.prf').write_text('new feature')
            (source / 'mkspecs/linux-donut-llvm/qplatformdefs.h').write_text('updated platform header')
            exporter.export(source, prefix, runtime)
            self.assertFalse((prefix / 'mkspecs/features/obsolete.prf').exists())
            self.assertTrue((prefix / 'mkspecs/features/new.prf').exists())
            self.assertEqual((prefix / 'mkspecs/default/qplatformdefs.h').read_text(), 'updated platform header')
            self.assertEqual((source / 'retained.o').read_text(), 'retained object bytes\n')

    def test_drift_and_changed_recipe_or_runtime_do_not_verify(self):
        for changed in ('default', 'common', 'extra', 'missing', 'exporter', 'runtime'):
            with self.subTest(changed=changed), tempfile.TemporaryDirectory() as temporary:
                source, prefix = seed_source(Path(temporary))
                runtime = '/opt/longreach-android'
                exporter.export(source, prefix, runtime)
                if changed == 'default': (prefix / 'mkspecs/default/qmake.conf').write_text('old spec')
                elif changed == 'common': (prefix / 'mkspecs/common/linux.conf').write_text('changed flags')
                elif changed == 'extra': (prefix / 'mkspecs/stale.conf').write_text('stale source')
                elif changed == 'missing': (prefix / 'mkspecs/qconfig.pri').unlink()
                elif changed == 'runtime': runtime = '/opt/longreach-android-api21'
                else:
                    path = prefix / 'mkspecs' / exporter.RECEIPT
                    record = json.loads(path.read_text())
                    record['exporter_sha256'] = '0' * 64
                    path.write_text(json.dumps(record))
                with self.assertRaises(ValueError): exporter.verify(prefix, runtime)

    def test_old_copy_without_receipt_is_not_backfilled(self):
        with tempfile.TemporaryDirectory() as temporary:
            source, prefix = seed_source(Path(temporary))
            shutil.copytree(source / 'mkspecs', prefix / 'mkspecs')
            with self.assertRaises(FileNotFoundError): exporter.verify(prefix, '/opt/longreach-android')
            self.assertFalse((prefix / 'mkspecs' / exporter.RECEIPT).exists())

    def test_incomplete_source_or_failed_copy_keeps_current_export(self):
        for failure in ('missing-common', 'missing-header', 'copy'):
            with self.subTest(failure=failure), tempfile.TemporaryDirectory() as temporary:
                source, prefix = seed_source(Path(temporary))
                runtime = '/opt/longreach-android'
                record = exporter.export(source, prefix, runtime)
                if failure == 'missing-common': (source / 'mkspecs/common').rename(source / 'retained-common')
                elif failure == 'missing-header': (source / 'mkspecs/linux-donut-llvm/qplatformdefs.h').unlink()
                def copy(*args, **kwargs): raise OSError('fixture metadata copy interruption')
                manager = patch.object(exporter.shutil, 'copyfile', copy) if failure == 'copy' else nullcontext()
                with manager, self.assertRaises((ValueError, OSError)): exporter.export(source, prefix, runtime)
                self.assertEqual(exporter.verify(prefix, runtime), record)

    def test_failed_publication_restores_previous_export(self):
        for failure in ('promotion', 'post-verification'):
            with self.subTest(failure=failure), tempfile.TemporaryDirectory() as temporary:
                source, prefix = seed_source(Path(temporary))
                runtime = '/opt/longreach-android'
                before = exporter.export(source, prefix, runtime)
                (source / 'mkspecs/qconfig.pri').write_text('changed configuration')
                rename, verify_tree = Path.rename, exporter.verify_tree
                def fail_stage(path, destination):
                    if path.name.startswith('.longreach-mkspec-stage-'): raise OSError('fixture promotion interruption')
                    return rename(path, destination)
                def fail_after_promotion(path, runtime):
                    record = verify_tree(path, runtime)
                    if path.name == 'mkspecs' and (path / 'qconfig.pri').read_text() == 'changed configuration':
                        raise OSError('fixture post-verification interruption')
                    return record
                manager = (patch.object(Path, 'rename', fail_stage) if failure == 'promotion'
                           else patch.object(exporter, 'verify_tree', fail_after_promotion))
                with manager, self.assertRaisesRegex(OSError, 'fixture ' + failure + ' interruption'):
                    exporter.export(source, prefix, runtime)
                self.assertEqual(exporter.verify(prefix, runtime), before)


@unittest.skipUnless(BASH, 'Bash needed for metadata-only producer fragments')
class ShellMetadata(unittest.TestCase):
    def invoke(self, root, fragment, variables):
        commands = root / 'metadata-bin'
        commands.mkdir(exist_ok=True)
        launcher = commands / 'python3'
        launcher.write_text('#!/bin/bash\nexec "$LONGREACH_METADATA_PYTHON" "$@"\n', encoding='utf-8', newline='\n')
        launcher.chmod(0o755)
        helper = ROOT / 'scripts/build/qt4-android/export-mkspecs.py'
        fragment = fragment.replace('/repo/scripts/build/qt4-android/export-mkspecs.py', shlex.quote(helper.as_posix()))
        script = root / 'metadata only.sh'
        assignments = '\n'.join(name + '=' + shlex.quote(str(value)) for name, value in variables.items())
        script.write_text('set -euo pipefail\n' + assignments + '\n' + fragment, encoding='utf-8', newline='\n')
        environment = dict(os.environ, PATH=str(commands) + os.pathsep + os.environ['PATH'],
                           LONGREACH_METADATA_PYTHON=Path(sys.executable).as_posix(), MSYS_NO_PATHCONV='1', MSYS2_ARG_CONV_EXCL='*')
        return subprocess.run([BASH, '--noprofile', '--norc', script.as_posix()], capture_output=True, text=True,
                              env=environment, timeout=10, creationflags=getattr(subprocess, 'CREATE_NO_WINDOW', 0))

    def test_actual_sdk_export_fragment_uses_current_cli_without_work_spec(self):
        text = (ROOT / 'scripts/build/qt4-android/build-api21-sdk.sh').read_text()
        fragment = text[text.index('# Export installed mkspecs independently'):text.index('cat > "$prefix/longreach-target.cmake"')]
        for runtime in sorted(exporter.RUNTIMES):
            with self.subTest(runtime=runtime), tempfile.TemporaryDirectory() as temporary:
                root = Path(temporary)
                source, prefix = seed_source(root)
                result = self.invoke(root, fragment, dict(tree=source.as_posix(), prefix=prefix.as_posix(), runtime=runtime))
                self.assertEqual(result.returncode, 0, result.stderr)
                self.assertEqual(exporter.verify(prefix, runtime)['default_spec'], exporter.SPEC)

    def test_actual_client_preflight_checks_selected_prefix_before_native_boundary(self):
        text = (ROOT / 'scripts/build/qt4-android/build-api21-examples.sh').read_text()
        fragment = text[text.index('phase=${1:-core}'):text.index('cxx=$runtime/bin/cxx')]
        # Pass the real fragment a phase through its original $1 interface.
        for phase in ('core', 'all'):
            with self.subTest(phase=phase), tempfile.TemporaryDirectory() as temporary:
                root = Path(temporary)
                source, prefix = seed_source(root)
                runtime = '/opt/longreach-android-api21'
                exporter.export(source, prefix, runtime)
                other = root / 'unused prefix'
                other.mkdir()
                variables = dict(core_prefix=(prefix if phase == 'core' else other).as_posix(),
                                 quick_prefix=(prefix if phase == 'all' else other).as_posix(), runtime=runtime)
                selected = 'set -- ' + phase + '\n' + fragment
                result = self.invoke(root, selected, variables)
                self.assertEqual(result.returncode, 0, result.stderr)
                (prefix / 'mkspecs/default/qmake.conf').write_text('stale default')
                result = self.invoke(root, selected, variables)
                self.assertNotEqual(result.returncode, 0)
                self.assertIn('mkspec bytes or file set changed', result.stderr)

    def test_final_sdk_stage_verifies_real_installed_metadata_for_all_abis(self):
        text = (ROOT / 'docker/qt4/android/Dockerfile').read_text()
        fragment = text.split('FROM ${ANDROID_ABI}-sdk AS sdk\n', 1)[1].split('\n\n# Historical', 1)[0]
        self.assertTrue(fragment.startswith('RUN --network=none '))
        fragment = fragment.removeprefix('RUN --network=none ')
        for abi, settings in TARGETS.items():
            with self.subTest(abi=abi), tempfile.TemporaryDirectory() as temporary:
                root = Path(temporary)
                source, prefix = seed_source(root)
                exporter.export(source, prefix, settings[3])
                (prefix / 'libexec').mkdir()
                shutil.copyfile(ROOT / 'scripts/build/qt4-android/export-mkspecs.py', prefix / 'libexec/longreach-export-mkspecs.py')
                adapted = fragment.replace('/opt/qt4-android-${ANDROID_ABI}-llvm', prefix.as_posix())
                variables = dict(ANDROID_ABI=abi, ANDROID_API=settings[0])
                result = self.invoke(root, adapted, variables)
                self.assertEqual(result.returncode, 0, result.stderr)
                (prefix / 'mkspecs/default/qmake.conf').write_text('stale default')
                result = self.invoke(root, adapted, variables)
                self.assertNotEqual(result.returncode, 0)
                self.assertIn('mkspec bytes or file set changed', result.stderr)


class Provenance(unittest.TestCase):
    def seed(self, root, abi):
        repo, tree, prefix, output = root / 'repo', root / 'tree', root / 'prefix', root / 'reports'
        tree.mkdir()
        selected_source, prepared_prefix = seed_source(root)
        selected_source.rename(tree / 'seed')
        (tree / 'seed/mkspecs').rename(tree / 'mkspecs')
        prepared_prefix.rename(prefix)
        runtime = root / 'runtime'
        (runtime / 'lib').mkdir(parents=True)
        (runtime / 'lib/libc++_shared.so').write_bytes(b'fixture runtime bytes')
        compiler = root / 'inert compiler file'
        compiler.write_bytes(b'Not an executable: only this file hash is used')
        for name in provenance.HELPERS:
            path = repo / 'scripts/build/qt4-android' / name
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_bytes((ROOT / 'scripts/build/qt4-android' / name).read_bytes())
        for name in ('all/03-static-gui-animation-registration.patch', 'all/04-script-tagged-frame-pointers.patch',
                     'linux-sarge-llvm/01-xmlpatterns-color-mask.patch'):
            path = repo / 'patches/qt4' / name
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_text('fixture patch recipe input only')
        (repo / 'patches/qt4/android').mkdir()
        archive = root / 'tiny-source.tar.gz'
        with tarfile.open(archive, 'w:gz') as target:
            for name, data in {'configure': b'fixture configure, never executed', 'src/unit.cpp': b'pristine source'}.items():
                member = tarfile.TarInfo('qt/' + name)
                member.size = len(data)
                target.addfile(member, io.BytesIO(data))
        api, bits, machine, runtime_prefix = TARGETS[abi]
        helper = provenance.source_helper
        def recipe(stage, *args): (stage / 'src/unit.cpp').write_bytes(b'prepared source')
        with patch.object(helper, 'apply_recipe', recipe): helper.prepare(repo, archive, tree, 'quick', api)
        for name in ('.longreach-configuration', '.longreach-object-configuration', '.longreach-plugin-configuration'):
            (tree / name).write_text('a' * 64)
        exporter.export(tree, prefix, runtime_prefix)
        (prefix / 'lib').mkdir()
        elf = bytearray(52 if bits == 32 else 64)
        elf[:7] = b'\x7fELF' + bytes((1 if bits == 32 else 2, 1, 1))
        struct.pack_into('<H', elf, 16, 1)
        struct.pack_into('<I', elf, 20, 1)
        struct.pack_into('<H', elf, 18, machine)
        header = 'fixture.o/      ' + '0           ' + '0     ' + '0     ' + '100644  ' + f'{len(elf):<10}' + '`\n'
        data = b'!<arch>\n' + header.encode() + elf
        for index in range(14): (prefix / f'lib/libQtFixture{index:02}.a').write_bytes(data)
        return dict(prefix=prefix, source=tree, output=output, abi=abi, repo=repo, archive=archive, runtime=runtime, compiler=compiler)

    def test_actual_producer_records_specs_source_and_archives_for_every_installed_abi(self):
        for abi in TARGETS:
            with self.subTest(abi=abi), tempfile.TemporaryDirectory() as temporary:
                options = self.seed(Path(temporary), abi)
                record = provenance.produce(**options)
                self.assertEqual(record['installed_mkspecs'], exporter.verify(options['prefix'], TARGETS[abi][3]))
                self.assertIn('scripts/build/qt4-android/export-mkspecs.py', record['recipe_inputs'])
                self.assertIn('src/unit.cpp', record['patched_source'])
                self.assertEqual(json.loads((options['output'] / 'sdk-provenance.json').read_text()), record)
                archives = json.loads((options['output'] / 'sdk-static-elf.json').read_text())['archives']
                self.assertEqual(len(archives), 14)
                self.assertTrue(all(item['machine'] == TARGETS[abi][2] for item in archives))

    def test_invalid_source_config_archive_or_specs_cannot_leave_success_reports(self):
        for fault in ('source', 'config', 'archive', 'mkspecs'):
            with self.subTest(fault=fault), tempfile.TemporaryDirectory() as temporary:
                options = self.seed(Path(temporary), 'x86_64')
                provenance.produce(**options)
                if fault == 'source': (options['source'] / 'src/unit.cpp').write_text('unprepared source')
                elif fault == 'config': (options['source'] / '.longreach-plugin-configuration').write_text('b' * 64)
                elif fault == 'archive': (options['prefix'] / 'lib/libQtFixture00.a').write_bytes(b'not an archive')
                else: (options['prefix'] / 'mkspecs/default/qmake.conf').write_text('old default spec')
                with self.assertRaises((ValueError, RuntimeError)): provenance.produce(**options)
                self.assertTrue(all(not (options['output'] / name).exists() for name in provenance.REPORTS))


if __name__ == '__main__':
    unittest.main()
