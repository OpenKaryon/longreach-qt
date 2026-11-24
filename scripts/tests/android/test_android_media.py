# SPDX-License-Identifier: GPL-3.0-or-later
"""Small archive/cache fixtures; never execute an emulator or guest."""
import json
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch
import zipfile

import android_media_fixtures as fixtures

media = fixtures.media
fixture = fixtures.archives

class Media(unittest.TestCase):
    def test_prepares_and_reuses_all_abis_without_reextracting(self):
        for abi in media.ABIS:
            with self.subTest(abi=abi), tempfile.TemporaryDirectory() as directory:
                repo = Path(directory) / 'repo'
                output = Path(directory) / 'output'
                roles = fixture(repo, abi)
                ready = media.prepare(repo, output, abi)
                before = {name: (output / 'media' / name).stat().st_mtime_ns for name in ready['files']
                          if name != abi + '/system/build.prop'}
                with patch.object(media.shutil, 'copyfileobj', side_effect=AssertionError('warm extraction')):
                    self.assertEqual(media.prepare(repo, output, abi), ready)
                self.assertEqual({name: (output / 'media' / name).stat().st_mtime_ns for name in before}, before)
                self.assertEqual(ready['roles'], roles)
                self.assertEqual(media.verify_ready(output, abi, repo), ready)

    def test_marker_alone_and_changed_or_extra_cached_files_are_repaired(self):
        for change in ('marker-only', 'system', 'engine', 'extra'):
            with self.subTest(change=change), tempfile.TemporaryDirectory() as directory:
                repo, output = Path(directory) / 'repo', Path(directory) / 'output'
                roles = fixture(repo, 'x86')
                original = media.prepare(repo, output, 'x86')
                base = output / 'media'
                unrelated = base / 'other-abi/user.txt'
                unrelated.parent.mkdir()
                unrelated.write_text('preserve unrelated media')
                if change == 'marker-only':
                    for receipt in base.rglob('*.extracted.json'):
                        receipt.unlink()
                    (base / 'x86-21_r99.zip.sha256').write_text('old-style marker')
                elif change == 'extra':
                    (base / 'emulator-32.1.11/emulator/lib64/stale.dll').write_text('old extraction residue')
                else:
                    (base / (roles['system'] if change == 'system' else roles['engine_candidates'][0])).write_text('changed cached bytes')
                if change in ('system', 'engine', 'extra'):
                    with self.assertRaisesRegex(ValueError, 'bytes or inventory changed'):
                        media.verify_ready(output, 'x86', repo)
                self.assertEqual(media.prepare(repo, output, 'x86'), original)
                self.assertEqual(unrelated.read_text(), 'preserve unrelated media')
                self.assertTrue(list(base.rglob('previous-extraction-*')))

    def test_failed_extraction_leaves_live_media_but_no_ready_receipt(self):
        with tempfile.TemporaryDirectory() as directory:
            repo, output = Path(directory) / 'repo', Path(directory) / 'output'
            roles = fixture(repo, 'armeabi-v7a')
            media.prepare(repo, output, 'armeabi-v7a')
            path = output / 'media' / roles['system']
            path.write_text('prior bytes preserved on failed staging')
            with patch.object(media.shutil, 'copyfileobj', side_effect=OSError('fixture extraction interruption')):
                with self.assertRaisesRegex(OSError, 'interruption'):
                    media.prepare(repo, output, 'armeabi-v7a')
            self.assertEqual(path.read_text(), 'prior bytes preserved on failed staging')
            self.assertFalse(media.ready_path(output, 'armeabi-v7a').exists())
            media.prepare(repo, output, 'armeabi-v7a')
            media.verify_ready(output, 'armeabi-v7a', repo)

    def test_wrong_archive_and_incomplete_archive_cannot_leave_ready(self):
        for change in ('digest', 'incomplete'):
            with self.subTest(change=change), tempfile.TemporaryDirectory() as directory:
                repo, output = Path(directory) / 'repo', Path(directory) / 'output'
                fixture(repo, 'x86_64')
                media.prepare(repo, output, 'x86_64')
                archive = repo / 'downloads/android-lollipop/x86_64-21_r99.zip'
                with zipfile.ZipFile(archive, 'w') as package:
                    package.writestr('x86_64/system.img', 'incomplete fixture')
                if change == 'incomplete':
                    path = repo / media.LOCK
                    lock = json.loads(path.read_text())
                    lock['sources'][0]['sha256'] = media.digest(archive)
                    path.write_text(json.dumps(lock))
                with self.assertRaisesRegex(ValueError, 'SHA256 mismatch|Incomplete'):
                    media.prepare(repo, output, 'x86_64')
                self.assertFalse(media.ready_path(output, 'x86_64').exists())


if __name__ == '__main__':
    unittest.main()
