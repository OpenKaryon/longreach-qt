# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2026 OpenKaryon
"""Ordinary artifact-generation regressions; no builds, SDK, emulator or network."""
import importlib.util
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[2]
spec = importlib.util.spec_from_file_location('artifacts', ROOT / 'scripts/build/android-api21/artifact-manifest.py')
artifacts = importlib.util.module_from_spec(spec)
spec.loader.exec_module(artifacts)
SDK = 'sha256:' + 'a' * 64
PACKAGING_INPUTS = artifacts.packaging_inputs


class ArtifactTests(unittest.TestCase):
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
        runtime.write_text('matching runtime')
        artifacts.begin(root, qt, 'arm64-v8a', SDK)
        artifacts.finish(root, qt, 'arm64-v8a', SDK)
        for name in artifacts.apk_paths(qt):
            path = root / name
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_text(name)
        artifacts.begin_apks(root, qt, 'arm64-v8a', 'fixture-sdk')
        artifacts.record_apks(root, qt, 'arm64-v8a', 'fixture-sdk')

    def deployment(self, root, directory, app):
        for relative in (f'libs/arm64-v8a/lib{app}_arm64-v8a.so', 'res/values/libs.xml'):
            path = root / directory / relative
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_text(app)

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
            (root / 'sdk-modules.txt').write_text('another SDK')
            with self.assertRaisesRegex(ValueError, 'producer reports differ'):
                artifacts.check_apks(root, 6, 'arm64-v8a')

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
            for p in (java, script, jar, tool, javac, keytool, modules, sdk / 'platforms/android-35/framework.aidl'):
                p.parent.mkdir(parents=True, exist_ok=True)
                p.write_text('original')
            # The setup-wide packaging mock is bypassed for this direct snapshot test.
            real = PACKAGING_INPUTS
            with patch.object(artifacts, 'REPO', repo), patch.object(artifacts.subprocess, 'check_output', return_value='javac 21'), patch.object(artifacts.shutil, 'which', return_value=None), patch.dict(artifacts.os.environ, {'JAVA_HOME': str(root / 'jdk')}):
                initial = real(6, sdk, javac)
                for p in (java, script, jar, tool, javac, keytool, modules):
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
