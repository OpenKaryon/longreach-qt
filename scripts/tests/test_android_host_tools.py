# SPDX-License-Identifier: GPL-3.0-or-later
"""Java provenance fixtures; JVMs, compilers and Android tools are not run."""
import importlib.util
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[2]
spec = importlib.util.spec_from_file_location('fixture_host_tools', ROOT / 'scripts/build/android-api21/host-tools.py')
host = importlib.util.module_from_spec(spec)
spec.loader.exec_module(host)


def jdk(home):
    for relative in ('release', 'bin/java.exe', 'bin/javac.exe', 'bin/keytool.exe', 'bin/server/jvm.dll',
                     'lib/modules', 'lib/server/libjvm.so', 'lib/security/cacerts', 'conf/security/java.security',
                     'lib/src.zip', 'lib/ct.sym'):
        path = home / relative
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text('fixture/' + relative)
    return home


def sdk(root):
    for relative in ('build-tools/36.0.0/d8.bat', 'platforms/android-35/android.jar'):
        path = root / relative
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text('fixture/' + relative)
    return root


def output(command, **kwargs):
    home = Path(command[0]).parent.parent
    return f'    java.home = {home}\n' + ('javac 21.0.0\n' if command[1].startswith('-J-') else 'openjdk version fixture\n')


class HostTools(unittest.TestCase):
    def test_explicit_api4_platform_jar_needs_no_android35_platform(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            java, android = jdk(root / 'jdk'), sdk(root / 'sdk')
            (android / 'platforms/android-35/android.jar').unlink()
            jar = root / 'api4/android.jar'
            jar.parent.mkdir()
            jar.write_bytes(b'API4 platform fixture')
            with patch.object(host.subprocess, 'check_output', side_effect=output), patch.object(host.shutil, 'which', return_value=None), patch.dict(host.os.environ, {'JAVA_HOME': str(java)}):
                snapshot = host.snapshot(android, java / 'bin/javac.exe', android_jar=jar)
                self.assertEqual(snapshot['tool_sha256']['android-platform/android.jar'], host.digest(jar))
                self.assertNotIn('android-sdk/platforms/android-35/android.jar', snapshot['tool_sha256'])
                with self.assertRaises(FileNotFoundError):
                    host.snapshot(android, java / 'bin/javac.exe')

    def test_recursive_java_inputs_include_ct_sym_and_exclude_source_archive(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            java, android = jdk(root / 'jdk'), sdk(root / 'sdk')
            with patch.object(host.subprocess, 'check_output', side_effect=output), patch.object(host.shutil, 'which', return_value=None), patch.dict(host.os.environ, {'JAVA_HOME': str(java)}):
                initial = host.snapshot(android, java / 'bin/javac.exe')
                for relative in ('bin/server/jvm.dll', 'lib/server/libjvm.so', 'conf/security/java.security', 'lib/security/cacerts', 'release', 'lib/ct.sym'):
                    path = java / relative
                    before = path.read_bytes()
                    path.write_text('changed runtime file')
                    self.assertNotEqual(initial, host.snapshot(android, java / 'bin/javac.exe'), relative)
                    path.write_bytes(before)
                for relative in ('lib/src.zip',):
                    (java / relative).write_text('irrelevant compiler source/signature archive')
                    self.assertEqual(initial, host.snapshot(android, java / 'bin/javac.exe'))

    def test_distinct_compiler_java_home_and_path_runtime_are_bound_in_role_order(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            compiler, configured, path_java = [jdk(root / name) for name in ('compiler', 'configured', 'path-runtime')]
            with patch.object(host.subprocess, 'check_output', side_effect=output), patch.object(host.shutil, 'which', return_value=str(path_java / 'bin/java.exe')), patch.dict(host.os.environ, {'JAVA_HOME': str(configured)}):
                snapshot = host.snapshot(sdk(root / 'sdk'), compiler / 'bin/javac.exe')
            self.assertEqual(snapshot['java_selection'], {'javac': 'jdk/0', 'JAVA_HOME_directory': 'jdk/1', 'JAVA_HOME_runtime': 'jdk/1', 'PATH/java': 'jdk/2'})
            for index in range(3):
                self.assertIn(f'jdk/{index}/bin/server/jvm.dll', snapshot['tool_sha256'])

    def test_javac_wrapper_resolves_actual_jdk_and_records_wrapper_bytes(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            actual = jdk(root / 'real-jdk')
            wrapper = root / 'shims/javac.exe'
            wrapper.parent.mkdir()
            wrapper.write_text('compiler wrapper')
            with patch.object(host.subprocess, 'check_output', return_value=f'java.home = {actual}\njavac 21\n'), patch.object(host.shutil, 'which', return_value=None), patch.dict(host.os.environ, {'JAVA_HOME': str(actual)}):
                chain = host.java_toolchain(wrapper)
                self.assertEqual(chain['javac'], str(actual / 'bin/javac.exe'))
                snapshot = host.snapshot(sdk(root / 'sdk'), wrapper)
                self.assertEqual(snapshot['tool_sha256']['launcher/javac'], host.digest(wrapper))
                self.assertEqual(snapshot['tool_roots']['jdk/0'], str(actual))

    def test_incomplete_home_or_missing_settings_cannot_produce_an_empty_snapshot(self):
        for changed in ('release', 'java', 'settings'):
            with self.subTest(changed=changed), tempfile.TemporaryDirectory() as directory:
                root = Path(directory)
                home, android = jdk(root / 'jdk'), sdk(root / 'sdk')
                if changed in ('release', 'java'):
                    (home / ('release' if changed == 'release' else 'bin/java.exe')).unlink()
                with patch.object(host.subprocess, 'check_output', side_effect=(lambda *args, **kwargs: 'javac 21\n') if changed == 'settings' else output), patch.dict(host.os.environ, {'JAVA_HOME': str(home)}):
                    with self.assertRaisesRegex(ValueError, 'Java home release|Java tool|actual java.home'):
                        host.snapshot(android, home / 'bin/javac.exe')

    def test_invalid_configured_home_is_not_ignored(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            home, android = jdk(root / 'jdk'), sdk(root / 'sdk')
            with patch.object(host.subprocess, 'check_output', side_effect=output), patch.dict(host.os.environ, {'JAVA_HOME': str(root / 'missing-home')}):
                with self.assertRaises(FileNotFoundError):
                    host.snapshot(android, home / 'bin/javac.exe')

    def test_hash_labels_are_portable_when_only_host_roots_change(self):
        snapshots = []
        with tempfile.TemporaryDirectory() as directory:
            for name in ('machine-a', 'machine-b'):
                root = Path(directory) / name
                home, android = jdk(root / 'jdk'), sdk(root / 'sdk')
                with patch.object(host.subprocess, 'check_output', side_effect=output), patch.object(host.shutil, 'which', return_value=None), patch.dict(host.os.environ, {'JAVA_HOME': str(home)}):
                    snapshots.append(host.snapshot(android, home / 'bin/javac.exe'))
            self.assertEqual(snapshots[0]['tool_sha256'], snapshots[1]['tool_sha256'])
            self.assertNotEqual(snapshots[0]['tool_roots'], snapshots[1]['tool_roots'])
            self.assertTrue(all(key.startswith(('android-sdk/', 'jdk/', 'launcher/')) for key in snapshots[0]['tool_sha256']))


if __name__ == '__main__':
    unittest.main()
