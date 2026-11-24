# SPDX-License-Identifier: GPL-3.0-or-later
"""Own a Windows process tree before its first instruction; verify exit receipts.

This module uses ctypes and standard-library files only. Native supervision
requires Windows 10+; receipt validation is platform independent. Runner wiring
uses the companion PowerShell interface.
"""
import argparse
import contextlib
import ctypes
import hashlib
import importlib.util
import json
import os
from pathlib import Path
import re
import subprocess
import time
import uuid

BACKEND = 'windows-job-startup-v2'
HOST_SLOT = r'Global\OpenKaryon.LongreachQt.AndroidEmulatorSlot.v1'
REQUEST = 'host-process-request.json'
OWNER = 'host-process-owner.json'
EXIT = 'host-process-exit.json'
STOP = 'host-process-stop.json'
FAILED = 'host-process-failed.json'
LOG_REQUEST = 'host-logcat-request.json'
LOG_OWNER = 'host-logcat-owner.json'

_endpoint_spec = importlib.util.spec_from_file_location('owned_adb_endpoint', Path(__file__).with_name('android-adb-endpoint.py'))
endpoint = importlib.util.module_from_spec(_endpoint_spec)
_endpoint_spec.loader.exec_module(endpoint)


def digest(path):
    result = hashlib.sha256()
    with Path(path).open('rb') as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b''):
            result.update(block)
    return result.hexdigest()


def read(path):
    data = Path(path).read_bytes()
    return json.loads(data.decode('utf-8-sig')), hashlib.sha256(data).hexdigest()


def write(path, value):
    path = Path(path)
    temporary = path.with_name(path.name + '.' + uuid.uuid4().hex + '.tmp')
    try:
        temporary.write_text(json.dumps(value, indent=2, sort_keys=True) + '\n', encoding='utf-8')
        temporary.replace(path)
    finally:
        temporary.unlink(missing_ok=True)


def integer(value, low=0):
    return type(value) is int and value >= low


def token(pattern, value):
    return isinstance(value, str) and re.fullmatch(pattern, value) is not None


def request(directory):
    directory = Path(directory).resolve()
    value, sha = read(directory / REQUEST)
    if (not isinstance(value, dict) or value.get('schema_version') != 1 or
            not token('[0-9a-f]{32}', value.get('run_id', '')) or
            not integer(value.get('owner_pid'), 1) or
            not token('[1-9][0-9]*', value.get('owner_creation_filetime', '')) or
            not isinstance(value.get('program'), str) or not Path(value['program']).is_absolute() or
            not token('[0-9a-f]{64}', value.get('program_sha256', '')) or
            not isinstance(value.get('arguments'), list) or
            any(not isinstance(arg, str) or '\0' in arg for arg in value['arguments'])):
        raise ValueError('Invalid owned-process request')
    if '\0' in value['program'] or not isinstance(value.get('cwd'), str) or not Path(value['cwd']).is_absolute():
        raise ValueError('Invalid owned-process program or working directory')
    # Output names are fixed, avoiding redirects into retained SDK/input files.
    if value.get('stdout') != 'emulator.stdout' or value.get('stderr') != 'emulator.stderr':
        raise ValueError('Invalid owned-process output paths')
    if 'adb_endpoint' in value:
        endpoint.validate(value['adb_endpoint'])
    if 'artifact_lease' in value:
        lease = value['artifact_lease']
        if (not isinstance(lease, dict) or not isinstance(lease.get('root'), str) or
                not Path(lease['root']).is_absolute() or not token('[1-9][0-9]*', lease.get('handle', '')) or
                directory == Path(lease['root']).resolve() or not directory.is_relative_to(Path(lease['root']).resolve())):
            raise ValueError('Invalid owned-process artifact lease')
    return value, sha


def log_capture_request(directory, spec, request_sha):
    value, sha = read(Path(directory) / LOG_REQUEST)
    if not isinstance(value, dict):
        raise ValueError('Invalid owned log capture request')
    remote = value.get('remote_file', '')
    if (value.get('schema_version') != 1 or value.get('run_id') != spec['run_id']
            or value.get('request_sha256') != request_sha or 'adb_endpoint' not in spec
            or not token(r'/data/local/longreach-log-[0-9a-f]{32}\.log', remote)
            or value.get('serial') != 'emulator-5580'
            or not isinstance(value.get('program'), str) or not Path(value['program']).is_absolute()
            or Path(value['program']).name.lower() != 'adb.exe'
            or not token('[0-9a-f]{64}', value.get('program_sha256', ''))):
        raise ValueError('Invalid owned log capture request')
    expected = ['-H', 'localhost', '-P', str(spec['adb_endpoint']['port']), '-s', value['serial'],
                'shell', 'logcat', '-v', 'brief', '-f', remote]
    if value.get('arguments') != expected:
        raise ValueError('Log capture differs from the frozen ADB endpoint or command')
    return value, sha


