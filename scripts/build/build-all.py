#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2026 OpenKaryon
"""Build every SDK and its test applications: the full regression run.

    python scripts/build/build-all.py                       # one target at a time
    python scripts/build/build-all.py --jobs 2              # two at once
    python scripts/build/build-all.py --only 'qt5-*' --skip '*-arm64'
    python scripts/build/build-all.py --no-cache            # rebuild from nothing
    python scripts/build/build-all.py --list                # what would be built
    make build-all-examples      # the same through make; make build-all: SDKs only

It asks before it starts (--yes does not); without a terminal to ask on it
stops unless --yes is given.

Each target runs `make <target>-examples` (`make build-<target>` with
--sdk-only): the SDK image is built when one of
its inputs changed (or always, with --force or --no-cache), then the test
applications are built against it into artifacts/tests-<image>/ on this
machine. qt6-host, which the cross-built Qt 6 targets copy their tools from,
comes first, built like the SDKs only when its inputs changed. A failed
target does not stop the others; at the end the failed ones are built again,
one at a time (--retries, default once).

--jobs sets how many targets build at the same time; --make-jobs the compiler
jobs inside each (PARALLEL_JOBS). A Qt link can take several GB, so a new
target starts only while at least --min-free-gb of memory is free; with
several targets at once keep --jobs x --make-jobs within the machine.

Ctrl-C (or Ctrl-Break, SIGTERM, a closed terminal on Linux and macOS) stops
every build it started: each gets a minute to end by itself (interrupt again
to end them at once), then it is killed; it exits 130, and the summary lists
what finished and what was stopped. So does any error that ends build-all,
which then exits with its own status.
On Windows build-all holds its builds in a job object, so they end with it
however it ends: a closed console or a killed build-all ends them at once.

Logs and a summary (summary.md, summary.json) go to build/build-all-<time>/.
Exits 1 if any target failed. This is a long run (hours per target without
the Docker cache); make build-all and build-all-examples run it.
"""
from __future__ import annotations

import argparse
import ctypes
import datetime
import fnmatch
import json
import os
import platform
import signal
import subprocess
import sys
import time
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]

# target: (whether a licence profile other than the default is added to its
# image name, whether it needs qt6-host first).
TARGETS = {
    'qt4-win-i386': (False, False),
    'qt4-win-amd64': (False, False),
    'qt4-linux-i386': (False, False),
    'qt4-linux-amd64': (False, False),
    'qt4-macos-i386': (False, False),
    'qt4-macos-ppc': (False, False),
    'qt5-win-i386': (True, False),
    'qt5-win-amd64': (True, False),
    'qt5-win-arm64': (True, False),
    'qt5-linux-i386': (True, False),
    'qt5-linux-amd64': (True, False),
    'qt5-linux-arm64': (True, False),
    'qt5-macos-amd64': (True, False),
    'qt5-macos-i386': (True, False),
    'qt5-macos-arm64': (True, False),
    'qt6-win-amd64': (True, True),
    'qt6-win-arm64': (True, True),
    'qt6-linux-amd64': (True, False),
    'qt6-linux-arm64': (True, True),
    'qt6-macos-amd64': (True, True),
    'qt6-macos-arm64': (True, True),
}
# Seconds a stopped build gets to end by itself before it is killed.
STOP_GRACE = 60
# Binary audits run after the examples where the Makefile has them.
AUDITS = {'qt6-win-amd64': 'qt6-win-amd64-audit', 'qt6-macos-amd64': 'qt6-macos-amd64-audit',
          'qt6-macos-arm64': 'qt6-macos-arm64-audit'}


def free_memory_gb() -> float | None:
    system = platform.system()
    try:
        if system == 'Windows':
            class Status(ctypes.Structure):
                _fields_ = [('length', ctypes.c_ulong), ('load', ctypes.c_ulong),
                            ('total', ctypes.c_ulonglong), ('avail', ctypes.c_ulonglong),
                            ('total_page', ctypes.c_ulonglong), ('avail_page', ctypes.c_ulonglong),
                            ('total_virtual', ctypes.c_ulonglong), ('avail_virtual', ctypes.c_ulonglong),
                            ('avail_extended', ctypes.c_ulonglong)]
            status = Status()
            status.length = ctypes.sizeof(Status)
            ctypes.windll.kernel32.GlobalMemoryStatusEx(ctypes.byref(status))
            return status.avail / 2 ** 30
        if system == 'Linux':
            for line in Path('/proc/meminfo').read_text().splitlines():
                if line.startswith('MemAvailable:'):
                    return int(line.split()[1]) / 2 ** 20
        if system == 'Darwin':
            out = subprocess.run(['vm_stat'], capture_output=True, text=True).stdout
            page = int(out.split('page size of ')[1].split()[0])
            pages = sum(int(line.split()[-1].rstrip('.')) for line in out.splitlines()
                        if line.startswith(('Pages free', 'Pages inactive', 'Pages speculative')))
            return pages * page / 2 ** 30
    except (OSError, ValueError, IndexError, AttributeError):
        pass
    return None


