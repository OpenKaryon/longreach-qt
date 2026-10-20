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
    if not args.yes:
        if not sys.stdin.isatty():
            print('Not starting: no terminal to confirm on; pass --yes (make ... YES=1).', file=sys.stderr)
            return 2
        if input('Continue? [y/N] ').strip().lower() not in ('y', 'yes'):
            print('Not started.')
            return 1

    # The files already in downloads/ against their pins: make fetches only
    # what is missing, so a file from an earlier pin would otherwise be used.
    if subprocess.run([args.make, '--no-print-directory', 'verify-downloads'], cwd=ROOT).returncode:
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
        line = f'[{datetime.datetime.now().strftime("%H:%M:%S")}] {text}'
        print(line, flush=True)
        with (log_dir / 'progress.log').open('a', encoding='utf-8') as f:
            f.write(line + '\n')

    def run(targets, parallel):
        """Build targets, at most parallel at a time; returns the finished jobs."""
        jobs, done = [], []
        pending = list(targets)
        last = None
        host_job = None
        if any(TARGETS[t][1] for t in targets):
            host_job = Job('qt6-host', [[args.make, '--no-print-directory', 'build-qt6-host', *make_vars]], log_dir, env)
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
            time.sleep(10)
        return done

    say(f'{len(targets)} targets, {parallel} at a time, logs in {log_dir}')
    done = {job.target: job for job in run(targets, parallel)}
    attempts = dict.fromkeys(done, 1)
    # A build can fail only under load (a large image export timing out while
    # another build runs); the failed ones get another try on their own.
    for attempt in range(args.retries):
        again = [t for t in targets if done[t].status != 'PASS']
        if not again:
            break
        say(f'retry {attempt + 1}: {", ".join(again)}, one at a time')
        for job in run(again, 1):
            done[job.target] = job
            attempts[job.target] = attempts.get(job.target, 0) + 1
    done = list(done.values())

    results = []
    for job in done:
        image = image_of(job.target, args.license_profile) if job.target in TARGETS else None
        out = ROOT / 'artifacts' / f'tests-{image}' if image else None
        newest = max((p.stat().st_mtime for p in out.rglob('*') if p.is_file()), default=0) if out and out.is_dir() else 0
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
        apps = (f'`{r["artifacts"]}`' + ('' if r['artifacts_rebuilt'] else ' (not rebuilt)')) if r['artifacts'] else '-'
        lines.append(f'| {r["target"]} | {r["status"]} | {r["attempts"]} | {r["minutes"]} | {apps} | {r["log"] or "-"} |')
    failed = [r for r in results if r['status'] != 'PASS']
    lines += ['', f'{len(results) - len(failed)} passed, {len(failed)} failed or skipped.']
    (log_dir / 'summary.md').write_text('\n'.join(lines) + '\n', encoding='utf-8')
    say(f'done: {len(results) - len(failed)} passed, {len(failed)} failed or skipped; see {log_dir / "summary.md"}')
    return 1 if failed else 0


if __name__ == '__main__':
    sys.exit(main())