def validate_log_capture(directory, bindings=None):
    directory = Path(directory)
    validate(directory)
    spec, request_sha = request(directory)
    capture, capture_sha = log_capture_request(directory, spec, request_sha)
    owner, owner_sha = read(directory / LOG_OWNER)
    proof, _ = read(directory / EXIT)
    if (not isinstance(owner, dict) or owner.get('schema_version') != 1 or owner.get('run_id') != spec['run_id']
            or owner.get('request_sha256') != request_sha or owner.get('capture_request_sha256') != capture_sha
            or owner.get('contained_before_start') is not True or not integer(owner.get('client_pid'), 1)
            or not token('[1-9][0-9]*', owner.get('client_creation_filetime', ''))
            or proof.get('log_capture_request_sha256') != capture_sha
            or proof.get('log_capture_owner_sha256') != owner_sha or proof['total_processes'] < 2
            or any(proof.get('log_capture_' + kind + '_sha256') != digest(directory / ('logcat-client.' + kind))
                   for kind in ('stdout', 'stderr'))):
        raise ValueError('Log capture was not bound to the completed owned job')
    result = {'log_capture_request_sha256': capture_sha, 'log_capture_owner_sha256': owner_sha}
    if bindings is not None and any(bindings.get(key) != value for key, value in result.items()):
        raise ValueError('Guest log capture belongs to another owned job')
    return result


def validate(directory, bindings=None):
    """Validate historical file evidence, not reobserve a current process tree."""
    directory = Path(directory).resolve()
    if (directory / FAILED).exists():
        raise ValueError('Owned-process supervisor failed')
    spec, request_sha = request(directory)
    owner, owner_sha = read(directory / OWNER)
    proof, proof_sha = read(directory / EXIT)
    if (not isinstance(owner, dict) or owner.get('schema_version') != 1 or owner.get('backend') != BACKEND or
            owner.get('run_id') != spec['run_id'] or owner.get('request_sha256') != request_sha or
            owner.get('contained_before_start') is not True or
            not integer(owner.get('supervisor_pid'), 1) or not integer(owner.get('frontend_pid'), 1) or
            not token('[1-9][0-9]*', owner.get('supervisor_creation_filetime', '')) or
            not token('[1-9][0-9]*', owner.get('frontend_creation_filetime', ''))):
        raise ValueError('Owned-process ownership differs from the launch request')
    if (not isinstance(proof, dict) or proof.get('schema_version') != 1 or proof.get('backend') != BACKEND or
            proof.get('run_id') != spec['run_id'] or proof.get('request_sha256') != request_sha or
            proof.get('owner_sha256') != owner_sha or
            proof.get('supervisor_pid') != owner['supervisor_pid'] or
            proof.get('frontend_pid') != owner['frontend_pid'] or
            proof.get('host_tree_exit_confirmed') is not True or
            proof.get('frontend_signaled') is not True or proof.get('logs_closed_before_hash') is not True or
            type(proof.get('frontend_exited_before_stop')) is not bool or
            not integer(proof.get('active_processes')) or proof['active_processes'] != 0 or
            not integer(proof.get('total_processes'), 1) or
            not integer(proof.get('frontend_exit_code')) or
            proof.get('reason') not in ('natural', 'requested') or type(proof.get('forced')) is not bool):
        raise ValueError('Owned process tree exit is not confirmed')
    if ((proof['reason'] == 'natural' or proof['frontend_exited_before_stop']) and proof['frontend_exit_code'] != 0 or
            proof['reason'] == 'natural' and proof['forced']):
        raise ValueError('Owned frontend did not exit successfully')
    if (owner.get('host_slot') != HOST_SLOT or owner.get('host_slot_acquired_before_start') is not True or
            proof.get('host_slot_held_until_tree_exit') is not True):
        raise ValueError('Missing or mismatched host emulator slot evidence')
    if 'adb_endpoint' in spec and owner.get('adb_endpoint_applied_before_start') is not True:
        raise ValueError('Frozen ADB endpoint was not applied before frontend startup')
    if 'artifact_lease' in spec:
        if (owner.get('artifact_lease_held') is not True or proof.get('artifact_lease_held_until_exit') is not True or
                Path(owner.get('artifact_lease_root', '')).resolve() != Path(spec['artifact_lease']['root']).resolve()):
            raise ValueError('Artifact lease was not held through tree completion')
    if any(proof.get(key + '_sha256') != digest(directory / spec[key]) for key in ('stdout', 'stderr')):
        raise ValueError('Owned-process logs changed after completion')
    result = {'host_process_owner_sha256': owner_sha, 'host_process_exit_sha256': proof_sha,
              'host_process_request_sha256': request_sha}
    if bindings is not None and any(bindings.get(key) != sha for key, sha in result.items()):
        raise ValueError('Case belongs to different owned-process evidence')
    return result


