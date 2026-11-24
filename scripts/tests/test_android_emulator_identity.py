# SPDX-License-Identifier: GPL-3.0-or-later
"""Invocation/media identity fixtures without Android or native execution."""
import json
from pathlib import Path
import tempfile
import unittest

import android_media_fixtures as fixtures


class Identity(unittest.TestCase):
    def test_captures_all_abis_and_allows_mutable_runtime_userdata(self):
        for abi in fixtures.media.ABIS:
            with self.subTest(abi=abi), tempfile.TemporaryDirectory() as directory:
                root = Path(directory)
                result = fixtures.launch(root, abi)
                run = root / 'fixture-run'
                (run / 'userdata-qemu.img').write_text('normal guest disk writes')
                self.assertEqual(fixtures.identity.validate(root, run, abi, root / 'fixture-media-repo'), result)
                self.assertEqual(result['emulator_identity']['cpu_model'], fixtures.identity.CPU[abi][0])
                self.assertGreaterEqual(len(result['emulator_identity']['files']), 5)

    def test_changed_media_engine_or_config_cannot_reuse_identity(self):
        for change in ('system', 'engine', 'dependency', 'config'):
            with self.subTest(change=change), tempfile.TemporaryDirectory() as directory:
                root = Path(directory)
                fixtures.launch(root, 'x86')
                run = root / 'fixture-run'
                ready = json.loads((run / 'emulator-media.json').read_text())
                path = {'system': root / 'media' / ready['roles']['system'],
                        'engine': root / 'media' / ready['roles']['engine_candidates'][0],
                        'dependency': root / 'media/emulator-32.1.11/emulator/lib64/fixture.dll',
                        'config': run / 'emulator-config-input.ini'}[change]
                path.write_text('changed bytes')
                with self.assertRaisesRegex(ValueError, 'bytes or inventory changed|input snapshot changed'):
                    fixtures.identity.validate(root, run, 'x86', root / 'fixture-media-repo')

    def test_wrong_cpu_and_media_argv_are_rejected_even_with_rebound_receipts(self):
        for change in ('cpu', 'kernel'):
            with self.subTest(change=change), tempfile.TemporaryDirectory() as directory:
                root = Path(directory)
                fixtures.launch(root, 'x86_64')
                run = root / 'fixture-run'
                launch_path = run / 'emulator-launch.json'
                launch = json.loads(launch_path.read_text())
                flag = '-cpu' if change == 'cpu' else '-kernel'
                launch['arguments'][launch['arguments'].index(flag) + 1] = 'wrong-input'
                receipt_path = run / 'emulator-identity.json'
                receipt = json.loads(receipt_path.read_text())
                receipt['arguments'] = launch['arguments']
                receipt_path.write_text(json.dumps(receipt))
                launch['emulator_identity_sha256'] = fixtures.media.digest(receipt_path)
                launch_path.write_text(json.dumps(launch))
                with self.assertRaisesRegex(ValueError, 'CPU arguments|media argument'):
                    fixtures.identity.validate(root, run, 'x86_64', root / 'fixture-media-repo')

    def test_missing_identity_and_nonpristine_initial_userdata_fail(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            fixtures.launch(root, 'arm64-v8a')
            run = root / 'fixture-run'
            (run / 'emulator-identity.json').unlink()
            with self.assertRaises(FileNotFoundError):
                fixtures.identity.validate(root, run, 'arm64-v8a', root / 'fixture-media-repo')
            (run / 'userdata-qemu.img').write_text('previous guest disk')
            with self.assertRaisesRegex(ValueError, 'initial userdata'):
                fixtures.identity.capture(root, run, 'arm64-v8a', root / 'fixture-media-repo')


if __name__ == '__main__':
    unittest.main()