def docker_memory_gb() -> float | None:
    """Memory of the machine Docker builds on (Docker Desktop's VM on Windows and macOS)."""
    try:
        out = subprocess.run(['docker', 'info', '--format', '{{.MemTotal}}'], capture_output=True,
                             text=True, timeout=120).stdout.strip()
        return int(out) / 2 ** 30 if out.isdigit() else None
    except (OSError, subprocess.TimeoutExpired):
        return None


def image_of(target: str, profile: str) -> str:
    return target + (f'-{profile}' if TARGETS[target][0] and profile != 'gpl-enabled' else '')


# Stopping build-all reaches every process it started, however deep (make,
# ensure-image.py, the nested make, docker build): stopping make alone left
# the rest running, holding their locks. On Windows build-all puts itself in a
# job object that ends everything in it when build-all exits, however it
# exits; every process it starts is in it from its first instruction.
# Elsewhere each step is a process group of its own, remembered until empty.
if os.name == 'nt':
    from ctypes import wintypes

    class _BasicLimit(ctypes.Structure):
        _fields_ = [('PerProcessUserTimeLimit', ctypes.c_int64), ('PerJobUserTimeLimit', ctypes.c_int64),
                    ('LimitFlags', wintypes.DWORD), ('MinimumWorkingSetSize', ctypes.c_size_t),
                    ('MaximumWorkingSetSize', ctypes.c_size_t), ('ActiveProcessLimit', wintypes.DWORD),
                    ('Affinity', ctypes.c_size_t), ('PriorityClass', wintypes.DWORD),
                    ('SchedulingClass', wintypes.DWORD)]

    class _IoCounters(ctypes.Structure):
        _fields_ = [(name, ctypes.c_uint64) for name in (
            'ReadOperationCount', 'WriteOperationCount', 'OtherOperationCount',
            'ReadTransferCount', 'WriteTransferCount', 'OtherTransferCount')]

    class _ExtendedLimit(ctypes.Structure):
        _fields_ = [('BasicLimitInformation', _BasicLimit), ('IoInfo', _IoCounters),
                    ('ProcessMemoryLimit', ctypes.c_size_t), ('JobMemoryLimit', ctypes.c_size_t),
                    ('PeakProcessMemoryUsed', ctypes.c_size_t), ('PeakJobMemoryUsed', ctypes.c_size_t)]

    class _Accounting(ctypes.Structure):
        _fields_ = [('TotalUserTime', ctypes.c_int64), ('TotalKernelTime', ctypes.c_int64),
                    ('ThisPeriodTotalUserTime', ctypes.c_int64), ('ThisPeriodTotalKernelTime', ctypes.c_int64),
                    ('TotalPageFaultCount', wintypes.DWORD), ('TotalProcesses', wintypes.DWORD),
                    ('ActiveProcesses', wintypes.DWORD), ('TotalTerminatedProcesses', wintypes.DWORD)]

    _kernel32 = ctypes.WinDLL('kernel32', use_last_error=True)
    _kernel32.CreateJobObjectW.restype = wintypes.HANDLE
    _kernel32.CreateJobObjectW.argtypes = (ctypes.c_void_p, ctypes.c_wchar_p)
    _kernel32.SetInformationJobObject.argtypes = (wintypes.HANDLE, ctypes.c_int, ctypes.c_void_p, wintypes.DWORD)
    _kernel32.QueryInformationJobObject.argtypes = (wintypes.HANDLE, ctypes.c_int, ctypes.c_void_p,
                                                    wintypes.DWORD, ctypes.c_void_p)
    _kernel32.AssignProcessToJobObject.argtypes = (wintypes.HANDLE, wintypes.HANDLE)
    _kernel32.GetCurrentProcess.restype = wintypes.HANDLE
    _kernel32.CloseHandle.argtypes = (wintypes.HANDLE,)

    def contain_self():
        """Put build-all in a new job object that ends all its processes when
        build-all exits; the handle, or None (and why) if Windows refuses."""
        job = _kernel32.CreateJobObjectW(None, None)
        if not job:
            return None, ctypes.get_last_error()
        limits = _ExtendedLimit()
        limits.BasicLimitInformation.LimitFlags = 0x2000  # JOB_OBJECT_LIMIT_KILL_ON_JOB_CLOSE
        if (_kernel32.SetInformationJobObject(job, 9, ctypes.byref(limits), ctypes.sizeof(limits))
                and _kernel32.AssignProcessToJobObject(job, _kernel32.GetCurrentProcess())):
            return job, 0
        error = ctypes.get_last_error()
        _kernel32.CloseHandle(job)
        return None, error

    def processes_in(job):
        """How many processes the job holds, build-all included; None if Windows
        does not say."""
        accounting = _Accounting()
        if not _kernel32.QueryInformationJobObject(job, 1, ctypes.byref(accounting),
                                                   ctypes.sizeof(accounting), None):
            return None
        return accounting.ActiveProcesses

