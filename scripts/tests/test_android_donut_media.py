# SPDX-License-Identifier: GPL-3.0-or-later
"""Pinned API4 extraction/cache file fixtures only; never runs any binary."""
import importlib.util
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch
import zipfile

ROOT = Path(__file__).resolve().parents[2]
spec = importlib.util.spec_from_file_location('api4_prepared_test', ROOT / 'scripts/build/qt4-android/prepare-media.py')
media = importlib.util.module_from_spec(spec)
spec.loader.exec_module(media)


class DonutMedia(unittest.TestCase):
    def setUp(self):
        temporary = tempfile.TemporaryDirectory(prefix='longreach API4 media-')
        self.addCleanup(temporary.cleanup)
        self.root = Path(temporary.name).resolve()
        self.destination = self.root / 'artifacts/inputs'
        self.destination.mkdir(parents=True)
        self.archives = self.root / 'archives'
        self.archives.mkdir()
        self.contents = {
            'android-1.6_r03-linux.zip': {name: ('data/' + name).encode() for name in media.LAYOUT['android-1.6_r03-linux.zip'][1]},
            'tools_r24.4.1-windows.zip': {'tools/emulator-arm.exe': b'DATA ONLY', 'tools/lib/fixture.dll': b'DEPENDENCY DATA'},
        }
        for name in self.contents:
            self.write_archive(name)
        context = patch.dict(media.PINS, {name: media.common.digest(self.archives / name) for name in self.contents}, clear=True)
        context.start()
        self.addCleanup(context.stop)

    def write_archive(self, name):
        with zipfile.ZipFile(self.archives / name, 'w') as archive:
            for member, data in self.contents[name].items():
                archive.writestr(member, data)

    def prepare(self):
        for name in media.PINS:
            media.extract(self.archives / name, self.destination, media.LAYOUT[name][1][0], media.PINS[name])
        return media.verify(self.destination)

    def test_complete_archive_inventories_and_warm_reuse_without_extraction(self):
        ready = self.prepare()
        files = {self.destination.parent / name: sha for name, sha in ready['files'].items()}
        before = {path: path.stat().st_mtime_ns for path in files}
        with patch.object(media.extractor.shutil, 'copyfileobj', side_effect=AssertionError('unexpected warm extraction')):
            self.assertEqual(self.prepare(), ready)
        self.assertEqual({path: path.stat().st_mtime_ns for path in files}, before)
        self.assertEqual(ready['archives'], media.PINS)
        self.assertEqual(ready['schema_version'], 2)
        self.assertIn('inputs/tools/lib/fixture.dll', ready['files'])

    def test_marker_only_changed_or_extra_cached_files_are_repaired_and_preserved(self):
        self.prepare()
        unrelated = self.destination / 'other-abi/notes.txt'
        unrelated.parent.mkdir()
        unrelated.write_text('retained unrelated media')
        userdata = self.destination.parent / 'run/old/userdata-qemu.img'
        userdata.parent.mkdir(parents=True)
        userdata.write_text('retained mutable guest data')
        for change in ('marker-only', 'system', 'dependency', 'extra'):
            if change == 'marker-only':
                for path in self.destination.glob('*.extracted.json'):
                    path.unlink()
                (self.destination / 'android-1.6_r03-linux/android.jar.old-marker').write_text('old marker')
            elif change == 'system':
                (self.destination / 'android-1.6_r03-linux/images/system.img').write_text('changed cached image')
            elif change == 'dependency':
                (self.destination / 'tools/lib/fixture.dll').write_text('changed cached dependency')
            else:
                (self.destination / 'tools/extra.dll').write_text('extra cached file')
            with self.subTest(change=change), self.assertRaises((ValueError, OSError)):
                media.verify(self.destination)
            self.prepare()
        self.assertEqual(unrelated.read_text(), 'retained unrelated media')
        self.assertEqual(userdata.read_text(), 'retained mutable guest data')
        histories = list(self.destination.glob('previous-extraction-*'))
        self.assertGreaterEqual(len(histories), 4)
        self.assertTrue(any((path / 'tools/extra.dll').is_file() for path in histories))
        self.assertTrue(any((path / 'android-1.6_r03-linux/images/system.img').is_file() for path in histories))

    def test_failed_staging_keeps_previous_tree_and_no_ready_receipt(self):
        self.prepare()
        target = self.destination / 'tools/lib/fixture.dll'
        target.write_text('preserve this interrupted cache state')
        with patch.object(media.extractor.shutil, 'copyfileobj', side_effect=OSError('recorded partial extraction')):
            with self.assertRaisesRegex(OSError, 'partial extraction'):
                media.extract(self.archives / 'tools_r24.4.1-windows.zip', self.destination, 'tools/emulator-arm.exe', media.PINS['tools_r24.4.1-windows.zip'])
        self.assertEqual(target.read_text(), 'preserve this interrupted cache state')
        self.assertTrue(list(self.destination.glob('.extract-*')))
        self.assertFalse((self.destination / 'tools_r24.4.1-windows.zip.extracted.json').exists())
        with self.assertRaises((ValueError, OSError)):
            media.verify(self.destination)
        self.prepare()

    def test_wrong_archive_and_incomplete_archive_cannot_publish_ready(self):
        name = 'tools_r24.4.1-windows.zip'
        path = self.archives / name
        original = path.read_bytes()
        path.write_bytes(original + b'changed archive bytes')
        with self.assertRaisesRegex(ValueError, 'SHA256 mismatch'):
            media.extract(path, self.destination, 'tools/emulator-arm.exe', media.PINS[name])
        self.assertFalse((self.destination / (name + '.extracted.json')).exists())
        self.contents[name] = {'tools/lib/fixture.dll': b'missing frontend'}
        self.write_archive(name)
        with patch.dict(media.PINS, {name: media.common.digest(path)}):
            with self.assertRaisesRegex(ValueError, 'Incomplete'):
                media.extract(path, self.destination, 'tools/emulator-arm.exe', media.PINS[name])
        self.assertFalse((self.destination / (name + '.extracted.json')).exists())

    def test_receipt_recipe_and_pin_drift_are_refused_before_reuse(self):
        self.prepare()
        path = self.destination / 'tools_r24.4.1-windows.zip.extracted.json'
        original = path.read_bytes()
        for field in ('archive_sha256', 'extractor_sha256'):
            value = media.common.read_json(path)
            value[field] = '0' * 64
            media.common.write_json(path, value)
            with self.subTest(field=field), self.assertRaisesRegex(ValueError, 'receipt'):
                media.verify(self.destination)
            path.write_bytes(original)
        self.assertEqual(media.verify(self.destination)['archives'], media.PINS)

    def test_standalone_cli_refuses_another_process_lease_without_clearing_reports(self):
        report = self.destination.parent / 'final-results.json'
        report.write_text('current owner report')
        name = 'tools_r24.4.1-windows.zip'
        with media.common.artifact_lease(self.destination.parent):
            result = subprocess.run([sys.executable, str(ROOT / 'scripts/build/qt4-android/prepare-media.py'), 'extract',
                '--destination', str(self.destination), '--archive', str(self.archives / name),
                '--member', 'tools/emulator-arm.exe', '--sha256', media.PINS[name]],
                capture_output=True, text=True, timeout=10, creationflags=getattr(subprocess, 'CREATE_NO_WINDOW', 0))
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('Another Longreach operation', result.stderr)
        self.assertEqual(report.read_text(), 'current owner report')
        self.assertFalse((self.destination / 'tools').exists())


if __name__ == '__main__':
    unittest.main()
