# SPDX-License-Identifier: GPL-3.0-or-later
"""Ordinary process/file fixtures for the retained Qt4 client-volume lease."""
import importlib.util
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import time
import unittest

ROOT = Path(__file__).resolve().parents[2]
HELPER = ROOT / 'scripts/build/qt4-android/client-cache-lock.py'
spec = importlib.util.spec_from_file_location('qt4_cache_owner', HELPER)
owner = importlib.util.module_from_spec(spec)
spec.loader.exec_module(owner)
OPTIONS = {'creationflags': subprocess.CREATE_NO_WINDOW} if os.name == 'nt' else {}


class CacheOwner(unittest.TestCase):
    def run_child(self, args, **kwargs):
        return subprocess.run([sys.executable, *map(str, args)], capture_output=True,
                              text=True, timeout=10, **OPTIONS, **kwargs)

    def test_busy_cache_rejects_command_and_releases_after_owner_exits(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            ready, marker = root / 'ready', root / 'command-ran'
            code = ('import importlib.util, pathlib, time; '
                    's=importlib.util.spec_from_file_location("owner",' + repr(str(HELPER)) + '); '
                    'm=importlib.util.module_from_spec(s); s.loader.exec_module(m); '
                    'lease=m.CacheLease(' + repr(str(root)) + '); '
                    'pathlib.Path(' + repr(str(ready)) + ').touch(); time.sleep(20)')
            child = subprocess.Popen([sys.executable, '-c', code], stdout=subprocess.PIPE,
                                     stderr=subprocess.PIPE, text=True, **OPTIONS)
            try:
                deadline = time.monotonic() + 5
                while not ready.exists() and child.poll() is None and time.monotonic() < deadline:
                    time.sleep(0.02)
                self.assertTrue(ready.exists(), 'Owned process did not acquire its cache lease')
                result = self.run_child([HELPER, '--root', root, '--', sys.executable, '-c',
                                         'from pathlib import Path; Path(' + repr(str(marker)) + ').touch()'])
                self.assertNotEqual(result.returncode, 0)
                self.assertIn('Qt4 client cache is busy', result.stderr)
                self.assertFalse(marker.exists())
            finally:
                if child.poll() is None:
                    child.terminate()
                child.communicate(timeout=5)
            with owner.CacheLease(root):
                self.assertTrue((root / owner.LOCK).is_file())

    def test_cli_propagates_exit_code_without_removing_cached_objects(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            saved = root / 'warm.o'
            saved.write_bytes(b'existing cached object')
            result = self.run_child([HELPER, '--root', root, '--', sys.executable,
                                     '-c', 'raise SystemExit(7)'])
            self.assertEqual(result.returncode, 7, result.stderr)
            self.assertEqual(saved.read_bytes(), b'existing cached object')
            with owner.CacheLease(root):
                pass

    def test_unverified_inheritance_cannot_skip_the_volume_lease(self):
        with tempfile.TemporaryDirectory() as directory:
            env = os.environ.copy()
            env[owner.HELD_ENV] = '1'
            env.pop(owner.FD_ENV, None)
            result = self.run_child([HELPER, '--root', directory, '--verify-inherited'], env=env)
            self.assertNotEqual(result.returncode, 0)
            self.assertIn('lease is invalid', result.stderr)

    @unittest.skipUnless(os.name == 'posix', 'Container descriptor inheritance requires POSIX')
    def test_delegated_child_close_does_not_unlock_parent(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            with owner.CacheLease(root) as lease:
                result = self.run_child([HELPER, '--root', root, '--verify-inherited'],
                                        env=lease.child_environment(), **lease.child_options())
                self.assertEqual(result.returncode, 0, result.stderr)
                with self.assertRaisesRegex(RuntimeError, 'cache is busy'):
                    owner.CacheLease(root)
            with owner.CacheLease(root):
                pass

    @unittest.skipUnless(os.name == 'posix', 'Container descriptor inheritance requires POSIX')
    def test_delegated_child_retains_lease_after_original_owner_closes(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            lease = owner.CacheLease(root)
            child = subprocess.Popen([sys.executable, '-c', 'import time; time.sleep(20)'],
                                     **lease.child_options(), env=lease.child_environment())
            try:
                lease.close()
                with self.assertRaisesRegex(RuntimeError, 'cache is busy'):
                    owner.CacheLease(root)
            finally:
                lease.close()
                if child.poll() is None:
                    child.terminate()
                child.wait(timeout=5)
            with owner.CacheLease(root):
                pass

    @unittest.skipUnless(os.name == 'posix', 'Container descriptor inheritance requires POSIX')
    def test_descriptor_for_another_file_is_rejected(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            with owner.CacheLease(root) as lease, (root / 'unrelated').open('w+b') as other:
                env = lease.child_environment()
                env[owner.FD_ENV] = str(other.fileno())
                result = self.run_child([HELPER, '--root', root, '--verify-inherited'],
                                        env=env, pass_fds=(other.fileno(),))
                self.assertNotEqual(result.returncode, 0)
                self.assertIn('lease is invalid', result.stderr)


if __name__ == '__main__':
    unittest.main()