# Every step started, one record per process: a stop reaches all of them.
STEPS = []
# Signals received; the main loop stops the builds when it sees one.
STOP_REQUESTED = []


def request_stop(signum, _frame):
    """Only noted here: the main loop stops the builds at a point where no
    step is half started or half reaped."""
    STOP_REQUESTED.append(signum)


def install_stop_handlers():
    # Ctrl-C, Ctrl-Break, a closed terminal or a kill: the steps run in
    # groups of their own, so these no longer reach them by themselves. A
    # signal that was ignored stays ignored (nohup, a background job).
    for name in ('SIGINT', 'SIGTERM', 'SIGHUP', 'SIGBREAK'):
        number = getattr(signal, name, None)
        if number is not None and signal.getsignal(number) is not signal.SIG_IGN:
            signal.signal(number, request_stop)


class StopRequested(Exception):
    pass


def check_stop():
    if STOP_REQUESTED:
        raise StopRequested()


def wait(seconds):
    """Sleep, waking for a stop at once."""
    deadline = time.time() + seconds
    while time.time() < deadline:
        check_stop()
        time.sleep(min(1, max(0.0, deadline - time.time())))
    check_stop()


class Step:
    """One process build-all started (make with a target), and on POSIX its
    process group. A group found empty once its make has ended is crossed
    off for good: its number can then be given to someone else's group."""

    def __init__(self, target, proc):
        self.target, self.proc, self.gone = target, proc, False

    def probe(self) -> bool:
        """Whether anything of the step is left."""
        if self.gone:
            return False
        if os.name == 'nt':
            return self.proc.poll() is None  # without a job object: the step itself only
        if self.proc.poll() is None:
            return True  # make leads its group: the number is still ours
        try:
            os.killpg(self.proc.pid, 0)
            return True
        except OSError:
            # Gone (ESRCH), or now the group of someone we may not signal
            # (EPERM): ours run as us. Either way never ours again.
            self.gone = True
            return False

    def interrupt(self):
        """Ctrl-Break to the step's group on Windows (docker then cancels its
        build; it reaches the group after make has gone, and the pid is not
        reused while its handle is open), SIGTERM elsewhere."""
        if not self.probe() and os.name != 'nt':
            return
        try:
            if os.name == 'nt':
                os.kill(self.proc.pid, signal.CTRL_BREAK_EVENT)
            else:
                os.killpg(self.proc.pid, signal.SIGTERM)
        except (OSError, ValueError):
            pass  # gone already, or no console to send it through

    def kill(self):
        """End what is left of the step at once."""
        if not self.probe():
            return
        try:
            if os.name != 'nt':
                os.killpg(self.proc.pid, signal.SIGKILL)
            else:
                # Bytes: taskkill writes in the console's code page.
                result = subprocess.run(['taskkill', '/T', '/F', '/PID', str(self.proc.pid)],
                                        capture_output=True, check=False)
                if result.returncode and self.proc.poll() is None:
                    self.proc.kill()
        except (OSError, ValueError):
            pass