def validate_emulator(directory, launch=None, bindings=None, program_sha256=None, arguments=None, artifact_root=None):
    result = validate(directory, bindings)
    spec, _ = request(directory)
    if 'adb_endpoint' not in spec:
        raise ValueError('Missing frozen ADB endpoint for emulator launch')
    if bindings is not None and 'adb_endpoint' in bindings:
        endpoint.validate(bindings['adb_endpoint'])
        if bindings['adb_endpoint'] != spec['adb_endpoint']:
            raise ValueError('Case ADB endpoint differs from its owned launch')
    if artifact_root is not None:
        if ('artifact_lease' not in spec or Path(spec['artifact_lease']['root']).resolve() != Path(artifact_root).resolve()):
            raise ValueError('Missing or mismatched emulator artifact lease')
    if launch is None and arguments is None:
        launch, _ = read(Path(directory) / 'emulator-launch.json')
    if launch is not None:
        if Path(spec['program']).resolve() != Path(launch.get('emulator', '')).resolve():
            raise ValueError('Owned process is not the recorded emulator')
        arguments = launch.get('arguments')
        program_sha256 = digest(spec['program'])
    if (not isinstance(arguments, list) or not arguments or spec['arguments'] != arguments or
            spec['program_sha256'] != program_sha256):
        raise ValueError('Owned process differs from the emulator invocation')
    return result


