# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2026 OpenKaryon
"""Qt4 generation and packaging receipts, using synthetic files only."""
import json
import hashlib
from pathlib import Path
import struct
import tempfile
import unittest
from unittest.mock import patch
import zipfile

import android_result_fixtures as fixtures

artifacts = fixtures.QT4_ARTIFACTS


class Qt4Artifacts(unittest.TestCase):
    def test_native_abi_is_required_even_for_matching_packaged_native_bytes(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            fixtures.qt4(root)
            examples = artifacts.check_examples(root, 'x86_64')
            path = root / 'bootstrap.apk'
            with zipfile.ZipFile(path) as archive:
                entries = {name: archive.read(name) for name in archive.namelist()}
            member = 'lib/x86_64/libdonut_probe.so'
            data = bytearray(entries[member])
            struct.pack_into('<H', data, 16, 2)
            entries[member] = data
            examples['files']['native/bootstrap.so'] = hashlib.sha256(data).hexdigest()
            with zipfile.ZipFile(path, 'w') as archive:
                for name, value in entries.items():
                    archive.writestr(name, value)
            with self.assertRaisesRegex(ValueError, 'ET_DYN'):
                artifacts.package_records(root, examples)

    def test_complete_generations_bind_all_native_clients_for_every_installed_abi(self):
        for abi in ('x86', 'x86_64', 'arm64-v8a'):
            with self.subTest(abi=abi), tempfile.TemporaryDirectory() as directory:
                root = Path(directory)
                fixtures.qt4(root, abi)
                packages = artifacts.check_apks(root, abi)
                self.assertEqual(len(packages), 12)
                generation = artifacts.check_examples(root, abi)
                for package in packages:
                    self.assertEqual(package['generation'], generation['generation'])
                    self.assertEqual(package['native_sha256'], artifacts.common.digest(root / f'native/{package["profile"]}.so'))
                    self.assertEqual(package['examples_manifest_sha256'], artifacts.common.digest(root / 'examples-manifest.json'))
                self.assertEqual(artifacts.common.read_json(root / 'apk-manifest.json')['signing_inputs'],
                                 {'local-probe.jks': artifacts.common.digest(root / 'local-probe.jks')})

    def test_new_native_generation_invalidates_packages_and_preserves_saved_apks(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            fixtures.qt4(root)
            apk = (root / 'core.apk').read_bytes()
            (root / 'final-results.json').write_text('old PASS')
            artifacts.begin(root, 'x86_64', fixtures.SDK)
            for name in ('examples-manifest.json', 'apk-manifest.json', 'apk-packages.json', 'final-results.json'):
                self.assertFalse((root / name).exists(), name)
            with self.assertRaisesRegex(ValueError, 'example generation is incomplete'):
                artifacts.check_apks(root, 'x86_64')
            self.assertEqual((root / 'core.apk').read_bytes(), apk)
            # A successful native build with identical output still has a new
            # generation and must be packaged again before it can be tested.
            artifacts.finish(root, 'x86_64', fixtures.SDK)
            with self.assertRaises(FileNotFoundError):
                artifacts.check_apks(root, 'x86_64')

    def test_changed_native_manifest_same_sdk_is_not_a_current_apk_generation(self):
        for changed in ('native', 'manifest', 'report'):
            with self.subTest(changed=changed), tempfile.TemporaryDirectory() as directory:
                root = Path(directory)
                fixtures.qt4(root)
                if changed == 'native':
                    (root / 'native/core.so').write_bytes(b'new native generation')
                    manifest = artifacts.common.read_json(root / 'native/examples-build.json')
                    next(item for item in manifest['clients'] if item['profile'] == 'core')['sha256'] = artifacts.common.digest(root / 'native/core.so')
                    artifacts.common.write_json(root / 'native/examples-build.json', manifest)
                elif changed == 'manifest':
                    manifest = artifacts.common.read_json(root / 'native/examples-build.json')
                    manifest['changed_build'] = True
                    artifacts.common.write_json(root / 'native/examples-build.json', manifest)
                else:
                    (root / 'sdk-reports/new-report.txt').write_text('producer report changed')
                with self.assertRaisesRegex(ValueError, 'report set changed' if changed == 'report' else 'generation or producer reports changed'):
                    artifacts.check_apks(root, 'x86_64')

    def test_failed_partial_packaging_has_no_completed_generation(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            fixtures.qt4(root)
            old = (root / 'strict.apk').read_bytes()
            with patch.object(artifacts.common, 'packaging_inputs', return_value={'fixture': True}):
                artifacts.begin_apks(root, 'x86_64', 'sdk')
                (root / 'bootstrap.apk').write_bytes(b'partial package output')
                with self.assertRaisesRegex(ValueError, 'APK generation is incomplete'):
                    artifacts.check_apks(root, 'x86_64')
                with self.assertRaises(zipfile.BadZipFile):
                    artifacts.record_apks(root, 'x86_64', 'sdk')
            self.assertFalse((root / 'apk-manifest.json').exists())
            self.assertFalse((root / 'apk-packages.json').exists())
            self.assertTrue((root / 'apk-in-progress.json').exists())
            self.assertEqual((root / 'strict.apk').read_bytes(), old)

    def test_native_bytes_inside_apk_are_checked_even_if_outer_hash_is_updated(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            fixtures.qt4(root)
            with zipfile.ZipFile(root / 'core.apk', 'w') as archive:
                archive.writestr('lib/x86_64/libc++_shared.so', (root / 'native/libc++_shared.so').read_bytes())
                archive.writestr('lib/x86_64/libdonut_probe.so', (root / 'native/strict.so').read_bytes())
            packages = artifacts.common.read_json(root / 'apk-packages.json')
            next(item for item in packages if item['profile'] == 'core')['sha256'] = artifacts.common.digest(root / 'core.apk')
            artifacts.common.write_json(root / 'apk-packages.json', packages)
            manifest = artifacts.common.read_json(root / 'apk-manifest.json')
            manifest['packages_sha256'] = artifacts.common.digest(root / 'apk-packages.json')
            artifacts.common.write_json(root / 'apk-manifest.json', manifest)
            with self.assertRaisesRegex(ValueError, 'Packaged Qt4 native library differs'):
                artifacts.check_apks(root, 'x86_64')

    def test_changed_tools_and_signing_key_cannot_finish_packaging(self):
        for changed in ('tools', 'signing'):
            with self.subTest(changed=changed), tempfile.TemporaryDirectory() as directory:
                root = Path(directory)
                fixtures.qt4(root)
                with patch.object(artifacts.common, 'packaging_inputs', return_value={'fixture': 'before'}):
                    artifacts.begin_apks(root, 'x86_64', 'sdk')
                snapshot = {'fixture': 'after' if changed == 'tools' else 'before'}
                if changed == 'signing':
                    (root / 'local-probe.jks').write_text('replacement key')
                with patch.object(artifacts.common, 'packaging_inputs', return_value=snapshot):
                    with self.assertRaisesRegex(ValueError, 'inputs changed during packaging|signing input changed'):
                        artifacts.record_apks(root, 'x86_64', 'sdk')
                self.assertFalse((root / 'apk-manifest.json').exists())

    def test_refused_begin_does_not_invalidate_the_owner_generation(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            fixtures.qt4(root)
            artifacts.begin(root, 'x86_64', fixtures.SDK)
            (root / 'final-results.json').write_text('current owner report')
            with self.assertRaises(FileExistsError):
                artifacts.begin(root, 'x86_64', fixtures.SDK)
            self.assertEqual((root / 'final-results.json').read_text(), 'current owner report')

    def test_missing_initial_key_cannot_start_a_package_generation(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            fixtures.qt4(root)
            old = (root / 'core.apk').read_bytes()
            (root / 'local-probe.jks').unlink()
            with patch.object(artifacts.common, 'packaging_inputs', return_value={'fixture': True}):
                with self.assertRaises(FileNotFoundError):
                    artifacts.begin_apks(root, 'x86_64', 'sdk')
            self.assertFalse((root / 'apk-in-progress.json').exists())
            self.assertEqual((root / 'core.apk').read_bytes(), old)

    def test_native_api_metadata_must_match_the_selected_sdk(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            fixtures.qt4(root)
            artifacts.begin(root, 'x86_64', fixtures.SDK)
            manifest = artifacts.common.read_json(root / 'native/examples-build.json')
            manifest['api'] = 10
            artifacts.common.write_json(root / 'native/examples-build.json', manifest)
            with self.assertRaisesRegex(ValueError, 'Native generation ABI/API/SDK/runtime differs'):
                artifacts.finish(root, 'x86_64', fixtures.SDK)
            self.assertFalse((root / 'examples-manifest.json').exists())
            self.assertTrue((root / 'examples-in-progress.json').exists())

    def test_real_qt4_packaging_snapshot_tracks_java_scripts_and_tools(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            repo, sdk, jdk = root / 'repo', root / 'sdk', root / 'jdk'
            files = [repo / name for name in (
                'tests/android-donut/java/ProbeActivity.java', 'tests/android-donut/java/AndroidManifest.xml',
                'scripts/build/qt4-android/package.ps1', 'scripts/build/qt4-android/host.ps1',
                'scripts/build/qt4-android/api21.ps1', 'scripts/build/qt4-android/artifact-manifest.py',
                'scripts/build/android-api21/artifact-manifest.py')]
            files += [sdk / 'platforms/android-35/android.jar', sdk / 'build-tools/36.0.0/d8.bat',
                      jdk / 'bin/javac.exe', jdk / 'bin/keytool.exe', jdk / 'bin/java.exe', jdk / 'release', jdk / 'lib/modules']
            for path in files:
                path.parent.mkdir(parents=True, exist_ok=True)
                path.write_text('original')
            common = artifacts.common
            with patch.object(common, 'REPO', repo), patch.object(common.shutil, 'which', return_value=None), \
                    patch.object(common.subprocess, 'check_output', return_value=f'java.home = {jdk}\njavac fixture\n'), \
                    patch.dict(common.os.environ, {'JAVA_HOME': str(jdk)}):
                initial = common.packaging_inputs(4, sdk, jdk / 'bin/javac.exe')
                for path in files:
                    path.write_text('changed')
                    self.assertNotEqual(initial, common.packaging_inputs(4, sdk, jdk / 'bin/javac.exe'), str(path))
                    path.write_text('original')


if __name__ == '__main__':
    unittest.main()
