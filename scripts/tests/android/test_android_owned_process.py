# SPDX-License-Identifier: GPL-3.0-or-later
"""Ordinary metadata and bounded host-process fixtures; no Android executable."""
import contextlib
import importlib.util
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import time
import unittest
import uuid

ROOT = Path(__file__).resolve().parents[3]
HELPER = ROOT / 'scripts/run/android/android-owned-process.py'
spec = importlib.util.spec_from_file_location('ordinary_owned_process', HELPER)
owned = importlib.util.module_from_spec(spec)
spec.loader.exec_module(owned)


def launch_spec(directory, program, arguments, owner_pid=1, owner_time='1'):
    value = {'schema_version': 1, 'run_id': uuid.uuid4().hex, 'owner_pid': owner_pid,
             'owner_creation_filetime': owner_time, 'program': str(program),
             'program_sha256': owned.digest(program), 'arguments': arguments,
             'cwd': str(directory), 'stdout': 'emulator.stdout', 'stderr': 'emulator.stderr'}
    owned.write(directory / owned.REQUEST, value)
    return value


def synthetic(directory):
    program = directory / 'program-fixture-data'
    program.write_text('metadata only, never executed')
    value = launch_spec(directory, program, ['fixture argument with spaces'])
    owner = {'schema_version': 1, 'backend': owned.BACKEND, 'run_id': value['run_id'],
             'request_sha256': owned.digest(directory / owned.REQUEST),
             'supervisor_pid': 123, 'supervisor_creation_filetime': '123',
             'frontend_pid': 456, 'frontend_creation_filetime': '456', 'contained_before_start': True, 'host_slot': owned.HOST_SLOT, 'host_slot_acquired_before_start': True}
    owned.write(directory / owned.OWNER, owner)
    for name in ('emulator.stdout', 'emulator.stderr'):
        (directory / name).write_text('synthetic process log')
    proof = {'schema_version': 1, 'backend': owned.BACKEND, 'run_id': value['run_id'],
             'request_sha256': owner['request_sha256'], 'owner_sha256': owned.digest(directory / owned.OWNER),
             'supervisor_pid': 123, 'frontend_pid': 456, 'active_processes': 0, 'total_processes': 3,
             'frontend_exit_code': 0, 'reason': 'requested', 'forced': True, 'host_tree_exit_confirmed': True, 'host_slot_held_until_tree_exit': True,
             'frontend_signaled': True, 'logs_closed_before_hash': True, 'frontend_exited_before_stop': True,
             'stdout_sha256': owned.digest(directory / 'emulator.stdout'), 'stderr_sha256': owned.digest(directory / 'emulator.stderr')}
    owned.write(directory / owned.EXIT, proof)
    return value, owner, proof