if os.name == 'nt':
    from ctypes import wintypes as w
    import msvcrt

    class Limits(ctypes.Structure):
        _fields_ = [('process_time', ctypes.c_int64), ('job_time', ctypes.c_int64),
                    ('flags', w.DWORD), ('min_working_set', ctypes.c_size_t),
                    ('max_working_set', ctypes.c_size_t), ('active_limit', w.DWORD),
                    ('affinity', ctypes.c_size_t), ('priority', w.DWORD), ('scheduling', w.DWORD)]

    class ExtendedLimits(ctypes.Structure):
        _fields_ = [('basic', Limits), ('io', ctypes.c_uint64 * 6),
                    ('process_memory', ctypes.c_size_t), ('job_memory', ctypes.c_size_t),
                    ('peak_process_memory', ctypes.c_size_t), ('peak_job_memory', ctypes.c_size_t)]

    class Accounting(ctypes.Structure):
        _fields_ = [('user_time', ctypes.c_int64), ('kernel_time', ctypes.c_int64),
                    ('period_user_time', ctypes.c_int64), ('period_kernel_time', ctypes.c_int64),
                    ('faults', w.DWORD), ('total', w.DWORD), ('active', w.DWORD), ('terminated', w.DWORD)]

    class Startup(ctypes.Structure):
        _fields_ = [('cb', w.DWORD), ('reserved', w.LPWSTR), ('desktop', w.LPWSTR), ('title', w.LPWSTR),
                    ('x', w.DWORD), ('y', w.DWORD), ('xsize', w.DWORD), ('ysize', w.DWORD),
                    ('xchars', w.DWORD), ('ychars', w.DWORD), ('fill', w.DWORD), ('flags', w.DWORD),
                    ('show', w.WORD), ('reserved_size', w.WORD), ('reserved_ptr', ctypes.c_void_p),
                    ('stdin', w.HANDLE), ('stdout', w.HANDLE), ('stderr', w.HANDLE)]

    class StartupEx(ctypes.Structure):
        _fields_ = [('startup', Startup), ('attributes', ctypes.c_void_p)]

    class ProcessInfo(ctypes.Structure):
        _fields_ = [('process', w.HANDLE), ('thread', w.HANDLE), ('pid', w.DWORD), ('tid', w.DWORD)]

    kernel = ctypes.WinDLL('kernel32', use_last_error=True)
    def api(name, result, *arguments):
        function = getattr(kernel, name)
        function.restype = result
        function.argtypes = list(arguments)
        return function

    close_handle = api('CloseHandle', w.BOOL, w.HANDLE)
    current_process = api('GetCurrentProcess', w.HANDLE)
    duplicate_handle = api('DuplicateHandle', w.BOOL, w.HANDLE, w.HANDLE, w.HANDLE, ctypes.POINTER(w.HANDLE), w.DWORD, w.BOOL, w.DWORD)
    final_path = api('GetFinalPathNameByHandleW', w.DWORD, w.HANDLE, w.LPWSTR, w.DWORD, w.DWORD)
    open_process = api('OpenProcess', w.HANDLE, w.DWORD, w.BOOL, w.DWORD)
    process_times = api('GetProcessTimes', w.BOOL, w.HANDLE, *([ctypes.POINTER(w.FILETIME)] * 4))
    wait_handle = api('WaitForSingleObject', w.DWORD, w.HANDLE, w.DWORD)
    mutex_create = api('CreateMutexW', w.HANDLE, ctypes.c_void_p, w.BOOL, w.LPCWSTR)
    mutex_release = api('ReleaseMutex', w.BOOL, w.HANDLE)
    job_create = api('CreateJobObjectW', w.HANDLE, ctypes.c_void_p, w.LPCWSTR)
    job_set = api('SetInformationJobObject', w.BOOL, w.HANDLE, ctypes.c_int, ctypes.c_void_p, w.DWORD)
    job_query = api('QueryInformationJobObject', w.BOOL, w.HANDLE, ctypes.c_int, ctypes.c_void_p, w.DWORD, ctypes.c_void_p)
    job_stop = api('TerminateJobObject', w.BOOL, w.HANDLE, w.UINT)
    attr_init = api('InitializeProcThreadAttributeList', w.BOOL, ctypes.c_void_p, w.DWORD, w.DWORD, ctypes.POINTER(ctypes.c_size_t))
    attr_update = api('UpdateProcThreadAttribute', w.BOOL, ctypes.c_void_p, w.DWORD, ctypes.c_size_t, ctypes.c_void_p, ctypes.c_size_t, ctypes.c_void_p, ctypes.c_void_p)
    attr_delete = api('DeleteProcThreadAttributeList', None, ctypes.c_void_p)
    process_create = api('CreateProcessW', w.BOOL, w.LPCWSTR, w.LPWSTR, ctypes.c_void_p, ctypes.c_void_p,
                         w.BOOL, w.DWORD, ctypes.c_void_p, w.LPCWSTR, ctypes.POINTER(StartupEx), ctypes.POINTER(ProcessInfo))
    exit_code = api('GetExitCodeProcess', w.BOOL, w.HANDLE, ctypes.POINTER(w.DWORD))
    file_open = api('CreateFileW', w.HANDLE, w.LPCWSTR, w.DWORD, w.DWORD, ctypes.c_void_p, w.DWORD, w.DWORD, w.HANDLE)

    def checked(value):
        if not value:
            raise ctypes.WinError(ctypes.get_last_error())
        return value

    def acquire_host_slot():
        handle = checked(mutex_create(None, False, HOST_SLOT))
        state = wait_handle(handle, 0)
        if state == 0:
            return handle
        error = ctypes.get_last_error()
        try:
            if state == 0x80:
                # This thread acquired an abandoned mutex. Refuse this attempt;
                # never silently start while an earlier supervisor failed.
                checked(mutex_release(handle))
                raise RuntimeError('Previous Android host slot was abandoned; inspect its stopped tree before a fresh attempt')
            if state == 258:
                raise RuntimeError('Another Android emulator owns the host slot')
            raise ctypes.WinError(error)
        finally:
            close_handle(handle)

    def release_host_slot(handle):
        try:
            checked(mutex_release(handle))
        finally:
            close_handle(handle)

    def creation_time(handle):
        values = [w.FILETIME() for _ in range(4)]
        checked(process_times(handle, *(ctypes.byref(value) for value in values)))
        return str((values[0].dwHighDateTime << 32) | values[0].dwLowDateTime)

    def process_creation_time(pid):
        handle = checked(open_process(0x1000, False, pid))
        try:
            return creation_time(handle)
        finally:
            close_handle(handle)

    def duplicate_artifact_lease(parent, value):
        duplicate = w.HANDLE()
        checked(duplicate_handle(parent, int(value['handle']), current_process(), ctypes.byref(duplicate), 0, False, 2))
        try:
            name = ctypes.create_unicode_buffer(32768)
            count = checked(final_path(duplicate, name, len(name), 0))
            if count >= len(name):
                raise ValueError('Artifact lease path exceeds its buffer')
            actual = name.value
            if actual.startswith('\\\\?\\UNC\\'):
                actual = '\\\\' + actual[8:]
            elif actual.startswith('\\\\?\\'):
                actual = actual[4:]
            expected = Path(value['root']).resolve() / '.longreach-artifacts.lock'
            if Path(actual) != expected:
                raise ValueError('Duplicated handle is not this artifact root lease')
            return duplicate
        except BaseException:
            close_handle(duplicate)
            raise

    def completed_log_digest(path):
        # Job accounting can reach active=0 before conhost closes inherited
        # handles. Hash only after obtaining an exclusive read handle.
        deadline = time.monotonic() + 5
        while True:
            handle = file_open(str(path), 0x80000000, 0, None, 3, 0x80, None)
            if handle != ctypes.c_void_p(-1).value:
                break
            error = ctypes.get_last_error()
            if error not in (32, 33) or time.monotonic() >= deadline:
                raise ctypes.WinError(error)
            time.sleep(.01)
        try:
            descriptor = msvcrt.open_osfhandle(handle, os.O_RDONLY | os.O_BINARY)
        except BaseException:
            close_handle(handle)
            raise
        result = hashlib.sha256()
        with os.fdopen(descriptor, 'rb') as stream:
            for block in iter(lambda: stream.read(1024 * 1024), b''):
                result.update(block)
        return result.hexdigest()

    @contextlib.contextmanager
    def lease(directory):
        with (directory / '.host-process.lock').open('a+b') as stream:
            if stream.tell() == 0:
                stream.write(b'0')
                stream.flush()
            stream.seek(0)
            try:
                msvcrt.locking(stream.fileno(), msvcrt.LK_NBLCK, 1)
            except OSError as error:
                raise ValueError('Another supervisor owns this process tree') from error
            try:
                yield
            finally:
                stream.seek(0)
                msvcrt.locking(stream.fileno(), msvcrt.LK_UNLCK, 1)

    class Job:
        def __init__(self):
            self.handle = checked(job_create(None, None))
            self.frontend = None
            try:
                limits = ExtendedLimits()
                limits.basic.flags = 0x2000  # KILL_ON_JOB_CLOSE, no breakaway flags
                checked(job_set(self.handle, 9, ctypes.byref(limits), ctypes.sizeof(limits)))
            except BaseException:
                self.close()
                raise

        def close(self):
            if self.handle:
                close_handle(self.handle)
                self.handle = None
            if self.frontend:
                close_handle(self.frontend)
                self.frontend = None

        def launch(self, directory, spec):
            size = ctypes.c_size_t()
            attr_init(None, 2, 0, ctypes.byref(size))
            attributes = ctypes.create_string_buffer(size.value)
            checked(attr_init(attributes, 2, 0, ctypes.byref(size)))
            try:
                jobs = (w.HANDLE * 1)(self.handle)
                checked(attr_update(attributes, 0, 0x2000D, jobs, ctypes.sizeof(jobs), None, None))
                # Restrict inheritance to stdio. In particular the job handle
                # must never be inherited and keep KILL_ON_JOB_CLOSE from firing.
                with open(os.devnull, 'rb') as stdin, (directory / spec['stdout']).open('xb') as stdout, (directory / spec['stderr']).open('xb') as stderr:
                    handles = (w.HANDLE * 3)(*(msvcrt.get_osfhandle(stream.fileno()) for stream in (stdin, stdout, stderr)))
                    for handle in handles:
                        os.set_handle_inheritable(handle, True)
                    checked(attr_update(attributes, 0, 0x20002, handles, ctypes.sizeof(handles), None, None))
                    startup = StartupEx()
                    startup.startup.cb = ctypes.sizeof(startup)
                    startup.startup.flags = 0x101  # stdio + hidden window
                    startup.startup.stdin, startup.startup.stdout, startup.startup.stderr = handles
                    startup.attributes = ctypes.addressof(attributes)
                    command = ctypes.create_unicode_buffer(subprocess.list2cmdline([spec['program'], *spec['arguments']]))
                    info = ProcessInfo()
                    # JOB_LIST assigns ownership during CreateProcess, avoiding
                    # the create-suspended/assign gap if the supervisor dies.
                    flags = 0x08000000 | 0x00080000
                    environment_buffer = None
                    if 'adb_endpoint' in spec:
                        environment = dict(os.environ)
                        environment.update(endpoint.environment(spec['adb_endpoint']))
                        block = '\0'.join(key + '=' + value for key, value in sorted(environment.items(), key=lambda item: item[0].upper())) + '\0\0'
                        environment_buffer = ctypes.create_unicode_buffer(block)
                        flags |= 0x400  # CREATE_UNICODE_ENVIRONMENT
                    checked(process_create(spec['program'], command, None, None, True,
                                           flags, environment_buffer, spec['cwd'], ctypes.byref(startup), ctypes.byref(info)))
                    self.frontend = info.process
                    close_handle(info.thread)
                    return info.pid
            finally:
                attr_delete(attributes)

        def counts(self):
            result = Accounting()
            checked(job_query(self.handle, 1, ctypes.byref(result), ctypes.sizeof(result), None))
            return result.active, result.total

        def wait_frontend(self):
            if self.frontend and wait_handle(self.frontend, 5000) != 0:
                raise RuntimeError('Owned frontend handle did not signal exit')

        def terminate(self):
            checked(job_stop(self.handle, 1))
            deadline = time.monotonic() + 5
            while self.counts()[0] and time.monotonic() < deadline:
                time.sleep(.01)
            if self.counts()[0]:
                raise RuntimeError('Owned process tree did not stop')
            self.wait_frontend()


