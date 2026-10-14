#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2026 OpenKaryon
"""Build every SDK and its test applications: the full regression run.

    python scripts/build/build-all.py                       # one target at a time
    python scripts/build/build-all.py --jobs 2              # two at once
    python scripts/build/build-all.py --only 'qt5-*' --skip '*-arm64'
    python scripts/build/build-all.py --no-cache            # rebuild from nothing
    python scripts/build/build-all.py --list                # what would be built

Each target runs `make <target>-examples`: the SDK image is built when one of
its inputs changed (or always, with --force or --no-cache), then the test
applications are built against it into artifacts/tests-<image>/ on this
machine. qt6-host, which the cross-built Qt 6 targets copy their tools from,
is built first. A failed target does not stop the others.

--jobs sets how many targets build at the same time; --make-jobs the compiler
jobs inside each (PARALLEL_JOBS). A Qt link can take several GB, so a new
target starts only while at least --min-free-gb of memory is free; with
several targets at once keep --jobs x --make-jobs within the machine.

Logs and a summary (summary.md, summary.json) go to build/build-all-<time>/.
Exits 1 if any target failed. This is a long run (hours per target without
the Docker cache) and is deliberately not a make target.
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

# target: image name without the licence suffix, whether it carries one,
# and whether it needs qt6-host first.
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


def image_of(target: str, profile: str) -> str:
    return target + (f'-{profile}' if TARGETS[target][0] else '')


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
        self.proc = subprocess.Popen(step, cwd=ROOT, stdout=self.log, stderr=subprocess.STDOUT,
                                     env=self.env)

    def poll(self) -> bool:
        """True once the job has finished (all steps, or a failed one)."""
        code = self.proc.poll()
        if code is None:
            return False
        if code == 0 and self.steps:
            self.next_step()
            return False
        if code:
            self.status, self.failed_step = 'FAIL', ' '.join(self.current)
        else:
            self.status = 'PASS'
        self.finished = time.time()
        self.log.write(f'\n=== {self.status} (exit {code})\n'.encode())
        self.log.close()
        return True

    def stop(self):
        if self.proc and self.proc.poll() is None:
            self.proc.terminate()


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument('--jobs', type=int, default=1, help='targets built at the same time (default 1)')
    parser.add_argument('--make-jobs', type=int, default=None,
                        help='compiler jobs inside one build, PARALLEL_JOBS (default: the Makefile\'s)')
    parser.add_argument('--min-free-gb', type=float, default=12.0,
                        help='start another target only while this much memory is free (default 12)')
    parser.add_argument('--only', action='append', default=[], metavar='PATTERN',
                        help='build only targets matching PATTERN (shell-style, repeatable)')
    parser.add_argument('--skip', action='append', default=[], metavar='PATTERN',
                        help='leave out targets matching PATTERN (repeatable)')
    parser.add_argument('--force', action='store_true', help='rebuild every SDK image, Docker cache allowed')
    parser.add_argument('--no-cache', action='store_true', help='rebuild every SDK image without the Docker cache')
    parser.add_argument('--license-profile', default='gpl-enabled',
                        choices=['lgpl-friendly', 'gpl-enabled', 'commercial-qt'])
    parser.add_argument('--make', default='make')
    parser.add_argument('--log-dir', type=Path)
    parser.add_argument('--list', action='store_true', help='print the targets and exit')
    args = parser.parse_args()

    targets = [t for t in TARGETS
               if (not args.only or any(fnmatch.fnmatch(t, p) for p in args.only))
               and not any(fnmatch.fnmatch(t, p) for p in args.skip)]
    if not targets:
        parser.error('no target left after --only/--skip')
    if args.list:
        for t in targets:
            print(f'{t:18} -> artifacts/tests-{image_of(t, args.license_profile)}/')
        return 0

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
        steps = []
        steps.append([args.make, '--no-print-directory', f'{target}-examples', *make_vars])
        if target in AUDITS:
            steps.append([args.make, '--no-print-directory', AUDITS[target], *make_vars])
        return steps

    def say(text):
        line = f'[{datetime.datetime.now().strftime("%H:%M:%S")}] {text}'
        print(line, flush=True)
        with (log_dir / 'progress.log').open('a', encoding='utf-8') as f:
            f.write(line + '\n')

    say(f'{len(targets)} targets, {args.jobs} at a time, logs in {log_dir}')
    jobs, done = [], []
    pending = list(targets)
    host_job = None
    if any(TARGETS[t][1] for t in targets):
        host_job = Job('qt6-host', [[args.make, '--no-print-directory', 'qt6-host', *make_vars]], log_dir, env)
        jobs.append(host_job)
        say('started qt6-host (the Qt 6 cross targets wait for it)')

    def stop_all(*_):
        for job in jobs:
            job.stop()
        say('interrupted; running builds stopped')
        sys.exit(130)
    signal.signal(signal.SIGINT, stop_all)

    while pending or jobs:
        for job in list(jobs):
            if job.poll():
                jobs.remove(job)
                done.append(job)
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
                done.append(skipped)
                say(f'SKIP {target} (qt6-host failed)')
        startable = [t for t in pending if host_ready or not TARGETS[t][1]]
        if startable and len(jobs) < args.jobs:
            free = free_memory_gb()
            if jobs and free is not None and free < args.min_free_gb:
                pass  # wait for memory
            else:
                target = startable[0]
                pending.remove(target)
                jobs.append(Job(target, steps_for(target), log_dir, env))
                say(f'started {target}' + (f' ({free:.1f} GB free)' if free is not None else ''))
                continue
        time.sleep(10)

    results = []
    for job in done:
        image = image_of(job.target, args.license_profile) if job.target in TARGETS else None
        out = ROOT / 'artifacts' / f'tests-{image}' if image else None
        newest = max((p.stat().st_mtime for p in out.rglob('*') if p.is_file()), default=0) if out and out.is_dir() else 0
        fresh = newest >= job.started
        results.append({'target': job.target, 'status': job.status,
                         'minutes': round((job.finished - job.started) / 60, 1),
                         'failed_step': job.failed_step,
                         'artifacts': out.relative_to(ROOT).as_posix() if out else None,
                         'artifacts_rebuilt': fresh if out else None,
                         'log': job.log_path.name if job.log_path else None})
    (log_dir / 'summary.json').write_text(json.dumps(results, indent=2) + '\n', encoding='utf-8')
    lines = ['| Target | Status | Minutes | Test applications | Log |', '|---|---|---|---|---|']
    for r in results:
        apps = (f'`{r["artifacts"]}`' + ('' if r['artifacts_rebuilt'] else ' (not rebuilt)')) if r['artifacts'] else '-'
        lines.append(f'| {r["target"]} | {r["status"]} | {r["minutes"]} | {apps} | {r["log"] or "-"} |')
    failed = [r for r in results if r['status'] != 'PASS']
    lines += ['', f'{len(results) - len(failed)} passed, {len(failed)} failed or skipped.']
    (log_dir / 'summary.md').write_text('\n'.join(lines) + '\n', encoding='utf-8')
    say(f'done: {len(results) - len(failed)} passed, {len(failed)} failed or skipped; see {log_dir / "summary.md"}')
    return 1 if failed else 0


if __name__ == '__main__':
    sys.exit(main())
