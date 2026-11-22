# SPDX-License-Identifier: GPL-3.0-or-later
"""Ordinary API10 evidence finalization without an SDK, build or guest."""
import hashlib
import importlib.util
import json
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch
import zipfile

ROOT = Path(__file__).resolve().parents[2]
spec = importlib.util.spec_from_file_location('legacy', ROOT / 'scripts/build/qt5-android/collect-legacy-results.py')
legacy = importlib.util.module_from_spec(spec)
spec.loader.exec_module(legacy)


def sha(data):
    return hashlib.sha256(data).hexdigest()


class LegacyResultsTests(unittest.TestCase):
    def fixture(self, root):
        sdk = 'sha256:' + 'a' * 64
        (root / 'sdk-image-id.txt').write_text(sdk)
        elf = bytearray(20)
        elf[:6] = b'\x7fELF\x01\x01'
        elf[18] = 3
        elf = bytes(elf)
        (root / 'native').mkdir()
        (root / 'native/libc++_shared.so').write_bytes(elf)
        targets = json.loads(legacy.coverage.BASELINES.read_text())['targets']['5/10/x86']
        for app in legacy.artifacts.APPS + ['extended/qt-selftest']:
            apk = root / 'apk' / (app + '.apk')
            apk.parent.mkdir(parents=True, exist_ok=True)
            with zipfile.ZipFile(apk, 'w') as z:
                z.writestr('lib/x86/libc++_shared.so', elf)
                z.writestr('lib/x86/libexample.so', elf)
        for name, baseline in targets.items():
            name = {'widgets-gui': 'widgets-gallery-render', 'qml-gui': 'quick-qml-gallery-render'}.get(name, name)
            case = root / 'run' / name
            (case / 'files').mkdir(parents=True)
            stdout = '\n'.join('PASS: ' + check for check in baseline.get('required_pass', []))
            stdout += f'\n---- fixture: {baseline["min_pass"]} passed, 0 failed, {baseline["max_skip"]} skipped ----\n'
            (case / 'files/selftest.stdout').write_text(stdout)
            (case / 'files/selftest-result.txt').write_text('0')
            (case / 'logcat.log').write_text('native returned zero')
            (case / 'power-before.txt').write_text('mStayOnConditions=3\n')
            (case / 'guest.txt').write_text('ro.build.version.sdk=10\nro.product.cpu.abi=x86\nro.build.version.release=2.3.7\n')
            relative = {'atomic-cow': 'qt-selftest', 'strict-cxx23': 'qt-selftest', 'strict-cxx23-extended': 'extended/qt-selftest',
                        'qt-selftest-extended': 'extended/qt-selftest', 'widgets-gallery-render': 'widgets-gallery',
                        'quick-qml-gallery-render': 'quick-qml-gallery'}.get(name, name)
            receipt = {'completed': True, 'case': name, 'sdk_image_id': sdk, 'abi': 'x86', 'api': 10,
                       'emulator_sha256': 'c' * 64,
                       'apk_sha256': sha((root / 'apk' / (relative + '.apk')).read_bytes()),
                       'stdout_sha256': sha((case / 'files/selftest.stdout').read_bytes()),
                       'guest_power_sha256': sha((case / 'power-before.txt').read_bytes())}
            (case / 'input-receipt.json').write_text(json.dumps(receipt))

    def test_complete_and_changed_launch_inputs(self):
        with tempfile.TemporaryDirectory() as tmp, patch.object(legacy.artifacts, 'check_apks'), patch.object(legacy.subprocess, 'run'), patch('builtins.print'):
            root = Path(tmp)
            self.fixture(root)
            self.assertEqual(legacy.collect(root, 'run', 'x86')['required_cases'], 14)
            path = root / 'run/qt-selftest/input-receipt.json'
            receipt = json.loads(path.read_text())
            receipt['apk_sha256'] = 'b' * 64
            path.write_text(json.dumps(receipt))
            with self.assertRaisesRegex(ValueError, 'launch receipt'):
                legacy.collect(root, 'run', 'x86')
            for name in ('final-results.json', 'final-results-table.md', 'apk-native-abi-check.json'):
                self.assertFalse((root / name).exists(), name)

    def test_preflight_and_emulator_identity_are_required(self):
        for changed in ('missing-preflight', 'different-emulator'):
            with self.subTest(changed=changed), tempfile.TemporaryDirectory() as tmp, patch.object(legacy.artifacts, 'check_apks'), patch.object(legacy.subprocess, 'run'), patch('builtins.print'):
                root = Path(tmp)
                self.fixture(root)
                if changed == 'missing-preflight':
                    (root / 'run/atomic-cow/input-receipt.json').unlink()
                else:
                    path = root / 'run/qt-selftest/input-receipt.json'
                    receipt = json.loads(path.read_text())
                    receipt['emulator_sha256'] = 'd' * 64
                    path.write_text(json.dumps(receipt))
                with self.assertRaises((ValueError, FileNotFoundError)):
                    legacy.collect(root, 'run', 'x86')
                self.assertFalse((root / 'final-results.json').exists())

    def test_report_and_cleanup_are_required(self):
        for changed in ('stdout', 'logcat', 'power'):
            with self.subTest(changed=changed), tempfile.TemporaryDirectory() as tmp, patch.object(legacy.artifacts, 'check_apks'), patch.object(legacy.subprocess, 'run'):
                root = Path(tmp)
                self.fixture(root)
                path = root / 'run/qt-selftest' / {'stdout': 'files/selftest.stdout', 'logcat': 'logcat.log', 'power': 'power-before.txt'}[changed]
                path.write_text({'stdout': 'changed report', 'logcat': 'Fatal signal 11', 'power': 'mStayOnConditions=1'}[changed])
                with self.assertRaises(ValueError):
                    legacy.collect(root, 'run', 'x86')


if __name__ == '__main__':
    unittest.main()
