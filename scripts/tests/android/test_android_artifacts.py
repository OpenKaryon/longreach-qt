# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2026 OpenKaryon
"""Ordinary artifact-generation regressions; no builds, SDK, emulator or network."""
import importlib.util
import json
from pathlib import Path
import struct
import tempfile
import unittest
import zipfile
import android_native_abi_fixtures as native_fixtures
from unittest.mock import patch
import android_sdk_report_fixtures as sdk_reports

ROOT = Path(__file__).resolve().parents[3]
spec = importlib.util.spec_from_file_location('artifacts', ROOT / 'scripts/build/android-api21/artifact-manifest.py')
artifacts = importlib.util.module_from_spec(spec)
spec.loader.exec_module(artifacts)
SDK = 'sha256:' + 'a' * 64
PACKAGING_INPUTS = artifacts.packaging_inputs


class ArtifactTests(unittest.TestCase):
    def test_native_abi_is_checked_at_packaging_and_even_after_a_matching_outer_digest(self):
        for qt in (5, 6):
            for phase in ('record', 'check'):
                with self.subTest(qt=qt, phase=phase), tempfile.TemporaryDirectory() as directory:
                    root = Path(directory)
                    self.fixture(root, qt)
                    relative = 'apk/qt-selftest.apk'
                    path = root / relative
                    with zipfile.ZipFile(path) as archive:
                        entries = {name: archive.read(name) for name in archive.namelist()}
                    data = bytearray(entries['lib/arm64-v8a/libfixture.so'])
                    struct.pack_into('<H', data, 16, 1)
                    entries['lib/arm64-v8a/libfixture.so'] = data
                    if phase == 'record':
                        artifacts.begin_apks(root, qt, 'arm64-v8a', 'fixture-sdk')
                    with zipfile.ZipFile(path, 'w') as archive:
                        for name, value in entries.items():
                            archive.writestr(name, value)
                    if phase == 'check':
                        manifest = root / 'apk-manifest.json'
                        receipt = json.loads(manifest.read_text())
                        receipt['files'][relative] = artifacts.digest(path)
                        manifest.write_text(json.dumps(receipt))
                    with self.assertRaisesRegex(ValueError, 'ET_DYN'):
                        if phase == 'record':
                            artifacts.record_apks(root, qt, 'arm64-v8a', 'fixture-sdk')
                        else:
                            artifacts.check_apks(root, qt, 'arm64-v8a')
                    if phase == 'record':
                        self.assertTrue((root / 'apk-in-progress.json').exists())
                        self.assertFalse((root / 'apk-manifest.json').exists())

    def setUp(self):
        stub = patch.object(artifacts, 'packaging_inputs', return_value={'java': 'fixture', 'tools': 'fixture'})
        stub.start()
        self.addCleanup(stub.stop)

    def fixture(self, root, qt):
        for app in artifacts.APPS:
            self.deployment(root, f'deployment/{app}', app)
        if qt == 5:
            self.deployment(root, 'deployment-extended/qt-selftest', 'qt-selftest')
        packaging = 'sdk-packaging' if qt == 6 else 'sdk'
        for relative in ('jar/QtAndroid.jar', 'src/android/java/src/Qt.java', 'src/android/java/res/values/strings.xml'):
            path = root / packaging / relative
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_text('java fixture')
        runtime = root / ('libc++_shared.so' if qt == 6 else 'native/libc++_shared.so')
        runtime.parent.mkdir(parents=True, exist_ok=True)
        runtime.write_bytes(native_fixtures.elf('arm64-v8a', b'matching runtime'))
        sdk_reports.export(root, qt, 'arm64-v8a', SDK, runtime.read_bytes())
        artifacts.begin(root, qt, 'arm64-v8a', SDK)
        artifacts.finish(root, qt, 'arm64-v8a', SDK)
        for name in artifacts.apk_paths(qt):
            path = root / name
            path.parent.mkdir(parents=True, exist_ok=True)
            with zipfile.ZipFile(path, 'w') as archive:
                archive.writestr('lib/arm64-v8a/libfixture.so', native_fixtures.elf('arm64-v8a', name.encode()))
                archive.writestr('lib/arm64-v8a/libc++_shared.so', runtime.read_bytes())
        for name in ('apk/local-examples.jks', *(['apk/extended/local-examples.jks'] if qt == 5 else [])):
            (root / name).write_text('fixture initial key')
        artifacts.begin_apks(root, qt, 'arm64-v8a', 'fixture-sdk')
        artifacts.record_apks(root, qt, 'arm64-v8a', 'fixture-sdk')

    def deployment(self, root, directory, app):
        for relative in (f'libs/arm64-v8a/lib{app}_arm64-v8a.so', 'res/values/libs.xml'):
            path = root / directory / relative
            path.parent.mkdir(parents=True, exist_ok=True)
            if path.suffix == '.so':
                path.write_bytes(native_fixtures.elf('arm64-v8a', app.encode()))
            else:
                path.write_text(app)

    def test_native_and_apk_generations_invalidate_previous_aggregate_success(self):
        reports = ('final-results.json', 'final-results-table.md', 'apk-native-abi-check.json',
                   'apk-architecture-final.json', 'screenshots.json')
        for qt in (5, 6):
            for phase in ('native', 'apk'):
                with self.subTest(qt=qt, phase=phase), tempfile.TemporaryDirectory() as directory:
                    root = Path(directory)
                    self.fixture(root, qt)
                    for name in reports:
                        (root / name).write_text('old successful run')
                    old_apk = root / 'apk/qt-selftest.apk'
                    old_bytes = old_apk.read_bytes()
                    if phase == 'native':
                        artifacts.begin(root, qt, 'arm64-v8a', SDK)
                    else:
                        artifacts.begin_apks(root, qt, 'arm64-v8a', 'fixture-sdk')
                    self.assertFalse(any((root / name).exists() for name in reports))
                    self.assertEqual(old_apk.read_bytes(), old_bytes)

    def test_refused_generation_does_not_clear_the_active_owners_reports(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            artifacts.begin(root, 6, 'arm64-v8a', SDK)
            (root / 'final-results.json').write_text('owner report')
            with self.assertRaisesRegex(ValueError, 'incomplete example generation'):
                artifacts.begin(root, 6, 'arm64-v8a', SDK)
            self.assertEqual((root / 'final-results.json').read_text(), 'owner report')
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            self.fixture(root, 6)
            artifacts.begin_apks(root, 6, 'arm64-v8a', 'fixture-sdk')
            (root / 'final-results.json').write_text('APK owner report')
            with self.assertRaisesRegex(ValueError, 'incomplete APK generation'):
                artifacts.begin_apks(root, 6, 'arm64-v8a', 'fixture-sdk')
            self.assertEqual((root / 'final-results.json').read_text(), 'APK owner report')

    def test_completed_qt5_and_qt6_generations(self):
        for qt in (5, 6):
            with self.subTest(qt=qt), tempfile.TemporaryDirectory() as directory:
                root = Path(directory)
                self.fixture(root, qt)
                artifacts.check_examples(root, qt, 'arm64-v8a')
                artifacts.check_apks(root, qt, 'arm64-v8a')
                # Test mode consumes saved APKs and metadata, not SDK/deployment trees.
                (root / 'deployment/qt-selftest/libs/arm64-v8a/libqt-selftest_arm64-v8a.so').unlink()
                artifacts.check_apks(root, qt, 'arm64-v8a')

    def test_failed_rebuild_refuses_old_packages(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            self.fixture(root, 6)
            artifacts.begin(root, 6, 'arm64-v8a', SDK)
            (root / 'deployment/qt-selftest/libs/arm64-v8a/libqt-selftest_arm64-v8a.so').write_text('first new app')
            for check in (artifacts.check_examples, artifacts.check_apks):
                with self.assertRaisesRegex(ValueError, 'incomplete'):
                    check(root, 6, 'arm64-v8a')
            self.assertTrue((root / 'apk/qt-selftest.apk').is_file())

    def test_changed_runtime_java_or_dependency_is_refused(self):
        for relative in ('libc++_shared.so', 'sdk-packaging/jar/QtAndroid.jar',
                         'deployment/network-gui/libs/arm64-v8a/libnetwork-gui_arm64-v8a.so'):
            with self.subTest(relative=relative), tempfile.TemporaryDirectory() as directory:
                root = Path(directory)
                self.fixture(root, 6)
                (root / relative).write_text('different generation')
                with self.assertRaisesRegex(ValueError, 'bytes changed'):
                    artifacts.check_examples(root, 6, 'arm64-v8a')

    def test_sdk_or_abi_mismatch_is_refused(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            self.fixture(root, 6)
            with self.assertRaisesRegex(ValueError, 'SDK/ABI'):
                artifacts.check_apks(root, 6, 'x86_64')
            (root / 'sdk-image-id.txt').write_text('sha256:' + 'b' * 64)
            with self.assertRaisesRegex(ValueError, 'identities differ'):
                artifacts.check_examples(root, 6, 'arm64-v8a')

    def test_incomplete_or_changed_apk_set_is_refused(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            self.fixture(root, 5)
            path = root / 'apk/extended/qt-selftest.apk'
            path.write_text('replaced after packaging')
            with self.assertRaisesRegex(ValueError, 'APK bytes changed'):
                artifacts.check_apks(root, 5, 'arm64-v8a')
            path.unlink()
            with self.assertRaises(FileNotFoundError):
                artifacts.record_apks(root, 5, 'arm64-v8a')

    def test_old_apks_cannot_follow_new_generation(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            self.fixture(root, 6)
            old = (root / 'apk-manifest.json').read_bytes()
            artifacts.begin(root, 6, 'arm64-v8a', SDK)
            artifacts.finish(root, 6, 'arm64-v8a', SDK)
            (root / 'apk-manifest.json').write_bytes(old)
            with self.assertRaisesRegex(ValueError, 'different or incomplete'):
                artifacts.check_apks(root, 6, 'arm64-v8a')

    def test_package_failure_has_no_ready_apk_generation(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            self.fixture(root, 6)
            (root / 'apk-manifest.json').unlink()
            (root / 'apk/qt-selftest.apk').write_text('first new APK')
            with self.assertRaises(FileNotFoundError):
                artifacts.check_apks(root, 6, 'arm64-v8a')

    def test_source_change_during_build_leaves_generation_incomplete(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            with patch.object(artifacts, 'build_sources', side_effect=[{'app.cpp': 'before'}, {'app.cpp': 'after'}]):
                artifacts.begin(root, 6, 'arm64-v8a', SDK)
                with self.assertRaisesRegex(ValueError, 'inputs changed'):
                    artifacts.finish(root, 6, 'arm64-v8a', SDK)
            self.assertTrue((root / 'examples-in-progress.json').is_file())
            self.assertFalse((root / 'examples-manifest.json').exists())

    def test_incomplete_generation_cannot_be_overwritten(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            artifacts.begin(root, 6, 'arm64-v8a', SDK)
            with self.assertRaisesRegex(ValueError, 'already exists'):
                artifacts.begin(root, 6, 'arm64-v8a', SDK)

    def test_java_can_be_repackaged_without_rebuilding_native_inputs(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            self.fixture(root, 6)
            native = (root / 'examples-manifest.json').read_bytes()
            with patch.object(artifacts, 'packaging_inputs', return_value={'java': 'new-java', 'tools': 'fixture'}):
                artifacts.begin_apks(root, 6, 'arm64-v8a', 'sdk')
                result = artifacts.record_apks(root, 6, 'arm64-v8a', 'sdk')
            self.assertEqual(native, (root / 'examples-manifest.json').read_bytes())
            self.assertEqual(result['packaging_inputs']['java'], 'new-java')

    def test_inputs_changing_during_packaging_are_refused(self):
        for field in ('java', 'tools'):
            with self.subTest(field=field), tempfile.TemporaryDirectory() as directory:
                root = Path(directory)
                self.fixture(root, 6)
                artifacts.begin_apks(root, 6, 'arm64-v8a', 'sdk')
                with patch.object(artifacts, 'packaging_inputs', return_value={field: 'changed'}):
                    with self.assertRaisesRegex(ValueError, 'changed during packaging'):
                        artifacts.record_apks(root, 6, 'arm64-v8a', 'sdk')
                self.assertFalse((root / 'apk-manifest.json').exists())

    def test_producer_reports_are_bound_to_apks(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            self.fixture(root, 6)
            source = root / sdk_reports.FIXTURE_SOURCE
            (source / 'sdk-modules.txt').write_text('another SDK')
            sdk_reports.reports.seal(source, 6, 'arm64-v8a')
            sdk_reports.reports.export(source, root, 6, 'arm64-v8a', SDK)
            with self.assertRaisesRegex(ValueError, 'producer reports differ'):
                artifacts.check_apks(root, 6, 'arm64-v8a')

    def test_missing_initial_keys_refuse_begin_and_clear_old_aggregate(self):
        for qt in (5, 6):
            names = ['apk/local-examples.jks'] + (['apk/extended/local-examples.jks'] if qt == 5 else [])
            for name in names:
                with self.subTest(qt=qt, key=name), tempfile.TemporaryDirectory() as directory:
                    root = Path(directory)
                    self.fixture(root, qt)
                    old_apk = (root / 'apk/qt-selftest.apk').read_bytes()
                    (root / name).unlink()
                    (root / 'final-results.json').write_text('previous PASS')
                    with self.assertRaisesRegex(ValueError, 'Missing initial signing key'):
                        artifacts.begin_apks(root, qt, 'arm64-v8a', 'fixture-sdk')
                    self.assertFalse((root / 'apk-in-progress.json').exists())
                    self.assertFalse((root / 'final-results.json').exists())
                    self.assertEqual((root / 'apk/qt-selftest.apk').read_bytes(), old_apk)

    def test_signing_set_cannot_change_or_grow_after_begin(self):
        for qt in (5, 6):
            for changed in ('existing', 'extra'):
                with self.subTest(qt=qt, changed=changed), tempfile.TemporaryDirectory() as directory:
                    root = Path(directory)
                    self.fixture(root, qt)
                    artifacts.begin_apks(root, qt, 'arm64-v8a', 'fixture-sdk')
                    (root / ('apk/local-examples.jks' if changed == 'existing' else 'apk/unrecorded.jks')).write_text('new key bytes')
                    with self.assertRaisesRegex(ValueError, 'Signing input changed'):
                        artifacts.record_apks(root, qt, 'arm64-v8a', 'fixture-sdk')
                    self.assertFalse((root / 'apk-manifest.json').exists())
                    self.assertTrue((root / 'apk-in-progress.json').exists())

    def test_real_packaging_snapshot_tracks_java_scripts_and_tools(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            sdk = root / 'android-sdk'
            repo = root / 'repo'
            java = repo / 'tests/android/java-qt6/SmokeActivity.java'
            script = repo / 'scripts/build/qt6-android/package.ps1'
            jar = sdk / 'platforms/android-35/android.jar'
            tool = sdk / 'build-tools/36.0.0/aapt.exe'
            javac = root / 'jdk/bin/javac.exe'
            keytool = root / 'jdk/bin/keytool.exe'
            modules = root / 'jdk/lib/modules'
            policy = repo / 'scripts/fetch/locks/android-windows-host-tools.json'
            for p in (java, script, policy, jar, tool, javac, keytool, modules, root / 'jdk/release', root / 'jdk/bin/java.exe', sdk / 'platforms/android-35/framework.aidl'):
                p.parent.mkdir(parents=True, exist_ok=True)
                p.write_text('original')
            # The setup-wide packaging mock is bypassed for this direct snapshot test.
            real = PACKAGING_INPUTS
            # Synthetic provenance inputs are independent of the tested Windows release.
            with patch.object(artifacts._host_tools, 'is_windows_host', return_value=False), patch.object(artifacts, 'REPO', repo), patch.object(artifacts.subprocess, 'check_output', return_value=f'java.home = {root / "jdk"}\njavac 21\n'), patch.object(artifacts.shutil, 'which', return_value=None), patch.dict(artifacts.os.environ, {'JAVA_HOME': str(root / 'jdk')}):
                initial = real(6, sdk, javac)
                for p in (java, script, policy, jar, tool, javac, keytool, modules):
                    p.write_text('changed')
                    self.assertNotEqual(initial, real(6, sdk, javac), str(p))
                    p.write_text('original')

    def test_apk_digest_rejects_linked_file(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            target = root / 'real.apk'
            target.write_text('bytes')
            link = root / 'linked.apk'
            try:
                link.symlink_to(target)
            except OSError:
                self.skipTest('host does not permit symbolic links')
            with self.assertRaisesRegex(ValueError, 'Linked APK'):
                artifacts.apk_digest(root, 'linked.apk')

    def test_finish_rejects_missing_app_and_wrong_sdk(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            artifacts.begin(root, 6, 'arm64-v8a', SDK)
            with self.assertRaisesRegex(ValueError, 'Missing completed deployment'):
                artifacts.finish(root, 6, 'arm64-v8a', SDK)
            with self.assertRaisesRegex(ValueError, 'selected SDK'):
                artifacts.finish(root, 6, 'arm64-v8a', 'sha256:' + 'b' * 64)


if __name__ == '__main__':
    unittest.main()
