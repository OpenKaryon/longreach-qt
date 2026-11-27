# SPDX-License-Identifier: GPL-3.0-or-later
"""Exact producer report inventories and interrupted-export file fixtures."""
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

import android_sdk_report_fixtures as fixtures

reports = fixtures.reports


class Reports(unittest.TestCase):
    def test_sdk_digest_does_not_require_python311_file_digest(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / 'report.txt'
            path.write_bytes(b'abc')
            with patch.dict(reports.hashlib.__dict__):
                reports.hashlib.__dict__.pop('file_digest', None)
                self.assertEqual(reports.digest(path), 'ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad')

    def test_exact_exports_for_every_installed_target(self):
        for qt in (4, 5, 6):
            for abi in (('x86', 'x86_64', 'arm64-v8a') if qt == 4 else ('armeabi-v7a', 'x86', 'x86_64', 'arm64-v8a')):
                with self.subTest(qt=qt, abi=abi), tempfile.TemporaryDirectory() as directory:
                    root = Path(directory)
                    source = fixtures.producer(root / 'source', qt, abi)
                    output = root / 'output'
                    output.mkdir()
                    result = reports.export(source, output, qt, abi, fixtures.SDK)
                    self.assertEqual(result, reports.verify_export(output, qt, abi, fixtures.SDK))
                    self.assertIn('runtime-elf.txt', result)
                    self.assertIn(reports.INVENTORY, result)
                    before = {name: (output / name).stat().st_mtime_ns for name in result}
                    with patch.object(reports.shutil, 'copyfile', side_effect=AssertionError('warm report copy')):
                        self.assertEqual(reports.export(source, output, qt, abi, fixtures.SDK), result)
                    self.assertEqual({name: (output / name).stat().st_mtime_ns for name in result}, before)
                    self.assertFalse((output / 'sdk-report-history').exists())
                    if qt == 6:
                        self.assertEqual(len([name for name in result if name.startswith('sdk-java-audit/')]), 10)

    def test_optional_qt6_full_build_log_is_sealed_exported_and_rechecked(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            source = fixtures.producer(root / 'source', 6, 'armeabi-v7a')
            log = b'[1/2] compile\ncompiler diagnostic\n[2/2] link\ninstall complete\n'
            (source / 'qt-sdk-build.log').write_bytes(log)
            reports.seal(source, 6, 'armeabi-v7a')
            output = root / 'output'
            output.mkdir()
            exported = reports.export(source, output, 6, 'armeabi-v7a', fixtures.SDK)
            self.assertIn('qt-sdk-build.log', exported)
            self.assertEqual((output / 'qt-sdk-build.log').read_bytes(), log)
            self.assertEqual(reports.verify_export(output, 6, 'armeabi-v7a', fixtures.SDK), exported)
            (output / 'qt-sdk-build.log').write_bytes(log + b'changed')
            with self.assertRaisesRegex(ValueError, 'report bytes changed'):
                reports.verify_export(output, 6, 'armeabi-v7a', fixtures.SDK)

    def test_atomic_export_report_required_for_all_installed_sdk_targets(self):
        for qt in (4, 5, 6):
            for abi in (('x86', 'x86_64', 'arm64-v8a') if qt == 4 else ('armeabi-v7a', 'x86', 'x86_64', 'arm64-v8a')):
                with self.subTest(qt=qt, abi=abi), tempfile.TemporaryDirectory() as directory:
                    source = fixtures.producer(Path(directory), qt, abi)
                    self.assertTrue((source / 'runtime-atomic-exports.txt').is_file())
                    (source / 'runtime-atomic-exports.txt').unlink()
                    with self.assertRaisesRegex(ValueError, 'report set differs'):
                        reports.seal(source, qt, abi)
                    self.assertFalse((source / reports.INVENTORY).exists())

    def test_export_reconciles_only_reports_and_preserves_old_data(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            source = fixtures.producer(root / 'source', 6, 'x86')
            output = root / 'output'
            output.mkdir()
            for name in ('sdk-removed-report.json', 'runtime-input-provenance.json', 'sdk-java-audit/Old.jar',
                         'apk/retained.apk', 'native/retained.o', 'run/log.txt', 'sdk-image-id.txt', 'notes.txt'):
                path = output / name
                path.parent.mkdir(parents=True, exist_ok=True)
                path.write_text('old/' + name)
            reports.export(source, output, 6, 'x86', fixtures.SDK)
            for name in ('sdk-removed-report.json', 'runtime-input-provenance.json', 'sdk-java-audit/Old.jar'):
                self.assertFalse((output / name).exists())
                self.assertEqual(len(list((output / 'sdk-report-history').glob('*/' + name))), 1)
            for name in ('apk/retained.apk', 'native/retained.o', 'run/log.txt', 'sdk-image-id.txt', 'notes.txt'):
                self.assertEqual((output / name).read_text(), 'old/' + name)

    def test_missing_added_or_changed_producer_report_is_rejected(self):
        for changed in ('missing', 'added', 'bytes', 'java'):
            with self.subTest(changed=changed), tempfile.TemporaryDirectory() as directory:
                source = fixtures.producer(Path(directory), 6, 'x86_64')
                if changed == 'missing':
                    (source / 'qt-sdk-config.summary').unlink()
                elif changed == 'added':
                    (source / 'sdk-stale.json').write_text('old result')
                elif changed == 'java':
                    (source / 'sdk-java-audit/Fixture0.jar').write_text('different SDK JAR')
                else:
                    (source / 'runtime-elf.txt').write_text('different runtime report')
                with self.assertRaisesRegex(ValueError, 'bytes or exact file set changed'):
                    reports.verify_producer(source, 6, 'x86_64')

    def test_wrong_sdk_binding_and_stale_export_files_cannot_be_accepted(self):
        for changed in ('image', 'bytes', 'added', 'inventory'):
            with self.subTest(changed=changed), tempfile.TemporaryDirectory() as directory:
                root = Path(directory)
                fixtures.export(root, 5, 'x86')
                sdk = fixtures.SDK
                if changed == 'image':
                    sdk = 'sha256:' + 'b' * 64
                elif changed == 'added':
                    (root / 'sdk-leftover.txt').write_text('old generation')
                elif changed == 'inventory':
                    (root / reports.INVENTORY).write_text((root / reports.INVENTORY).read_text() + '\n')
                else:
                    (root / 'qt-sdk-config.summary').write_text('changed producer bytes')
                with self.assertRaisesRegex(ValueError, 'different image/inventory|report set changed|report bytes changed'):
                    reports.verify_export(root, 5, 'x86', sdk)

    def test_failed_staging_preserves_current_export_and_saved_apk(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            initial = fixtures.export(root, 6, 'arm64-v8a')
            source = root / fixtures.FIXTURE_SOURCE
            (root / 'retained.apk').write_text('saved APK')
            with patch.object(reports.shutil, 'copyfile', side_effect=OSError('fixture stage interruption')):
                with self.assertRaisesRegex(OSError, 'stage interruption'):
                    reports.export(source, root, 6, 'arm64-v8a', 'sha256:' + 'b' * 64)
            self.assertEqual(reports.verify_export(root, 6, 'arm64-v8a', fixtures.SDK), initial)
            self.assertEqual((root / 'retained.apk').read_text(), 'saved APK')

    def test_source_change_during_live_export_cannot_publish_completion(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            fixtures.export(root, 6, 'arm64-v8a')
            source = root / fixtures.FIXTURE_SOURCE
            copy = reports.shutil.copyfile
            changed = False
            def change_source(incoming, outgoing):
                nonlocal changed
                result = copy(incoming, outgoing)
                if not changed and Path(outgoing) == root / 'sdk-modules.txt':
                    changed = True
                    (source / 'sdk-modules.txt').write_text('another producer snapshot')
                    reports.seal(source, 6, 'arm64-v8a')
                return result
            with patch.object(reports.shutil, 'copyfile', side_effect=change_source):
                with self.assertRaisesRegex(ValueError, 'source changed during export'):
                    reports.export(source, root, 6, 'arm64-v8a', 'sha256:' + 'b' * 64)
            self.assertTrue(changed)
            self.assertFalse((root / reports.SOURCE).exists())

    def test_failed_live_copy_or_final_publication_has_no_completion_binding(self):
        for failure in ('live-copy', 'publish'):
            with self.subTest(failure=failure), tempfile.TemporaryDirectory() as directory:
                root = Path(directory)
                fixtures.export(root, 4, 'x86')
                source = root / fixtures.FIXTURE_SOURCE
                copy = reports.shutil.copyfile
                write = reports.write
                def fail_copy(incoming, outgoing):
                    if Path(outgoing) == root / 'sdk-modules.txt':
                        raise OSError('fixture live-copy failure')
                    return copy(incoming, outgoing)
                def fail_write(path, value):
                    if path == root / reports.SOURCE:
                        raise OSError('fixture publish failure')
                    return write(path, value)
                with patch.object(reports.shutil, 'copyfile', side_effect=fail_copy if failure == 'live-copy' else copy), patch.object(reports, 'write', side_effect=fail_write if failure == 'publish' else write):
                    with self.assertRaisesRegex(OSError, 'fixture'):
                        reports.export(source, root, 4, 'x86', 'sha256:' + 'b' * 64)
                self.assertFalse((root / reports.SOURCE).exists())
                self.assertTrue(list((root / 'sdk-report-history').glob('*/' + reports.SOURCE)))


if __name__ == '__main__':
    unittest.main()