def prune():
    """Cross off the groups that have emptied (POSIX), each loop pass, so
    that none is looked at after its number could have been reused."""
    for step in STEPS:
        if not step.gone and step.proc.poll() is not None:
            step.probe()


def builds_left(job_object) -> int:
    """How many of build-all's builds are still running (processes in the job
    object, or steps); unknown counts as one."""
    if job_object:
        count = processes_in(job_object)
        return 1 if count is None else max(0, count - 1)  # build-all itself
    return sum(1 for step in STEPS if step.probe())


def stop_builds(job_object, say) -> int:
    """Ask every build to stop, give them one shared grace period (a second
    signal cuts it short), then end what is left; returns how many are left.
    With a job object what is left is ended by build-all's own exit."""
    # The signal that began the stop, if one did; any after it, also one that
    # came before the stop got going (Ctrl-C pressed twice), cuts the grace.
    signals = min(len(STOP_REQUESTED), 1)
    say(f'stopping the builds: up to {STOP_GRACE} s for them to end; '
        'interrupt again to end them at once')
    for step in STEPS:
        try:
            step.interrupt()
        except Exception:  # noqa: BLE001 - go on with the others
            pass
    deadline = time.time() + STOP_GRACE
    while time.time() < deadline and builds_left(job_object) and len(STOP_REQUESTED) <= signals:
        time.sleep(1)
    if not builds_left(job_object) or job_object:
        return builds_left(job_object)
    for step in STEPS:
        try:
            step.kill()
        except Exception:  # noqa: BLE001
            pass
    deadline = time.time() + 10  # a kill is not instant
    while time.time() < deadline and builds_left(job_object):
        time.sleep(0.5)
    return builds_left(job_object)


