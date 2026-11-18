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


class ArtifactTests(unittest.TestCase):
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
        artifacts.record_apks(root, qt, 'arm64-v8a')

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
