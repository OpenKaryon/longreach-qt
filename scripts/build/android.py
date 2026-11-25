#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2026 OpenKaryon
"""Make's Android adapter: build an SDK or prepare applications as ready APKs."""
from __future__ import annotations

import argparse
import importlib.util
import json
from pathlib import Path
import platform
import shlex
import shutil
import subprocess
import sys

from android_targets import ANDROID_TARGETS, LEGACY_TARGET, QT_VERSIONS

ROOT = Path(__file__).resolve().parents[2]


def parser() -> argparse.ArgumentParser:
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument('--targets', action='store_true', help='print canonical SDK target names')
    p.add_argument('--target')
    p.add_argument('--mode', choices=['sdk', 'examples', 'legacy'])
    p.add_argument('--powershell', default='pwsh')
    p.add_argument('--android-sdk', default='')
    p.add_argument('--output-directory', default='')
    p.add_argument('--sdk-image', default='')
    p.add_argument('--host-image', default='')
    p.add_argument('--input-directory', default='')
    p.add_argument('--parallel-jobs', type=int, default=2)
    p.add_argument('--no-cache', action='store_true')
    p.add_argument('--docker-build-flags', default='')
    p.add_argument('--license-profile', default='gpl-enabled')
    p.add_argument('--qt-version', default='')
    p.add_argument('--print-command', action='store_true', help='print JSON argv without running anything')
    return p


def command_for(args) -> list[str]:
    target = args.target
    legacy = target == LEGACY_TARGET
    if not legacy and target not in ANDROID_TARGETS:
        raise ValueError(f'unknown Android target: {args.target}')
    if not args.mode or legacy != (args.mode == 'legacy'):
        raise ValueError('The legacy recipe requires legacy mode; installed SDK profiles require sdk/examples mode')
    qt, abi = (4, 'armeabi') if legacy else ANDROID_TARGETS[target][:2]
    api4 = legacy or ANDROID_TARGETS[target].api == 4
    if args.license_profile != 'gpl-enabled':
        raise ValueError('Android recipes currently support LICENSE_PROFILE=gpl-enabled only')
    if args.qt_version and args.qt_version != QT_VERSIONS[qt]:
        raise ValueError(f'Android Qt {qt} is pinned to {QT_VERSIONS[qt]} and its patch series')
    if args.parallel_jobs < 1:
        raise ValueError('ANDROID_PARALLEL_JOBS must be positive')
    if args.input_directory and not api4:
        raise ValueError('ANDROID_INPUT is only supported by API4 profiles')
    if args.host_image and (qt != 6 or args.mode != 'sdk'):
        raise ValueError('ANDROID_HOST_IMAGE is only supported by Qt6 SDK mode')
    if legacy and (args.sdk_image or args.no_cache or args.docker_build_flags or args.parallel_jobs != 2):
        raise ValueError('API4 legacy does not support SDK image or Docker build overrides')
    options = {}
    for source, dest in [('android_sdk', 'AndroidSdk'), ('output_directory', 'OutputDirectory'),
                         ('sdk_image', 'SdkImage'), ('host_image', 'HostImage'),
                         ('input_directory', 'InputDirectory')]:
        if value := getattr(args, source):
            options[dest] = value
    if not legacy:
        options.update(Abi=abi, Mode=args.mode)
        if args.mode in {'sdk', 'examples'}:
            options['ParallelJobs'] = args.parallel_jobs
        if args.mode == 'sdk':
            options['NoCache'] = args.no_cache
            options['DockerBuildFlagsJson'] = json.dumps(shlex.split(args.docker_build_flags))
    # A JSON argument and PowerShell splatting preserve spaces and literal
    # punctuation across cmd, Git Bash and POSIX shells; no generated PS code.
    return [args.powershell, '-NoLogo', '-NoProfile', '-File',
            str(ROOT / 'scripts/build/android-make.ps1'), '-QtMajor', str(qt),
            '-OptionsJson', json.dumps(options, ensure_ascii=False)]


def main(argv=None) -> int:
    p = parser()
    args = p.parse_args(argv)
    if args.targets:
        print(' '.join(ANDROID_TARGETS))
        return 0
    if not args.target:
        p.error('--target is required')
    try:
        command = command_for(args)
    except ValueError as exc:
        p.error(str(exc))
    if args.print_command:
        print(json.dumps(command, ensure_ascii=False))
        return 0
    if platform.system() != 'Windows':
        p.error('Android host scripts currently require Windows; help, --list and --print-command work everywhere')
    if not shutil.which(args.powershell):
        p.error('PowerShell 7 was not found; set POWERSHELL to its executable path')
    spec = importlib.util.spec_from_file_location('android_build_lock', ROOT / 'scripts/build/ensure-image.py')
    ensure = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(ensure)
    try:
        with ensure.build_lock():
            return subprocess.run(command, cwd=ROOT).returncode
    except KeyboardInterrupt:
        return 130


if __name__ == '__main__':
    sys.exit(main())