def supervise(directory, expected_request_sha256):
    if os.name != 'nt':
        raise RuntimeError('Owned process supervision requires Windows 10 or newer')
    directory = Path(directory).resolve()
    with lease(directory):
        # Refused contenders/stale directories never overwrite their owner.
        if any((directory / name).exists() for name in (OWNER, EXIT, STOP, FAILED)):
            raise ValueError('Use a fresh owned-process attempt directory')
        parent = None
        job = None
        artifact_handle = None
        host_handle = None
        try:
            spec, request_sha = request(directory)
            if request_sha != expected_request_sha256 or digest(spec['program']) != spec['program_sha256']:
                raise ValueError('Owned-process inputs changed before launch')
            parent = checked(open_process(0x100000 | 0x1000 | (0x40 if 'artifact_lease' in spec else 0), False, spec['owner_pid']))
            if creation_time(parent) != spec['owner_creation_filetime'] or wait_handle(parent, 0) != 258:
                raise ValueError('Owned-process parent identity changed or exited')
            if 'artifact_lease' in spec:
                artifact_handle = duplicate_artifact_lease(parent, spec['artifact_lease'])
            host_handle = acquire_host_slot()
            job = Job()
            frontend_pid = job.launch(directory, spec)
            owner = {'schema_version': 1, 'backend': BACKEND, 'run_id': spec['run_id'],
                     'request_sha256': request_sha, 'supervisor_pid': os.getpid(),
                     'supervisor_creation_filetime': process_creation_time(os.getpid()),
                     'frontend_pid': frontend_pid, 'frontend_creation_filetime': creation_time(job.frontend),
                     'contained_before_start': True, 'host_slot': HOST_SLOT,
                     'host_slot_acquired_before_start': True}
            if 'adb_endpoint' in spec:
                owner['adb_endpoint_applied_before_start'] = True
            if artifact_handle:
                owner.update(artifact_lease_held=True, artifact_lease_root=str(Path(spec['artifact_lease']['root']).resolve()))
            write(directory / OWNER, owner)
            owner_sha = digest(directory / OWNER)
            reason, forced = 'natural', False
            capture_sha = capture_owner_sha = None
            frontend_exited_before_stop = True
            while job.counts()[0]:
                if wait_handle(parent, 0) == 0:
                    reason, forced = 'owner-exited', True
                    job.terminate()
                    break
                if (directory / LOG_REQUEST).exists() and capture_sha is None:
                    capture, capture_sha = log_capture_request(directory, spec, request_sha)
                    if digest(capture['program']) != capture['program_sha256']:
                        raise ValueError('Log capture program changed before launch')
                    frontend = job.frontend
                    try:
                        client_pid = job.launch(directory, dict(capture, cwd=spec['cwd'], adb_endpoint=spec['adb_endpoint'],
                            stdout='logcat-client.stdout', stderr='logcat-client.stderr'))
                        client_creation = creation_time(job.frontend)
                    finally:
                        if job.frontend != frontend:
                            close_handle(job.frontend)
                            job.frontend = frontend
                    capture_owner = dict(schema_version=1, run_id=spec['run_id'], request_sha256=request_sha,
                        capture_request_sha256=capture_sha, client_pid=client_pid,
                        client_creation_filetime=client_creation, contained_before_start=True)
                    write(directory / LOG_OWNER, capture_owner)
                    capture_owner_sha = digest(directory / LOG_OWNER)
                if (directory / STOP).exists():
                    stop, _ = read(directory / STOP)
                    if stop.get('run_id') != spec['run_id'] or stop.get('request_sha256') != request_sha or not integer(stop.get('grace_ms')) or stop['grace_ms'] > 7000:
                        raise ValueError('Stop request belongs to a different process tree')
                    reason = 'requested'
                    frontend_exited_before_stop = (wait_handle(job.frontend, 0) == 0)
                    deadline = time.monotonic() + stop['grace_ms'] / 1000
                    while job.counts()[0] and time.monotonic() < deadline:
                        time.sleep(.01)
                    if job.counts()[0]:
                        forced = True
                        job.terminate()
                    break
                time.sleep(.02)
            active, total = job.counts()
            job.wait_frontend()
            code = w.DWORD()
            checked(exit_code(job.frontend, ctypes.byref(code)))
            if digest(directory / REQUEST) != request_sha or digest(directory / OWNER) != owner_sha:
                raise ValueError('Owned-process records changed during execution')
            proof = dict(schema_version=1, backend=BACKEND, run_id=spec['run_id'], request_sha256=request_sha,
                         owner_sha256=owner_sha, supervisor_pid=os.getpid(), frontend_pid=frontend_pid,
                         active_processes=active, total_processes=total, frontend_exit_code=code.value,
                         reason=reason, forced=forced, host_tree_exit_confirmed=(active == 0),
                         # Signaled is the Windows process-handle wait state,
                         # established by wait_frontend(), not a sent shutdown signal.
                         frontend_signaled=True, shutdown_signal_sent=False,
                         shutdown_policy='passive-grace-then-owned-job-termination',
                         logs_closed_before_hash=True, frontend_exited_before_stop=frontend_exited_before_stop,
                         stdout_sha256=completed_log_digest(directory / spec['stdout']),
                         stderr_sha256=completed_log_digest(directory / spec['stderr']))
            proof['host_slot_held_until_tree_exit'] = True
            if capture_sha is not None:
                if digest(directory / LOG_REQUEST) != capture_sha or digest(directory / LOG_OWNER) != capture_owner_sha:
                    raise ValueError('Owned log capture records changed during execution')
                proof.update(log_capture_request_sha256=capture_sha, log_capture_owner_sha256=capture_owner_sha,
                    log_capture_stdout_sha256=completed_log_digest(directory / 'logcat-client.stdout'),
                    log_capture_stderr_sha256=completed_log_digest(directory / 'logcat-client.stderr'))
            # All job members exited and both output handles closed before this
            # release. Parent-side ADB endpoint isolation is a separate contract.
            completed_host_handle, host_handle = host_handle, None
            release_host_slot(completed_host_handle)
            if artifact_handle:
                proof['artifact_lease_held_until_exit'] = True
            write(directory / EXIT, proof)
            return proof
        except BaseException as error:
            if job:
                job.terminate()
            write(directory / FAILED, {'schema_version': 1, 'error': str(error)})
            raise
        finally:
            if job:
                job.close()
            if host_handle:
                release_host_slot(host_handle)
            if artifact_handle:
                close_handle(artifact_handle)
            if parent:
                close_handle(parent)


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('action', choices=('supervise', 'verify'))
    parser.add_argument('--directory', required=True, type=Path)
    parser.add_argument('--request-sha256')
    args = parser.parse_args(argv)
    if args.action == 'supervise':
        supervise(args.directory, args.request_sha256)
    else:
        print(json.dumps(validate(args.directory)))


if __name__ == '__main__':
    main()
