# SPDX-License-Identifier: GPL-3.0-or-later
"""API4 file provenance fixtures only; no JVM, compiler, Docker or guest executes."""
import importlib.util
import json
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch
import uuid
import zipfile

import android_native_abi_fixtures as elf

ROOT = Path(__file__).resolve().parents[2]
spec = importlib.util.spec_from_file_location('donut_test', ROOT / 'scripts/build/qt4-android/donut-artifacts.py')
donut = importlib.util.module_from_spec(spec)
spec.loader.exec_module(donut)
IMAGE = 'sha256:' + 'd' * 64


class DonutArtifacts(unittest.TestCase):
    def setUp(self):
        temporary = tempfile.TemporaryDirectory(prefix='longreach-donut-')
        self.addCleanup(temporary.cleanup)
        self.base = Path(temporary.name)
        self.repo, self.inputs, self.root = [self.base / name for name in ('repo', 'inputs', 'artifacts')]
        self.root.mkdir()
        self.inputs.mkdir()
        for relative in donut.SOURCE_TREES:
            path = self.repo / relative / 'fixture.txt'
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_text(relative)
        for relative in (*donut.SOURCE_FILES, 'scripts/build/qt4-android/package.ps1',
                         'scripts/build/qt4-android/host.ps1', 'scripts/build/qt4-android/donut-artifacts.py',
                         'scripts/build/android-api21/packaging-host.ps1', 'scripts/build/android-api21/host-tools.py',
                         'scripts/build/android-api21/artifact-manifest.py', 'scripts/build/android-api21/native-abi.py',
                         'tests/android-donut/java/ProbeActivity.java'):
            path = self.repo / relative
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_text('fixture source/' + relative)
        pins = {}
        for relative in donut.ARCHIVES:
            path = self.inputs / relative.split('/', 1)[1] if relative.startswith('android-inputs/') else self.repo / relative
            path.parent.mkdir(parents=True, exist_ok=True)
            if path.suffix == '.zip':
                with zipfile.ZipFile(path, 'w') as archive:
                    archive.writestr(donut.JAR_MEMBER, b'API4 platform fixture')
            else:
                path.write_bytes(relative.encode())
            pins[relative] = donut.common.digest(path)
        for context in (patch.dict(donut.ARCHIVES, pins, clear=True), patch.object(donut.common, 'REPO', self.repo),
                        patch.object(donut.common._host_tools, 'snapshot', side_effect=self.host_snapshot)):
            context.start()
            self.addCleanup(context.stop)
        self.jar = self.base / 'android.jar'
        self.jar.write_bytes(b'API4 platform fixture')
        self.sdk = self.base / 'sdk'
        self.sdk.mkdir()
        self.javac = self.base / 'javac.exe'
        self.javac.write_bytes(b'never executed')

    def host_snapshot(self, sdk, javac, *, android_jar):
        self.assertEqual(Path(android_jar), self.jar)
        return {'schema_version': 2, 'tool_sha256': {'android-platform/android.jar': donut.common.digest(Path(android_jar)), 'fixture_compiler': donut.common.digest(Path(javac))}}

    def start_native(self):
        return donut.begin(self.root, self.repo, self.inputs)

    def stage_native(self):
        stage = self.root / ('native-build-' + uuid.uuid4().hex)
        stage.mkdir()
        for profile in donut.PROFILES:
            (stage / (profile + '.so')).write_bytes(elf.elf('armeabi', profile.encode()))
            (stage / (profile + '-elf.txt')).write_text('synthetic ELF report/' + profile)
        (stage / 'libQtCore.a').write_bytes(b'!<arch>\nSYNTHETIC')
        return stage

    def complete_native(self):
        self.start_native()
        return donut.finish_native(self.root, self.repo, self.inputs, self.stage_native(), IMAGE)

    def start_apks(self):
        (self.root / 'local-probe.jks').write_bytes(b'data-only signing key')
        donut.begin_apks(self.root, self.sdk, self.jar, self.javac)

    def write_apks(self):
        for profile in donut.PROFILES:
            with zipfile.ZipFile(self.root / (profile + '.apk'), 'w') as archive:
                archive.writestr('lib/armeabi/libdonut_probe.so', (self.root / 'native' / (profile + '.so')).read_bytes())
                archive.writestr('AndroidManifest.xml', b'fixture')
                archive.writestr('classes.dex', b'fixture')
            (self.root / (profile + '.apk.badging.txt')).write_text("sdkVersion:'4'\nnative-code: 'armeabi'\n")

    def complete(self):
        self.complete_native()
        self.start_apks()
        self.write_apks()
        return donut.record_apks(self.root, self.sdk, self.jar, self.javac)

    def test_complete_eight_client_generation_and_exact_apk_jni_binding(self):
        receipt = self.complete()
        self.assertEqual(receipt, donut.check_apks(self.root))
        self.assertEqual([p['profile'] for p in receipt['packages']], list(donut.PROFILES))
        self.assertEqual(donut.check_native(self.root)['tool_image_id'], IMAGE)
        for name in (donut.NATIVE_PENDING, donut.APK_PENDING):
            self.assertFalse((self.root / name).exists())

    def test_failed_reservation_preserves_owner_reports_and_prior_receipts(self):
        self.complete()
        native = (self.root / donut.NATIVE_MANIFEST).read_bytes()
        self.start_native()
        report = self.root / 'final-results.json'
        report.write_text('active owner report')
        with self.assertRaises(FileExistsError):
            self.start_native()
        self.assertEqual(report.read_text(), 'active owner report')
        self.assertEqual((self.root / donut.NATIVE_MANIFEST).read_bytes(), native)
        with self.assertRaisesRegex(ValueError, 'native generation is incomplete'):
            donut.check_apks(self.root)

    def test_new_generation_clears_all_five_aggregate_reports(self):
        for name in ('final-results.json', 'final-results-table.md', 'apk-native-abi-check.json', 'apk-architecture-final.json', 'screenshots.json'):
            (self.root / name).write_text('old PASS')
        self.start_native()
        self.assertEqual(list(self.root.glob('final-results*')), [])
        self.assertFalse((self.root / 'screenshots.json').exists())
        self.assertFalse((self.root / 'apk-native-abi-check.json').exists())
        self.assertFalse((self.root / 'apk-architecture-final.json').exists())

    def test_stale_old_output_cannot_fill_a_missing_fresh_stage_client(self):
        self.complete()
        old = (self.root / 'native/graphics.so').read_bytes()
        self.start_native()
        stage = self.stage_native()
        (stage / 'graphics.so').unlink()
        with self.assertRaisesRegex(ValueError, 'exactly eight'):
            donut.finish_native(self.root, self.repo, self.inputs, stage, IMAGE)
        self.assertEqual((self.root / 'native/graphics.so').read_bytes(), old)
        self.assertTrue((self.root / donut.NATIVE_PENDING).exists())

    def test_changed_recipe_fails_before_native_promotion(self):
        self.start_native()
        stage = self.stage_native()
        (self.repo / 'tests/qt-selftest/fixture.txt').write_text('changed during compile')
        with self.assertRaisesRegex(ValueError, 'inputs changed during'):
            donut.finish_native(self.root, self.repo, self.inputs, stage, IMAGE)
        self.assertFalse((self.root / 'native').exists())

    def test_unpinned_archive_refuses_before_reservation(self):
        (self.inputs / 'aosp-ndk-r7-api4-arm.tar.gz').write_text('changed')
        with self.assertRaisesRegex(ValueError, 'Unpinned API4 archive'):
            self.start_native()
        self.assertFalse((self.root / donut.NATIVE_PENDING).exists())

    def test_native_history_retains_old_bytes_and_both_receipts(self):
        self.complete()
        old = {name: (self.root / name).read_bytes() for name in (donut.NATIVE_MANIFEST, donut.APK_MANIFEST)}
        before = (self.root / 'native/core.so').read_bytes()
        self.start_native()
        stage = self.stage_native()
        (stage / 'core.so').write_bytes(elf.elf('armeabi', b'new core generation'))
        donut.finish_native(self.root, self.repo, self.inputs, stage, IMAGE)
        histories = list((self.root / 'native-history').iterdir())
        self.assertEqual(len(histories), 1)
        self.assertEqual((histories[0] / 'native/core.so').read_bytes(), before)
        for name, data in old.items():
            self.assertEqual((histories[0] / name).read_bytes(), data)
        self.assertFalse((self.root / donut.APK_MANIFEST).exists())

    def test_publication_failure_keeps_pending_and_retains_old_generation(self):
        self.complete()
        previous = (self.root / 'native/core.so').read_bytes()
        self.start_native()
        stage = self.stage_native()
        with patch.object(donut.common, 'write_json', side_effect=RuntimeError('recorded publication failure')):
            with self.assertRaisesRegex(RuntimeError, 'publication failure'):
                donut.finish_native(self.root, self.repo, self.inputs, stage, IMAGE)
        self.assertTrue((self.root / donut.NATIVE_PENDING).exists())
        with self.assertRaisesRegex(ValueError, 'native generation is incomplete'):
            donut.check_apks(self.root)
        histories = list((self.root / 'native-history').iterdir())
        self.assertEqual((histories[0] / 'native/core.so').read_bytes(), previous)

    def test_changed_native_report_or_library_or_missing_provenance_is_rejected(self):
        self.complete()
        for relative in ('native/selftest.so', 'native/core-elf.txt', 'native/libQtCore.a'):
            path = self.root / relative
            previous = path.read_bytes()
            path.write_bytes(previous + b'changed')
            with self.subTest(relative=relative), self.assertRaisesRegex(ValueError, 'native files/reports changed'):
                donut.check_apks(self.root)
            path.write_bytes(previous)
        path = self.root / donut.NATIVE_MANIFEST
        value = donut.common.read_json(path)
        value['inputs']['sources'] = {}
        donut.common.write_json(path, value)
        with self.assertRaisesRegex(ValueError, 'Incomplete API4 recipe'):
            donut.check_native(self.root)

    def test_matching_outer_digest_does_not_accept_another_native_client(self):
        self.complete()
        with zipfile.ZipFile(self.root / 'bootstrap.apk', 'w') as archive:
            archive.writestr('lib/armeabi/libdonut_probe.so', (self.root / 'native/core.so').read_bytes())
            archive.writestr('AndroidManifest.xml', b'fixture')
            archive.writestr('classes.dex', b'fixture')
        receipt = donut.common.read_json(self.root / donut.APK_MANIFEST)
        receipt['packages'][0]['sha256'] = donut.common.digest(self.root / 'bootstrap.apk')
        donut.common.write_json(self.root / donut.APK_MANIFEST, receipt)
        with self.assertRaisesRegex(ValueError, 'JNI differs from native'):
            donut.check_apks(self.root)

    def test_packaging_input_drift_preserves_pending_state(self):
        self.complete_native()
        self.start_apks()
        self.write_apks()
        for path in (self.javac, self.root / 'local-probe.jks', self.repo / 'tests/android-donut/java/ProbeActivity.java'):
            previous = path.read_bytes()
            path.write_bytes(previous + b' changed')
            with self.subTest(path=path.name), self.assertRaisesRegex(ValueError, 'packaging or signing input changed'):
                donut.record_apks(self.root, self.sdk, self.jar, self.javac)
            self.assertTrue((self.root / donut.APK_PENDING).exists())
            self.assertFalse((self.root / donut.APK_MANIFEST).exists())
            path.write_bytes(previous)
        donut.record_apks(self.root, self.sdk, self.jar, self.javac)

    def test_unpinned_extracted_jar_and_incomplete_apk_cannot_complete(self):
        self.complete_native()
        self.jar.write_bytes(b'wrong extracted platform')
        with self.assertRaisesRegex(ValueError, 'android.jar differs'):
            self.start_apks()
        self.assertFalse((self.root / donut.APK_PENDING).exists())
        self.jar.write_bytes(b'API4 platform fixture')
        self.start_apks()
        self.write_apks()
        with zipfile.ZipFile(self.root / 'bootstrap.apk', 'w') as archive:
            archive.writestr('lib/armeabi/libdonut_probe.so', (self.root / 'native/bootstrap.so').read_bytes())
        with self.assertRaisesRegex(ValueError, 'Unexpected API4 APK members'):
            donut.record_apks(self.root, self.sdk, self.jar, self.javac)

    def test_missing_packaging_provenance_is_not_a_completed_generation(self):
        self.complete()
        path = self.root / donut.APK_MANIFEST
        original = donut.common.read_json(path)
        for field in ('packaging_inputs', 'signing_inputs'):
            changed = dict(original)
            changed.pop(field)
            donut.common.write_json(path, changed)
            with self.subTest(field=field), self.assertRaisesRegex(ValueError, 'Incomplete API4 packaging'):
                donut.check_apks(self.root)

    def test_cli_refuses_another_process_artifact_lease_before_reading_inputs(self):
        with donut.common.artifact_lease(self.root):
            result = subprocess.run([sys.executable, str(ROOT / 'scripts/build/qt4-android/donut-artifacts.py'),
                                     'check-apks', '--root', str(self.root)], capture_output=True, text=True, timeout=10)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('Another Longreach operation', result.stderr)
        self.assertFalse((self.root / donut.NATIVE_PENDING).exists())


if __name__ == '__main__':
    unittest.main()
