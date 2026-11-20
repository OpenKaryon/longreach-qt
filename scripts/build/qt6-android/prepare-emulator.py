#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
"""Prepare verified API21 target media and the pinned Windows emulator."""
import argparse
import hashlib
import json
from pathlib import Path
import shutil
import zipfile

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--abi', choices=('armeabi-v7a', 'arm64-v8a', 'x86', 'x86_64'), default='armeabi-v7a')
parser.add_argument('--repo', type=Path, required=True)
parser.add_argument('--output', type=Path, required=True)
args = parser.parse_args()
lock = json.loads((args.repo / 'scripts/fetch/locks/qt6-android-api21-inputs.json').read_text())
root = args.output / 'media'
root.mkdir(parents=True, exist_ok=True)
kernel = 'kernel-ranchu' if args.abi in ('x86', 'x86_64') else 'kernel-qemu'
emulator = 'emulator.exe' if args.abi in ('arm64-v8a', 'x86', 'x86_64') else 'emulator-arm.exe'
tools = {'x86': 'emulator-windows_x64-9536276.zip',
         'x86_64': 'emulator-windows_x64-9536276.zip',
         'arm64-v8a': 'tools_r25.2.5-windows.zip',
         'armeabi-v7a': 'tools_r24.4.1-windows.zip'}[args.abi]
images = [item['file'] for item in lock['sources'] if item['file'].startswith(f'{args.abi}-21_r')]
if len(images) != 1:
    raise ValueError(f'Expected one pinned API21 system image for {args.abi}')
for name in (images[0], tools):
    record = next(item for item in lock['sources'] if item['file'] == name)
    archive = args.repo / 'downloads/android-lollipop' / name
    with archive.open('rb') as stream:
        digest = hashlib.file_digest(stream, 'sha256').hexdigest()
    if digest != record['sha256']:
        raise ValueError(f'SHA256 mismatch: {name}')
    extract = root / {'tools_r25.2.5-windows.zip': 'emulator-25.2.5',
                      'emulator-windows_x64-9536276.zip': 'emulator-32.1.11'}.get(name, '')
    marker = extract / (name + '.sha256')
    required = ([args.abi + '/' + filename for filename in
                 (kernel, 'ramdisk.img', 'system.img', 'userdata.img', 'build.prop')]
                if name.startswith(args.abi) else [f'tools/{emulator}', 'tools/lib'])
    if name == 'emulator-windows_x64-9536276.zip':
        required = ['emulator/emulator.exe', 'emulator/lib64',
                    'emulator/qemu/windows-x86_64/qemu-system-' + ('i386' if args.abi == 'x86' else 'x86_64') + '-headless.exe']
    if (marker.is_file() and marker.read_text().strip() == digest
            and all((extract / relative).exists() for relative in required)):
        continue
    with zipfile.ZipFile(archive) as package:
        for member in package.infolist():
            path = Path(member.filename)
            if path.is_absolute() or '..' in path.parts:
                raise ValueError('Invalid media path')
            destination = extract / path
            if member.is_dir():
                destination.mkdir(parents=True, exist_ok=True)
            else:
                destination.parent.mkdir(parents=True, exist_ok=True)
                with package.open(member) as incoming, destination.open('wb') as outgoing:
                    shutil.copyfileobj(incoming, outgoing)
    marker.write_text(digest + '\n')
# SDK Tools24 looks here to recognize the system version instead of guessing10000.
properties = root / args.abi / 'system/build.prop'
properties.parent.mkdir(parents=True, exist_ok=True)
shutil.copyfile(root / args.abi / 'build.prop', properties)
print(f'Prepared Android5.0.2/API21 {args.abi} emulator media')
