#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2026 OpenKaryon
"""Publish the shared test suite (tests/) built against the installed Sarge SDK."""
import argparse
from contextlib import nullcontext
import hashlib
import json
from pathlib import Path
import runpy
import subprocess
import sys
import uuid

ROOT = Path(__file__).resolve().parents[2]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--arch', choices=['i386', 'amd64'], default='i386')
    parser.add_argument('--image')
    parser.add_argument('--out', type=Path)
    parser.add_argument('--jobs', type=int, default=6)
    parser.add_argument('--lock-held', action='store_true', help=argparse.SUPPRESS)
    args = parser.parse_args()
    args.image = args.image or f'qt4-linux-{args.arch}'
    args.out = args.out or ROOT / 'artifacts' / f'tests-{args.image}'
    if not 1 <= args.jobs <= 64:
        parser.error('--jobs must be between 1 and 64')
    output = args.out.resolve()
    if not output.is_relative_to(ROOT / 'artifacts') or output == ROOT / 'artifacts':
        parser.error('--out must name a directory inside this workspace artifacts/')
    helpers = runpy.run_path(str(ROOT / 'scripts/build/ensure-image.py'))
    with nullcontext() if args.lock_held else helpers['build_lock']():
        image = json.loads(subprocess.check_output(['docker', 'image', 'inspect', args.image], text=True))[0]
        if image['Config']['Labels'].get('org.openkaryon.longreach-qt.platform') != f'debian-sarge-{args.arch}':
            raise SystemExit(f'Build the Sarge SDK first: make build-qt4-linux-{args.arch}')
        image_id = image['Id']
        expected = helpers['fingerprint']('sarge-suite-v1;' + image_id, 'qt4', [])
        names = {line for line in (ROOT / 'tests/expected-apps.txt').read_text().splitlines()
                 if line and not line.startswith('#')}
        stamp = output / 'build-inputs.json'
        if stamp.is_file():
            try:
                previous = json.loads(stamp.read_text(encoding='utf-8'))
            except (ValueError, OSError):
                previous = {}
            binaries = previous.get('binaries', {})
            if previous.get('sha256') == expected and set(binaries) == names and all(
                    (output / name).is_file() and hashlib.sha256((output / name).read_bytes()).hexdigest() == sha
                    for name, sha in binaries.items()):
                print(f'{output}: {len(names)} binaries are current ({expected[:12]})')
                return
        pending = ROOT / 'build' / ('qt4-sarge-examples-' + uuid.uuid4().hex)
        pending.mkdir(parents=True)
        subprocess.run(['docker', 'run', '--rm', '--cpus', str(args.jobs),
                        '--env', 'SARGE_JOBS=' + str(args.jobs),
                        '--mount', f'type=bind,source={ROOT / "tests"},target=/input,readonly',
                        '--mount', f'type=bind,source={ROOT / "scripts/build/qt4-sarge"},target=/scripts,readonly',
                        '--mount', f'type=bind,source={ROOT / "scripts/audit"},target=/audit-scripts,readonly',
                        '--mount', f'type=bind,source={pending},target=/out',
                        args.image, '/scripts/build-examples.sh'], cwd=ROOT, check=True)
        audit = json.loads((pending / 'elf-audit.json').read_text())
        binaries = {item['binary']: item['sha256'] for item in audit['binaries']}
        if set(binaries) != names:
            raise SystemExit('Incomplete Sarge suite: expected tests/expected-apps.txt')
        for name in names:
            (pending / 'bin' / name).replace(pending / name)
        (pending / 'bin').rmdir()
        subprocess.run([sys.executable, str(ROOT / 'scripts/tests/write_manifest.py'),
                        '--out', str(pending), '--image', args.image, '--qt-version', '4.8.7',
                        '--openssl-version', '1.0.2u', '--kind', 'qt4-build-kit-tests',
                        '--license-profile', 'lgpl-friendly'], cwd=ROOT, check=True)
        manifest_path = pending / 'manifest.json'
        manifest = json.loads(manifest_path.read_text(encoding='utf-8'))
        manifest['artifact']['path'] = str(output)
        manifest['image_id'] = image_id
        manifest['target'] = {'os': 'Debian 3.1 Sarge', 'arch': args.arch, 'max_glibc': '2.3.2'}
        manifest_path.write_text(json.dumps(manifest, indent=2, ensure_ascii=False) + '\n', encoding='utf-8')
        (pending / 'build-inputs.json').write_text(json.dumps(
            {'sha256': expected, 'image_id': image_id, 'binaries': binaries}, indent=2) + '\n', encoding='utf-8')
        (pending / 'README.txt').write_text(
            f'Qt 4.8.7 Linux {args.arch} / Debian 3.1 Sarge, static OpenSSL 1.0.2u.\n'
            'On the guest: chmod +x *-gallery *-lab *-selftest smoke-runner\n'
            'Run ./widgets-gallery or ./quick-qml-gallery inside an X11 desktop.\n'
            'Run ./smoke-runner --timeout=90 for the sequential suite.\n'
            'This manifest records the build, not a runtime test result.\n'
            'See docs/targets/qt4-linux.md.\n', encoding='utf-8')
        output.parent.mkdir(parents=True, exist_ok=True)
        if output.exists():
            output.rename(pending.with_name(pending.name + '-previous'))
        pending.rename(output)
        print(f'Published {len(names)} ELF executables: {output}')


if __name__ == '__main__':
    main()