class Receipt(unittest.TestCase):
    def test_log_capture_shares_the_frozen_endpoint_and_completed_job(self):
        for changed in (None, 'endpoint', 'owner', 'count', 'log'):
            with self.subTest(changed=changed), tempfile.TemporaryDirectory() as folder:
                root = Path(folder)
                spec, owner, proof = synthetic(root)
                spec['adb_endpoint'] = {'schema_version': 1, 'host': 'localhost', 'port': 5061, 'socket': 'tcp:localhost:5061'}
                owned.write(root / owned.REQUEST, spec)
                owner.update(request_sha256=owned.digest(root / owned.REQUEST), adb_endpoint_applied_before_start=True)
                owned.write(root / owned.OWNER, owner)
                proof.update(request_sha256=owner['request_sha256'], owner_sha256=owned.digest(root / owned.OWNER))
                adb = root / 'adb.exe'
                adb.write_text('metadata only, never executed')
                remote = '/data/local/longreach-log-' + 'a' * 32 + '.log'
                capture = dict(schema_version=1, run_id=spec['run_id'], request_sha256=owner['request_sha256'],
                               serial='emulator-5580', remote_file=remote, program=str(adb), program_sha256=owned.digest(adb),
                               arguments=['-H', 'localhost', '-P', '5061', '-s', 'emulator-5580', 'shell', 'logcat', '-v', 'brief', '-f', remote])
                if changed == 'endpoint':
                    capture['arguments'][3] = '5037'
                owned.write(root / owned.LOG_REQUEST, capture)
                child = dict(schema_version=1, run_id=spec['run_id'], request_sha256=owner['request_sha256'],
                             capture_request_sha256=owned.digest(root / owned.LOG_REQUEST), client_pid=789,
                             client_creation_filetime='789', contained_before_start=True)
                if changed == 'owner':
                    child['capture_request_sha256'] = '0' * 64
                owned.write(root / owned.LOG_OWNER, child)
                for kind in ('stdout', 'stderr'):
                    (root / ('logcat-client.' + kind)).write_text('retained capture output')
                    proof['log_capture_' + kind + '_sha256'] = owned.digest(root / ('logcat-client.' + kind))
                proof.update(log_capture_request_sha256=owned.digest(root / owned.LOG_REQUEST),
                             log_capture_owner_sha256=owned.digest(root / owned.LOG_OWNER))
                if changed == 'count':
                    proof['total_processes'] = 1
                owned.write(root / owned.EXIT, proof)
                if changed == 'log':
                    (root / 'logcat-client.stderr').write_text('replaced capture output')
                if changed:
                    with self.assertRaisesRegex(ValueError, 'Log capture'):
                        owned.validate_log_capture(root)
                else:
                    self.assertEqual(owned.validate_log_capture(root)['log_capture_owner_sha256'], proof['log_capture_owner_sha256'])

    def test_exact_request_owner_exit_and_both_logs_are_bound(self):
        for changed in (owned.REQUEST, owned.OWNER, 'emulator.stdout', 'emulator.stderr'):
            with self.subTest(changed=changed), tempfile.TemporaryDirectory() as folder:
                root = Path(folder)
                synthetic(root)
                bindings = owned.validate(root)
                self.assertEqual(owned.validate(root, bindings), bindings)
                with (root / changed).open('a') as stream:
                    stream.write('\n')
                with self.assertRaisesRegex(ValueError, 'differs|changed|confirmed'):
                    owned.validate(root)

    def test_exit_counts_reasons_and_complete_flags_are_required(self):
        for field, value in [('active_processes', 1), ('active_processes', False), ('total_processes', 0),
                             ('host_tree_exit_confirmed', False), ('frontend_signaled', False), ('logs_closed_before_hash', False), ('reason', 'owner-exited'),
                             ('frontend_pid', 999), ('run_id', 'b' * 32), ('forced', 'true')]:
            with self.subTest(field=field, value=value), tempfile.TemporaryDirectory() as folder:
                root = Path(folder)
                _, _, proof = synthetic(root)
                proof[field] = value
                owned.write(root / owned.EXIT, proof)
                with self.assertRaisesRegex(ValueError, 'not confirmed'):
                    owned.validate(root)

    def test_natural_nonzero_exit_and_forced_natural_are_not_success(self):
        for code, forced in ((1, False), (0, True)):
            with tempfile.TemporaryDirectory() as folder:
                root = Path(folder)
                _, _, proof = synthetic(root)
                proof.update(reason='natural', frontend_exit_code=code, forced=forced)
                owned.write(root / owned.EXIT, proof)
                with self.assertRaisesRegex(ValueError, 'not exit successfully'):
                    owned.validate(root)

    def test_case_bindings_and_supervisor_failure_refuse_completion(self):
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            synthetic(root)
            bindings = owned.validate(root)
            bindings['host_process_exit_sha256'] = '0' * 64
            with self.assertRaisesRegex(ValueError, 'different owned-process evidence'):
                owned.validate(root, bindings)
            owned.write(root / owned.FAILED, {'error': 'fixture failed startup'})
            with self.assertRaisesRegex(ValueError, 'supervisor failed'):
                owned.validate(root)

    def test_declared_artifact_lease_requires_owner_and_exit_evidence(self):
        with tempfile.TemporaryDirectory() as folder:
            artifact_root=Path(folder)
            root=artifact_root/'run'
            root.mkdir()
            request,owner,proof=synthetic(root)
            request['artifact_lease']={'root':str(artifact_root),'handle':'123'}
            owned.write(root/owned.REQUEST,request)
            owner['request_sha256']=owned.digest(root/owned.REQUEST)
            proof['request_sha256']=owner['request_sha256']
            for mutation in ('owner','exit','root'):
                with self.subTest(mutation=mutation):
                    owner.update(artifact_lease_held=(mutation!='owner'),artifact_lease_root=str(artifact_root if mutation!='root' else root))
                    proof['artifact_lease_held_until_exit']=(mutation!='exit')
                    owned.write(root/owned.OWNER,owner)
                    proof['owner_sha256']=owned.digest(root/owned.OWNER)
                    owned.write(root/owned.EXIT,proof)
                    with self.assertRaisesRegex(ValueError,'Artifact lease was not held'):
                        owned.validate(root)
            owner.update(artifact_lease_held=True,artifact_lease_root=str(artifact_root))
            proof['artifact_lease_held_until_exit']=True
            owned.write(root/owned.OWNER,owner)
            proof['owner_sha256']=owned.digest(root/owned.OWNER)
            owned.write(root/owned.EXIT,proof)
            owned.validate(root)

    def test_host_slot_identity_and_lifetime_are_mandatory(self):
        for mutation in ('missing-owner', 'wrong-name', 'late-acquisition', 'early-release', 'missing-exit', 'legacy-backend'):
            with self.subTest(mutation=mutation), tempfile.TemporaryDirectory() as folder:
                root = Path(folder)
                _, owner, proof = synthetic(root)
                if mutation == 'missing-owner': owner.pop('host_slot')
                elif mutation == 'wrong-name': owner['host_slot'] = 'another slot'
                elif mutation == 'late-acquisition': owner['host_slot_acquired_before_start'] = False
                elif mutation == 'early-release': proof['host_slot_held_until_tree_exit'] = False
                elif mutation == 'missing-exit': proof.pop('host_slot_held_until_tree_exit')
                else: owner['backend'] = 'windows-job-startup-v1'
                owned.write(root / owned.OWNER, owner)
                proof['owner_sha256'] = owned.digest(root / owned.OWNER)
                owned.write(root / owned.EXIT, proof)
                with self.assertRaises(ValueError):
                    owned.validate(root)

    def test_endpoint_descriptor_is_canonical_and_applied_before_start(self):
        base = {'schema_version': 1, 'host': 'localhost', 'port': 5048, 'socket': 'tcp:localhost:5048'}
        for field, value in (('port', True), ('port', 0), ('port', 65536), ('host', '192.0.2.1'),
                             ('socket', 'tcp:localhost:5037'), ('schema_version', True), ('extra', 'ignored')):
            with self.subTest(field=field, value=value), tempfile.TemporaryDirectory() as folder:
                root = Path(folder)
                request, owner, proof = synthetic(root)
                request['adb_endpoint'] = dict(base)
                request['adb_endpoint'][field] = value
                owned.write(root / owned.REQUEST, request)
                owner['request_sha256'] = owned.digest(root / owned.REQUEST)
                owner['adb_endpoint_applied_before_start'] = True
                owned.write(root / owned.OWNER, owner)
                proof.update(request_sha256=owner['request_sha256'], owner_sha256=owned.digest(root / owned.OWNER))
                owned.write(root / owned.EXIT, proof)
                with self.assertRaisesRegex(ValueError, 'Invalid frozen Android ADB endpoint'):
                    owned.validate(root)
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            request, owner, proof = synthetic(root)
            request['adb_endpoint'] = base
            owned.write(root / owned.REQUEST, request)
            owner['request_sha256'] = owned.digest(root / owned.REQUEST)
            owned.write(root / owned.OWNER, owner)
            proof.update(request_sha256=owner['request_sha256'], owner_sha256=owned.digest(root / owned.OWNER))
            owned.write(root / owned.EXIT, proof)
            with self.assertRaisesRegex(ValueError, 'not applied before'):
                owned.validate(root)

    def test_emulator_receipt_requires_endpoint_but_generic_receipt_remains_valid(self):
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            request, owner, proof = synthetic(root)
            owned.validate(root)
            with self.assertRaisesRegex(ValueError, 'Missing frozen ADB endpoint'):
                owned.validate_emulator(root, program_sha256=request['program_sha256'], arguments=request['arguments'])
            request['adb_endpoint'] = {'schema_version': 1, 'host': 'localhost', 'port': 5048, 'socket': 'tcp:localhost:5048'}
            owned.write(root / owned.REQUEST, request)
            owner.update(request_sha256=owned.digest(root / owned.REQUEST), adb_endpoint_applied_before_start=True)
            owned.write(root / owned.OWNER, owner)
            proof.update(request_sha256=owner['request_sha256'], owner_sha256=owned.digest(root / owned.OWNER))
            owned.write(root / owned.EXIT, proof)
            owned.validate_emulator(root, program_sha256=request['program_sha256'], arguments=request['arguments'])
            bindings = owned.validate(root)
            bindings['adb_endpoint'] = {'schema_version': 1, 'host': 'localhost', 'port': 5049, 'socket': 'tcp:localhost:5049'}
            with self.assertRaisesRegex(ValueError, 'Case ADB endpoint differs'):
                owned.validate_emulator(root, bindings=bindings, program_sha256=request['program_sha256'], arguments=request['arguments'])

    def test_output_paths_and_launch_arguments_are_checked(self):
        for field, value in [('stdout', '../input.apk'), ('arguments', 'one string'), ('arguments', ['nul\0arg']),
                             ('owner_pid', 0), ('owner_creation_filetime', '0'), ('program', 'relative.exe')]:
            with self.subTest(field=field), tempfile.TemporaryDirectory() as folder:
                root = Path(folder)
                request, _, _ = synthetic(root)
                request[field] = value
                owned.write(root / owned.REQUEST, request)
                with self.assertRaisesRegex(ValueError, 'Invalid owned-process'):
                    owned.request(root)


