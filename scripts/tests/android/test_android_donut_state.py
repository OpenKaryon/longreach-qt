# SPDX-License-Identifier: GPL-3.0-or-later
"""API4 attempt metadata and synthetic reports; never executes a guest or binary."""
import importlib.util
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch
import uuid
import zipfile

import android_owned_process_fixtures as host
import android_result_fixtures as reports

ROOT = Path(__file__).resolve().parents[3]
spec = importlib.util.spec_from_file_location('api4_attempt_test', ROOT / 'scripts/run/android/android-donut-state.py')
state = importlib.util.module_from_spec(spec)
spec.loader.exec_module(state)


class DonutState(unittest.TestCase):
    def setUp(self):
        temporary = tempfile.TemporaryDirectory(prefix='longreach-api4-attempt-')
        self.addCleanup(temporary.cleanup)
        self.root = Path(temporary.name).resolve()
        self.jar = self.root / 'inputs/android-1.6_r03-linux/android.jar'
        for relative in ('inputs/tools/emulator-arm.exe', 'inputs/tools/lib/fixture.dll',
                         'inputs/android-1.6_r03-linux/android.jar',
                         *('inputs/android-1.6_r03-linux/images/' + name for name in ('kernel-qemu', 'system.img', 'ramdisk.img', 'userdata.img'))):
            path = self.root / relative
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_text('data-only media/' + relative)
        archive_root = self.root / 'fixture-archives'
        archive_root.mkdir()
        pins = {}
        for name, (directory, _) in state.prepared.LAYOUT.items():
            path = archive_root / name
            with zipfile.ZipFile(path, 'w') as archive:
                for member in sorted((self.root / 'inputs' / directory).rglob('*')):
                    if member.is_file():
                        archive.write(member, member.relative_to(self.root / 'inputs').as_posix())
            pins[name] = state.common.digest(path)
        context = patch.dict(state.prepared.PINS, pins, clear=True)
        context.start()
        self.addCleanup(context.stop)
        for name in pins:
            state.prepared.extract(archive_root / name, self.root / 'inputs', state.prepared.LAYOUT[name][1][0], pins[name])
        for name in (state.artifacts.NATIVE_MANIFEST, state.artifacts.APK_MANIFEST):
            (self.root / name).write_text('data-only generation receipt')
        self.packages = []
        for profile in state.artifacts.PROFILES:
            path = self.root / (profile + '.apk')
            path.write_text('selected APK data/' + profile)
            self.packages.append({'profile': profile, 'apk': path.name, 'sha256': state.common.digest(path), 'native_sha256': 'a' * 64})
        self.receipt = {'generation': 'b' * 32, 'packages': self.packages}
        for context in (patch.object(state.artifacts, 'check_apks', return_value=self.receipt),
                        patch.object(state.artifacts, 'check_native', return_value={'inputs': {'android_jar_sha256': state.common.digest(self.jar)}})):
            context.start()
            self.addCleanup(context.stop)

    def save(self, run, record):
        state.common.write_json(run / 'run-inputs.json', record)

    def attempt(self, profile='core'):
        identity = uuid.uuid4().hex
        run = self.root / 'run' / (profile + '-' + identity)
        run.mkdir(parents=True)
        package = next(p for p in self.packages if p['profile'] == profile)
        record = dict(schema_version=1, run_id=identity, qt_major=4, api=4, abi='armeabi', profile=profile,
                      generation=self.receipt['generation'], apk=package['apk'], apk_sha256=package['sha256'], native_sha256=package['native_sha256'],
                      native_manifest_sha256=state.common.digest(self.root / state.artifacts.NATIVE_MANIFEST),
                      apk_manifest_sha256=state.common.digest(self.root / state.artifacts.APK_MANIFEST),
                      completed=False, qualification=False, host_tree_exit_verified=False, evidence_scope='api4-jni-resident-diagnostic')
        self.save(run, record)
        program = self.root / 'inputs/tools/emulator-arm.exe'
        arguments = state.arguments(self.root, run)
        state.common.write_json(run / 'emulator-launch.json', {'schema_version': 1, 'abi': 'armeabi', 'emulator': str(program), 'arguments': arguments})
        state.capture(self.root, run)
        record.update(emulator_launch_sha256=state.common.digest(run / 'emulator-launch.json'), emulator_media_sha256=state.common.digest(run / 'emulator-media.json'))
        record.update(host.capture(run, program, arguments, artifact_root=self.root))
        body = 'I/LongreachDonut( 123): Native probe returned ' + ('42' if profile == 'bootstrap' else '0') + '\n'
        if profile == 'core':
            body += 'I/LongreachDonut( 123): QtCore 4.8.7 PASS\n'
        if profile == 'strict':
            body += 'I/LongreachDonut( 123): Classic locale check passed\n'
        (run / 'case-logcat.log').write_text(body)
        (run / 'final-logcat.log').write_text(body)
        state.common.write_json(run / 'final-logcat-capture.json', dict(schema_version=1, serial='emulator-5580', captured=True,
            logcat_sha256=state.common.digest(run / 'final-logcat.log'),
            **{key: record[key] for key in ('host_process_owner_sha256', 'host_process_request_sha256')}))
        if profile in state.REPORTS:
            (run / (state.REPORTS[profile] + '-guest.stdout')).write_text(reports.stdout(4, 4, 'armeabi', profile, state.REPORTS[profile]))
        elif profile == 'strict':
            (run / 'strict-cxx23-guest.stdout').write_text(reports.stdout(4, 4, 'armeabi', 'strict'))
        elif profile == 'quick':
            (run / 'instrumentation.log').write_text('INSTRUMENTATION_CODE: -1\n')
            (run / 'quick-smoke-guest.txt').write_text('\n'.join('PASS: ' + name for name in state.QUICK) + '\n')
        record['case_outputs'] = {name: state.common.digest(run / name) for name in state.report_files(record)}
        self.save(run, record)
        return run, record

    def test_all_eight_diagnostics_require_host_completion_and_stay_unqualified(self):
        for profile in state.artifacts.PROFILES:
            with self.subTest(profile=profile):
                run, _ = self.attempt(profile)
                result = state.verify(self.root, run, completing=True)
                self.assertTrue(result['completed'])
                self.assertTrue(result['host_tree_exit_verified'])
                self.assertFalse(result['qualification'])
                self.assertEqual(result, state.verify(self.root, run))

    def test_late_debuggerd_even_with_rebound_final_hash_never_completes(self):
        for crash in ('*** *** ***', 'FATAL EXCEPTION: main', '>>> org.longreachqt.donut <<<'):
            run, record = self.attempt()
            (run / 'final-logcat.log').write_text(crash + '\n')
            record['final_logcat_sha256'] = state.common.digest(run / 'final-logcat.log')
            self.save(run, record)
            with self.subTest(crash=crash), self.assertRaisesRegex(ValueError, 'Fatal API4'):
                state.verify(self.root, run, completing=True)
            self.assertFalse(state.common.read_json(run / 'run-inputs.json')['completed'])

    def test_writable_userdata_is_separate_from_immutable_media_and_dependencies(self):
        run, _ = self.attempt()
        (run / 'userdata-qemu.img').write_text('expected guest writes')
        state.verify(self.root, run, completing=True)
        for relative in ('inputs/tools/lib/fixture.dll', 'inputs/android-1.6_r03-linux/images/system.img'):
            path = self.root / relative
            previous = path.read_bytes()
            path.write_text('changed media')
            with self.subTest(relative=relative), self.assertRaisesRegex(ValueError, 'emulator/media changed'):
                state.verify(self.root, run)
            path.write_bytes(previous)
        extra = self.root / 'inputs/tools/extra.dll'
        extra.write_text('extra dependency')
        with self.assertRaisesRegex(ValueError, 'emulator/media changed'):
            state.verify(self.root, run)

    def test_modified_argv_is_rejected_even_when_the_launch_digest_is_rebound(self):
        run, record = self.attempt()
        launch = state.common.read_json(run / 'emulator-launch.json')
        launch['arguments'][launch['arguments'].index('-memory') + 1] = '64'
        state.common.write_json(run / 'emulator-launch.json', launch)
        record['emulator_launch_sha256'] = state.common.digest(run / 'emulator-launch.json')
        self.save(run, record)
        with self.assertRaisesRegex(ValueError, 'invocation differs'):
            state.verify(self.root, run, completing=True)

    def test_active_or_unbound_host_tree_cannot_complete(self):
        for fault in ('active', 'missing', 'case-binding', 'lease'):
            run, record = self.attempt()
            if fault == 'missing':
                (run / host.owned.EXIT).unlink()
            elif fault == 'case-binding':
                record['host_process_owner_sha256'] = '0' * 64
            else:
                proof = state.common.read_json(run / host.owned.EXIT)
                if fault == 'active':
                    proof['active_processes'] = 1
                else:
                    proof['artifact_lease_held_until_exit'] = False
                state.common.write_json(run / host.owned.EXIT, proof)
                record['host_process_exit_sha256'] = state.common.digest(run / host.owned.EXIT)
            self.save(run, record)
            with self.subTest(fault=fault), self.assertRaises((ValueError, OSError)):
                state.verify(self.root, run, completing=True)
            self.assertFalse(state.common.read_json(run / 'run-inputs.json')['completed'])

    def test_report_and_return_semantics_still_reject_rebound_output_digests(self):
        for profile, name, text, error in (
                ('core', 'case-logcat.log', 'I/LongreachDonut: Native probe returned 0\nI/LongreachDonut: Native probe returned 0\nQtCore 4.8.7 PASS\n', 'ambiguous'),
                ('quick', 'quick-smoke-guest.txt', 'PASS: qrc and first frame\n', 'required behavior'),
                ('quick', 'quick-smoke-guest.txt', '\n'.join('PASS: ' + name for name in state.QUICK) + '\nSKIP: ' + state.QUICK[0] + '\n', 'required behavior'),
                ('strict', 'strict-cxx23-guest.stdout', '__cplusplus: 202302\nSUMMARY: 0 passed, 0 failed, 0 skipped\n', 'must PASS'),
                ('network', 'network-gui-guest.stdout', 'FAIL: observed failure\n---- network-gui: 2 passed, 0 failed, 0 skipped ----\n', 'failed named')):
            run, record = self.attempt(profile)
            (run / name).write_text(text)
            record['case_outputs'][name] = state.common.digest(run / name)
            self.save(run, record)
            with self.subTest(profile=profile), self.assertRaisesRegex((ValueError, RuntimeError), error):
                state.verify(self.root, run, completing=True)

    def test_missing_or_empty_final_capture_cannot_complete_a_diagnostic(self):
        for fault in ('missing', 'empty', 'wrong-owner'):
            run, record = self.attempt()
            path = run / 'final-logcat-capture.json'
            if fault == 'missing':
                path.unlink()
            else:
                value = state.common.read_json(path)
                if fault == 'empty':
                    value['captured'] = False
                else:
                    value['host_process_owner_sha256'] = '0' * 64
                state.common.write_json(path, value)
            with self.subTest(fault=fault), self.assertRaises((ValueError, OSError)):
                state.verify(self.root, run, completing=True)
            self.assertFalse(state.common.read_json(run / 'run-inputs.json')['completed'])

    def test_cleanup_replacement_of_report_and_final_log_changes_is_rejected(self):
        run, _ = self.attempt('selftest')
        (run / 'qt-selftest-guest.stdout').write_text('late replaced report')
        with self.assertRaisesRegex(ValueError, 'output changed'):
            state.verify(self.root, run, completing=True)
        run, _ = self.attempt()
        state.verify(self.root, run, completing=True)
        (run / 'final-logcat.log').write_text('replacement without crash')
        with self.assertRaisesRegex(ValueError, 'unchanged completed|final log capture'):
            state.verify(self.root, run)


if __name__ == '__main__':
    unittest.main()
