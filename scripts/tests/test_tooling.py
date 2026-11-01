# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2026 OpenKaryon
"""Lightweight tooling regressions; no Docker, guests, builds or network."""
import importlib.util
from pathlib import Path
import subprocess
import tempfile
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[2]


def load(name, relative):
    spec = importlib.util.spec_from_file_location(name, ROOT / relative)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


ensure = load('ensure', 'scripts/build/ensure-image.py')
builder = load('builder', 'scripts/build/qt6-build-project.py')
runner = load('runner', 'scripts/run/run.py')
forward = load('forward', 'scripts/tests/linux-forward-check.py')


class SourceArchiveTests(unittest.TestCase):
    def test_archive_fingerprint_tracks_resources_but_not_local_outputs(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            for name in ('scripts/build/input.py', 'tests/assets/icon.png',
                         'build/output', 'downloads/source.tar', 'scripts/__pycache__/cache.pyc'):
                path = root / name
                path.parent.mkdir(parents=True, exist_ok=True)
                path.write_bytes(b'one')
            with patch.object(ensure, 'ROOT', root), patch.object(
                    ensure.subprocess, 'check_output', side_effect=AssertionError('archive must not query parent Git')):
                initial = ensure.fingerprint('config', 'qt6', [])
                for name in ('build/output', 'downloads/source.tar', 'scripts/__pycache__/cache.pyc'):
                    (root / name).write_bytes(b'two')
                self.assertEqual(initial, ensure.fingerprint('config', 'qt6', []))
                (root / 'tests/assets/icon.png').write_bytes(b'new shipped resource')
                self.assertNotEqual(initial, ensure.fingerprint('config', 'qt6', []))
                names = {name for name, _ in ensure.context_files(root, ['scripts', 'tests'])}
                self.assertEqual(names, {'scripts/build/input.py', 'tests/assets/icon.png'})

    def test_git_inventory_still_includes_tracked_deleted_inputs(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            (root / '.git').write_text('gitdir: linked-worktree', encoding='utf-8')
            with patch.object(ensure, 'ROOT', root), patch.object(
                    ensure.subprocess, 'check_output', return_value='scripts/build/deleted.py\0'):
                before = ensure.fingerprint('config', 'qt6', [])
                (root / 'scripts/build').mkdir(parents=True)
                (root / 'scripts/build/deleted.py').write_text('restored', encoding='utf-8')
                self.assertNotEqual(before, ensure.fingerprint('config', 'qt6', []))


class ConsumerBuildTests(unittest.TestCase):
    def test_explicit_jobs_reaches_consumer_build(self):
        with tempfile.TemporaryDirectory() as tmp, patch.object(builder.subprocess, 'run') as run:
            run.return_value.returncode = 0
            builder.build_project(Path(tmp), Path(tmp) / 'out', 'linux-amd64',
                                  builder.PLATFORM_CONFIG['linux-amd64'], 'existing-image', jobs=1)
            script = run.call_args.args[0][-1]
            self.assertIn('cmake --build . --parallel 1', script)
            self.assertNotIn('-maxdepth 1', script)


class GuestRunnerTests(unittest.TestCase):
    def run_windows(self, direct, starts, report):
        tmp = tempfile.TemporaryDirectory()
        self.addCleanup(tmp.cleanup)
        out = Path(tmp.name)
        base = r'C:\qtkit-run'
        previous = base + r'\smoke-report.txt'
        guest = {previous: b'old successful report'}
        launches = []

        def fake_vmrun(host, command, vmx, *args, check=True):
            code = 0
            if command == 'runProgramInGuest':
                launches.append(args)
                if starts:
                    # The copied runner is in the freshly created directory.
                    directory = next(name for name in created if name != base)
                    guest[directory + r'\smoke-report.txt'] = report
                else:
                    code = 1
            elif command == 'createDirectoryInGuest':
                created.append(args[0])
            elif command == 'copyFileFromGuestToHost':
                if args[0] in guest:
                    Path(args[1]).write_bytes(guest[args[0]])
                else:
                    code = 1
            return subprocess.CompletedProcess([], code, stdout='', stderr='')

        created = []
        host = {'os': 'windows', 'vmx': 'example.vmx', 'user': 'example', 'direct': direct}
        with patch.object(runner, 'password', return_value='example'), patch.object(
                runner, 'suite_files', return_value=[]), patch.object(runner, 'vmrun', side_effect=fake_vmrun):
            if starts:
                runner.run_vmware(host, out, out, '--timeout=10')
                self.assertEqual((out / 'smoke-report.txt').read_bytes(), report)
            else:
                with self.assertRaisesRegex(SystemExit, 'No report from the new VMware run'):
                    runner.run_vmware(host, out, out, '--timeout=10')
                self.assertFalse((out / 'smoke-report.txt').exists())
        self.assertEqual(guest[previous], b'old successful report')
        self.assertEqual(len(created), 2)
        self.assertNotEqual(created[0], created[1])
        self.assertEqual(len(Path(created[1].replace('\\', '/')).name), 8)
        self.assertEqual(len(launches), 1)

    def test_failed_loader_cannot_reuse_report(self):
        for direct in (False, True):
            with self.subTest(direct=direct):
                self.run_windows(direct, False, b'')

    def test_success_collects_only_the_new_report(self):
        self.run_windows(False, True, b'fresh report')

    def test_virtualbox_credentials_precede_guest_argv(self):
        host = {'vm': 'example', 'user': 'example', '_password': 'example'}
        with patch.object(runner.subprocess, 'run') as run:
            run.return_value.returncode = 0
            runner.vbox(host, 'run', '--exe', '/bin/sh', '--', '/bin/sh', '-c', 'true')
            argv = run.call_args.args[0]
            self.assertLess(argv.index('--username'), argv.index('--'))
            self.assertLess(argv.index('--password'), argv.index('--'))
            self.assertEqual(argv[argv.index('--') + 1:], ['/bin/sh', '-c', 'true'])

    def test_virtualbox_rejects_unsupported_os_before_guest_operations(self):
        with patch.object(runner, 'vbox') as vbox:
            with self.assertRaisesRegex(SystemExit, 'supports Linux'):
                runner.run_virtualbox({'os': 'windows'}, None, None, '')
            vbox.assert_not_called()


class ForwardMatrixTests(unittest.TestCase):
    def test_every_supported_pair_has_packages(self):
        count = 0
        for suite in forward.SUITES.values():
            for distro in forward.DISTROS.values():
                if suite[1] == 'i386' and distro[1] == 'arch' or distro[2] < suite[3]:
                    continue
                with self.subTest(arch=suite[1], family=distro[1], kind=suite[2]):
                    self.assertIn('xvfb', forward.install_command(distro[1], suite[1], suite[2]).lower())
                    count += 1
        self.assertGreater(count, 20)


if __name__ == '__main__':
    unittest.main()
