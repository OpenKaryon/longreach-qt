# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2026 OpenKaryon
"""Android make/batch contracts; no Docker, downloads, SDK builds or guests."""
import contextlib
import importlib.util
import io
import json
from pathlib import Path
import re
import shutil
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import Mock, patch

ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT / 'scripts/build'))
import android_targets as matrix


def load(name, path):
    spec = importlib.util.spec_from_file_location(name, ROOT / path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


android = load('android_make_tests', 'scripts/build/android.py')
batch = load('android_batch_tests', 'scripts/build/build-all.py')


def options(target='qt5-android-i386', mode='examples', *extra):
    return android.parser().parse_args(['--target', target, '--mode', mode, *extra])


def payload(args):
    return json.loads(android.command_for(args)[-1])


class MatrixTests(unittest.TestCase):
    def test_exact_sdk_matrix_and_existing_locations(self):
        expected = {
            'qt4-android-i386': ('x86', 10, 'gingerbread-x86'),
            'qt4-android-amd64': ('x86_64', 21, 'lollipop-x86_64'),
            'qt4-android-arm64': ('arm64-v8a', 21, 'lollipop-arm64-v8a'),
            'qt5-android-armv7': ('armeabi-v7a', 10, 'gingerbread'),
            'qt5-android-i386': ('x86', 10, 'gingerbread-x86'),
            'qt5-android-amd64': ('x86_64', 21, 'lollipop-x86_64'),
            'qt5-android-arm64': ('arm64-v8a', 21, 'lollipop-arm64-v8a'),
            'qt6-android-armv7': ('armeabi-v7a', 21, 'lollipop'),
            'qt6-android-i386': ('x86', 21, 'lollipop-x86'),
            'qt6-android-amd64': ('x86_64', 21, 'lollipop-x86_64'),
            'qt6-android-arm64': ('arm64-v8a', 21, 'lollipop-arm64-v8a'),
        }
        self.assertEqual(set(expected), set(matrix.ANDROID_TARGETS))
        for target, (abi, api, profile) in expected.items():
            with self.subTest(target=target):
                info = matrix.ANDROID_TARGETS[target]
                self.assertEqual((info.abi, info.api), (abi, api))
                self.assertEqual(batch.image_of(target, 'gpl-enabled'),
                                 f'longreach-qt{info.qt}-android-{profile}:llvm21')
                self.assertEqual(batch.output_of(target, 'gpl-enabled'),
                                 f'artifacts/qt{info.qt}-android-{profile}')

    def test_abi_spellings_do_not_add_make_or_batch_targets(self):
        for info in matrix.ANDROID_TARGETS.values():
            name = f'qt{info.qt}-android-{info.abi}'
            with self.subTest(name=name), self.assertRaises(ValueError):
                android.command_for(options(name))
            self.assertFalse(any(batch.matches(t, [name]) for t in batch.TARGETS))
        self.assertEqual(sum(batch.matches(t, ['*-android-*']) for t in batch.TARGETS), 11)
        self.assertNotIn(matrix.LEGACY_TARGET, batch.TARGETS)

    def test_all_profiles_offer_sdk_and_ready_apk_examples(self):
        for target, info in matrix.ANDROID_TARGETS.items():
            for mode in ('sdk', 'examples'):
                with self.subTest(target=target, mode=mode):
                    self.assertEqual(android.command_for(options(target, mode))[-3], str(info.qt))
                    self.assertEqual(payload(options(target, mode))['Mode'], mode)
                    self.assertEqual(payload(options(target, mode))['Abi'], info.abi)


class ArgumentTests(unittest.TestCase):
    def test_literal_paths_and_sdk_controls(self):
        args = options('qt6-android-arm64', 'sdk', '--android-sdk', 'C:/SDK with spaces',
                       '--output-directory', 'C:/outputs/тест $literal', '--host-image', 'ready-host',
                       '--parallel-jobs', '3', '--no-cache',
                       '--docker-build-flags=--pull --label "note=two words"')
        result = payload(args)
        self.assertEqual(result['AndroidSdk'], 'C:/SDK with spaces')
        self.assertEqual(result['OutputDirectory'], 'C:/outputs/тест $literal')
        self.assertEqual(result['HostImage'], 'ready-host')
        self.assertTrue(result['NoCache'])
        self.assertEqual(result['ParallelJobs'], 3)
        self.assertEqual(json.loads(result['DockerBuildFlagsJson']), ['--pull', '--label', 'note=two words'])

    def test_examples_select_ready_sdk_without_sdk_build_controls(self):
        result = payload(options('qt5-android-i386', 'examples', '--sdk-image', 'ready-fixed-sdk',
                                 '--parallel-jobs', '3', '--no-cache', '--docker-build-flags=--pull'))
        self.assertEqual(result['SdkImage'], 'ready-fixed-sdk')
        self.assertEqual(result['ParallelJobs'], 3)
        self.assertNotIn('NoCache', result)
        self.assertNotIn('DockerBuildFlagsJson', result)

    def test_incompatible_options_fail_before_execution(self):
        cases = [
            ('qt5-android-i386', 'examples', ['--host-image', 'host']),
            ('qt5-android-i386', 'sdk', ['--input-directory', 'inputs']),
            ('qt4-android-arm64', 'sdk', ['--qt-version', '4.8.8']),
            ('qt6-android-arm64', 'sdk', ['--parallel-jobs', '0']),
            ('qt5-android-i386', 'sdk', ['--license-profile', 'commercial-qt']),
            ('qt4-android-arm64', 'sdk', ['--license-profile', 'lgpl-friendly']),
            (matrix.LEGACY_TARGET, 'sdk', []),
            (matrix.LEGACY_TARGET, 'legacy', ['--no-cache']),
            (matrix.LEGACY_TARGET, 'legacy', ['--parallel-jobs', '3']),
        ]
        for target, mode, extra in cases:
            with self.subTest(target=target, mode=mode, extra=extra), self.assertRaises(ValueError):
                android.command_for(options(target, mode, *extra))

    def test_legacy_retains_its_combined_recipe(self):
        result = payload(options(matrix.LEGACY_TARGET, 'legacy', '--input-directory', 'C:/old inputs'))
        self.assertEqual(result, {'InputDirectory': 'C:/old inputs'})

    def test_listing_and_command_preview_do_not_execute_tools(self):
        with patch.object(android.subprocess, 'run', side_effect=AssertionError('must not execute')):
            for args in (['--targets'], ['--target', 'qt4-android-arm64', '--mode', 'sdk', '--print-command']):
                with contextlib.redirect_stdout(io.StringIO()) as out:
                    self.assertEqual(android.main(args), 0)
                    self.assertTrue(out.getvalue())
            with contextlib.redirect_stdout(io.StringIO()) as out:
                with patch.object(sys, 'argv', ['build-all.py', '--list', '--only', '*-android-*']):
                    self.assertEqual(batch.main(), 0)
                self.assertEqual(out.getvalue().count('[Windows host]'), 11)
                self.assertNotIn('artifacts/tests-', out.getvalue())


class BatchTests(unittest.TestCase):
    def test_android_schedules_sdk_then_apks_without_build_aliases(self):
        self.assertEqual(batch.steps_for('qt4-android-arm64', 'my-make', ['NO_CACHE=1']), [
            ['my-make', '--no-print-directory', 'qt4-android-arm64', 'NO_CACHE=1'],
            ['my-make', '--no-print-directory', 'qt4-android-arm64-examples', 'NO_CACHE=1']])
        self.assertEqual(batch.steps_for('qt4-android-arm64', sdk_only=True),
                         [['make', '--no-print-directory', 'qt4-android-arm64']])

    def test_desktop_routes_and_outputs_are_unchanged(self):
        self.assertEqual(batch.steps_for('qt5-linux-amd64'),
                         [['make', '--no-print-directory', 'qt5-linux-amd64-examples']])
        self.assertEqual(batch.steps_for('qt5-linux-amd64', sdk_only=True),
                         [['make', '--no-print-directory', 'build-qt5-linux-amd64']])
        self.assertEqual(batch.steps_for('qt6-win-amd64')[-1][2], 'qt6-win-amd64-audit')
        self.assertEqual(batch.output_of('qt5-linux-amd64', 'gpl-enabled'),
                         'artifacts/tests-qt5-linux-amd64-llvm21')

    def test_android_is_exclusive_and_queue_drains_before_it_starts(self):
        desktop, arm, intel = 'qt5-linux-amd64', 'qt4-android-arm64', 'qt6-android-amd64'
        self.assertEqual(matrix.startable_targets([desktop, arm, intel], []), [arm])
        self.assertEqual(matrix.startable_targets([arm, desktop], [desktop]), [])
        self.assertEqual(matrix.startable_targets([desktop, intel], [arm]), [])
        self.assertEqual(matrix.startable_targets([desktop], []), [desktop])
        self.assertEqual(matrix.startable_targets([desktop], ['qt4-linux-amd64']), [desktop])

    def test_failed_sdk_does_not_launch_examples(self):
        with tempfile.TemporaryDirectory() as tmp:
            process = Mock()
            process.poll.return_value = 17
            with patch.object(batch.subprocess, 'Popen', return_value=process) as popen:
                with patch.object(batch, 'STEPS', []):
                    job = batch.Job('qt4-android-arm64', batch.steps_for('qt4-android-arm64'), Path(tmp), {})
                    self.assertTrue(job.poll())
                    self.assertEqual(job.status, 'FAIL')
                    self.assertEqual(popen.call_count, 1)


@unittest.skipUnless(shutil.which('make'), 'GNU make is needed for read-only route checks')
class MakeRoutingTests(unittest.TestCase):
    def make(self, *args, expected=(0,)):
        result = subprocess.run(['make', '--no-print-directory', *args, f'PYTHON={sys.executable}'],
                                cwd=ROOT, text=True, capture_output=True, timeout=30)
        self.assertIn(result.returncode, expected, result.stderr)
        return result.stdout

    def test_exactly_two_rules_per_profile_without_aliases_package_or_test_rules(self):
        database = self.make('-qp', expected=(0, 1))
        rules = set(re.findall(r'^(qt[456]-android-[A-Za-z0-9_-]+):(?:\s|$)', database, re.M))
        expected = {name + suffix for name in matrix.ANDROID_TARGETS for suffix in ('', '-examples')}
        self.assertEqual(rules, expected | {matrix.LEGACY_TARGET})
        for name, info in matrix.ANDROID_TARGETS.items():
            self.assertNotRegex(database, re.compile(rf'^build-{re.escape(name)}(?:-examples)?:', re.M), name)
            alias = f'qt{info.qt}-android-{info.abi}'
            self.assertNotIn(alias, rules)

    def test_sdk_and_examples_routes_keep_sdk_prerequisites_separate(self):
        for name in matrix.ANDROID_TARGETS:
            for suffix, mode in [('', 'sdk'), ('-examples', 'examples')]:
                with self.subTest(target=name, mode=mode):
                    output = self.make('-n', name + suffix)
                    self.assertEqual(output.count('scripts/build/android.py --target'), 1)
                    self.assertIn(f'--mode {mode}', output)
                    self.assertNotIn('docker ', output)
                    if mode == 'examples':
                        self.assertNotIn('ensure-image.py', output)
        output = self.make('-n', 'qt4-android-arm64-examples', 'ANDROID_SDK=C:/SDK with spaces',
                           'ANDROID_OUTPUT=C:/output with spaces')
        self.assertIn('--android-sdk "C:/SDK with spaces"', output)
        self.assertIn('--output-directory "C:/output with spaces"', output)

    def test_qt6_host_preparation_is_sdk_only_and_custom_host_is_retained(self):
        sdk = self.make('-n', 'qt6-android-arm64', 'OS=Windows_NT')
        self.assertIn('--target "qt6-linux-amd64"', sdk)
        custom = self.make('-n', 'qt6-android-arm64', 'OS=Windows_NT', 'ANDROID_HOST_IMAGE=ready-host')
        self.assertNotIn('ensure-image.py', custom)
        self.assertIn('--host-image "ready-host"', custom)
        denied = subprocess.run(['make', '--no-print-directory', '-n', 'qt6-android-arm64',
                                 'LICENSE_PROFILE=commercial-qt'], cwd=ROOT,
                                text=True, capture_output=True, timeout=30)
        self.assertNotEqual(denied.returncode, 0)
        self.assertIn('gpl-enabled only', denied.stderr)
        self.assertNotIn('ensure-image.py', denied.stdout)

    def test_help_and_batch_keep_only_the_main_pair(self):
        output = self.make('-n', 'build-all-examples', 'BUILD_ALL_ARGS=--only *-android-*')
        self.assertIn('--android-make-jobs 2', output)
        help_text = self.make('help')
        self.assertIn('qt4-android-arm64', help_text)
        self.assertIn('ready SDK', help_text)
        self.assertIn('APKs', help_text)
        self.assertNotIn('ABI aliases', help_text)
        self.assertNotIn('<android-target>-package', help_text)
        self.assertNotIn('<android-target>-test', help_text)


@unittest.skipUnless(shutil.which('pwsh'), 'PowerShell 7 is needed for the recording fixture')
class PowerShellAdapterTests(unittest.TestCase):
    def run_fixture(self, qt, mode, *, fail_phase='', extra=None):
        with tempfile.TemporaryDirectory(prefix='android make ') as tmp:
            fixture = Path(tmp)
            shutil.copyfile(ROOT / 'scripts/build/android-make.ps1', fixture / 'android-make.ps1')
            receipt = fixture / 'receipt.jsonl'
            entry = fixture / f'qt{qt}-android.ps1'
            entry.write_text(
                'param($Abi,$Mode,$OutputDirectory,$SdkImage,$ParallelJobs,'
                '[switch]$NoCache,$DockerBuildFlagsJson)\n'
                '$record=@{}+$PSBoundParameters\n'
                'if($record.ContainsKey("NoCache")) { $record.NoCache=[bool]$NoCache }\n'
                '$record | ConvertTo-Json -Compress | Add-Content -LiteralPath $OutputDirectory\n'
                f"if($Mode -eq '{fail_phase}') {{ exit 17 }}\n", encoding='utf-8')
            value = {'Abi': 'x86', 'Mode': mode, 'OutputDirectory': str(receipt), **(extra or {})}
            result = subprocess.run(['pwsh', '-NoLogo', '-NoProfile', '-File', str(fixture / 'android-make.ps1'),
                                     '-QtMajor', str(qt), '-OptionsJson', json.dumps(value)],
                                    text=True, capture_output=True, timeout=30)
            records = [json.loads(line) for line in receipt.read_text(encoding='utf-8-sig').splitlines()]
            return result, records, value

    def test_examples_compile_then_package_for_each_qt_with_literal_options(self):
        for qt in (4, 5, 6):
            with self.subTest(qt=qt):
                result, records, value = self.run_fixture(qt, 'examples', extra={
                    'SdkImage': 'ready-$literal; образ', 'ParallelJobs': 3})
                self.assertEqual(result.returncode, 0, result.stderr)
                self.assertEqual([r['Mode'] for r in records], ['examples', 'package'])
                self.assertEqual(records[0], value)
                self.assertEqual(records[1], {k: v for k, v in {**value, 'Mode': 'package'}.items()
                                              if k not in ('SdkImage', 'ParallelJobs')})

    def test_sdk_never_packages(self):
        result, records, value = self.run_fixture(5, 'sdk', extra={'NoCache': True, 'ParallelJobs': 3})
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(records, [value])

    def test_native_failure_stops_packaging_and_package_failure_is_not_success(self):
        for phase, expected in [('examples', ['examples']), ('package', ['examples', 'package'])]:
            with self.subTest(phase=phase):
                result, records, _ = self.run_fixture(5, 'examples', fail_phase=phase)
                self.assertEqual(result.returncode, 17, result.stderr)
                self.assertEqual([r['Mode'] for r in records], expected)


if __name__ == '__main__':
    unittest.main()
