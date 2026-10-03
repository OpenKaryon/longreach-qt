#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2026 OpenKaryon
"""Build and publish the tests/ applications as Mac bundles: Tiger i386 or Jaguar PowerPC."""
import argparse
from contextlib import nullcontext
import hashlib
import json
from pathlib import Path
import runpy
import subprocess
import uuid

ROOT = Path(__file__).resolve().parents[2]

# platform label -> (default image, scripts mount or None, script, jobs variable)
PLATFORMS = {
    'macos-tiger-i386': ('qt4-macos-i386', 'scripts/build/qt4-macos', '/scripts/build-examples.sh', 'TIGER_JOBS'),
    # The Jaguar image carries its suite script, which checks every import
    # against the 10.2.8 SDK.
    'macos-jaguar-ppc': ('qt4-macos-ppc', None, '/scripts/build-suite.sh', 'JAGUAR_JOBS'),
}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--platform', choices=sorted(PLATFORMS), default='macos-tiger-i386')
    parser.add_argument('--image')
    parser.add_argument('--out', type=Path)
    parser.add_argument('--jobs', type=int, default=6)
    parser.add_argument('--lock-held', action='store_true', help=argparse.SUPPRESS)
    args = parser.parse_args()
    default_image, scripts, script, jobs_var = PLATFORMS[args.platform]
    args.image = args.image or default_image
    args.out = args.out or ROOT / 'artifacts' / f'tests-{args.image}'
    output = args.out.resolve()
    if not output.is_relative_to(ROOT / 'artifacts') or output == ROOT / 'artifacts':
        parser.error('--out must be a directory inside artifacts/')
    if not 1 <= args.jobs <= 64:
        parser.error('--jobs must be between 1 and 64')
    helpers = runpy.run_path(str(ROOT / 'scripts/build/ensure-image.py'))
    with nullcontext() if args.lock_held else helpers['build_lock']():
        image = json.loads(subprocess.check_output(['docker', 'image', 'inspect', args.image], text=True))[0]
        if image['Config']['Labels'].get('org.openkaryon.longreach-qt.platform') != args.platform:
            raise SystemExit(f'{args.image} is not the {args.platform} SDK; build it first (make build-{args.image})')
        image_id = image['Id']
        expected = helpers['fingerprint'](f'{args.platform}-suite-v2;' + image_id, 'qt4', [])
        stamp = output / 'build-inputs.json'
        if stamp.is_file():
            previous = json.loads(stamp.read_text())
            files = previous.get('files', {})
            if previous.get('sha256') == expected and files and all(
                    (output / name).is_file() and hashlib.sha256((output / name).read_bytes()).hexdigest() == sha
                    for name, sha in files.items()):
                print(f'{output}: {args.platform} bundles are current ({expected[:12]})')
                return
        pending = ROOT / 'build' / (f'qt4-{args.platform}-examples-' + uuid.uuid4().hex)
        pending.mkdir(parents=True)
        mounts = ['--mount', f'type=bind,source={ROOT / "tests"},target=/input,readonly',
                  '--mount', f'type=bind,source={pending},target=/out']
        if scripts:
            mounts += ['--mount', f'type=bind,source={ROOT / scripts},target=/scripts,readonly']
        subprocess.run(['docker', 'run', '--rm', '--cpus', str(args.jobs),
                        '--entrypoint', 'bash', '--env', f'{jobs_var}={args.jobs}',
                        *mounts, args.image, script], cwd=ROOT, check=True)
        # Archive is created inside Linux to preserve Unix executable permissions.
        # Copying loose .app folders through Windows would lose those permissions.
        import shutil
        shutil.rmtree(pending / 'bin')
        files = {p.name: hashlib.sha256(p.read_bytes()).hexdigest() for p in pending.iterdir() if p.is_file()}
        (pending / 'build-inputs.json').write_text(json.dumps(
            {'sha256': expected, 'image_id': image_id, 'files': files}, indent=2) + '\n')
        output.mkdir(parents=True, exist_ok=True)
        for path in pending.iterdir():
            path.replace(output / path.name)
        pending.rmdir()
        print(f'{args.platform} bundles: {output}; runtime testing pending')


if __name__ == '__main__':
    main()