@unittest.skipUnless(os.name == 'nt', 'Real Windows job ownership requires a Windows 10+ host')
class WindowsTree(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory(prefix='longreach-owned-process-')
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)
        self.stack = contextlib.ExitStack()
        self.addCleanup(self.stack.close)
        self.helpers = []
        self.addCleanup(self.stop_helpers)

    def stop_helpers(self):
        # Popen retains the specific process handle; never stop by a reused PID.
        for process in reversed(self.helpers):
            if process.poll() is None:
                process.kill()
            process.wait(timeout=5)
        # The parent-exit fixture starts its worker in a separate controlled
        # parent. Retain and compare that worker's creation time before cleanup;
        # a reused numeric PID must never select an unrelated process.
        if (self.root / owned.OWNER).exists():
            owner, _ = owned.read(self.root / owned.OWNER)
            handle = owned.open_process(0x100001 | 0x1000, False, owner['supervisor_pid'])
            if handle:
                try:
                    if (owned.creation_time(handle) == owner['supervisor_creation_filetime'] and
                            owned.wait_handle(handle, 0) == 258):
                        terminate = owned.api('TerminateProcess', owned.w.BOOL, owned.w.HANDLE, owned.w.UINT)
                        # It may exit between the zero-time wait and termination.
                        if not terminate(handle, 1) and owned.wait_handle(handle, 1000) != 0:
                            raise OSError('Owned fixture supervisor did not stop')
                        self.assertEqual(owned.wait_handle(handle, 5000), 0)
                finally:
                    owned.close_handle(handle)
        for name in ('emulator.stdout', 'emulator.stderr'):
            if (self.root / name).exists():
                owned.completed_log_digest(self.root / name)

    def popen(self, argv, **extra):
        error_file = self.stack.enter_context((self.root / ('helper-'+uuid.uuid4().hex+'.log')).open('wb'))
        process = subprocess.Popen(argv, stdout=subprocess.DEVNULL, stderr=error_file,
                                   creationflags=subprocess.CREATE_NO_WINDOW,
                                   env=dict(os.environ, PYTHONUTF8='1'), **extra)
        self.helpers.append(process)
        return process

    def wait_for(self, predicate, timeout=10):
        deadline = time.monotonic() + timeout
        while time.monotonic() < deadline:
            try:
                result = predicate()
                if result:
                    return result
            except (FileNotFoundError, json.JSONDecodeError, ValueError):
                pass
            time.sleep(.01)
        self.fail('Bounded ordinary process fixture timed out')

    def start(self, code, arguments=(), owner_time=None):
        return self.start_at(self.root, code, arguments, owner_time)

    def start_at(self, directory, code, arguments=(), owner_time=None):
        request = launch_spec(directory, Path(sys.executable).resolve(), ['-c', code, *arguments],
                              os.getpid(), owner_time or owned.process_creation_time(os.getpid()))
        sha = owned.digest(directory / owned.REQUEST)
        process = self.popen([sys.executable, str(HELPER), 'supervise', '--directory', str(directory), '--request-sha256', sha])
        return process, request, sha

    def retain(self, pid_path):
        pid = self.wait_for(lambda: int(pid_path.read_text()))
        handle = owned.checked(owned.open_process(0x100000 | 0x1000, False, pid))
        self.stack.callback(owned.close_handle, handle)
        self.assertEqual(owned.wait_handle(handle, 0), 258)
        return handle

    def descendant_code(self):
        leaf = 'import time; time.sleep(60)'
        middle = ('import pathlib,subprocess,sys,time; '
                  f'p=subprocess.Popen([sys.executable,"-c",{leaf!r}],creationflags=0x08000000); '
                  f'pathlib.Path({str(self.root / "grandchild.pid")!r}).write_text(str(p.pid)); time.sleep(60)')
        return ('import pathlib,subprocess,sys; '
                f'p=subprocess.Popen([sys.executable,"-c",{middle!r}],creationflags=0x08000000); '
                f'pathlib.Path({str(self.root / "child.pid")!r}).write_text(str(p.pid)); print("frontend returned",flush=True)')

    def test_frontend_exit_keeps_descendants_owned_and_control_unaffected(self):
        control = self.popen([sys.executable, '-c', 'import time; time.sleep(60)'])
        supervisor, request, sha = self.start(self.descendant_code())
        self.wait_for(lambda: (self.root / owned.OWNER).exists())
        children = [self.retain(self.root / name) for name in ('child.pid', 'grandchild.pid')]
        self.assertIsNone(supervisor.poll(), 'Frontend exit ended ownership while descendants remained')
        owned.write(self.root / owned.STOP, {'run_id': request['run_id'], 'request_sha256': sha, 'grace_ms': 0})
        self.assertEqual(supervisor.wait(timeout=10), 0)
        proof, _ = owned.read(self.root / owned.EXIT)
        self.assertGreaterEqual(proof['total_processes'], 3)
        self.assertTrue(proof['forced'])
        self.assertEqual(proof['frontend_exit_code'], 0)
        owned.validate(self.root)
        for handle in children:
            self.assertEqual(owned.wait_handle(handle, 5000), 0)
        self.assertIsNone(control.poll(), 'Unrelated control process was stopped')

    def test_natural_exit_preserves_exact_windows_argv_and_logs(self):
        arguments = ['two words', 'embedded"quote', 'trailing\\', 'кириллица']
        supervisor, _, _ = self.start('import json,sys; print(json.dumps(sys.argv[1:],ensure_ascii=False))', arguments)
        self.assertEqual(supervisor.wait(timeout=10), 0)
        self.assertEqual(json.loads((self.root / 'emulator.stdout').read_text(encoding='utf-8')), arguments)
        proof, _ = owned.read(self.root / owned.EXIT)
        self.assertEqual((proof['reason'], proof['forced']), ('natural', False))
        self.assertGreaterEqual(proof['total_processes'], 1)
        owned.validate(self.root)

    def test_existing_logs_are_preserved_and_frontend_never_starts(self):
        log = self.root / 'emulator.stdout'
        log.write_text('preserved earlier evidence')
        supervisor, _, _ = self.start('raise RuntimeError("must not run")')
        self.assertNotEqual(supervisor.wait(timeout=10), 0)
        self.assertEqual(log.read_text(), 'preserved earlier evidence')
        self.assertFalse((self.root / owned.OWNER).exists())
        self.assertTrue((self.root / owned.FAILED).exists())

    def test_wrong_stop_attempt_refuses_completion_and_stops_owned_job(self):
        supervisor, request, sha = self.start('import time; time.sleep(60)')
        owner = self.wait_for(lambda: owned.read(self.root / owned.OWNER)[0])
        handle = owned.checked(owned.open_process(0x100000 | 0x1000, False, owner['frontend_pid']))
        self.stack.callback(owned.close_handle, handle)
        owned.write(self.root / owned.STOP, {'run_id': 'f' * 32, 'request_sha256': sha, 'grace_ms': 0})
        self.assertNotEqual(supervisor.wait(timeout=10), 0)
        self.assertEqual(owned.wait_handle(handle, 5000), 0)
        self.assertFalse((self.root / owned.EXIT).exists())
        with self.assertRaisesRegex(ValueError, 'supervisor failed'):
            owned.validate(self.root)

    def test_parent_identity_refusal_happens_before_frontend_creation(self):
        supervisor, _, _ = self.start('raise RuntimeError("must not run")', owner_time='1')
        self.assertNotEqual(supervisor.wait(timeout=10), 0)
        self.assertFalse((self.root / owned.OWNER).exists())
        self.assertFalse((self.root / 'emulator.stdout').exists())
        self.assertTrue((self.root / owned.FAILED).exists())

    def test_failed_frontend_with_live_children_cannot_be_qualified(self):
        supervisor, request, sha = self.start(self.descendant_code()+'; sys.exit(1)')
        owner = self.wait_for(lambda: owned.read(self.root / owned.OWNER)[0])
        self.retain(self.root / 'child.pid')
        self.retain(self.root / 'grandchild.pid')
        handle = owned.checked(owned.open_process(0x100000 | 0x1000, False, owner['frontend_pid']))
        self.stack.callback(owned.close_handle, handle)
        self.assertEqual(owned.wait_handle(handle, 5000), 0)
        owned.write(self.root / owned.STOP, {'run_id': request['run_id'], 'request_sha256': sha, 'grace_ms': 0})
        self.assertEqual(supervisor.wait(timeout=10), 0)
        proof, _ = owned.read(self.root / owned.EXIT)
        self.assertTrue(proof['frontend_exited_before_stop'])
        self.assertEqual((proof['frontend_exit_code'], proof['active_processes']), (1, 0))
        with self.assertRaisesRegex(ValueError, 'not exit successfully'):
            owned.validate(self.root)

    def test_supervisor_termination_closes_job_and_cannot_publish_success(self):
        supervisor, _, _ = self.start(self.descendant_code())
        self.wait_for(lambda: (self.root / owned.OWNER).exists())
        children = [self.retain(self.root / name) for name in ('child.pid', 'grandchild.pid')]
        supervisor.kill()
        supervisor.wait(timeout=5)
        for handle in children:
            self.assertEqual(owned.wait_handle(handle, 5000), 0)
        self.assertFalse((self.root / owned.EXIT).exists())
        with self.assertRaises(FileNotFoundError):
            owned.validate(self.root)

    def test_different_roots_cannot_launch_until_the_first_tree_completely_exits(self):
        first, second, third = (self.root / name for name in ('first', 'second', 'third'))
        for directory in (first, second, third): directory.mkdir()
        def close_logs():
            for directory in (first, second, third):
                for name in ('emulator.stdout', 'emulator.stderr'):
                    if (directory / name).exists(): owned.completed_log_digest(directory / name)
        self.stack.callback(close_logs)
        supervisor, request, sha = self.start_at(first, self.descendant_code())
        self.wait_for(lambda: (first / owned.OWNER).exists())
        descendants = [self.retain(self.root / name) for name in ('child.pid', 'grandchild.pid')]
        before = owned.digest(first / owned.OWNER)
        marker = second / 'frontend-started.txt'
        contender, _, _ = self.start_at(second, 'from pathlib import Path; Path(' + repr(str(marker)) + ').write_text("started")')
        self.assertNotEqual(contender.wait(timeout=10), 0)
        failure, _ = owned.read(second / owned.FAILED)
        self.assertIn('Another Android emulator owns the host slot', failure['error'])
        self.assertFalse(marker.exists())
        self.assertFalse((second / owned.OWNER).exists())
        self.assertFalse((second / 'emulator.stdout').exists())
        self.assertEqual(owned.digest(first / owned.OWNER), before)
        self.assertTrue(all(owned.wait_handle(handle, 0) == 258 for handle in descendants))
        owned.write(first / owned.STOP, {'run_id': request['run_id'], 'request_sha256': sha, 'grace_ms': 0})
        self.assertEqual(supervisor.wait(timeout=10), 0)
        owned.validate(first)
        self.assertTrue(all(owned.wait_handle(handle, 5000) == 0 for handle in descendants))
        next_worker, _, _ = self.start_at(third, 'print("next host owner")')
        self.assertEqual(next_worker.wait(timeout=10), 0)
        owned.validate(third)

    def test_abandoned_host_slot_is_not_silently_reused(self):
        driver = self.root / 'slot-owner.py'
        driver.write_text('import importlib.util,pathlib,sys,time\n'
                         'spec=importlib.util.spec_from_file_location("owned",sys.argv[1]); '
                         'owned=importlib.util.module_from_spec(spec); spec.loader.exec_module(owned)\n'
                         'handle=owned.acquire_host_slot(); pathlib.Path(sys.argv[2]).write_text("held"); time.sleep(60)\n')
        marker = self.root / 'slot-held.txt'
        owner = self.popen([sys.executable, str(driver), str(HELPER), str(marker)])
        self.wait_for(marker.exists)
        # Keep this object alive after its owning thread is terminated.
        handle = owned.checked(owned.mutex_create(None, False, owned.HOST_SLOT))
        self.stack.callback(owned.close_handle, handle)
        owner.kill()
        owner.wait(timeout=5)
        started = self.root / 'must-not-start.txt'
        worker, _, _ = self.start('from pathlib import Path; Path(' + repr(str(started)) + ').touch()')
        self.assertNotEqual(worker.wait(timeout=10), 0)
        failure, _ = owned.read(self.root / owned.FAILED)
        self.assertIn('host slot was abandoned', failure['error'])
        self.assertFalse(started.exists())
        self.assertFalse((self.root / owned.OWNER).exists())

    def test_duplicate_supervisor_refuses_without_overwriting_active_owner(self):
        supervisor, request, sha = self.start('import time; time.sleep(60)')
        self.wait_for(lambda: (self.root / owned.OWNER).exists())
        before = owned.digest(self.root / owned.OWNER)
        contender = self.popen([sys.executable, str(HELPER), 'supervise', '--directory', str(self.root), '--request-sha256', sha])
        self.assertNotEqual(contender.wait(timeout=10), 0)
        self.assertEqual(owned.digest(self.root / owned.OWNER), before)
        self.assertFalse((self.root / owned.FAILED).exists())
        owned.write(self.root / owned.STOP, {'run_id': request['run_id'], 'request_sha256': sha, 'grace_ms': 0})
        self.assertEqual(supervisor.wait(timeout=10), 0)
        owned.validate(self.root)

    def test_parent_exit_stops_owned_tree_but_is_not_qualification(self):
        driver = self.root / 'parent.py'
        driver.write_text('''import importlib.util,os,pathlib,subprocess,sys,time,uuid
spec=importlib.util.spec_from_file_location('owned',sys.argv[1]); owned=importlib.util.module_from_spec(spec); spec.loader.exec_module(owned)
root=pathlib.Path(sys.argv[2]); program=pathlib.Path(sys.executable).resolve()
code='import pathlib,os,time; pathlib.Path('+repr(str(root/'child.pid'))+').write_text(str(os.getpid())); time.sleep(60)'
request=dict(schema_version=1,run_id=uuid.uuid4().hex,owner_pid=os.getpid(),owner_creation_filetime=owned.process_creation_time(os.getpid()),program=str(program),program_sha256=owned.digest(program),arguments=['-c',code],cwd=str(root),stdout='emulator.stdout',stderr='emulator.stderr')
owned.write(root/owned.REQUEST,request)
worker=subprocess.Popen([sys.executable,sys.argv[1],'supervise','--directory',str(root),'--request-sha256',owned.digest(root/owned.REQUEST)],creationflags=0x08000000,stdout=subprocess.DEVNULL,stderr=subprocess.DEVNULL)
try:
    deadline=time.monotonic()+10
    while not (root/'release-parent').exists() and time.monotonic()<deadline: time.sleep(.01)
finally:
    # Exiting this parent is the event the retained owner handle must observe.
    pass
''', encoding='utf-8')
        parent = self.popen([sys.executable, str(driver), str(HELPER), str(self.root)])
        self.wait_for(lambda: (self.root / owned.OWNER).exists())
        child = self.retain(self.root / 'child.pid')
        (self.root / 'release-parent').touch()
        self.assertEqual(parent.wait(timeout=10), 0)
        self.wait_for(lambda: (self.root / owned.EXIT).exists())
        self.assertEqual(owned.wait_handle(child, 5000), 0)
        proof, _ = owned.read(self.root / owned.EXIT)
        self.assertEqual((proof['reason'], proof['active_processes']), ('owner-exited', 0))
        with self.assertRaisesRegex(ValueError, 'not confirmed'):
            owned.validate(self.root)


if __name__ == '__main__':
    unittest.main()