class Job:
    def __init__(self, target, steps, log_dir, env):
        self.target, self.steps, self.env = target, list(steps), env
        self.log_path = log_dir / f'{target}.log'
        self.log = self.log_path.open('ab')
        self.proc = None
        self.status = 'running'
        self.started = time.time()
        self.finished = None
        self.failed_step = None
        self.next_step()

    def next_step(self):
        step = self.steps.pop(0)
        self.current = step
        stamp = datetime.datetime.now().strftime('%Y-%m-%d %H:%M:%S')
        self.log.write(f'\n=== {stamp} $ {" ".join(step)}\n'.encode())
        self.log.flush()
        group = ({'creationflags': subprocess.CREATE_NEW_PROCESS_GROUP} if os.name == 'nt'
                 else {'start_new_session': True})
        self.proc = subprocess.Popen(step, cwd=ROOT, stdout=self.log, stderr=subprocess.STDOUT,
                                     env=self.env, **group)
        STEPS.append(Step(self.target, self.proc))

    def poll(self, start_next=True) -> bool:
        """True once the job has finished (all steps, or a failed one). Without
        start_next (a stop) a step that ended with steps left is STOPPED."""
        code = self.proc.poll()
        if code is None:
            return False
        if code == 0 and self.steps:
            if start_next:
                self.next_step()
                return False
            self.status, self.failed_step = 'STOPPED', 'stopped'
        elif code:
            self.status, self.failed_step = 'FAIL', ' '.join(self.current)
        else:
            self.status = 'PASS'
        self.finished = time.time()
        self.log.write(f'\n=== {self.status} (exit {code})\n'.encode())
        self.log.close()
        return True


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument('--jobs', type=int, default=1, help='targets built at the same time (default 1)')
    parser.add_argument('--make-jobs', type=int, default=None,
                        help='compiler jobs inside one build, PARALLEL_JOBS (default: the Makefile\'s)')
    parser.add_argument('--min-free-gb', type=float, default=12.0,
                        help='start another target only while this much memory is free (default 12)')
    parser.add_argument('--gb-per-job', type=float, default=2.0,
                        help='memory one compiler job can take while Qt links (default 2); with --make-jobs '
                             'it caps --jobs to what the Docker memory holds')
    parser.add_argument('--start-gap', type=int, default=300,
                        help='seconds after starting a target before the next one (default 300), so that the '
                             'free-memory check sees what it took; none once it has finished')
    parser.add_argument('--only', action='append', default=[], metavar='PATTERN',
                        help='build only targets matching PATTERN (shell-style, repeatable)')
    parser.add_argument('--skip', action='append', default=[], metavar='PATTERN',
                        help='leave out targets matching PATTERN (repeatable)')
    parser.add_argument('--force', action='store_true', help='rebuild every SDK image, Docker cache allowed')
    parser.add_argument('--no-cache', action='store_true', help='rebuild every SDK image without the Docker cache')
    parser.add_argument('--license-profile', default='gpl-enabled',
                        choices=['lgpl-friendly', 'gpl-enabled', 'commercial-qt'])
    parser.add_argument('--make', default='make')
    parser.add_argument('--retries', type=int, default=1,
                        help='build failed targets again, one at a time, this many times (default 1)')
    parser.add_argument('--log-dir', type=Path)
    parser.add_argument('--list', action='store_true', help='print the targets and exit')
    parser.add_argument('--sdk-only', action='store_true', help='build the SDK images, not the test applications')
    parser.add_argument('--yes', action='store_true', help='start without asking')
    args = parser.parse_args()

    targets = [t for t in TARGETS
               if (not args.only or any(fnmatch.fnmatch(t, p) for p in args.only))
               and not any(fnmatch.fnmatch(t, p) for p in args.skip)]
    # lgpl-friendly is enforced for the Linux Qt 5/6 targets only; make refuses
    # it for the others (docs/licensing.md).
    refused = [t for t in targets if args.license_profile == 'lgpl-friendly'
               and TARGETS[t][0] and '-linux-' not in t]
    if refused:
        print('LICENSE_PROFILE=lgpl-friendly: skipping ' + ', '.join(refused) + ' (Linux Qt 5/6 only)')
        targets = [t for t in targets if t not in refused]
    if not targets:
        parser.error('no target left after --only/--skip')
    if args.list:
        for t in targets:
            print(f'{t:18} -> artifacts/tests-{image_of(t, args.license_profile)}/')
        return 0

    # A target's memory peaks hours in, when Qt links, so the free memory at
    # its start says little: cap the concurrency by what Docker has.
    make_jobs = args.make_jobs or 6
    per_build = make_jobs * args.gb_per_job
    memory = docker_memory_gb()
    cap = max(1, int(memory // per_build)) if memory else 1
    parallel = max(1, min(args.jobs, cap, len(targets)))
    what = 'SDK images' if args.sdk_only else 'SDK images and their test applications'
    if args.jobs > cap:
        where = f'Docker has {memory:.0f} GB' if memory else 'the Docker memory is unknown'
        print(f'--jobs {args.jobs} is more than fits: {where} and one build can take about '
              f'{per_build:.0f} GB ({make_jobs} compiler jobs x {args.gb_per_job:g} GB), so {cap} at a time. '
              f'Fewer compiler jobs (PARALLEL_JOBS) allow more at once.')
    print(f'{len(targets)} targets will be built ({what}), {parallel} at a time:')
    print('  ' + ' '.join(targets))
    print('Without the Docker cache that is hours per target, the whole set a day or more.')
    # One build at a time on this machine; several targets at once are this
    # build-all with --jobs, which keeps them within the memory. Held to the
    # end (the system lets go of it when build-all ends, however it ends).
    sys.path.insert(0, str(ROOT / 'scripts' / 'fetch'))
    import fetch  # noqa: E402 - its lock helpers, as ensure-image.py uses them
    build_lock = ROOT / 'build' / '.sdk-build.lock'
    build_lock.parent.mkdir(parents=True, exist_ok=True)
    lock_stream = build_lock.open('a+b')
    if lock_stream.seek(0, os.SEEK_END) == 0:
        lock_stream.write(b'0')
        lock_stream.flush()
    if not fetch.try_lock(lock_stream):
        print('Not started: another build is running on this machine (build-all or make '
              'build-<target>). To build several targets at once, run one build-all with '
              '--jobs N (make build-all BUILD_ALL_JOBS=N).', file=sys.stderr)
        return 1

    if not args.yes:
        if not sys.stdin.isatty():
            print('Not starting: no terminal to confirm on; pass --yes (make ... YES=1).', file=sys.stderr)
            return 2
        try:
            answer = input('Continue? [y/N] ')
        except KeyboardInterrupt:
            print('\nNot started.')
            return 130
        except EOFError:
            print('\nNot started.')
            return 1
        if answer.strip().lower() not in ('y', 'yes'):
            print('Not started.')
            return 1

    job_object = None
    if os.name == 'nt':
        job_object, error = contain_self()
        if not job_object:
            print(f'WARNING: Windows would not hold build-all in a job object (error {error}); '
                  'a stop ends each build through taskkill instead, and a process whose make '
                  'has gone may be missed.', file=sys.stderr)
    install_stop_handlers()
    # The files already in downloads/ against their pins: make fetches only
    # what is missing, so a file from an earlier pin would otherwise be used.
    verify = subprocess.run([args.make, '--no-print-directory', 'verify-downloads'], cwd=ROOT)
    if STOP_REQUESTED:  # the verify had the signal too: its exit says nothing
        print('Not started: interrupted.', file=sys.stderr)
        return 130
    if verify.returncode:
        print('Not started: a file in downloads/ does not match its pin (make verify-downloads).',
              file=sys.stderr)
        return 1

    stamp = datetime.datetime.now().strftime('%Y%m%d-%H%M')
    log_dir = args.log_dir or ROOT / 'build' / f'build-all-{stamp}'
    log_dir.mkdir(parents=True, exist_ok=True)
    make_vars = [f'LICENSE_PROFILE={args.license_profile}']
    if args.make_jobs:
        make_vars.append(f'PARALLEL_JOBS={args.make_jobs}')
    if args.no_cache:
        make_vars.append('NO_CACHE=1')
    elif args.force:
        make_vars.append('FORCE=1')
    env = dict(os.environ, LONGREACH_BUILDS_COORDINATED='1')

    def steps_for(target):
        if args.sdk_only:
            return [[args.make, '--no-print-directory', f'build-{target}', *make_vars]]
        steps = [[args.make, '--no-print-directory', f'{target}-examples', *make_vars]]
        if target in AUDITS:
            steps.append([args.make, '--no-print-directory', AUDITS[target], *make_vars])
        return steps

    def say(text):
        """Log a line; never fails, so that a full disk or a closed terminal
        cannot keep build-all from stopping its builds."""
        line = f'[{datetime.datetime.now().strftime("%H:%M:%S")}] {text}'
        try:
            with (log_dir / 'progress.log').open('a', encoding='utf-8') as f:
                f.write(line + '\n')
        except OSError:
            pass
        try:
            print(line, flush=True)
        except OSError:
            pass

    done, attempts = {}, {}

    def record(job):
        done[job.target] = job
        attempts[job.target] = attempts.get(job.target, 0) + 1

    jobs = []  # running now, in the current run()

    def run(targets, parallel):
        """Build targets, at most parallel at a time; each finished job is recorded."""
        check_stop()
        jobs.clear()
        pending = list(targets)
        last = None
        host_job = None
        if any(TARGETS[t][1] for t in targets):
            host_job = Job('qt6-host', [[args.make, '--no-print-directory', 'build-qt6-host', *make_vars]], log_dir, env)
            jobs.append(host_job)
            say('started qt6-host (the Qt 6 cross targets wait for it)')

        while pending or jobs:
            check_stop()
            prune()
            for job in list(jobs):
                if job.poll():
                    jobs.remove(job)
                    record(job)
                    say(f'{job.status} {job.target} in {(job.finished - job.started) / 60:.0f} min'
                        + (f' (failed: {job.failed_step})' if job.failed_step else ''))
            host_ready = host_job is None or host_job.status == 'PASS'
            host_failed = host_job is not None and host_job.status == 'FAIL'
            for target in list(pending):
                if TARGETS[target][1] and host_failed:
                    pending.remove(target)
                    skipped = Job.__new__(Job)
                    skipped.target, skipped.status, skipped.failed_step = target, 'SKIP', 'qt6-host failed'
                    skipped.started = skipped.finished = time.time()
                    skipped.log_path = None
                    record(skipped)
                    say(f'SKIP {target} (qt6-host failed)')
            startable = [t for t in pending if host_ready or not TARGETS[t][1]]
            # A target whose image was current is done in a minute: no gap after it.
            settled = last not in jobs or time.time() - last.started >= args.start_gap
            if startable and len(jobs) < parallel and settled:
                free = free_memory_gb()
                if not jobs or free is None or free >= args.min_free_gb:
                    target = startable[0]
                    pending.remove(target)
                    last = Job(target, steps_for(target), log_dir, env)
                    jobs.append(last)
                    say(f'started {target}' + (f' ({free:.1f} GB free)' if free is not None else ''))
            if pending or jobs:
                wait(10)

    def write_summary(outcome):
        results = []
        for job in done.values():
            image = image_of(job.target, args.license_profile) if job.target in TARGETS else None
            out = ROOT / 'artifacts' / f'tests-{image}' if image else None
            newest = max((p.stat().st_mtime for p in out.rglob('*') if p.is_file()), default=0) \
                if out and out.is_dir() else 0
            fresh = newest >= job.started
            results.append({'target': job.target, 'status': job.status,
                            'minutes': round((job.finished - job.started) / 60, 1),
                            'attempts': attempts.get(job.target, 1),
                            'failed_step': job.failed_step,
                            'artifacts': out.relative_to(ROOT).as_posix() if out else None,
                            'artifacts_rebuilt': fresh if out else None,
                            'log': job.log_path.name if job.log_path else None})
        (log_dir / 'summary.json').write_text(json.dumps(results, indent=2) + '\n', encoding='utf-8')
        lines = ['| Target | Status | Attempts | Minutes | Test applications | Log |', '|---|---|---|---|---|---|']
        for r in results:
            apps = (f'`{r["artifacts"]}`' + ('' if r['artifacts_rebuilt'] else ' (not rebuilt)')) \
                if r['artifacts'] else '-'
            lines.append(f'| {r["target"]} | {r["status"]} | {r["attempts"]} | {r["minutes"]} | {apps} '
                         f'| {r["log"] or "-"} |')
        passed = sum(1 for r in results if r['status'] == 'PASS')
        not_built = [t for t in targets if t not in done]
        lines += ['', f'{passed} passed, {len(results) - passed} failed, stopped or skipped.']
        if outcome != 'done':
            lines.append(f'{"Interrupted" if outcome == "interrupted" else "build-all failed"}; '
                         f'not built: {", ".join(not_built) or "none"}.')
        (log_dir / 'summary.md').write_text('\n'.join(lines) + '\n', encoding='utf-8')

    say(f'{len(targets)} targets, {parallel} at a time, logs in {log_dir}')
    outcome = 'failed'  # until the runs end one way or the other
    try:
        run(targets, parallel)
        # A build can fail only under load (a large image export timing out
        # while another build runs); the failed ones get another try on their own.
        for attempt in range(args.retries):
            again = [t for t in targets if done[t].status != 'PASS']
            if not again:
                break
            say(f'retry {attempt + 1}: {", ".join(again)}, one at a time')
            run(again, 1)
        check_stop()  # a signal during the last poll
        outcome = 'done'
    except (StopRequested, KeyboardInterrupt):
        outcome = 'interrupted'
    finally:
        # The jobs whose make had ended before the stop: they keep PASS or
        # FAIL. The others end because of it, and are STOPPED.
        ended_before = {id(job) for job in jobs if job.status == 'running' and job.proc.poll() is not None}
        # Stop first, talk after: nothing build-all started is left behind,
        # whatever ended the runs, and a message that cannot be written
        # does not keep it from that.
        if builds_left(job_object):
            if outcome == 'failed':
                say('build-all failed; stopping the builds it started')
            elif outcome == 'done':
                say('processes left behind by finished builds; stopping them')
            left = stop_builds(job_object, say)
            say('builds stopped' if not left else
                f'{left} still running: ended as build-all exits' if job_object else
                f'{left} could not be stopped')
        for job in jobs:  # the ones still running when the runs ended
            if job.status != 'running':
                continue
            finished = False
            if id(job) in ended_before:
                try:
                    finished = job.poll(start_next=False)
                except OSError:
                    pass
            if not finished:
                job.status, job.failed_step, job.finished = 'STOPPED', 'stopped', time.time()
                try:
                    job.log.close()
                except OSError:
                    pass
            record(job)
        try:
            write_summary(outcome)
        except Exception as error:  # noqa: BLE001 - the original failure matters more
            say(f'the summary could not be written ({error})')
    passed = sum(1 for job in done.values() if job.status == 'PASS')
    failed = len(done) - passed
    not_built = sum(1 for t in targets if t not in done)
    if outcome == 'interrupted':
        say(f'interrupted: {passed} passed, {failed} failed, stopped or skipped, {not_built} not built; '
            f'see {log_dir / "summary.md"}')
        return 130
    say(f'done: {passed} passed, {failed} failed or skipped; see {log_dir / "summary.md"}')
    return 1 if failed else 0


if __name__ == '__main__':
    sys.exit(main())
