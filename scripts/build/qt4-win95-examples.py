#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2026 OpenKaryon
"""Build and publish the shared 24-app suite against the public Win95 SDK."""
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
    parser.add_argument('--image', default='qt4-win-i386')
    parser.add_argument('--out', type=Path, default=ROOT / 'artifacts/tests-qt4-win-i386')
    parser.add_argument('--jobs', type=int, default=6)
    parser.add_argument('--lock-held', action='store_true', help=argparse.SUPPRESS)
    args = parser.parse_args()
    if not 1 <= args.jobs <= 64:
        parser.error('--jobs must be between 1 and 64')
    output = args.out.resolve()
    if not output.is_relative_to(ROOT / 'artifacts') or output == ROOT / 'artifacts':
        parser.error('--out must name a directory inside this workspace artifacts/')
    helpers = runpy.run_path(str(ROOT / 'scripts/build/ensure-image.py'))
    # ensure-image keeps its lock while dispatching the examples target.
    with nullcontext() if args.lock_held else helpers['build_lock']():
        image_id = subprocess.check_output(['docker', 'image', 'inspect', args.image,
                                           '--format', '{{.Id}}'], text=True).strip()
        expected = helpers['fingerprint']('win95-suite-v2;' + image_id, 'qt4', [])
        count = len([line for line in (ROOT / 'tests/expected-apps.txt').read_text().splitlines()
                     if line and not line.startswith('#')])
        stamp = output / 'build-inputs.json'
        if stamp.is_file():
            previous = json.loads(stamp.read_text(encoding='utf-8'))
            if previous.get('sha256') == expected and len(previous.get('binaries', {})) == count \
                    and all((output / name).is_file() and hashlib.sha256((output / name).read_bytes()).hexdigest() == sha
                            for name, sha in previous['binaries'].items()):
                print(f'{output}: {count} binaries are current ({expected[:12]})')
                return
        (ROOT / 'build').mkdir(exist_ok=True)
        # Path.mkdir inherits the workspace ACL on Windows. Python 3.13+
        # mkdtemp uses an owner-only ACL, which would make published EXEs
        # unreadable to other workspace tools after an elevated build.
        pending = ROOT / 'build' / ('qt4-win95-examples-' + uuid.uuid4().hex)
        pending.mkdir()
        subprocess.run(['docker', 'run', '--rm', '--cpus', str(args.jobs),
                        '--mount', f'type=bind,source={ROOT / "tests"},target=/input,readonly',
                        '--mount', f'type=bind,source={ROOT / "scripts/build"},target=/scripts,readonly',
                        '--mount', f'type=bind,source={pending},target=/out',
                        args.image, 'bash', '/scripts/qt4-win95-suite.sh', str(args.jobs)],
                       cwd=ROOT, check=True)
        binaries = {p.name: hashlib.sha256(p.read_bytes()).hexdigest() for p in sorted(pending.glob('*.exe'))}
        if len(binaries) != count:
            raise SystemExit(f'Incomplete Win95 suite: expected {count} EXEs including runner')
        subprocess.run([sys.executable, str(ROOT / 'scripts/tests/write_manifest.py'),
                        '--out', str(pending), '--image', args.image, '--qt-version', '4.8.7',
                        '--openssl-version', '1.0.2u', '--kind', 'qt4-build-kit-tests',
                        '--license-profile', 'lgpl-friendly'], cwd=ROOT, check=True)
        manifest_path = pending / 'manifest.json'
        manifest = json.loads(manifest_path.read_text(encoding='utf-8'))
        manifest['artifact']['path'] = str(output)
        manifest['image_id'] = image_id
        manifest_path.write_text(json.dumps(manifest, indent=2, ensure_ascii=False) + '\n', encoding='utf-8')
        (pending / 'build-inputs.json').write_text(json.dumps(
            {'sha256': expected, 'image_id': image_id, 'binaries': binaries}, indent=2) + '\n', encoding='utf-8')
        (pending / 'README.txt').write_text(
            'Qt 4.8.7 Windows i386 / Win95 backport, static OpenSSL 1.0.2u.\n'
            'Run smoke-runner.exe --timeout=900 for the sequential suite.\n'
            'This build manifest records provenance, not a runtime test result.\n'
            'See docs/targets/qt4-windows.md for measured OS configurations and limitations.\n', encoding='utf-8')
        output.parent.mkdir(parents=True, exist_ok=True)
        if output.exists():
            # Retain the old binaries/reports for comparison; never mix their
            # runtime evidence into a newly compiled suite.
            output.rename(pending.with_name(pending.name + '-previous'))
        pending.rename(output)
        print(f'Published {count} EXEs: {output}')


if __name__ == '__main__':
    main()
